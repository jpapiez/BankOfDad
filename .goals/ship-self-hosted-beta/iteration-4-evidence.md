# Iteration 4 evidence

## Quality gates

All required local gates were rerun against the current worktree:

| Gate | Result |
|---|---|
| `dotnet restore backend/BankOfDad.slnx` | **PASS** — all projects up to date |
| Release backend build with warnings as errors | **PASS** — 0 warnings, 0 errors |
| `dotnet test backend/BankOfDad.slnx --configuration Release --no-build` | **PASS** — 77 tests |
| `docker compose build && docker compose up -d && curl -fsS http://localhost:8080/health` | **PASS** — `Healthy` |
| `cd ios && xcodegen generate` | **PASS** |
| iOS simulator unit tests on iPhone 17 Pro Max | **PASS** — 36 tests |
| `cd ios && ./scripts/run-ui-tests.sh OnboardingTests` | **PASS** — 10 tests, 0 failures |
| `cd ios && ./scripts/run-ui-tests.sh` | **PASS** — 71 tests, 0 failures on retry attempt 2 |
| `cd ios && UPLOAD=0 ./scripts/testflight.sh` | **PASS** — signed Release export `20261003.0402` |

Result bundles:

```text
ios/build/Logs/Test/Test-BankOfDad-2026.10.02_20-33-49--0700.xcresult
ios/build/Logs/Test/Test-BankOfDad-2026.10.02_20-37-06--0700.xcresult
```

The complete UI runner's first attempt stopped during
`NewLoanTests/testPreviewAndCreateASimpleLoan`; its built-in retry reset the
simulator and the second complete attempt passed all 71 tests. The command
returned success and no product changes were made for the transient failure.

## TestFlight upload attempt

The release script was also run with upload enabled:

```text
cd ios && ./scripts/testflight.sh
```

It archived build `20261003.0332` but export/upload stopped before delivery:

```text
error: exportArchive Failed to Use Accounts
App Store Connect access for “ZPKA84F3TY” is required.
```

The signed export gate remains independently verified by build `20261003.0402`,
but this environment has no usable App Store Connect API key or authenticated
read-only web session:

- `ASC_KEY_PATH`, `ASC_KEY_ID`, and `ASC_ISSUER_ID` are unset.
- `$HOME/.appstoreconnect/private_keys` does not exist.
- The available App Store Connect Safari window exposes neither a verified URL
  nor an accessibility tree, so its live contents cannot be safely inferred.

Consequently, this iteration cannot safely claim that a new build was
delivered, processed, selectable for the intended external group, or carrying
the saved beta metadata. No build/group selection, metadata, or Beta App
Review submission state was changed.
