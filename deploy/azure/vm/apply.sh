#!/usr/bin/env bash
# Runs as root on the VM, from a bundle pushed by deploy/azure/update.sh through `az vm run-command`.
# Installs the compose stack and settings into /opt/bankofdad and (re)starts it. Safe to re-run.
set -euo pipefail

src=$(cd "$(dirname "$0")" && pwd)
app=/opt/bankofdad

ghcr_logged_in=
cleanup() {
  if [[ -n $ghcr_logged_in ]]; then docker logout ghcr.io >/dev/null 2>&1 || true; fi
  # The Azure agent keeps a copy of every run-command script, and ours embeds this bundle
  # (settings can include TS_AUTHKEY or a GHCR token). Settings stay in $app, readable by root only.
  rm -f /var/lib/waagent/run-command/download/*/script.sh
}
trap cleanup EXIT

# On a new VM, wait for cloud-init to finish installing Docker.
cloud-init status --wait >/dev/null 2>&1 || true
command -v docker >/dev/null || { echo "Docker is missing; check 'cloud-init status --long' on the VM." >&2; exit 1; }

install -d -m 0700 "$app"
install -d -m 0755 "$app/tailscale" "$app/secrets"
install -m 0644 "$src/docker-compose.yml" "$app/docker-compose.yml"
install -m 0644 "$src/serve.json" "$app/tailscale/serve.json"
install -m 0755 "$src/backup.sh" "$app/backup.sh"
install -m 0600 "$src/settings.env" "$app/settings.env"

# Generated once on the VM and never leave it. The Postgres password is fixed when the volume is first created.
if [[ ! -s $app/secrets.env ]]; then
  (umask 077; printf 'POSTGRES_PASSWORD=%s\nJWT_SIGNING_KEY=%s\n' "$(openssl rand -hex 32)" "$(openssl rand -hex 32)" > "$app/secrets.env")
fi
(umask 077; cat "$app/settings.env" "$app/secrets.env" > "$app/.env")

# The API container runs as the .NET image's non-root user (uid 1654).
if [[ -f $src/SignInWithAppleKey.p8 ]]; then
  install -m 0400 -o 1654 -g 1654 "$src/SignInWithAppleKey.p8" "$app/secrets/SignInWithAppleKey.p8"
fi
[[ -s $app/secrets/SignInWithAppleKey.p8 ]] || {
  echo "Sign in with Apple key is missing; set APPLE_KEY_FILE on the first update." >&2
  exit 1
}
if [[ -f $src/AuthKey.p8 ]]; then
  install -m 0400 -o 1654 -g 1654 "$src/AuthKey.p8" "$app/secrets/AuthKey.p8"
fi

if [[ -f $src/ghcr.env ]]; then
  { read -r ghcr_user; read -r ghcr_token; } < "$src/ghcr.env"
  docker login ghcr.io -u "$ghcr_user" --password-stdin <<<"$ghcr_token" >/dev/null
  # Only for this run's pull (see cleanup); don't leave the token in /root/.docker.
  ghcr_logged_in=1
fi

install -m 0644 "$src/bankofdad.service" "$src/bankofdad-backup.service" "$src/bankofdad-backup.timer" /etc/systemd/system/
systemctl daemon-reload
systemctl enable bankofdad.service bankofdad-backup.timer >/dev/null 2>&1
systemctl start bankofdad-backup.timer

cd "$app"
docker compose pull --quiet
docker compose up -d --remove-orphans --quiet-pull 2>&1 | tail -n 5
docker image prune -f >/dev/null

port=$(grep -E '^API_LOCAL_PORT=' .env | tail -n 1 | cut -d= -f2)
health=unreachable
for _ in $(seq 60); do
  if health=$(curl -fsS "http://127.0.0.1:${port:-8080}/health" 2>/dev/null); then break; fi
  health=unreachable
  sleep 2
done
echo "API health: $health"

ts=$(docker compose exec -T tailscale tailscale status --json 2>/dev/null || echo '{}')
state=$(jq -r '.BackendState // "unknown"' <<<"$ts")
echo "Tailscale: $state"
case $state in
  Running) echo "URL: https://$(jq -r '.Self.DNSName' <<<"$ts" | sed 's/\.$//')" ;;
  # Without an auth key the container retries login every minute with a new URL, so a key is required.
  NeedsLogin|NoState) echo "Tailscale is not logged in: set TS_AUTHKEY to a fresh auth key and run update.sh again." ;;
esac

[[ $health == Healthy ]] || { echo "The API is not healthy; check 'docker compose logs api' on the VM." >&2; exit 1; }
echo BANKOFDAD_APPLY_OK
