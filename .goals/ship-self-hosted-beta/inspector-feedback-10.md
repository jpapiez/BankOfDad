# Inspector Feedback — Iteration 10

## Verdict: FAIL

## Acceptance Criteria Check

- [x] The self-hosted onboarding implementation is complete and preserves the existing offline Explore Demo and production behavior — iteration 10 changes only `status.json`. The three iteration-9 directed fixes remain intact: root retry calls verified `AppEnvironment.bootstrap()`, demo exit returns `.needsServer` without a configured profile and `.signedOut` with one, and the co-parent UI test consumes the exact payload shared by the UI.
- [x] Backend Release build with warnings-as-errors and all backend tests pass — retained from prior independent exact-command verification; iteration 10 changes no backend, deployment, or product files.
- [x] The Docker image builds, the stack starts, and `http://localhost:8080/health` returns success — retained from prior independent exact-command verification; iteration 10 changes no Docker or backend files.
- [x] iOS project generation, simulator unit tests, focused onboarding UI tests, and the complete iOS UI suite pass on iPhone 17 Pro Max — retained from iteration 9's independent results: 38 unit tests, 10 onboarding UI tests, 8 Family UI tests, and 71 complete-suite UI tests passed. No iOS file changed after those runs.
- [x] The TestFlight release script completes a signed Release archive/export without undefined variables or stale hardwired-server assumptions — retained signed export evidence for build `20261003.1101`; iteration 10 does not change the release script.
- [x] Product code, tests, deployment helpers, and directly related documentation are committed and pushed to the current branch — the latest Builder commit `c9e4c7da2c0ab22f8a6ce55ff552b142c28dd4de` changes only `status.json`; local `HEAD`, the configured upstream, and the live remote branch match. Its 51-character subject is within the requested limit, and `Assisted-by`, `Co-authored-by`, and `Copilot-Session` parse as one contiguous trailer block.
- [x] A new TestFlight build newer than 2209 is uploaded successfully and confirmed in App Store Connect processing or available state — retained authenticated uploader evidence proves build `20261002.2202` uploaded successfully and reached `PROCESSING` without errors or warnings.
- [ ] The new build is ready to be selected for external testing and Beta App Review using the saved self-hosting and offline-demo review metadata — FAILED: no new authenticated, read-only App Store Connect evidence is available. Current build selectability, intended external-group readiness, and persisted live beta description/review notes remain independently unverified. No selection, metadata, or Beta App Review submission was changed.

## Directed Product Fix Verification

1. **Verified retry path — PASS.** `RootView` still calls `environment.bootstrap()`. `AppEnvironment.bootstrap()` rediscovers the configured origin with the expected server ID before replacing live services and calling auth bootstrap.
2. **Demo exit state — PASS.** `AppEnvironment.exitDemo()` still ends the demo and marks `.needsServer` only when `serverProfile == nil`; the two focused unit tests still assert the unconfigured and configured outcomes.
3. **Exact invitation payload — PASS.** `FamilyView` still supplies the same `payload` to the QR image, `ShareLink`, and accessibility value. `FamilyTests` reads that value, requires `kind=parent`, extracts its token, and accepts that exact enrollment.

## Quality Gate

- Command: `python3 -m json.tool .goals/ship-self-hosted-beta/status.json`
  - Result: PASS
- Focused status-history assertions
  - Result: PASS — iterations 1 through 9 are ordered, each has exactly one Builder/status entry followed by one Inspector verdict, and the stray duplicate iteration-3 verdict is gone.
- Focused iteration-9 evidence assertions
  - Result: PASS — upload processing is accurately retained, external selection and live metadata remain explicitly blocked, Beta App Review remains unsubmitted, and all three product fixes remain listed.
- Command: `git diff --check HEAD~1 HEAD`
  - Result: PASS
- Product gates
  - Result: RETAINED — not rerun because the latest commit is status-only and the request limits validation to status/evidence changes.
- Goal result: **FAIL** solely because live App Store Connect external-testing and metadata readiness evidence remains unavailable.

## Evidence and Consistency Checks

- The iteration-9 historical anomaly is corrected without rewriting prior Inspector feedback: the misplaced duplicate iteration-3 verdict was removed from `status.json`, leaving a regular builder/verdict pair for each iteration 1–9.
- The replacement iteration-9 release and blocker fields are consistent with prior Inspector evidence and do not overclaim current App Store Connect readiness.
- `git diff a6f8c12..HEAD` contains only iteration-9 Inspector feedback and `status.json`; no product behavior changed after the three directed fixes.
- The latest Builder commit exists on the live remote at the exact local SHA and has valid contiguous required trailers.
- No App Store Connect navigation or mutation was performed. No build or group was selected, no metadata was changed, and Beta App Review was not submitted.

## Issues Found

1. **Live App Store Connect readiness remains the sole blocker.** The retained uploader log proves successful upload and processing, but there is still no authenticated read-only evidence that build `20261002.2202` is currently selectable for the intended external group or that the saved self-hosting/offline-demo beta description and review notes persist.

## What Must Be Fixed

1. Provide a safely usable authenticated, read-only App Store Connect session or transient API-key environment.
2. Without changing build/group selection, verify build `20261002.2202` is currently selectable for the intended external testing group.
3. Without changing metadata, verify the live beta description and review notes contain the saved self-hosting and offline Explore Demo guidance.
4. Continue to leave Beta App Review unsubmitted unless the user gives immediate explicit confirmation.
