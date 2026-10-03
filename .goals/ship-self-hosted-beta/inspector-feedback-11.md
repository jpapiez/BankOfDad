# Inspector Feedback — Iteration 11

## Verdict: FAIL

## Acceptance Criteria Check

- [x] The self-hosted onboarding implementation is complete and preserves the existing offline Explore Demo and production behavior — verified by source review, 40 iOS unit tests, the 10-test focused onboarding suite, the 8-test focused family suite, and the complete 71-test UI suite. Demo isolation and both configured/unconfigured demo-exit tests still pass.
- [x] Backend Release build with warnings-as-errors and all backend tests pass — exact restore and Release build passed with 0 warnings and 0 errors; the full suite passed 80/80 tests (49 API and 31 domain). The focused Production/legacy-migration run passed 3/3 tests.
- [ ] The Docker image builds, the stack starts, and `http://localhost:8080/health` returns success — FAILED for the exact required gate. `docker compose build` exhausted all five configured v3 restore attempts with `NU1301`, TLS EOF, and exit code 1. A subsequent build with `NUGET_SOURCE=https://www.nuget.org/api/v2` succeeded, and both the normal and overridden-project-name stacks returned `Healthy`, but the exact documented command remains non-reproducible in this environment.
- [x] iOS project generation, simulator unit tests, focused onboarding UI tests, and the complete iOS UI suite pass on iPhone 17 Pro Max — `xcodegen generate` passed; 40 unit tests passed; focused OnboardingTests passed 10/10; focused FamilyTests passed 8/8; the complete suite passed 71/71 on attempt 1. The Builder's “complete suite blocked” status is superseded by this independent successful run.
- [x] The TestFlight release script completes a signed Release archive/export without undefined variables or stale hardwired-server assumptions — `UPLOAD=0 ./scripts/testflight.sh` exported build `20261003.1632`. The exported IPA is signed by Apple Distribution for team `ZPKA84F3TY`, has `beta-reports-active=true`, and has `get-task-allow=false`.
- [x] Product code, tests, deployment helpers, and directly related documentation are committed and pushed to the current branch — local `HEAD`, upstream, and the live remote branch all equal `730a28fe370670d4d5e2d97dd7afc82e6116fbc6`; the worktree was clean before Inspector artifacts. The latest Builder commit's `Assisted-by` line is visible in the message but is separated from the final trailer block by blank lines, so `git %(trailers:only)` recognizes only `Copilot-Session`.
- [x] A new TestFlight build newer than 2209 is uploaded successfully and confirmed in App Store Connect processing or available state — retained authenticated uploader evidence establishes that build `20261002.2202` was accepted with HTTP 200 and reached `PROCESSING` without errors or warnings.
- [ ] The new build is ready to be selected for external testing and Beta App Review using the saved self-hosting and offline-demo review metadata — FAILED: `ASC_KEY_PATH`, `ASC_KEY_ID`, and `ASC_ISSUER_ID` are unset, and no safely usable authenticated App Store Connect session was available. Current build selectability, intended external-group readiness, and persistence of the live beta description/review notes remain independently unverified. No selection, metadata, or Beta App Review submission was changed.

## Explicit Finding Verification

1. **Legacy multi-family upgrade — PASS.** The old migration no longer aborts or deletes families; the new migration records `LegacyMultiFamily`; discovery returns `legacy-multi-family`; bootstrap and server-aware enrollment paths are rejected while existing login remains available. The PostgreSQL migration test preserved both families and passed.
2. **Private IPv6 policy — PASS.** HTTP now uses `inet_pton` and byte-prefix checks for loopback, `fc00::/7`, and `fe80::/10`. Tests accept valid literals and reject public IPv6 plus DNS names such as `fc.example.com`.
3. **Production legacy registration availability — PASS.** The Production integration test confirms `/api/v1/auth/register` returns 404.
4. **Production unconfigured Apple availability — PASS.** The Production integration test confirms `/api/v1/auth/apple` returns 404 when Apple sign-in is not configured.
5. **Child-login rate boundary — PASS.** The child endpoint no longer inherits the general auth limiter; the focused Production test proves requests 1–10 return 200 and request 11 returns 429.
6. **Configured server replacement — PASS by code inspection.** `ConnectServerView` uses `configureServer` only for the initial profile and awaits `switchServer` for replacement. `switchServer` logs out the authenticated session against the old live service, deletes tokens, saves the new profile, replaces services, and marks signed out.
7. **UI retry scope and destination handling — PASS.** Shell tests prove simulator-ID extraction and that only the known XCUITest runner kill/crash signature is retryable; assertion and build failures are non-retryable. The complete suite passed without invoking a retry.
8. **Exact parent invitation payload — PASS.** The existing family UI test reads the UI's accessibility payload, validates `kind=parent`, extracts its token, and redeems that exact token.
9. **Exact child enrollment payload — PASS.** The new family UI test reads `pairingSheet.qr`, validates `kind=child`, extracts its token, and completes child enrollment with that exact token.
10. **Apple-button UI false-positive prevention — PASS.** The onboarding test now waits for the email sign-in control before asserting the Apple control is absent.
11. **Overridden Compose project name — PASS with fallback feed.** `COMPOSE_PROJECT_NAME=custombeta` produced `custombeta-api`; `api-ready` used the same image, all services became healthy, and the health request returned `Healthy`.
12. **NuGet v3 default and retries — PARTIAL/FAILED gate.** The Dockerfile and Compose file correctly default to the standard v3 service index and execute five retries, but all five attempts failed with TLS EOF in the exact build. The documented v2 override succeeded from cache.
13. **Family-scoped installation reset on account deletion — PASS by code inspection and regression suite.** Deletion now selects the installation whose `FamilyId` equals the deleted family and leaves a legacy installation with `FamilyId = null` untouched. Existing account-deletion tests pass, though there is no new dedicated legacy multi-family deletion test.
14. **Enrollment-inspection production rate limit — PASS.** The endpoint has a dedicated 30-per-minute policy and an independent live check returned 401 for requests 1–30 and 429 for request 31.

## Quality Gate

- Command: `dotnet restore backend/BankOfDad.slnx`
  - Result: PASS
- Command: `dotnet build backend/BankOfDad.slnx --configuration Release --no-restore -p:TreatWarningsAsErrors=true "-p:WarningsNotAsErrors=NU1901%3BNU1902%3BNU1903%3BNU1904"`
  - Result: PASS — 0 warnings, 0 errors
- Command: `dotnet test backend/BankOfDad.slnx --configuration Release --no-build`
  - Result: PASS — 80/80
- Focused Production and legacy-migration integration tests
  - Result: PASS — 3/3
- Command: `docker compose build`
  - Result: FAIL — all five v3 restore attempts ended in `NU1301` / TLS unexpected EOF
- Command: `NUGET_SOURCE=https://www.nuget.org/api/v2 docker compose build && docker compose up -d && curl -fsS http://localhost:8080/health`
  - Result: PASS — fallback build succeeded and health returned `Healthy`
- Overridden project-name build/up/readiness/health
  - Result: PASS — `custombeta-api` and `custombeta-api-ready` ran successfully
- Command: `cd ios && xcodegen generate`
  - Result: PASS
- iPhone 17 Pro Max unit command
  - Result: PASS — 40/40
- Focused `OnboardingTests`
  - Result: PASS — 10/10 with v2 Docker feed override
- Focused `FamilyTests`
  - Result: PASS — 8/8
- Complete UI suite
  - Result: PASS — 71/71 on attempt 1
- Command: `cd ios && ./scripts/run-ui-tests-lib.tests.sh`
  - Result: PASS
- Command: `cd ios && UPLOAD=0 ./scripts/testflight.sh`
  - Result: PASS — exported build `20261003.1632`; exported IPA has distribution entitlements
- Command: `git diff --check HEAD~1 HEAD`
  - Result: PASS

## Issues Found

1. **The exact Docker quality gate fails.** The fallback feed demonstrates that the product builds and runs, but the goal explicitly lists the unmodified `docker compose build` command. That command exhausted the newly added retries and failed.
2. **Live App Store Connect readiness remains unverified.** The uploaded build is proven to have reached processing, but current external-group selectability and persisted self-hosting/offline-demo metadata cannot be checked without authenticated read access.
3. **The latest Builder commit has a malformed trailer block.** Blank lines separate `Assisted-by` and `Co-authored-by` from the final recognized trailer block, so Git recognizes only `Copilot-Session`.

## What Must Be Fixed

1. Make the exact documented Docker build gate reproducibly pass in the Inspector environment, without requiring an undeclared command override.
2. Provide safely usable authenticated, read-only App Store Connect access and verify build `20261002.2202` is selectable for the intended external group and that the saved beta description/review notes contain the self-hosting and offline Explore Demo guidance.
3. Continue to leave Beta App Review unsubmitted until the user gives immediate explicit confirmation.
4. Keep required commit trailers in one contiguous parseable trailer block.
