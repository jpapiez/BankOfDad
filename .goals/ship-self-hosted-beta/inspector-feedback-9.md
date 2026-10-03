# Inspector Feedback — Iteration 9

## Verdict: FAIL

## Acceptance Criteria Check

- [x] The self-hosted onboarding implementation is complete and preserves the existing offline Explore Demo and production behavior — verified the three user-directed fixes by code inspection and execution. `RootView` retry calls `AppEnvironment.bootstrap()`, which rediscovers the configured origin and enforces descriptor-origin and expected-server-ID checks before calling `AuthSession.bootstrap()`. Demo exit returns `.needsServer` without a profile and `.signedOut` with one. The co-parent UI test consumes the same `payload` used by the QR and `ShareLink`.
- [x] Backend Release build with warnings-as-errors and all backend tests pass — retained from the iteration-7 Inspector's independent exact-command run: 0 warnings, 0 errors, and 77 tests passed. Iteration 9 changes no backend source. The independently run UI gates also rebuilt and started the backend container successfully.
- [x] The Docker image builds, the stack starts, and `http://localhost:8080/health` returns success — retained from iteration 7's independent exact gate. Each iteration-9 focused/full UI run rebuilt and started the same Compose backend successfully; no deployment files changed.
- [x] iOS project generation, simulator unit tests, focused onboarding UI tests, and the complete iOS UI suite pass on iPhone 17 Pro Max — independently verified XcodeGen, 38 unit tests, 10 focused onboarding UI tests, 8 focused Family UI tests, and all 71 UI tests with zero failures.
- [x] The TestFlight release script completes a signed Release archive/export without undefined variables or stale hardwired-server assumptions — iteration 9 did not change the script; the retained export is build `20261003.1101`, and its archive/distribution metadata records `beta-reports-active=true` and `get-task-allow=false`. Earlier Inspectors independently passed this unchanged release gate.
- [x] Product code, tests, deployment helpers, and directly related documentation are committed and pushed to the current branch — before Inspector artifacts, local `HEAD`, configured upstream, and live remote all resolved to `a6f8c120e8cea25ccf0f2e4351e9e6c48ad8c325`. The 66-character Builder subject is within the requested limit, and all required Builder trailers parse contiguously.
- [x] A new TestFlight build newer than 2209 is uploaded successfully and confirmed in App Store Connect processing or available state — retained authenticated Xcode delivery evidence for build `20261002.2202` records successful upload, no errors or warnings, and `state: PROCESSING`.
- [ ] The new build is ready to be selected for external testing and Beta App Review using the saved self-hosting and offline-demo review metadata — FAILED: iteration 9 supplies no new authenticated, read-only App Store Connect evidence. Current build selectability, intended external-group readiness, and persisted live beta description/review notes therefore remain independently unverified. No selection, metadata, or Beta App Review submission was changed.

## Directed Fix Verification

1. **Verified retry path — PASS.** `RootView.swift` now invokes `environment.bootstrap()`, not `authSession.bootstrap()`. `AppEnvironment.bootstrap()` calls `ServerDiscoveryClient.discover(origin:expectedServerID:)`; that method rejects protocol mismatches, descriptor-origin mismatches, and server-ID mismatches before replacing live services or bootstrapping authentication.
2. **Demo exit state — PASS.** `AppEnvironment.exitDemo()` restores live services, ends the demo session, then explicitly marks `.needsServer` when `serverProfile == nil`; otherwise `AuthSession.endDemo()` leaves the state `.signedOut`. Both new tests passed independently.
3. **Exact UI invitation payload — PASS.** The test reads `family.inviteShare.value`, which is set from the exact `payload` also supplied to the QR generator and `ShareLink`. It parses that payload, requires `kind=parent`, extracts its token, and sends that token to `/api/v1/auth/accept-enrollment`. A missing, malformed, wrong-kind, invalid, or non-acceptable UI payload would fail the test; no separate invitation is created by the test.

## Quality Gate

- Command: `cd ios && xcodegen generate`
  - Result: PASS
- Command: focused `BankOfDadTests/DemoModeTests` on iPhone 17 Pro Max
  - Result: PASS — 22 tests, including both new demo-exit tests.
- Command: `cd ios && xcodebuild test -project BankOfDad.xcodeproj -scheme BankOfDad -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -skip-testing:BankOfDadUITests CODE_SIGNING_ALLOWED=NO`
  - Result: PASS — 38 tests, 0 failures.
- Command: `cd ios && ./scripts/run-ui-tests.sh FamilyTests`
  - Result: PASS — 8 tests, 0 failures; `testInviteCoParentProducesAnAcceptableCode` passed using the UI payload.
- Command: `cd ios && ./scripts/run-ui-tests.sh OnboardingTests`
  - Result: PASS — 10 tests, 0 failures.
- Command: `cd ios && ./scripts/run-ui-tests.sh`
  - Result: PASS — 71 tests, 0 failures.
- Command: `git diff --check`
  - Result: PASS
- Local iOS/product gates: **PASS**
- Goal result: **FAIL** because the final live App Store Connect readiness criterion remains unverified.

## Evidence and Repository Checks

- Iteration-9 evidence counts match the independent runs: 38 unit, 10 onboarding UI, 8 Family UI, and 71 complete UI tests.
- The retained archive and IPA exist under `ios/build`; archive and distribution metadata identify build `20261003.1101`.
- The Builder commit subject is `fix(self-hosted): [B] fix verified retry demo exit and invite test` (66 characters).
- Parsed Builder trailers include `Assisted-by: OpenAI:GPT-5.6 Luna`, `Co-authored-by`, and `Copilot-Session` in one contiguous block.
- The worktree was clean before Inspector artifacts, and Builder `HEAD`, upstream, and the live remote branch matched exactly.
- No App Store Connect build/group selection, metadata mutation, or Beta App Review submission was performed.
- `status.json` iteration-9 product and test claims are consistent with the inspected code and independent runs. Its history still contains a pre-existing duplicate/misnumbered iteration-3 verdict after iteration 8; iteration 9 did not introduce or correct that historical anomaly.

## Issues Found

1. **The final App Store Connect readiness criterion remains unmet.** Processing evidence proves upload acceptance, but there is still no independently usable live evidence that build `20261002.2202` is selectable for the intended external group or that the saved beta description and review notes persist.
2. **The status history has a historical ordering/numbering anomaly.** A second iteration-3 Inspector verdict appears after iteration 8. This does not contradict iteration-9 test evidence, but it makes the audit history internally irregular.

## What Must Be Fixed

1. Provide a safely usable authenticated, read-only App Store Connect session or transient API-key environment.
2. Without changing selection, verify build `20261002.2202` is currently selectable for the intended external testing group.
3. Without changing metadata, verify the live beta description and review notes contain the saved self-hosting and offline Explore Demo guidance.
4. Continue to leave Beta App Review unsubmitted and do not alter build/group selection or metadata.
5. Correct the historical iteration-number anomaly in a future Builder status update without rewriting prior Inspector feedback.
