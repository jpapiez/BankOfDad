# Inspector Feedback — Iteration 7

## Verdict: FAIL

## Acceptance Criteria Check

- [x] The self-hosted onboarding implementation is complete and preserves the existing offline Explore Demo and production behavior — verified from the goal-wide product diff, focused onboarding coverage, server-profile and demo-isolation tests, and independently rerun backend, unit, focused UI, and complete UI suites. The latest Builder commit changes only iteration evidence and status, so it does not regress the previously implemented product behavior.
- [x] Backend Release build with warnings-as-errors and all backend tests pass — independently reran the exact restore, Release build, and test commands: 0 warnings, 0 errors, 77 tests passed.
- [x] The Docker image builds, the stack starts, and `http://localhost:8080/health` returns success — independently reran the exact required command; Compose rebuilt and started the stack and curl returned `Healthy`.
- [x] iOS project generation, simulator unit tests, focused onboarding UI tests, and the complete iOS UI suite pass on iPhone 17 Pro Max — independently reran all four gates: 36 unit tests, 10 focused onboarding UI tests, and 71 complete-suite UI tests passed with 0 failures on attempt 1.
- [x] The TestFlight release script completes a signed Release archive/export without undefined variables or stale hardwired-server assumptions — independently ran `UPLOAD=0 ./scripts/testflight.sh`; version `1.0` build `20261003.0803` exported successfully. The IPA is signed by Apple Distribution for `com.jpapiez.bankofdad`, with `beta-reports-active=true` and `get-task-allow=false`.
- [x] Product code, tests, deployment helpers, and directly related documentation are committed and pushed to the current branch — before Inspector artifacts, local HEAD, the configured upstream, and the live remote branch all resolved to `aa89bb810f7679c5472e606b49ea416bb507e659`, and the worktree had no tracked changes.
- [x] A new TestFlight build newer than 2209 is uploaded successfully and confirmed in App Store Connect processing or available state — independently checked the retained authenticated Xcode delivery log for build `20261002.2202`; it contains a successful 200 response marker, `PROCESSING`, `UPLOAD SUCCEEDED with no errors`, and no authorization header, bearer token, or private-key material.
- [ ] The new build is ready to be selected for external testing and Beta App Review using the saved self-hosting and offline-demo review metadata — FAILED: current build selectability, intended external-group readiness, and persisted live beta description/review notes remain independently unobservable. Edge is on a Diablo 4 guide with no verified URL or web accessibility tree. The Safari window titled App Store Connect also exposes no verified URL or accessibility tree. No safely usable App Store Connect API credential is configured, and repository metadata proves only the intended source copy.

## Quality Gate

- Command: `dotnet restore backend/BankOfDad.slnx`
  - Result: PASS — all projects were up to date.
- Command: `dotnet build backend/BankOfDad.slnx --configuration Release --no-restore -p:TreatWarningsAsErrors=true "-p:WarningsNotAsErrors=NU1901%3BNU1902%3BNU1903%3BNU1904"`
  - Result: PASS — 0 warnings, 0 errors.
- Command: `dotnet test backend/BankOfDad.slnx --configuration Release --no-build`
  - Result: PASS — 77 tests passed.
- Command: `docker compose build && docker compose up -d && curl -fsS http://localhost:8080/health`
  - Result: PASS — curl returned `Healthy`.
- Command: `cd ios && xcodegen generate`
  - Result: PASS.
- Command: `cd ios && xcodebuild test -project BankOfDad.xcodeproj -scheme BankOfDad -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -skip-testing:BankOfDadUITests CODE_SIGNING_ALLOWED=NO`
  - Result: PASS — 36 tests passed, 0 failures.
- Command: `cd ios && ./scripts/run-ui-tests.sh OnboardingTests`
  - Result: PASS on attempt 1 — 10 tests passed, 0 failures.
- Command: `cd ios && ./scripts/run-ui-tests.sh`
  - Result: PASS on attempt 1 — 71 tests passed, 0 failures.
- Command: `cd ios && UPLOAD=0 ./scripts/testflight.sh`
  - Result: PASS — exported signed version `1.0` build `20261003.0803`.
- Local quality gates: **PASS**
- Goal result: **FAIL** because the final live App Store Connect readiness criterion remains unverified.

## Signal-Kill Fix Verification

- Direct inspection confirms `ios/scripts/run-ui-tests.sh` validates `UI_TEST_ATTEMPTS`, retries the complete `xcodebuild` invocation, resets the selected simulator between attempts, and returns nonzero if no attempt succeeds.
- An isolated test-double run forced the first `xcodebuild` attempt to exit 65 with `Test runner exited due to signal 9`. The script then called simulator shutdown, boot, and bootstatus, reran `xcodebuild`, and returned 0 after the second attempt succeeded.
- The real focused and complete UI gates both passed on their first attempts, confirming the retry logic does not interfere with normal successful runs.

## Edge / App Store Connect Safety Verification

- The iteration-7 Edge account is accurate and fail-closed. A fresh non-mutating accessibility read confirmed window title `Firewall Sorc - Diablo 4 Sorcerer Build Guide`, missing verified URL, unavailable page tree, and the instruction not to infer page content from pixels.
- A fresh non-mutating read of the separate Safari window titled App Store Connect produced the same missing-URL and unavailable-tree limitation. No screenshot fallback, navigation, click, typing, selection, or submission was performed.
- No matching App Store Connect/API credential variables are configured, and the standard private-key directories checked are absent.
- No credentials, private keys, provisioning profiles, IPA files, `Local.xcconfig`, build output, or `secrets/` content are tracked. The only source match for a private-key marker is code that removes PEM delimiters while reading an operator-configured APNs key path.
- The retained upload log contains no authorization header, bearer token, or private-key marker and no Beta App Review submission marker. No final submission or live build/group/metadata mutation is evidenced.

## Commit / Push / Trailer Verification

- PASS: Builder subject `fix(self-hosted): [B] record iteration 7 evidence` is imperative, uses the required role marker, and is 49 characters.
- PASS: local HEAD, upstream, and the live remote branch matched before Inspector artifacts.
- FAIL: the Builder message contains `Assisted-by: OpenAI:GPT-5.6 Luna` as text, but it is separated from the final footer block by blank lines. `git log --format='%(trailers:only)'` parses only `Copilot-Session`, so the required `Assisted-by` value is not a valid parsed commit trailer.

## Issues Found

1. **The external-testing and saved-review-metadata criterion is still unmet.** There is no independently verifiable live evidence that build `20261002.2202` is currently selectable for the intended external group or that the self-hosting/offline-demo beta description and review notes remain persisted.
2. **The blocker is transparently and safely documented, but documentation does not satisfy the live-state criterion.** Both available browser windows fail closed, and there is no read-only API credential path.
3. **The iteration-7 Builder footer does not parse as required.** The `Assisted-by` line is present but is not in the contiguous trailer block.

## What Must Be Fixed

1. Provide a safely usable authenticated, read-only App Store Connect session or transient API-key environment so the Inspector can verify build `20261002.2202` is selectable for external testing and Beta App Review.
2. In the same read-only verification, confirm the intended external testing group and the persisted self-hosting/offline-demo beta description and review notes.
3. Continue to leave Beta App Review unsubmitted and do not change build/group selection or metadata while collecting this evidence.
4. In the next Builder commit, place `Assisted-by` and any repository-required Copilot trailers together in one contiguous footer block so Git parses them as trailers. Do not rewrite or force-push existing history solely to repair iteration metadata without explicit user approval.
