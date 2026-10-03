# Inspector Feedback — Iteration 3

## Verdict: FAIL

## Acceptance Criteria Check

- [x] The self-hosted onboarding implementation is complete and preserves the existing offline Explore Demo and production behavior — verified by 77 passing backend tests, 36 passing iOS unit tests, 10 passing focused onboarding tests, and all 71 tests passing in the complete UI suite.
- [x] Backend Release build with warnings-as-errors and all backend tests pass — independently reran restore, the exact Release build, and tests: 0 warnings, 0 errors, 77 tests passed.
- [x] The Docker image builds, the stack starts, and `http://localhost:8080/health` returns success — independently reran the required build/start/health gate after cleaning up a collision caused by concurrent Inspector commands; curl returned `Healthy`.
- [x] iOS project generation, simulator unit tests, focused onboarding UI tests, and the complete iOS UI suite pass on iPhone 17 Pro Max — independently verified project generation, 36 unit tests, 10/10 focused tests, and 71/71 complete-suite tests. An injected first-attempt `Test crashed with signal kill` failure reset the simulator and passed all 10 focused tests on attempt 2; a persistent invalid-option probe exhausted both attempts and returned non-zero.
- [x] The TestFlight release script completes a signed Release archive/export without undefined variables or stale hardwired-server assumptions — `bash -n` passed and `UPLOAD=0 ./scripts/testflight.sh` exported version `1.0` build `20261003.0918`. The IPA is Apple Distribution-signed for `com.jpapiez.bankofdad`, with `beta-reports-active=true` and `get-task-allow=false`.
- [x] Product code, tests, deployment helpers, and directly related documentation are committed and pushed to the current branch — the configured upstream is the latest Builder commit `6d4a8579b8c2950821543a6242b9f6a0e0543687` and contains the product implementation and evidence. Before this inspection, only the prior Inspector commit was local and ahead of upstream.
- [x] A new TestFlight build newer than 2209 is uploaded successfully and confirmed in App Store Connect processing or available state — independently reread the retained authenticated Xcode delivery log. Build `20261002.2202` has empty error and warning arrays, reports `state: PROCESSING`, and ends with `UPLOAD SUCCEEDED with no errors`.
- [ ] The new build is ready to be selected for external testing and Beta App Review using the saved self-hosting and offline-demo review metadata — FAILED: current live build selectability, external-group readiness, and persisted beta description/review notes remain independently unverifiable. Microsoft Edge is running on a Diablo 4 guide and exposes neither a verified URL nor a web accessibility tree; Safari likewise exposes neither. No App Store Connect API credentials or default key directory are available.

## Quality Gate

- Command: `dotnet restore backend/BankOfDad.slnx`
  - Result: PASS
- Command: `dotnet build backend/BankOfDad.slnx --configuration Release --no-restore -p:TreatWarningsAsErrors=true "-p:WarningsNotAsErrors=NU1901%3BNU1902%3BNU1903%3BNU1904"`
  - Result: PASS — 0 warnings, 0 errors.
- Command: `dotnet test backend/BankOfDad.slnx --configuration Release --no-build`
  - Result: PASS — 77 tests passed.
- Command: `docker compose build && docker compose up -d && curl -fsS http://localhost:8080/health`
  - Result: PASS — curl returned `Healthy`. The first attempt collided with the focused UI command because both Inspector commands concurrently recreated the same Compose container; the isolated rerun passed.
- Command: `cd ios && xcodegen generate`
  - Result: PASS
- Command: `cd ios && xcodebuild test -project BankOfDad.xcodeproj -scheme BankOfDad -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -skip-testing:BankOfDadUITests CODE_SIGNING_ALLOWED=NO`
  - Result: PASS — 36 tests passed, 0 failures.
- Command: `cd ios && ./scripts/run-ui-tests.sh OnboardingTests`
  - Result: PASS on attempt 1 — 10 tests passed, 0 failures.
- Signal-kill retry probe: injected `Test crashed with signal kill` on attempt 1.
  - Result: PASS — the runner reset the selected simulator and attempt 2 passed all 10 tests.
- Persistent-failure probe: passed an invalid `xcodebuild` option on both attempts.
  - Result: PASS — both attempts ran and the script returned status 1, so persistent failures are not hidden.
- Command: `cd ios && ./scripts/run-ui-tests.sh`
  - Result: PASS on attempt 1 — 71 tests passed, 0 failures.
- Command: `cd ios && UPLOAD=0 ./scripts/testflight.sh`
  - Result: PASS — exported signed version `1.0` build `20261003.0918`.
- Local quality gates: **PASS**
- Goal result: **FAIL** because the final live App Store Connect readiness criterion is not independently verifiable.

## Release / Live-State Verification

- The retained `ContentDelivery.log` independently proves build `20261002.2202` was accepted by App Store Connect in `PROCESSING` state with no upload errors or warnings.
- Repository metadata contains the intended self-hosting and offline Explore Demo beta description and review notes, but repository text does not prove that the live App Store Connect fields persisted.
- Microsoft Edge is available at `/Applications/Microsoft Edge.app`; its active window title is `Firewall Sorc - Diablo 4 Sorcerer Build Guide`. The background inspection interface reports a missing fail-closed URL and no web accessibility tree, so no page content or authentication state can be safely inferred.
- Safari's `App Store Connect` window also reports a missing fail-closed URL and no web accessibility tree.
- `ASC_KEY_PATH`, `ASC_KEY_ID`, and `ASC_ISSUER_ID` are unset, and `$HOME/.appstoreconnect/private_keys` does not exist.
- No App Store Connect navigation or mutation was performed. Beta App Review was not submitted, and build/group selection and metadata were not changed.

## Issues Found

1. **Current external-testing readiness is not independently evidenced.** The retained upload log proves processing at upload time but cannot show that build `20261002.2202` is currently selectable for the intended external group.
2. **Persisted live beta metadata is not independently evidenced.** The intended self-hosting and offline-demo copy exists in the repository, but the live beta description and review notes cannot be read from the available browser sessions or an API.
3. **The available Edge session is not usable for read-only App Store Connect verification.** It is on a Diablo 4 guide and exposes neither a verified URL nor an accessibility tree. Safari has the same fail-closed inspection limitation.

## What Must Be Fixed

1. Provide a safely usable authenticated, read-only App Store Connect session or transient API-key environment.
2. Without changing selection, verify build `20261002.2202` is currently selectable for the intended external testing group.
3. Without changing metadata, verify the live beta description and review notes contain the saved self-hosting and offline Explore Demo guidance.
4. Continue to leave Beta App Review unsubmitted and do not alter build/group selection or metadata.
