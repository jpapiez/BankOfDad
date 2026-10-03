# Inspector Feedback — Iteration 2

## Verdict: FAIL

## Acceptance Criteria Check

- [x] The self-hosted onboarding implementation is complete and preserves the existing offline Explore Demo and production behavior — verified by the unchanged iteration-1 implementation, 36 passing iOS unit tests, all 71 tests passing in the complete UI suite, and 77 passing backend tests.
- [x] Backend Release build with warnings-as-errors and all backend tests pass — independently reran restore, Release build, and tests: 0 warnings, 0 errors, 77 tests passed.
- [x] The Docker image builds, the stack starts, and `http://localhost:8080/health` returns success — the exact required command passed and returned `Healthy`; an additional uncached build also completed successfully through the hardened NuGet v2 restore.
- [ ] iOS project generation, simulator unit tests, focused onboarding UI tests, and the complete iOS UI suite pass on iPhone 17 Pro Max — FAILED: project generation, 36 unit tests, and the 71-test complete UI suite passed, but the exact focused onboarding command failed twice with the same five tests recorded as `Test crashed with signal kill.`
- [x] The TestFlight release script completes a signed Release archive/export without undefined variables or stale hardwired-server assumptions — `UPLOAD=0 ./scripts/testflight.sh` exported version `1.0` build `20261003.0212`; the IPA is Apple Distribution-signed with `get-task-allow=false` and `beta-reports-active=true`.
- [x] Product code, tests, deployment helpers, and directly related documentation are committed and pushed to the current branch — local HEAD and upstream both resolve to `bdb52c17af4e7ba5ef898c840a07ce979e452010`, with no product-worktree changes before Inspector artifacts.
- [ ] A new TestFlight build newer than 2209 is uploaded successfully and confirmed in App Store Connect processing or available state — FAILED: prior archive evidence supports successful delivery of build `20261002.2202`, but the live App Store Connect session is logged out and no App Store Connect API credential is configured, so the claimed `Ready to Submit` state could not be independently verified.
- [ ] The new build is ready to be selected for external testing and Beta App Review using the saved self-hosting and offline-demo review metadata — FAILED: the repository contains the intended description and review notes, but the logged-out live session prevented independent verification that those values persisted and that the external group/build selection is currently available. No selection or submission state was changed.

## Quality Gate

- Command: `dotnet restore backend/BankOfDad.slnx`
  - Result: PASS
- Command: `dotnet build backend/BankOfDad.slnx --configuration Release --no-restore -p:TreatWarningsAsErrors=true "-p:WarningsNotAsErrors=NU1901%3BNU1902%3BNU1903%3BNU1904"`
  - Result: PASS — 0 warnings, 0 errors.
- Command: `dotnet test backend/BankOfDad.slnx --configuration Release --no-build`
  - Result: PASS — 77 tests passed.
- Command: `docker compose build && docker compose up -d && curl -fsS http://localhost:8080/health`
  - Result: PASS — image built, PostgreSQL and API became healthy, the readiness barrier completed, and curl returned `Healthy`.
- Additional check: `docker compose build --no-cache`
  - Result: PASS — NuGet v2 restored all projects from an uncached layer and the Release image published successfully.
- Command: `cd ios && xcodegen generate`
  - Result: PASS
- Command: `cd ios && xcodebuild test -project BankOfDad.xcodeproj -scheme BankOfDad -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -skip-testing:BankOfDadUITests CODE_SIGNING_ALLOWED=NO`
  - Result: PASS — 36 tests passed.
- Command: `cd ios && ./scripts/run-ui-tests.sh OnboardingTests`
  - Result: FAIL on two independent runs — each run completed only 5 of 10 tests successfully. The same five tests crashed with signal kill:
    - `testCoParentJoinsWithAnEnrollmentLink()`
    - `testEnrollmentDeepLinkWhileOnChildLoginScreen()`
    - `testKidCompletesPINEnrollment()`
    - `testParentCreatesAccountThroughTheForm()`
    - `testParentSignsInWithEmailAndPassword()`
- Command: `cd ios && ./scripts/run-ui-tests.sh`
  - Result: PASS — all 71 tests passed with 0 failures.
- Command: `cd ios && UPLOAD=0 ./scripts/testflight.sh`
  - Result: PASS — exported Apple Distribution-signed version `1.0` build `20261003.0212`.
- Overall result: **FAIL**

## Release / Live-State Verification

- The current export proves the release script can archive, sign, and export the self-hosted app without stale server configuration.
- The exact Docker gate and a no-cache Docker build both pass after the NuGet retry hardening.
- Safari's App Store Connect page was at `https://appstoreconnect.apple.com/login`; the passkey control could not be safely completed in the background, and there were no configured `ASC_KEY_PATH`, `ASC_KEY_ID`, or `ASC_ISSUER_ID` values or default private-key directory.
- Consequently, build `20261002.2202` status, persisted beta description/review notes, and external-testing group readiness were not independently observable. The Builder's `status.json` claims are not independent evidence.
- No Beta App Review submission, build selection, group selection, or metadata change was performed.

## Issues Found

1. **The required focused onboarding UI gate is reproducibly failing.** Two exact-command runs produced identical five-test crash sets, even though the complete suite later passed all 71 tests. The acceptance criterion requires the focused command itself to pass.
2. **Live App Store Connect state remains independently unverified.** The available browser session is logged out and no API credential is configured, so the Inspector cannot confirm build `20261002.2202` as `Ready to Submit`.
3. **Persisted review metadata and external-testing readiness remain independently unverified.** Repository source copy is present, but it does not prove the live App Store Connect fields or group selection state.

## What Must Be Fixed

1. Make `cd ios && ./scripts/run-ui-tests.sh OnboardingTests` pass reliably on iPhone 17 Pro Max without signal-kill crashes, then rerun both focused and complete UI gates.
2. Provide an independently usable read-only App Store Connect session or API credential path so the Inspector can verify build `20261002.2202`, the persisted beta description and review notes, and external-group selection readiness.
3. Continue to leave Beta App Review unsubmitted and do not alter build/group selection while performing verification.
