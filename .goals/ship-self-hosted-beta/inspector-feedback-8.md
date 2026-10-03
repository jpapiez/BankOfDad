# Inspector Feedback — Iteration 8

## Verdict: FAIL

## Acceptance Criteria Check

- [x] The self-hosted onboarding implementation is complete and preserves the existing offline Explore Demo and production behavior — verified by the unchanged product tree since the iteration-7 independent inspection, which passed the backend, unit, focused onboarding UI, and complete UI suites.
- [x] Backend Release build with warnings-as-errors and all backend tests pass — retained from the iteration-7 Inspector's independent execution of the exact commands: 0 warnings, 0 errors, and 77 tests passed. Iteration 8 changes only goal evidence and status files.
- [x] The Docker image builds, the stack starts, and `http://localhost:8080/health` returns success — retained from the iteration-7 Inspector's independent execution of the exact Compose and curl gate, which returned `Healthy`; no deployment or product files changed afterward.
- [x] iOS project generation, simulator unit tests, focused onboarding UI tests, and the complete iOS UI suite pass on iPhone 17 Pro Max — retained from the iteration-7 independent results: project generation passed, 36 unit tests passed, 10 focused onboarding tests passed, and 71 complete-suite UI tests passed with 0 failures. No iOS files changed in iteration 8.
- [x] The TestFlight release script completes a signed Release archive/export without undefined variables or stale hardwired-server assumptions — retained from the iteration-7 independent `UPLOAD=0 ./scripts/testflight.sh` run, which exported signed version `1.0` build `20261003.0839` with `beta-reports-active=true` and `get-task-allow=false`.
- [x] Product code, tests, deployment helpers, and directly related documentation are committed and pushed to the current branch — `HEAD` and the configured upstream both resolve to `6d4a8579b8c2950821543a6242b9f6a0e0543687`. The iteration-8 Builder changed only `.goals/ship-self-hosted-beta/iteration-8-evidence.md` and `status.json`.
- [x] A new TestFlight build newer than 2209 is uploaded successfully and confirmed in App Store Connect processing or available state — independently reread the retained authenticated Xcode delivery log. It identifies build `20261002.2202`, contains empty error and warning arrays, reports `state: PROCESSING`, and ends with `UPLOAD SUCCEEDED with no errors`.
- [ ] The new build is ready to be selected for external testing and Beta App Review using the saved self-hosting and offline-demo review metadata — FAILED: there is still no independently usable live App Store Connect evidence of current build selectability, intended external-group readiness, or persisted beta description and review notes. The retained upload log proves processing only, and repository metadata proves intended source copy rather than live persisted values.

## Quality Gate

- Command: `dotnet restore backend/BankOfDad.slnx`
  - Result: PASS — retained from iteration-7 independent execution; unchanged product tree.
- Command: `dotnet build backend/BankOfDad.slnx --configuration Release --no-restore -p:TreatWarningsAsErrors=true "-p:WarningsNotAsErrors=NU1901%3BNU1902%3BNU1903%3BNU1904"`
  - Result: PASS — retained result: 0 warnings, 0 errors.
- Command: `dotnet test backend/BankOfDad.slnx --configuration Release --no-build`
  - Result: PASS — retained result: 77 tests passed.
- Command: `docker compose build && docker compose up -d && curl -fsS http://localhost:8080/health`
  - Result: PASS — retained result: `Healthy`.
- Command: `cd ios && xcodegen generate`
  - Result: PASS — retained from iteration-7 independent execution.
- Command: `cd ios && xcodebuild test -project BankOfDad.xcodeproj -scheme BankOfDad -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -skip-testing:BankOfDadUITests CODE_SIGNING_ALLOWED=NO`
  - Result: PASS — retained result: 36 tests passed, 0 failures.
- Command: `cd ios && ./scripts/run-ui-tests.sh OnboardingTests`
  - Result: PASS — retained result: 10 tests passed, 0 failures.
- Command: `cd ios && ./scripts/run-ui-tests.sh`
  - Result: PASS — retained result: 71 tests passed, 0 failures.
- Command: `cd ios && UPLOAD=0 ./scripts/testflight.sh`
  - Result: PASS — retained signed export result for build `20261003.0839`.
- Local quality gates: **PASS**
- Goal result: **FAIL** because the final live App Store Connect readiness criterion remains unverified.

## Retained Evidence and Commit Convention

- The latest Builder commit is `6d4a8579b8c2950821543a6242b9f6a0e0543687`.
- `git log -1 --format='%(trailers:only)'` parses all three Builder footer entries: `Assisted-by: OpenAI:GPT-5.6 Luna`, `Co-authored-by`, and `Copilot-Session`. The iteration-7 trailer-format defect is fixed for the new commit.
- The retained Xcode `ContentDelivery.log` remains present and independently supports only successful upload and processing for build `20261002.2202`; it does not establish current post-processing status or external-review readiness.
- The iteration-8 Builder accurately records the blocker and does not claim that the missing live readiness evidence exists.
- No build/group selection, metadata mutation, or Beta App Review submission was performed during this inspection.

## Issues Found

1. **Current external-testing readiness is not independently evidenced.** There is no authenticated read-only App Store Connect view or API result showing that build `20261002.2202` is currently selectable for the intended external group.
2. **Persisted live beta metadata is not independently evidenced.** The repository contains the intended self-hosting and offline Explore Demo copy, but no current live App Store Connect result confirms the beta description and review notes remain saved.
3. **Processing evidence is narrower than final readiness.** The authenticated delivery log proves successful upload and `PROCESSING`, satisfying the upload criterion, but cannot prove the final external Beta App Review preparation criterion.

## What Must Be Fixed

1. Provide a safely usable authenticated, read-only App Store Connect session or transient API-key environment.
2. Without changing selection, verify build `20261002.2202` is currently selectable for the intended external testing group.
3. Without changing metadata, verify the live beta description and review notes contain the saved self-hosting and offline Explore Demo guidance.
4. Continue to leave Beta App Review unsubmitted and do not alter build/group selection.
