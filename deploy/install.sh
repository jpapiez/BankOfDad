#!/usr/bin/env bash
# Installs or updates the Bank of Dad home server (see deploy/README.md):
#
#   curl -fsSL https://raw.githubusercontent.com/jpapiez/BankOfDad/main/deploy/install.sh | bash
#
# Downloads the compose stack into $BANKOFDAD_DIR, generates secrets on first run, asks for a
# Tailscale auth key, and starts the stack. Re-runs keep the existing .env and update the stack.
# Back up the database before updating; image updates can apply migrations.
#
# Optional environment variables:
#   BANKOFDAD_DIR   install directory (default: ~/bankofdad)
#   BANKOFDAD_REF   git branch, tag or commit to download the stack from (default: main)
#   BANKOFDAD_PORT  loopback port for the API on first install (default: 8080);
#                   existing installs use API_LOCAL_PORT in .env
#   TS_AUTHKEY      Tailscale auth key; skips the prompt on first install
#   TS_HOSTNAME     Tailscale node name (default: bankofdad)
#   TS_EXTRA_ARGS   extra `tailscale up` flags, e.g. --advertise-tags=tag:bankofdad
set -euo pipefail

REPO=jpapiez/BankOfDad

say() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

DOCKER=()
STAGING_DIR=""
docker_cmd() { "${DOCKER[@]}" "$@"; }

cleanup() {
  if [[ -n $STAGING_DIR ]]; then
    rm -f -- "$STAGING_DIR/docker-compose.yml" "$STAGING_DIR/serve.json" \
      "$STAGING_DIR/.env.example" "$STAGING_DIR/.env"
    rmdir -- "$STAGING_DIR"
  fi
}

detect_docker() {
  if docker info >/dev/null 2>&1; then
    DOCKER=(docker)
  elif command -v sudo >/dev/null && sudo docker info >/dev/null; then
    DOCKER=(sudo docker)
  else
    die "cannot talk to Docker. Is it running? (sudo systemctl enable --now docker)"
  fi
}

random_secret() {
  if command -v openssl >/dev/null; then
    openssl rand -hex 32
  else
    head -c 32 /dev/urandom | od -An -v -tx1 | tr -d ' \n'
  fi
}

check_prerequisites() {
  case "$(uname -s)" in
    Linux) ;;
    *) die "this installer supports Linux only (found $(uname -s))." ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64|aarch64|arm64) ;;
    *) die "a 64-bit OS is required (found $(uname -m)). On a Raspberry Pi, use Raspberry Pi OS 64-bit." ;;
  esac
  command -v curl >/dev/null || die "curl is required."
  command -v docker >/dev/null || die "Docker is required: https://docs.docker.com/engine/install/"
  detect_docker
  docker_cmd compose version >/dev/null 2>&1 \
    || die "the Docker Compose plugin is required: https://docs.docker.com/compose/install/linux/"
}

download() {
  local base=$1 path=$2 dest=$3
  curl -fsSL --connect-timeout 10 --max-time 120 "$base/$path" -o "$dest" \
    || die "failed to download $base/$path"
}

prompt_authkey() {
  if [[ -n ${TS_AUTHKEY:-} ]]; then
    printf '%s' "$TS_AUTHKEY"
    return
  fi
  # stdin is the script itself when piped from curl, so ask on the terminal.
  { : </dev/tty; } 2>/dev/null || die "no terminal to prompt on. Re-run with TS_AUTHKEY=tskey-... set."
  local key
  {
    echo
    echo "A Tailscale auth key is needed for the server's first login."
    echo "Create one at https://login.tailscale.com/admin/settings/keys (see deploy/README.md, step 1)."
  } >/dev/tty
  read -rsp "Tailscale auth key: " key </dev/tty
  echo >/dev/tty
  [[ $key == tskey-* ]] || die "that doesn't look like a Tailscale auth key (expected tskey-...)."
  printf '%s' "$key"
}

valid_port() { [[ $1 =~ ^[1-9][0-9]{0,4}$ ]] && (( $1 <= 65535 )); }

# Compose treats an unset or empty API_LOCAL_PORT as 8080.
env_port() {
  local value
  value=$(sed -n -E '/^[[:space:]]*(export[[:space:]]+)?API_LOCAL_PORT[[:space:]]*=/{s/^[^=]*=//;s/[[:space:]]+#.*$//;p;}' "$1" \
    | tail -n 1 | tr -d "\"'\r[:space:]")
  printf '%s' "${value:-8080}"
}

# Anything accepting connections on 127.0.0.1:port blocks Docker from publishing it there.
port_in_use() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }

# On re-runs the port is legitimately held by this stack's own netns container.
stack_publishes_port() {
  local dir=$1 port=$2 binding
  [[ -f $dir/docker-compose.yml ]] || return 1
  binding=$(cd "$dir" && docker_cmd compose port netns 8080 2>/dev/null) || return 1
  [[ ${binding##*:} == "$port" ]]
}

check_port() {
  local dir=$1 port=$2 fix=$3
  stack_publishes_port "$dir" "$port" && return 0
  port_in_use "$port" || return 0
  die "port $port on 127.0.0.1 is already in use by another program (find it with: sudo ss -ltnp 'sport = :$port'). $fix"
}

write_env() {
  local env_file=$1 port=$2 authkey db_password jwt_key
  authkey=$(prompt_authkey)
  [[ $authkey == tskey-* && $authkey != *$'\n'* && $authkey != *$'\r'* ]] \
    || die "that doesn't look like a single-line Tailscale auth key (expected tskey-...)."
  db_password=$(random_secret) || die "could not generate the database password."
  jwt_key=$(random_secret) || die "could not generate the JWT signing key."
  [[ $db_password =~ ^[a-f0-9]{64}$ && $jwt_key =~ ^[a-f0-9]{64}$ ]] \
    || die "secret generation did not return 32 random bytes."
  (
    umask 077
    {
      echo "# Generated by install.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ). Keep private; back it up with the database."
      echo "POSTGRES_USER=bankofdad"
      echo "POSTGRES_PASSWORD=$db_password"
      echo "POSTGRES_DB=bankofdad"
      echo "JWT_SIGNING_KEY=$jwt_key"
      echo "TS_AUTHKEY=$authkey"
      echo "TS_HOSTNAME=${TS_HOSTNAME:-bankofdad}"
      echo "TS_EXTRA_ARGS=${TS_EXTRA_ARGS:-}"
      echo "BANKOFDAD_IMAGE=ghcr.io/jpapiez/bankofdad-api:latest"
      echo "API_LOCAL_PORT=$port"
      echo "APNS_KEY_ID="
      echo "APNS_TEAM_ID="
      echo "APNS_BUNDLE_ID=com.example.bankofdad"
      echo "APNS_USE_SANDBOX=true"
    } >"$env_file"
  )
}

wait_for_health() {
  local port=$1 health
  for _ in $(seq 60); do
    if health=$(curl -fsS --max-time 2 "http://127.0.0.1:$port/health" 2>/dev/null) && [[ $health == Healthy ]]; then
      return 0
    fi
    sleep 2
  done
  return 1
}

tailscale_url() {
  local status url rest
  status=$(docker_cmd compose exec -T tailscale tailscale serve status 2>/dev/null) || return 1
  while read -r url rest; do
    if [[ $url =~ ^https://[a-zA-Z0-9.-]+\.ts\.net(:443)?/?$ ]]; then
      printf '%s\n' "${url%/}"
      return 0
    fi
  done <<<"$status"
  return 1
}

main() {
  local dir=${BANKOFDAD_DIR:-$HOME/bankofdad}
  local ref=${BANKOFDAD_REF:-main}
  local base="https://raw.githubusercontent.com/$REPO/$ref/deploy"

  check_prerequisites

  if [[ -e $dir/.env || -L $dir/.env ]]; then
    [[ -f $dir/.env && -s $dir/.env ]] \
      || die "$dir/.env exists but is empty or not a regular file. Restore it from backup; it will not be overwritten."
  fi

  local port requested=${BANKOFDAD_PORT:-}
  [[ -z $requested ]] || valid_port "$requested" \
    || die "BANKOFDAD_PORT must be a port number from 1 to 65535 (got '$requested')."
  if [[ -s $dir/.env ]]; then
    port=$(env_port "$dir/.env")
    valid_port "$port" || die "API_LOCAL_PORT in $dir/.env is not a valid port ('$port')."
    [[ -z $requested || $requested == "$port" ]] \
      || die "this install uses port $port from $dir/.env; BANKOFDAD_PORT only applies to first installs. Set API_LOCAL_PORT=$requested in $dir/.env and re-run."
    check_port "$dir" "$port" "Free it, or set API_LOCAL_PORT to a free port in $dir/.env and re-run."
  else
    port=${requested:-8080}
    check_port "$dir" "$port" "Free it, or re-run with a free port: curl -fsSL https://raw.githubusercontent.com/$REPO/$ref/deploy/install.sh | BANKOFDAD_PORT=8090 bash"
  fi

  say "Installing into $dir (from $REPO@$ref)"
  mkdir -p "$dir/tailscale" "$dir/secrets"
  dir=$(cd "$dir" && pwd -P)
  STAGING_DIR=$(mktemp -d "$dir/.install.XXXXXX")
  trap cleanup EXIT
  download "$base" docker-compose.yml "$STAGING_DIR/docker-compose.yml"
  download "$base" tailscale/serve.json "$STAGING_DIR/serve.json"
  download "$base" .env.example "$STAGING_DIR/.env.example"

  if [[ -s $dir/.env ]]; then
    say "Keeping existing $dir/.env"
    say "Updating may apply database migrations. Backup guidance: https://github.com/$REPO/blob/$ref/deploy/README.md#backups"
  else
    write_env "$STAGING_DIR/.env" "$port"
    # Publish the complete private file without replacing a concurrently created .env.
    ln -- "$STAGING_DIR/.env" "$dir/.env"
    say "Wrote $dir/.env with generated database and JWT secrets"
  fi
  mv -- "$STAGING_DIR/docker-compose.yml" "$dir/docker-compose.yml"
  mv -- "$STAGING_DIR/serve.json" "$dir/tailscale/serve.json"
  mv -- "$STAGING_DIR/.env.example" "$dir/.env.example"

  cd "$dir"
  say "Pulling images"
  docker_cmd compose pull --quiet
  say "Starting the stack"
  docker_cmd compose up -d db netns api \
    || die "could not start the stack (see the Docker error above). If port $port is taken, free it or change API_LOCAL_PORT in $dir/.env, then re-run."
  # A replaced single-file bind mount otherwise keeps the old inode in a running container.
  docker_cmd compose up -d --force-recreate --no-deps tailscale

  local binding
  binding=$(docker_cmd compose port netns 8080)
  port=${binding##*:}
  [[ $port =~ ^[0-9]+$ ]] || die "could not determine the API's published port."
  say "Waiting for the API to become healthy"
  wait_for_health "$port" \
    || die "the API is not healthy after 60 attempts. Check: cd '$dir' && docker compose logs api"
  say "API healthy on http://127.0.0.1:$port/health"

  local url=""
  for _ in $(seq 30); do
    url=$(tailscale_url || true)
    [[ -n $url ]] && break
    sleep 2
  done
  if [[ -n $url ]]; then
    say "Done. Verify from a device on your tailnet: $url/health"
    echo "    Set API_BASE_URL = https:/\$()/${url#https://} in ios/Config/Local.xcconfig (see deploy/README.md)."
  else
    die "Tailscale Serve is not ready. Check: cd '$dir' && docker compose logs tailscale. If it needs login, set a fresh TS_AUTHKEY in $dir/.env and re-run."
  fi
}

# Everything runs from here, so a partially downloaded script does nothing.
main "$@"
