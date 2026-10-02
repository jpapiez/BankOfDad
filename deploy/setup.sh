#!/bin/sh
set -eu

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

command -v docker >/dev/null 2>&1 || die "docker is required"
command -v openssl >/dev/null 2>&1 || die "openssl is required"
command -v curl >/dev/null 2>&1 || die "curl is required"
docker compose version >/dev/null 2>&1 || die "the Docker Compose plugin is required"

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$script_dir"

public_base_url=${1:-${PUBLIC_BASE_URL:-}}
[ -n "$public_base_url" ] || die "usage: ./setup.sh https://bankofdad.example (private http:// hosts are also supported)"
public_base_url=${public_base_url%/}

case "$public_base_url" in
  https://*|http://*) ;;
  *) die "the public base URL must start with https:// or http://" ;;
esac

[ -f .env ] || cp .env.example .env
chmod 600 .env
mkdir -p secrets
chmod 700 secrets

read_value() {
  key=$1
  value=$(grep "^${key}=" .env | tail -n 1 | cut -d= -f2- || true)
  printf '%s' "$value"
}

set_value() {
  key=$1
  value=$2
  temp_file=".env.tmp.$$"
  awk -v key="$key" -v value="$value" '
    BEGIN { found = 0 }
    index($0, key "=") == 1 {
      if (!found) print key "=" value
      found = 1
      next
    }
    { print }
    END { if (!found) print key "=" value }
  ' .env > "$temp_file"
  chmod 600 "$temp_file"
  mv "$temp_file" .env
}

ensure_secret() {
  key=$1
  bytes=$2
  current=$(read_value "$key")
  if [ -z "$current" ]; then
    current=$(openssl rand -hex "$bytes")
    set_value "$key" "$current"
  fi
  printf '%s' "$current"
}

set_value PUBLIC_BASE_URL "$public_base_url"
ensure_secret POSTGRES_PASSWORD 32 >/dev/null
ensure_secret JWT_SIGNING_KEY 48 >/dev/null
setup_code=$(ensure_secret SETUP_CODE 12)

printf 'Starting Bank of Dad...\n'
docker compose up -d

local_port=$(read_value API_LOCAL_PORT)
[ -n "$local_port" ] || local_port=8080
health_url="http://127.0.0.1:${local_port}/health"
descriptor_url="http://127.0.0.1:${local_port}/.well-known/bankofdad"

attempt=1
while [ "$attempt" -le 60 ]; do
  if curl --fail --silent --show-error "$health_url" >/dev/null 2>&1; then
    break
  fi
  if [ "$attempt" -eq 60 ]; then
    docker compose ps
    die "the API did not become healthy; inspect docker compose logs api"
  fi
  sleep 2
  attempt=$((attempt + 1))
done

descriptor=$(curl --fail --silent --show-error "$descriptor_url") || die "the server descriptor is not available"
printf '%s' "$descriptor" | grep -F "\"origin\":\"${public_base_url}\"" >/dev/null ||
  die "the running server did not report the configured public base URL"

printf '\nBank of Dad is ready at:\n  %s\n' "$public_base_url"
if printf '%s' "$descriptor" | grep -F '"setupState":"uninitialized"' >/dev/null; then
  printf '\nOpen that address and enter this one-time setup code:\n  %s\n\n' "$setup_code"
else
  printf '\nThis server is already connected to a family; its setup code is inactive.\n\n'
fi
