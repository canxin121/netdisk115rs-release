#[cfg(windows)]
mod windows_service_host {
    use std::ffi::OsString;
    use std::fs::{self, OpenOptions};
    use std::path::PathBuf;
    use std::process::{Child, Command, Stdio};
    use std::sync::{OnceLock, mpsc};
    use std::time::Duration;

    use windows_service::define_windows_service;
    use windows_service::service::{
        ServiceControl, ServiceControlAccept, ServiceExitCode, ServiceState, ServiceStatus,
        ServiceType,
    };
    use windows_service::service_control_handler::{self, ServiceControlHandlerResult};
    use windows_service::service_dispatcher;

    const SERVICE_NAME: &str = "netdisk115rs";

    #[derive(Clone, Debug)]
    struct LaunchConfig {
        binary: PathBuf,
        config: PathBuf,
        working_dir: PathBuf,
    }

    static CONFIG: OnceLock<LaunchConfig> = OnceLock::new();

    define_windows_service!(ffi_service_main, service_main);

    pub fn main() -> Result<(), Box<dyn std::error::Error>> {
        let config = parse_args(std::env::args_os().skip(1).collect())?;
        CONFIG
            .set(config)
            .map_err(|_| "service launch configuration was already initialized")?;
        service_dispatcher::start(SERVICE_NAME, ffi_service_main)?;
        Ok(())
    }

    fn parse_args(args: Vec<OsString>) -> Result<LaunchConfig, Box<dyn std::error::Error>> {
        if args.first().and_then(|v| v.to_str()) != Some("run") {
            return Err("usage: netdisk115rs-service.exe run --binary PATH --config PATH --working-dir PATH".into());
        }
        let mut binary = None;
        let mut config = None;
        let mut working_dir = None;
        let mut index = 1;
        while index < args.len() {
            let key = args[index].to_string_lossy();
            let value = args
                .get(index + 1)
                .ok_or_else(|| format!("missing value for {key}"))?;
            match key.as_ref() {
                "--binary" => binary = Some(PathBuf::from(value)),
                "--config" => config = Some(PathBuf::from(value)),
                "--working-dir" => working_dir = Some(PathBuf::from(value)),
                _ => return Err(format!("unknown argument: {key}").into()),
            }
            index += 2;
        }
        Ok(LaunchConfig {
            binary: binary.ok_or("missing --binary")?,
            config: config.ok_or("missing --config")?,
            working_dir: working_dir.ok_or("missing --working-dir")?,
        })
    }

    fn service_main(_arguments: Vec<OsString>) {
        if let Err(error) = run_service() {
            eprintln!("netdisk115rs service host failed: {error}");
        }
    }

    fn status(
        state: ServiceState,
        controls: ServiceControlAccept,
        exit: ServiceExitCode,
    ) -> ServiceStatus {
        ServiceStatus {
            service_type: ServiceType::OWN_PROCESS,
            current_state: state,
            controls_accepted: controls,
            exit_code: exit,
            checkpoint: 0,
            wait_hint: Duration::default(),
            process_id: None,
        }
    }

    fn run_service() -> Result<(), Box<dyn std::error::Error>> {
        let (stop_tx, stop_rx) = mpsc::channel::<()>();
        let handler = move |event| -> ServiceControlHandlerResult {
            match event {
                ServiceControl::Stop | ServiceControl::Shutdown => {
                    let _ = stop_tx.send(());
                    ServiceControlHandlerResult::NoError
                }
                ServiceControl::Interrogate => ServiceControlHandlerResult::NoError,
                _ => ServiceControlHandlerResult::NotImplemented,
            }
        };
        let status_handle = service_control_handler::register(SERVICE_NAME, handler)?;
        status_handle.set_service_status(status(
            ServiceState::Running,
            ServiceControlAccept::STOP | ServiceControlAccept::SHUTDOWN,
            ServiceExitCode::Win32(0),
        ))?;

        let config = CONFIG.get().ok_or("missing launch configuration")?.clone();
        let mut child = spawn_backend(&config)?;
        let mut service_exit = ServiceExitCode::Win32(0);

        loop {
            if stop_rx.try_recv().is_ok() {
                stop_child(&mut child);
                break;
            }
            if let Some(exit) = child.try_wait()? {
                let code = exit.code().unwrap_or(1).unsigned_abs().max(1);
                service_exit = ServiceExitCode::ServiceSpecific(code);
                break;
            }
            std::thread::sleep(Duration::from_millis(500));
        }

        status_handle.set_service_status(status(
            ServiceState::Stopped,
            ServiceControlAccept::empty(),
            service_exit,
        ))?;
        Ok(())
    }

    fn spawn_backend(config: &LaunchConfig) -> Result<Child, Box<dyn std::error::Error>> {
        fs::create_dir_all(&config.working_dir)?;
        let logs = config.working_dir.join("logs");
        fs::create_dir_all(&logs)?;
        let stdout = OpenOptions::new()
            .create(true)
            .append(true)
            .open(logs.join("netdisk115rs.log"))?;
        let stderr = OpenOptions::new()
            .create(true)
            .append(true)
            .open(logs.join("netdisk115rs.error.log"))?;
        Ok(Command::new(&config.binary)
            .arg("--config")
            .arg(&config.config)
            .arg("serve")
            .current_dir(&config.working_dir)
            .stdin(Stdio::null())
            .stdout(Stdio::from(stdout))
            .stderr(Stdio::from(stderr))
            .spawn()?)
    }

    fn stop_child(child: &mut Child) {
        let _ = child.kill();
        let _ = child.wait();
    }
}

#[cfg(windows)]
fn main() -> Result<(), Box<dyn std::error::Error>> {
    windows_service_host::main()
}

#[cfg(not(windows))]
fn main() {
    eprintln!("netdisk115rs-service is only supported on Windows");
    std::process::exit(1);
}
