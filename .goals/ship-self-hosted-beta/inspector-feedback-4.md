# Inspector Feedback — Iteration 4

## Verdict: FAIL

## Acceptance Criteria Check

- [x] The self-hosted onboarding implementation is complete and preserves the existing offline Explore Demo and production behavior — verified by direct inspection of the server-origin, stable-server-identity, one-family-per-installation, serialized single-use enrollment, child-credential, optional Apple/APNs, and demo-isolation paths; 77 backend tests, 36 iOS unit tests, 10 focused onboarding UI tests, and all 71 UI tests passed.
- [x] Backend Release build with warnings-as-errors and all backend tests pass — independently reran the exact restore, Release build, and test commands: 0 warnings, 0 errors, 77 tests passed.
- [x] The Docker image builds, the stack starts, and `http://localhost:8080/health` returns success — independently reran the exact required command; Compose built and started the stack and curl returned `Healthy`.
- [x] iOS project generation, simulator unit tests, focused onboarding UI tests, and the complete iOS UI suite pass on iPhone 17 Pro Max — independently verified project generation, 36 unit tests, the focused suite with 10/10 passing, and the complete suite with 71/71 passing on attempt 1. An injected first-attempt `Test crashed with signal kill` failure reset the selected simulator and passed all 10 focused tests on attempt 2. An injected persistent invalid-option failure ran both attempts and returned non-zero.
- [x] The TestFlight release script completes a signed Release archive/export without undefined variables or stale hardwired-server assumptions — independently ran `UPLOAD=0 ./scripts/testflight.sh`; version `1.0` build `20261003.0437` exported successfully. The IPA is signed by Apple Distribution for `com.jpapiez.bankofdad`, with `beta-reports-active=true` and `get-task-allow=false`.
- [x] Product code, tests, deployment helpers, and directly related documentation are committed and pushed to the current branch — before Inspector artifacts, local HEAD, the configured upstream, and the live remote branch all resolved to `a4a0b92012322dabbd97adf3c578bf1eaeaf9c5f`. The iteration-4 Builder subject is 59 characters and its `Assisted-by: OpenAI:GPT-5.6 Luna` trailer parses correctly.
- [ ] A new TestFlight build newer than 2209 is uploaded successfully and confirmed in App Store Connect processing or available state — FAILED: local Xcode distribution logs independently prove that build `20261002.2202` uploaded successfully, but they do not contain a subsequent processing/available state. The iteration-4 upload attempt failed before delivery because Xcode could not find an account with App Store Connect access. No API-key environment/default key directory exists, and Safari exposes neither a verified URL nor a web accessibility tree, so live state cannot be safely inferred.
- [ ] The new build is ready to be selected for external testing and Beta App Review using the saved self-hosting and offline-demo review metadata — FAILED: the repository metadata is present, usable, and contains no secrets or real family data, but the live build, external-testing group selection, and persisted App Store Connect beta description/review notes remain independently unobservable. No build/group selection, metadata, or Beta App Review submission state was changed.

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
- Signal-kill retry probe: injected a first-attempt exit with `Test crashed with signal kill`, then allowed the real focused suite to run.
  - Result: PASS — the runner reset the iPhone 17 Pro Max simulator and attempt 2 passed all 10 tests.
- Persistent-failure probe: injected an invalid `xcodebuild` option for both attempts.
  - Result: PASS — both attempts ran and the script returned non-zero.
- Command: `cd ios && ./scripts/run-ui-tests.sh`
  - Result: PASS on attempt 1 — 71 tests passed, 0 failures.
- Command: `cd ios && UPLOAD=0 ./scripts/testflight.sh`
  - Result: PASS — exported signed version `1.0` build `20261003.0437`.
- Overall result: **PASS**

## Evidence, Constraints, and Commit Checks

- The iteration-4 referenced result bundles exist locally and independently parse as 10/10 focused tests and 71/71 complete-suite tests on an iPhone 17 Pro Max. They are ignored build artifacts rather than portable committed evidence, so this inspection also reran every gate instead of trusting the Builder's summaries.
- The committed evidence and metadata contain no credentials, private keys, passwords, tokens, or real family/server data. `ios/Config/Local.xcconfig` and `ios/build/` are ignored; no `.p8`, `.p12`, mobile-provision, `secrets/`, or local Xcode configuration files are tracked.
- One-family-per-server behavior is enforced through the installation record, a unique filtered family index, a serializable initialization transaction, and row locking. Enrollment tokens are random, hashed, time-limited, row-locked, and marked used. Public HTTP is rejected while local/private HTTP is permitted. Apple and APNs remain optional capabilities.
- Demo isolation is covered by `testDemoServicesNeverTouchTheNetwork`; the independently run unit suite passed it.
- The latest Builder commit is pushed and has a valid parsed `Assisted-by` trailer. Historical goal commits `8e79d68`, `e639d60`, `bdb52c1`, `20c4b5b`, and `2dcf2bf` still do not expose `Assisted-by` as a parsed final trailer because of blank-separated trailer blocks or literal escaped newlines. This does not change the product/push criterion, but the full iteration history is not uniformly trailer-conformant.
- The final Beta App Review submission was not performed.

## Issues Found

1. **Live App Store Connect processing/availability remains independently unverified.** Local upload logs prove delivery of build `20261002.2202`, but not its current processing or available state.
2. **External-testing and saved review-metadata readiness remain independently unverified.** There is no safely usable authenticated App Store Connect browser/API path in this environment.
3. **Historical goal-commit trailer formatting is inconsistent.** The latest Builder commit is correct, but five earlier goal commits do not return the required `Assisted-by` value from `git interpret-trailers --parse`.

## What Must Be Fixed

1. Provide a safely usable authenticated, read-only App Store Connect session or transient API-key environment so the Inspector can confirm build `20261002.2202` is processing or available.
2. In the same read-only verification, confirm the build is selectable for the intended external testing group and that the saved self-hosting/offline-demo beta description and review notes are present.
3. Continue to leave Beta App Review unsubmitted and do not alter build/group selection or metadata while collecting verification evidence.
4. Before finalizing/squashing the goal history, ensure the resulting commit history carries correctly parsed required trailers.
