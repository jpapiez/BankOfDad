#!/usr/bin/env bash
# Create or update the Azure resources in main.bicep, then push and start the app with update.sh.
# Safe to re-run. Settings come from environment variables; see deploy/azure/README.md.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
rg=${AZ_RESOURCE_GROUP:-rg-bankofdad}
location=${AZ_LOCATION:-westus2}
deployment=${AZ_DEPLOYMENT_NAME:-bankofdad}

die() { echo "deploy.sh: $*" >&2; exit 1; }

ssh_key=${SSH_PUBLIC_KEY:-}
if [[ -z $ssh_key ]]; then
  key_file=${SSH_PUBLIC_KEY_FILE:-$HOME/.ssh/id_ed25519.pub}
  [[ -f $key_file ]] || die "set SSH_PUBLIC_KEY or SSH_PUBLIC_KEY_FILE (no $key_file)"
  ssh_key=$(<"$key_file")
fi

az group create -n "$rg" -l "$location" -o none
echo "Deploying infrastructure to $rg ($location)..."
az deployment group create -g "$rg" -n "$deployment" -f "$here/main.bicep" -o none \
  -p namePrefix="${AZ_NAME_PREFIX:-bankofdad}" \
     vmSize="${AZ_VM_SIZE:-Standard_B2ats_v2}" \
     osImageSku="${AZ_OS_IMAGE_SKU:-server}" \
     sshPublicKey="$ssh_key" \
     backupRetentionDays="${BACKUP_RETENTION_DAYS:-30}"

exec "$here/update.sh"
