#!/usr/bin/env bash
# Runs the BankOfDadUITests end-to-end suite against the real Docker backend.
#
#   ios/scripts/run-ui-tests.sh                          # whole suite
#   ios/scripts/run-ui-tests.sh OnboardingTests          # one class
#   ios/scripts/run-ui-tests.sh LoansListTests/testStatusFilters
#
# Environment overrides:
#   SIMULATOR_ID     UDID of the simulator to use (default: first available iPhone 17 Pro Max, then any iPhone)
#   DESTINATION      full xcodebuild -destination value (wins over SIMULATOR_ID)
#   NUGET_SOURCE     NuGet v3 feed for the Docker build when api.nuget.org is blocked
#   API_URL          backend URL (default http://localhost:8080)
#   SKIP_BACKEND=1   don't (re)start docker compose; just wait for the API
#   NO_BUILD=1       start compose without --build
#   DERIVED_DATA     xcodebuild derived data path (default ios/build)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_DIR="$(cd "$IOS_DIR/.." && pwd)"
API_URL="${API_URL:-http://localhost:8080}"
DERIVED_DATA="${DERIVED_DATA:-$IOS_DIR/build}"

log() { printf '\n==> %s\n' "$*"; }

if [[ "${SKIP_BACKEND:-0}" != "1" ]]; then
  log "Starting backend (docker compose, test hooks enabled)"
  build_flag="--build"
  [[ "${NO_BUILD:-0}" == "1" ]] && build_flag=""
  (cd "$REPO_DIR" && ASPNETCORE_ENVIRONMENT=Development TEST_HOOKS_ENABLED=true docker compose up -d $build_flag)
fi

log "Waiting for $API_URL/health"
for _ in $(seq 1 60); do
  if [[ "$(curl -fsS "$API_URL/health" 2>/dev/null || true)" == "Healthy" ]]; then break; fi
  sleep 2
done
[[ "$(curl -fsS "$API_URL/health" 2>/dev/null || true)" == "Healthy" ]] || { echo "Backend never became healthy at $API_URL" >&2; exit 1; }

# The suite needs the Development-only hooks; a 404 means they are off, 401 means they are mapped.
hook_status="$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API_URL/api/v1/testing/sweep")"
if [[ "$hook_status" == "404" ]]; then
  echo "Test hooks are disabled on the backend (TEST_HOOKS_ENABLED=true and ASPNETCORE_ENVIRONMENT=Development are required)." >&2
  exit 1
fi

log "Generating Xcode project"
(cd "$IOS_DIR" && xcodegen generate --quiet)

if [[ -z "${DESTINATION:-}" ]]; then
  if [[ -z "${SIMULATOR_ID:-}" ]]; then
    SIMULATOR_ID="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = [d for runtime in json.load(sys.stdin)["devices"].values() for d in runtime if d.get("isAvailable")]
preferred = [d for d in devices if d["name"] == "iPhone 17 Pro Max"] or [d for d in devices if d["name"].startswith("iPhone")]
print(preferred[0]["udid"] if preferred else "")
')"
  fi
  [[ -n "$SIMULATOR_ID" ]] || { echo "No iPhone simulator found; set SIMULATOR_ID or DESTINATION." >&2; exit 1; }
  log "Booting simulator $SIMULATOR_ID"
  xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || true
  xcrun simctl bootstatus "$SIMULATOR_ID" -b >/dev/null
  DESTINATION="id=$SIMULATOR_ID"
fi

only_testing=("-only-testing:BankOfDadUITests")
if [[ $# -gt 0 ]]; then
  only_testing=()
  for filter in "$@"; do only_testing+=("-only-testing:BankOfDadUITests/$filter"); done
fi

log "Running UI tests on $DESTINATION"
# TEST_RUNNER_-prefixed variables are forwarded to the test runner, and API_BASE_URL points the app at the
# same backend. (ATS only allows plain HTTP to localhost/127.0.0.1.) Ad-hoc signing keeps the app's keychain
# entitlements (CODE_SIGNING_ALLOWED=NO breaks the keychain).
cd "$IOS_DIR"
TEST_RUNNER_BANKOFDAD_API_URL="$API_URL" xcodebuild test \
  -project BankOfDad.xcodeproj \
  -scheme BankOfDad \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA" \
  "${only_testing[@]}" \
  API_BASE_URL="$API_URL" \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  ${XCODEBUILD_EXTRA_ARGS:-}
