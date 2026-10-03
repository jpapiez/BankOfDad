# Inspector Feedback — Iteration 5

## Verdict: FAIL

## Acceptance Criteria Check

- [x] The self-hosted onboarding implementation is complete and preserves the existing offline Explore Demo and production behavior — verified by direct inspection of the server-bound onboarding, one-family initialization, short-lived single-use enrollment, child credential, private-HTTP/public-HTTPS, optional Apple/APNs, runtime server selection, and demo-isolation paths. The independently rerun backend, iOS unit, focused UI, and complete UI suites all passed.
- [x] Backend Release build with warnings-as-errors and all backend tests pass — independently reran the exact restore, Release build, and test commands: 0 warnings, 0 errors, 77 tests passed.
- [x] The Docker image builds, the stack starts, and `http://localhost:8080/health` returns success — independently reran the exact required command; Compose built and started the stack and curl returned `Healthy`.
- [x] iOS project generation, simulator unit tests, focused onboarding UI tests, and the complete iOS UI suite pass on iPhone 17 Pro Max — independently verified project generation, 36 unit tests, a signal-kill-injected focused run with 10/10 tests passing on retry attempt 2, and the complete suite with 71/71 tests passing on attempt 1. A persistent invalid-option probe exercised both attempts and returned non-zero.
- [x] The TestFlight release script completes a signed Release archive/export without undefined variables or stale hardwired-server assumptions — independently ran `UPLOAD=0 ./scripts/testflight.sh`; version `1.0` build `20261003.0546` exported successfully. The IPA is signed by Apple Distribution for `com.jpapiez.bankofdad`, with `beta-reports-active=true` and `get-task-allow=false`.
- [x] Product code, tests, deployment helpers, and directly related documentation are committed and pushed to the current branch — before Inspector artifacts, local HEAD, the configured upstream, and the live remote branch all resolved to `b68c8d962e86c12c39f8d18ccfcd5c50434e7bba`. The iteration-5 Builder commit has a correctly parsed `Assisted-by: OpenAI:GPT-5.6 Luna` trailer.
- [x] A new TestFlight build newer than 2209 is uploaded successfully and confirmed in App Store Connect processing or available state — verified from Xcode's authenticated App Store Connect delivery response in `BankOfDad_2026-10-02_15-03-06.668.xcdistributionlogs/ContentDelivery.log`: build `20261002.2202` received HTTP 200, reported `state: PROCESSING`, had no errors or warnings, and ended with `UPLOAD SUCCEEDED with no errors`. This satisfies the criterion's permitted processing state even though current post-processing state is not accessible now.
- [ ] The new build is ready to be selected for external testing and Beta App Review using the saved self-hosting and offline-demo review metadata — FAILED: current build selectability, external-testing group readiness, and persisted beta description/review notes remain independently unobservable. The Safari App Store Connect window exposes neither a verified URL nor an accessibility tree, the App Store Connect API variables and default key directory are absent, and the repository metadata only proves the intended source copy. No build/group selection, metadata, or Beta App Review submission state was changed.

## Quality Gate

- Command: `dotnet restore backend/BankOfDad.slnx`
  - Result: PASS
- Command: `dotnet build backend/BankOfDad.slnx --configuration Release --no-restore -p:TreatWarningsAsErrors=true "-p:WarningsNotAsErrors=NU1901%3BNU1902%3BNU1903%3BNU1904"`
  - Result: PASS — 0 warnings, 0 errors.
- Command: `dotnet test backend/BankOfDad.slnx --configuration Release --no-build`
  - Result: PASS — 77 tests passed.
- Command: `docker compose build && docker compose up -d && curl -fsS http://localhost:8080/health`
  - Result: PASS — curl returned `Healthy`.
- Command: `cd ios && xcodegen generate`
  - Result: PASS
- Command: `cd ios && xcodebuild test -project BankOfDad.xcodeproj -scheme BankOfDad -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -skip-testing:BankOfDadUITests CODE_SIGNING_ALLOWED=NO`
  - Result: PASS — 36 tests passed.
- Signal-kill retry probe: injected `Test crashed with signal kill` on attempt 1 of the focused onboarding command.
  - Result: PASS — the script reset the selected iPhone 17 Pro Max simulator, attempt 2 ran the real suite, and all 10 tests passed.
- Persistent-failure probe: injected an invalid `xcodebuild` option for both focused-suite attempts.
  - Result: PASS — both attempts ran and the script returned non-zero.
- Command: `cd ios && ./scripts/run-ui-tests.sh`
  - Result: PASS on attempt 1 — 71 tests passed, 0 failures.
- Command: `cd ios && UPLOAD=0 ./scripts/testflight.sh`
  - Result: PASS — exported signed version `1.0` build `20261003.0546`.
- Overall result: **PASS**

## Evidence, Constraints, and Commit Checks

- The signal-kill behavior is genuinely reproducible: the injected first attempt exited with the same failure text, the runner logged the simulator reset, the real second attempt passed 10 tests, and an independently injected persistent failure still propagated a non-zero exit.
- The iteration-5 evidence understates the available upload evidence. Although there is no safely usable current browser/API path, the retained authenticated App Store Connect uploader response itself proves build `20261002.2202` reached the accepted `PROCESSING` state at upload time.
- The current App Store Connect readiness blocker is narrower than previously reported: only post-processing build selectability, external group readiness, and persisted live metadata remain unverified.
- The user constraints were respected. No final Beta App Review submission was performed, no build/group selection or metadata was changed, and no credential was requested, persisted, or committed.
- `ios/Config/Local.xcconfig`, `ios/build/`, and `secrets/` remain ignored; no private key, provisioning profile, API credential, or local Xcode configuration is tracked.
- The iteration-5 Builder commit is pushed and has valid parsed trailers. Earlier goal commits with malformed trailer blocks remain in history; the eventual squash/final commit must carry correctly parsed required trailers.

## Issues Found

1. **External-testing and saved review-metadata readiness remain independently unverified.** There is no safely usable authenticated App Store Connect browser or API path to confirm that build `20261002.2202` is selectable for the intended external group and that the self-hosting/offline-demo beta description and review notes are still persisted.
2. **Iteration-5 evidence misclassifies the upload-processing criterion as blocked.** The retained authenticated uploader log contains a successful App Store Connect response for build `20261002.2202` with `state: PROCESSING`; only the later external-testing and metadata criterion remains blocked.
3. **Historical goal-commit trailer formatting remains inconsistent.** The latest Builder commit is correct, but the final squashed history must preserve correctly parsed required trailers.

## What Must Be Fixed

1. Provide a safely usable authenticated, read-only App Store Connect session or transient API-key environment so the Inspector can confirm build `20261002.2202` is selectable for external testing and Beta App Review.
2. In that read-only verification, confirm the intended external testing group and the persisted self-hosting/offline-demo beta description and review notes.
3. Correct the goal evidence/status narrative to distinguish the already-proven upload/processing criterion from the still-blocked external-testing and metadata criterion.
4. Continue to leave Beta App Review unsubmitted and do not alter build/group selection or metadata while collecting verification evidence.
5. Ensure the final squashed commit has correctly parsed required trailers.
