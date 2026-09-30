#!/usr/bin/env bash
# Push the deploy/ compose stack and its settings to the Azure VM and (re)start it.
# Uses `az vm run-command`, so no SSH or open ports are needed. Settings come from environment
# variables; see deploy/azure/README.md. Run after deploy.sh has created the VM (deploy.sh calls this).
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
deploy_dir=$(dirname "$here")
rg=${AZ_RESOURCE_GROUP:-rg-bankofdad}
deployment=${AZ_DEPLOYMENT_NAME:-bankofdad}

die() { echo "update.sh: $*" >&2; exit 1; }
command -v jq >/dev/null || die "jq is required"

outputs=$(az deployment group show -g "$rg" -n "$deployment" --query properties.outputs -o json) \
  || die "no '$deployment' deployment in resource group '$rg'; run deploy.sh first"
vm=$(jq -r .vmName.value <<<"$outputs")
account=$(jq -r .backupStorageAccount.value <<<"$outputs")
container=$(jq -r .backupContainer.value <<<"$outputs")

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
bundle=$work/bundle
mkdir -p "$bundle"
cp "$deploy_dir/docker-compose.yml" "$deploy_dir/tailscale/serve.json" "$here"/vm/* "$bundle/"

# NAME=value from the environment, or the default (which matches deploy/docker-compose.yml).
setting() {
  local value
  value=$(printenv "$1" || true)
  value=${value:-${2:-}}
  [[ $value != *$'\n'* ]] || die "$1 must be a single line"
  printf '%s=%s\n' "$1" "$value"
}
{
  setting TS_HOSTNAME bankofdad
  setting TS_AUTHKEY
  setting TS_EXTRA_ARGS
  setting BANKOFDAD_IMAGE ghcr.io/jpapiez/bankofdad-api:latest
  setting API_LOCAL_PORT 8080
  setting POSTGRES_USER bankofdad
  setting POSTGRES_DB bankofdad
  setting APPLE_CLIENT_ID com.example.bankofdad
  setting APNS_KEY_ID
  setting APNS_TEAM_ID
  setting APNS_BUNDLE_ID com.example.bankofdad
  setting APNS_USE_SANDBOX true
  printf 'BACKUP_STORAGE_ACCOUNT=%s\nBACKUP_CONTAINER=%s\n' "$account" "$container"
} > "$bundle/settings.env"

if [[ -n ${APNS_KEY_FILE:-} ]]; then
  cp "$APNS_KEY_FILE" "$bundle/AuthKey.p8"
fi
# Only needed if BANKOFDAD_IMAGE points at a private registry image.
if [[ -n ${GHCR_TOKEN:-} ]]; then
  printf '%s\n%s\n' "${GHCR_USER:?Set GHCR_USER with GHCR_TOKEN}" "$GHCR_TOKEN" > "$bundle/ghcr.env"
fi

payload=$(COPYFILE_DISABLE=1 tar --no-xattrs -C "$bundle" -czf - . | base64 | tr -d '\n')
script="set -e; d=\$(mktemp -d); trap 'rm -rf \"\$d\"' EXIT; echo '$payload' | base64 -d | tar -xzf - -C \"\$d\" 2>/dev/null; bash \"\$d/apply.sh\""

echo "Updating $vm in $rg (this takes a few minutes on a new VM)..."
result=$(az vm run-command invoke -g "$rg" -n "$vm" --command-id RunShellScript --scripts "$script" -o json)
message=$(jq -r '.value[0].message' <<<"$result")
echo "$message"
grep -q BANKOFDAD_APPLY_OK <<<"$message" || die "the update did not complete; see the output above"
