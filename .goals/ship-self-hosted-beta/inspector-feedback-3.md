# Inspector Feedback — Iteration 3

## Verdict: FAIL

## Acceptance Criteria Check

- [x] The self-hosted onboarding implementation is complete and preserves the existing offline Explore Demo and production behavior — verified by 77 passing backend tests, 36 passing iOS unit tests including the demo isolation coverage, 10 passing focused onboarding UI tests, and all 71 tests passing in the complete UI suite.
- [x] Backend Release build with warnings-as-errors and all backend tests pass — independently reran restore, the exact Release build, and tests: 0 warnings, 0 errors, 77 tests passed.
- [x] The Docker image builds, the stack starts, and `http://localhost:8080/health` returns success — independently reran the exact required command; Compose built and started the stack and curl returned `Healthy`.
- [x] iOS project generation, simulator unit tests, focused onboarding UI tests, and the complete iOS UI suite pass on iPhone 17 Pro Max — independently verified project generation, 36 unit tests, the exact focused command with 10/10 tests passing on its first attempt, and the exact complete command with 71/71 tests passing on its first attempt. An injected first-attempt signal-kill probe reset the simulator and passed all 10 focused tests on attempt 2; an injected persistent invalid-option failure exhausted both attempts and returned non-zero.
- [x] The TestFlight release script completes a signed Release archive/export without undefined variables or stale hardwired-server assumptions — independently ran `UPLOAD=0 ./scripts/testflight.sh`; version `1.0` build `20261003.0325` exported successfully. The IPA is signed by Apple Distribution for `com.jpapiez.bankofdad`, with `beta-reports-active=true` and `get-task-allow=false`.
- [x] Product code, tests, deployment helpers, and directly related documentation are committed and pushed to the current branch — before Inspector artifacts, local HEAD and upstream both resolved to `2dcf2bfd515eb1061ffcd840045442accd5b4bca`, and the worktree was clean.
- [ ] A new TestFlight build newer than 2209 is uploaded successfully and confirmed in App Store Connect processing or available state — FAILED: prior local Xcode distribution evidence proves successful delivery of build `20261002.2202` to Apple, but no independently usable authenticated App Store Connect session or API credential is available to confirm the build is processing or available. The Safari window exposes neither a verified URL nor a web accessibility tree, so its contents cannot be safely inferred.
- [ ] The new build is ready to be selected for external testing and Beta App Review using the saved self-hosting and offline-demo review metadata — FAILED: the repository contains the intended metadata, but the live App Store Connect build, external group availability, and persisted beta description/review notes remain independently unobservable. No build/group selection, metadata, or Beta App Review submission state was changed.

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
- Command: `cd ios && ./scripts/run-ui-tests.sh OnboardingTests`
  - Result: PASS on attempt 1 — 10 tests passed, 0 failures.
- Signal-kill retry probe: injected a first-attempt exit with `Test crashed with signal kill`, then allowed the real focused suite to run.
  - Result: PASS — the runner reset the selected simulator and attempt 2 passed all 10 tests.
- Persistent-failure probe: injected an invalid `xcodebuild` option for both attempts.
  - Result: PASS — both attempts ran and the script returned non-zero, confirming a persistent failure is not hidden.
- Command: `cd ios && ./scripts/run-ui-tests.sh`
  - Result: PASS on attempt 1 — 71 tests passed, 0 failures.
- Command: `cd ios && UPLOAD=0 ./scripts/testflight.sh`
  - Result: PASS — exported signed version `1.0` build `20261003.0325`.
- Overall result: **PASS**

## Status / Commit / Release Evidence

- `status.json` is valid JSON, remains at iteration 3 with `ready_for_inspection`, and accurately records App Store Connect verification as blocked rather than claiming live state that is unavailable.
- The iteration-3 Builder commit and its product changes are pushed. Its subject follows the required `[B]` format, but its body contains literal `\n\n` characters, so `Assisted-by: OpenAI:GPT-5.6 Luna` is not an actual Git trailer (`git interpret-trailers --parse` returns no trailer).
- `ASC_KEY_PATH`, `ASC_KEY_ID`, and `ASC_ISSUER_ID` are unset, and `$HOME/.appstoreconnect/private_keys` does not exist.
- The Safari App Store Connect window cannot be used as evidence: the automation interface reports a missing fail-closed URL and no web accessibility tree. Per the tool's safety constraint, no page identity or content was inferred from pixels.
- Local signed archives and Xcode upload records can prove signing/export and delivery to Apple, but they cannot prove App Store Connect processing/availability, saved live metadata, or external-testing selection readiness.

## Issues Found

1. **Live App Store Connect build state remains independently unverified.** Build `20261002.2202` cannot be confirmed as processing or available from the current environment.
2. **External-testing and review-metadata readiness remain independently unverified.** Repository metadata is not evidence that the live App Store Connect fields persisted or that the intended external group/build can be selected.
3. **The latest Builder commit is missing the required real `Assisted-by` trailer.** The text is present only after literal `\n\n` characters in the commit body, not as a parsed trailer.

## What Must Be Fixed

1. Provide a safely usable authenticated, read-only App Store Connect session or API credential path so the Inspector can independently verify build `20261002.2202` is processing or available.
2. In the same read-only verification, confirm the build is selectable for the intended external testing group and that the saved self-hosting/offline-demo beta description and review notes are present.
3. Continue to leave Beta App Review unsubmitted and do not alter build/group selection or metadata while collecting verification evidence.
4. Ensure the next Builder commit uses a real final `Assisted-by: OpenAI:GPT-5.6 Luna` trailer rather than escaped newline text.
