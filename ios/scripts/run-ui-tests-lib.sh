#!/usr/bin/env bash

extract_simulator_id() {
  local destination="${1:-}"
  if [[ "$destination" =~ (^|,)id=([^,[:space:]]+)($|,) ]]; then
    printf '%s\n' "${BASH_REMATCH[2]}"
  fi
}

is_retryable_ui_failure() {
  local output="${1:-}"
  [[ "$output" =~ (XCUITest|test[[:space:]]runner|IDETestOperationsObserverErrorDomain).*(signal[[:space:]]+kill|signal[[:space:]]+SIGKILL|killed|crash|crashed) ]] ||
    [[ "$output" =~ (signal[[:space:]]+kill|signal[[:space:]]+SIGKILL).*(XCUITest|test[[:space:]]+runner|IDETestOperationsObserverErrorDomain) ]]
}
