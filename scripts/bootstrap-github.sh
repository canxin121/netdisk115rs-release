#!/usr/bin/env bash
set -euo pipefail

SOURCE_REPO="${SOURCE_REPO:-canxin121/netdisk115rs}"
RELEASE_REPO="${RELEASE_REPO:-canxin121/netdisk115rs-release}"
DEPLOY_KEY_TITLE="netdisk115rs-release-actions"

command -v gh >/dev/null 2>&1 || { echo "gh CLI is required" >&2; exit 69; }
gh auth status -h github.com >/dev/null

if ! gh repo view "$RELEASE_REPO" >/dev/null 2>&1; then
  gh repo create "$RELEASE_REPO" --public --description "Public installers and binary releases for closed-source netdisk115rs"
fi

if ! git remote get-url origin >/dev/null 2>&1; then
  git remote add origin "https://github.com/${RELEASE_REPO}.git"
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/netdisk115rs-deploy-key.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT INT TERM
ssh-keygen -q -t ed25519 -N '' -C "$DEPLOY_KEY_TITLE" -f "$tmp/id_ed25519"

existing_id="$(gh api "repos/$SOURCE_REPO/keys" --paginate --jq ".[] | select(.title == \"$DEPLOY_KEY_TITLE\") | .id" | head -n 1 || true)"
if [[ -n "$existing_id" ]]; then
  gh api --method DELETE "repos/$SOURCE_REPO/keys/$existing_id"
fi
gh api --method POST "repos/$SOURCE_REPO/keys" \
  -f title="$DEPLOY_KEY_TITLE" \
  -f key="$(cat "$tmp/id_ed25519.pub")" \
  -F read_only=true >/dev/null

gh secret set SOURCE_REPO_SSH_KEY --repo "$RELEASE_REPO" < "$tmp/id_ed25519"

git push -u origin main
echo "GitHub repository and read-only cross-repo deploy key are configured."
echo "Run CI with: gh workflow run ci.yml --repo $RELEASE_REPO"
