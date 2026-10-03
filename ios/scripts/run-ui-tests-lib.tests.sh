#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/run-ui-tests-lib.sh"

[[ "$(extract_simulator_id 'platform=iOS Simulator,id=01234567-89AB-CDEF-0123-456789ABCDEF')" == "01234567-89AB-CDEF-0123-456789ABCDEF" ]]
[[ "$(extract_simulator_id 'id=01234567-89AB-CDEF-0123-456789ABCDEF')" == "01234567-89AB-CDEF-0123-456789ABCDEF" ]]
[[ -z "$(extract_simulator_id 'platform=iOS Simulator,name=iPhone 17 Pro Max')" ]]
is_retryable_ui_failure 'Testing failed: The test runner process was killed (signal SIGKILL) during XCUITest execution'
! is_retryable_ui_failure 'Testing failed: XCTAssertEqual failed - expected 1, got 2'
! is_retryable_ui_failure 'xcodebuild: error: Build input file cannot be found'

printf 'run-ui-tests destination parsing passed\n'
