#!/usr/bin/env bash
# Database backups to Blob storage, authenticated with the VM's managed identity (no storage keys).
#   backup.sh                   dump the database and upload it (run nightly by bankofdad-backup.timer)
#   backup.sh list              list backups, oldest first
#   backup.sh restore <name>    replace the database with a backup; <name> may be "latest"
set -euo pipefail

app=/opt/bankofdad
cd "$app"

setting() { grep -E "^$1=" .env | tail -n 1 | cut -d= -f2-; }
account=$(setting BACKUP_STORAGE_ACCOUNT)
container=$(setting BACKUP_CONTAINER)
[[ -n $account && -n $container ]] || { echo "BACKUP_STORAGE_ACCOUNT and BACKUP_CONTAINER must be set in $app/.env" >&2; exit 1; }
base="https://$account.blob.core.windows.net/$container"

token() {
  curl -fsS -H Metadata:true \
    'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fstorage.azure.com%2F' \
    | jq -r .access_token
}
blob() { curl -fsS -H "Authorization: Bearer $(token)" -H 'x-ms-version: 2023-11-03' "$@"; }
list() { blob "$base?restype=container&comp=list" | grep -o '<Name>[^<]*</Name>' | sed -e 's/<Name>//' -e 's#</Name>##' | sort; }

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

case ${1:-backup} in
  backup)
    docker compose exec -T db sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' > "$tmp"
    name="bankofdad-$(date -u +%Y%m%dT%H%M%SZ).dump"
    blob -X PUT -H 'x-ms-blob-type: BlockBlob' -H 'Content-Type: application/octet-stream' --data-binary @"$tmp" "$base/$name"
    echo "Uploaded $name ($(stat -c %s "$tmp") bytes)"
    ;;
  list)
    list
    ;;
  restore)
    name=${2:?Usage: backup.sh restore <name|latest>}
    [[ $name == latest ]] && name=$(list | tail -n 1)
    [[ $name =~ ^[A-Za-z0-9._-]+$ ]] || { echo "No such backup: '$name'" >&2; exit 1; }
    blob -o "$tmp" "$base/$name"
    docker compose stop api
    docker compose exec -T db sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists --no-owner' < "$tmp"
    docker compose start api
    echo "Restored $name"
    ;;
  *)
    echo "Usage: backup.sh [backup | list | restore <name|latest>]" >&2
    exit 2
    ;;
esac
