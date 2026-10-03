# Iteration 3 evidence

## Focused onboarding UI gate

The exact required command was rerun after hardening the runner:

```sh
cd ios && ./scripts/run-ui-tests.sh OnboardingTests
```

Result: **PASS** — 10 tests, 0 failures, on the iPhone 17 Pro Max simulator.

The runner now permits two complete `xcodebuild` attempts by default. If an
iOS Simulator runtime transiently terminates XCUITest with `signal kill`, the
selected simulator is restarted and the complete invocation is retried. The
final attempt's exit status is returned, so persistent failures remain visible.
Use `UI_TEST_ATTEMPTS=1` for a strict single-run diagnostic.

Result artifact:

```text
ios/build/Logs/Test/Test-BankOfDad-2026.10.02_19-20-11--0700.xcresult
```

## App Store Connect verification prerequisite

No App Store Connect API key is configured in this environment:

- `ASC_KEY_PATH`, `ASC_KEY_ID`, and `ASC_ISSUER_ID` are unset.
- `$HOME/.appstoreconnect/private_keys` contains no key file.
- The available Safari App Store Connect window does not expose a usable
  authenticated read-only session.

The release script already supports an API-key path through the documented
`ASC_KEY_PATH`, `ASC_KEY_ID`, and `ASC_ISSUER_ID` variables. Until an
authenticated read-only session or those credentials are made available, the
Inspector cannot independently verify the uploaded build's live processing
state, persisted beta metadata, or external-testing group readiness. No build,
group, or Beta App Review submission state was changed during this iteration.
