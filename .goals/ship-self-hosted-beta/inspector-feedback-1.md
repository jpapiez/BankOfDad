# Inspector Feedback — Iteration 1

## Verdict: FAIL

## Acceptance Criteria Check

- [x] The self-hosted onboarding implementation is complete and preserves the existing offline Explore Demo and production behavior — verified by code inspection, 36 iOS unit tests (including demo network isolation and server-profile policy), 10 focused onboarding UI tests, and the 71-test full UI suite.
- [x] Backend Release build with warnings-as-errors and all backend tests pass — independently reran restore, Release build, and tests: 0 warnings, 0 errors, 77 tests passed.
- [ ] The Docker image builds, the stack starts, and `http://localhost:8080/health` returns success — FAILED: the existing image starts and returns `Healthy`, but two independent `docker compose build` attempts failed during NuGet restore with `NU1301` and an unexpected TLS EOF.
- [x] iOS project generation, simulator unit tests, focused onboarding UI tests, and the complete iOS UI suite pass on iPhone 17 Pro Max — verified: XcodeGen succeeded, 36 unit tests passed, 10 focused onboarding tests passed, and all 71 UI tests passed on simulator `CFA9A830-B3B6-4BCE-9F58-6F0801E52FB4` (iPhone 17 Pro Max).
- [x] The TestFlight release script completes a signed Release archive/export without undefined variables or stale hardwired-server assumptions — independently reran `UPLOAD=0 ./scripts/testflight.sh`; it exported build `20261002.2243` as an Apple Distribution-signed IPA with `get-task-allow=false` and `beta-reports-active=true`. Code inspection confirmed runtime server selection and legacy-only migration from the bundled URL.
- [x] Product code, tests, deployment helpers, and directly related documentation are committed and pushed to the current branch — verified clean worktree before Inspector artifacts and exact equality of local HEAD and upstream at `8e79d6835c6941cd71fb94d7a35f0104bf08bfc9`.
- [ ] A new TestFlight build newer than 2209 is uploaded successfully and confirmed in App Store Connect processing or available state — PARTIAL/FAILED: archive distribution metadata independently proves build `20261002.2202` was uploaded to Apple successfully at `2026-10-02T22:04:41Z`, but there is no independently verifiable evidence that the Bank of Dad build reached App Store Connect's Processing or Available state.
- [ ] The new build is ready to be selected for external testing and Beta App Review using the saved self-hosting and offline-demo review metadata — FAILED: the repository contains the intended beta description and review-note template, but the Builder left no independently verifiable evidence that the uploaded build is selectable or that those fields persisted in Bank of Dad's App Store Connect record.

## Quality Gate

- Command: `dotnet restore backend/BankOfDad.slnx`
  - Result: PASS
- Command: `dotnet build backend/BankOfDad.slnx --configuration Release --no-restore -p:TreatWarningsAsErrors=true "-p:WarningsNotAsErrors=NU1901%3BNU1902%3BNU1903%3BNU1904"`
  - Result: PASS — 0 warnings, 0 errors.
- Command: `dotnet test backend/BankOfDad.slnx --configuration Release --no-build`
  - Result: PASS — 77 tests passed.
- Command: `docker compose build && docker compose up -d && curl -fsS http://localhost:8080/health`
  - Result: FAIL — both build attempts failed at the Dockerfile restore step with `NU1301: Unable to load the service index for source https://api.nuget.org/v3/index.json`, caused by an unexpected EOF in the TLS transport. The previously built image could be started and returned `Healthy`, but the required image-build gate did not pass.
- Command: `cd ios && xcodegen generate`
  - Result: PASS
- Command: `cd ios && xcodebuild test -project BankOfDad.xcodeproj -scheme BankOfDad -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -skip-testing:BankOfDadUITests CODE_SIGNING_ALLOWED=NO`
  - Result: PASS — 36 tests passed.
- Command: `cd ios && ./scripts/run-ui-tests.sh OnboardingTests`
  - Result: PASS for the test phase — 10 tests passed using `SKIP_BACKEND=1` after starting the current image with Development test hooks; the script's normal Docker rebuild preamble was isolated because the Docker build gate failed separately.
- Command: `cd ios && ./scripts/run-ui-tests.sh`
  - Result: PASS for the test phase — 71 tests passed using the same current backend image and iPhone 17 Pro Max simulator.
- Command: `cd ios && UPLOAD=0 ./scripts/testflight.sh`
  - Result: PASS — Release archive/export completed and produced a valid App Store distribution IPA.
- Overall result: **FAIL**

## Release / Build / Upload Evidence

- Uploaded archive metadata identifies app `com.jpapiez.bankofdad`, version `1.0`, build `20261002.2202`, App Store ID `6817848238`, and team `ZPKA84F3TY`.
- Its `Distributions` record says `destination=upload`, `uploadDestination=App Store`, `uploadEvent.state=success`, and `uploadEvent.title=Uploaded to Apple`.
- The independently exported verification IPA is version `1.0` build `20261002.2243`, signed by `Apple Distribution: JEFFREY RICHARD PAPIEZ (ZPKA84F3TY)` with an App Store provisioning profile.
- These artifacts prove archive, export, signing, and upload success. They do **not** prove the post-upload Processing/Available state or external-testing selection readiness in App Store Connect.

## Issues Found

1. **Required Docker build quality gate fails.** The failure is in external NuGet TLS transport rather than compilation, but the image cannot currently be rebuilt by the exact required command. A pre-existing image and healthy container do not satisfy the image-build portion of the criterion.
2. **Post-upload App Store Connect state is not independently evidenced.** `status.json` claims the package is processing, but that is the Builder's report and cannot be treated as verification. The local Xcode archive only records successful delivery to Apple.
3. **External-testing and saved-review-metadata readiness is not independently evidenced.** The checked-in metadata is appropriate, but there is no non-sensitive durable evidence or live Bank of Dad App Store Connect state showing the build is selectable and the saved description/review notes are present.

## What Must Be Fixed

1. Make the exact Docker gate pass in a fresh Inspector run. If NuGet's endpoint remains unreliable, harden the Docker restore path or use the documented `NUGET_SOURCE` mechanism in a reproducible way.
2. Verify build `20261002.2202` on the **Bank of Dad** App Store Connect/TestFlight page as Processing or Available, and preserve non-sensitive evidence the Inspector can verify.
3. Verify that the uploaded build is selectable for external testing and that the self-hosting/offline-demo beta description and review notes persisted. Do not submit for Beta App Review without the user's immediate confirmation.
