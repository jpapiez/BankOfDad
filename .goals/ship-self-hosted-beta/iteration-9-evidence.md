# Builder Evidence — Iteration 9

## Product fixes

- Retry in `RootView` now calls `AppEnvironment.bootstrap()`, preserving verified
  server descriptor origin and server-ID checks before auth bootstrap.
- Exiting demo mode now returns to `needsServer` when no server profile exists,
  while configured-server sessions continue to return to `signedOut`.
- The co-parent invitation UI exposes the exact generated QR/share payload to
  the UI test. `FamilyTests.testInviteCoParentProducesAnAcceptableCode` extracts
  the token from that payload and accepts it through the enrollment endpoint;
  it no longer creates a separate API-only invitation.

## Validation

- `cd ios && xcodegen generate` — passed.
- iOS unit tests on iPhone 17 Pro Max — passed: 38 tests.
- `cd ios && ./scripts/run-ui-tests.sh OnboardingTests` — passed: 10 tests.
- `cd ios && ./scripts/run-ui-tests.sh FamilyTests` — passed: 8 tests.
- `cd ios && ./scripts/run-ui-tests.sh` — passed: 71 tests.
- `cd ios && UPLOAD=0 ./scripts/testflight.sh` — passed; signed Release export
  `1.0 (20261003.1101)`.
- `git diff --check` — passed.

The full UI suite was rerun after the invitation test fix; the prior failure was
the test accepting the wrong invitation type, and the rerun passed all 71 tests.
No App Store Connect selection, metadata, or Beta App Review submission was
performed.
