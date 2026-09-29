#!/usr/bin/env bash
# Create or update the Azure resources in main.bicep, then push and start the app with update.sh.
# Safe to re-run. Settings come from environment variables; see deploy/azure/README.md.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
rg=${AZ_RESOURCE_GROUP:-rg-bankofdad}
location=${AZ_LOCATION:-westus2}
deployment=${AZ_DEPLOYMENT_NAME:-bankofdad}

die() { echo "deploy.sh: $*" >&2; exit 1; }

prefix=${AZ_NAME_PREFIX:-bankofdad}
vm_exists=false
if az vm show -g "$rg" -n "$prefix-vm" -o none 2>/dev/null; then
  # customData and the SSH key are fixed at creation; they're ignored from here on.
  vm_exists=true
fi

ssh_key=${SSH_PUBLIC_KEY:-}
if [[ -z $ssh_key && $vm_exists == false ]]; then
  key_file=${SSH_PUBLIC_KEY_FILE:-$HOME/.ssh/id_ed25519.pub}
  [[ -f $key_file ]] || die "set SSH_PUBLIC_KEY or SSH_PUBLIC_KEY_FILE (no $key_file)"
  ssh_key=$(<"$key_file")
fi

az group create -n "$rg" -l "$location" -o none
echo "Deploying infrastructure to $rg ($location)..."
az deployment group create -g "$rg" -n "$deployment" -f "$here/main.bicep" -o none \
  -p namePrefix="$prefix" \
     vmExists="$vm_exists" \
     vmSize="${AZ_VM_SIZE:-Standard_B2ats_v2}" \
     osImageSku="${AZ_OS_IMAGE_SKU:-server}" \
     sshPublicKey="$ssh_key" \
     backupRetentionDays="${BACKUP_RETENTION_DAYS:-30}"

exec "$here/update.sh"
