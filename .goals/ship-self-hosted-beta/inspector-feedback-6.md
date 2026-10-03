# Inspector Feedback — Iteration 6

## Verdict: FAIL

## Acceptance Criteria Check

- [x] The self-hosted onboarding implementation is complete and preserves the existing offline Explore Demo and production behavior — verified by direct inspection of the stable server-profile and origin policy, one-family initialization, locked short-lived single-use enrollment flow, parent/child credentials, optional Apple/APNs capabilities, runtime server switching, and demo network isolation. The independently rerun backend, unit, focused UI, and complete UI suites all passed.
- [x] Backend Release build with warnings-as-errors and all backend tests pass — independently reran the exact restore, Release build, and test commands: 0 warnings, 0 errors, 77 tests passed.
- [x] The Docker image builds, the stack starts, and `http://localhost:8080/health` returns success — independently reran the exact required command; Compose rebuilt and started the stack and curl returned `Healthy`.
- [x] iOS project generation, simulator unit tests, focused onboarding UI tests, and the complete iOS UI suite pass on iPhone 17 Pro Max — independently reran all four gates: 36 unit tests, 10 focused onboarding UI tests, and 71 complete-suite UI tests passed with 0 failures on attempt 1.
- [x] The TestFlight release script completes a signed Release archive/export without undefined variables or stale hardwired-server assumptions — independently ran `UPLOAD=0 ./scripts/testflight.sh`; version `1.0` build `20261003.0627` exported successfully. The IPA is signed by Apple Distribution for `com.jpapiez.bankofdad`, with `beta-reports-active=true` and `get-task-allow=false`.
- [x] Product code, tests, deployment helpers, and directly related documentation are committed and pushed to the current branch — before Inspector artifacts, local HEAD, the configured upstream, and the live remote branch all resolved to `8aa83a681ba5c0e6cfdafa44502ab31f1ae47239`. The iteration-6 Builder commit has a correctly parsed `Assisted-by: OpenAI:GPT-5.6 Luna` trailer.
- [x] A new TestFlight build newer than 2209 is uploaded successfully and confirmed in App Store Connect processing or available state — independently verified the retained authenticated Xcode delivery log for build `20261002.2202`: App Store Connect returned HTTP 200, reported `state: PROCESSING`, recorded no errors or warnings, and ended with `UPLOAD SUCCEEDED with no errors`.
- [ ] The new build is ready to be selected for external testing and Beta App Review using the saved self-hosting and offline-demo review metadata — FAILED: current build selectability, external-testing group readiness, and persisted live beta description/review notes remain independently unobservable. Safari exposes neither a verified URL nor an accessibility tree for its App Store Connect window, no App Store Connect API variables or default API key are available, and repository metadata proves only the intended source copy. Iteration 6 now records this limitation accurately, but a transparent blocker does not satisfy the live-state acceptance criterion.

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
  - Result: PASS — 36 tests passed, 0 failures.
- Command: `cd ios && ./scripts/run-ui-tests.sh OnboardingTests`
  - Result: PASS on attempt 1 — 10 tests passed, 0 failures.
- Command: `cd ios && ./scripts/run-ui-tests.sh`
  - Result: PASS on attempt 1 — 71 tests passed, 0 failures.
- Command: `cd ios && UPLOAD=0 ./scripts/testflight.sh`
  - Result: PASS — exported signed version `1.0` build `20261003.0627`.
- Local quality gates: **PASS**
- Goal result: **FAIL** because the final live App Store Connect readiness criterion remains unverified.

## Evidence, Blocker, and Prohibited-Action Checks

- Iteration 6 correctly distinguishes the proven upload/processing result from the narrower unresolved live-state requirement. Its evidence and `status.json` no longer misclassify the upload criterion as blocked.
- The live verification attempt failed closed: the running Safari window is titled App Store Connect, but the automation surface reports a missing verified URL and no web accessibility tree and explicitly forbids inferring content from pixels.
- No safely usable App Store Connect API credential is configured in the environment or standard private-key locations. This is a legitimate blocker to independent read-only verification, not evidence that the live criterion passed.
- No prohibited App Store Connect mutation was observed. The retained delivery log contains build-upload resources only and no Beta App Review submission, beta-group, or beta-localization mutation endpoint. The latest Builder diff changes only iteration evidence and status narrative.
- No credential, private key, provisioning profile, `Local.xcconfig`, build output, or `secrets/` content is tracked. The sensitive local paths remain ignored.
- No final Beta App Review submission was performed in the verifiable evidence. Because live App Store Connect is inaccessible, the current remote submission state cannot be asserted beyond that evidence.

## Issues Found

1. **The external-testing and saved-review-metadata criterion is still unmet.** There is no independently verifiable live evidence that build `20261002.2202` is currently selectable for the intended external group or that the self-hosting/offline-demo beta description and review notes remain persisted.
2. **The blocker is now correctly and transparently recorded, but it remains a blocker.** The corrected evidence is accurate and does not overclaim; however, documentation of unavailable authenticated access cannot replace the required live-state verification.

## What Must Be Fixed

1. Provide a safely usable authenticated, read-only App Store Connect session or transient API-key environment so the Inspector can verify build `20261002.2202` is selectable for external testing and Beta App Review.
2. In the same read-only verification, confirm the intended external testing group and the persisted self-hosting/offline-demo beta description and review notes.
3. Continue to leave Beta App Review unsubmitted and do not change build/group selection or metadata while collecting this evidence.
