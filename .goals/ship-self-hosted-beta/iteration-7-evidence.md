# Iteration 7 evidence

## Local quality gates

All required local gates were rerun against the current worktree:

| Gate | Result |
|---|---|
| `dotnet restore backend/BankOfDad.slnx` | **PASS** — all projects up to date |
| `dotnet build backend/BankOfDad.slnx --configuration Release --no-restore -p:TreatWarningsAsErrors=true "-p:WarningsNotAsErrors=NU1901%3BNU1902%3BNU1903%3BNU1904"` | **PASS** — 0 warnings, 0 errors |
| `dotnet test backend/BankOfDad.slnx --configuration Release --no-build` | **PASS** — 77 tests |
| `docker compose build && docker compose up -d && curl -fsS http://localhost:8080/health` | **PASS** — `Healthy` |
| `cd ios && xcodegen generate` | **PASS** |
| `cd ios && xcodebuild test -project BankOfDad.xcodeproj -scheme BankOfDad -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -skip-testing:BankOfDadUITests CODE_SIGNING_ALLOWED=NO` | **PASS** — 36 tests, 0 failures |
| `cd ios && ./scripts/run-ui-tests.sh OnboardingTests` | **PASS** — 10 tests, 0 failures |
| `cd ios && ./scripts/run-ui-tests.sh` | **PASS** — 71 tests, 0 failures |
| `cd ios && UPLOAD=0 ./scripts/testflight.sh` | **PASS** — signed Release export `20261003.0730` |

The exported IPA was checked locally:

- Bundle identifier: `com.jpapiez.bankofdad`
- Marketing version: `1.0`
- Build number: `20261003.0730`
- Distribution entitlements: `beta-reports-active=true`, `get-task-allow=false`

The onboarding and offline-demo acceptance criteria remain covered by the
focused and complete UI suites. No product code or App Store Connect state was
changed during this iteration.

## App Store Connect verification attempt and limitation

The retained authenticated Xcode delivery log still independently proves that
build `20261002.2202` reached App Store Connect processing with HTTP 200, no
errors or warnings, and `UPLOAD SUCCEEDED with no errors`. No new upload was
attempted because the current task requires leaving App Store Connect
selection and submission state untouched.

As required, a live read-only verification attempt was made through the
already-running Microsoft Edge session without navigating or changing
anything. At the supplied attempt time, Edge's active window was a Diablo 4
guide, not App Store Connect. The computer-use accessibility result was:

- Window title: `Firewall Sorc - Diablo 4 Sorcerer Build Guide`
- URL: missing (fail-closed)
- Page accessibility tree: unavailable
- Perception instruction: stop rather than infer page identity or content from
  an unverified screenshot

Therefore the current build's external-testing selectability, intended
external group readiness, and persisted beta description/review notes remain
independently unverifiable. This is an evidence limitation, not a claim that
the live state is ready.

No navigation, click, screenshot inspection, build/group selection, metadata
mutation, or Beta App Review submission was performed. No credentials,
private keys, personal data, real family data, or private server addresses
were added or stored.
