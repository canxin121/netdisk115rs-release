#!/usr/bin/env bash
set -euo pipefail
source_dir="${1:?source dir}"
out_dir="${2:?out dir}"
platform="${3:?platform}"
arch="${4:?arch}"
mkdir -p "$out_dir"
stage="$(mktemp -d "${TMPDIR:-/tmp}/netdisk115rs-package.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
install -m 0755 "$source_dir/target/release/netdisk115rs" "$stage/netdisk115rs"
cp "$source_dir/config.example.yaml" "$stage/config.example.yaml"
cp -R "$source_dir/static" "$stage/static"
git -C "$source_dir" rev-parse HEAD > "$stage/SOURCE_COMMIT.txt"
tar -C "$stage" -czf "$out_dir/netdisk115rs-${platform}-${arch}.tar.gz" .
