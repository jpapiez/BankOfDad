# Goal: Ship the self-hosted TestFlight beta

## User Request

Make the current self-hosted Bank of Dad implementation ready for Apple beta review, upload a new TestFlight build that contains it, and use that build for review instead of build 2209.

## Refined Goal

Finish the existing self-hosted onboarding work without discarding the current dirty-worktree implementation, fix all release-blocking defects and regressions, and validate the backend, Docker deployment, iOS unit tests, and complete iOS UI suite. Commit and push the completed product work, then archive and upload a newly numbered TestFlight build containing the self-hosted server selection, QR/manual onboarding, invitation, child credential, and offline Explore Demo experiences. Prepare the uploaded build for external Beta App Review, but do not perform the final App Store Connect submission without the user's explicit confirmation immediately before submission.

## Acceptance Criteria

- [ ] The self-hosted onboarding implementation is complete and preserves the existing offline Explore Demo and production behavior.
- [ ] Backend Release build with warnings-as-errors and all backend tests pass.
- [ ] The Docker image builds, the stack starts, and `http://localhost:8080/health` returns success.
- [ ] iOS project generation, simulator unit tests, focused onboarding UI tests, and the complete iOS UI suite pass on iPhone 17 Pro Max.
- [ ] The TestFlight release script completes a signed Release archive/export without undefined variables or stale hardwired-server assumptions.
- [ ] Product code, tests, deployment helpers, and directly related documentation are committed and pushed to the current branch.
- [ ] A new TestFlight build newer than 2209 is uploaded successfully and confirmed in App Store Connect processing or available state.
- [ ] The new build is ready to be selected for external testing and Beta App Review using the saved self-hosting and offline-demo review metadata.

## Scope Boundaries

**In scope:**
- Existing uncommitted backend, iOS, deployment, test, and documentation changes for self-hosted onboarding.
- Fixes required for all relevant quality gates and release tooling.
- A new signed TestFlight archive and upload.
- Verification in App Store Connect that the new build exists and can proceed to external beta review.

**Out of scope:**
- Unrelated product features or visual redesigns.
- Production backend deployment for any particular family.
- App Store production release submission.
- Final Beta App Review form submission without the required immediate user confirmation.
- Replacing the already-saved TestFlight description and review notes unless verification finds they did not persist.

## Applicable Project Conventions

**Quality gate commands:**
- `dotnet restore backend/BankOfDad.slnx`
- `dotnet build backend/BankOfDad.slnx --configuration Release --no-restore -p:TreatWarningsAsErrors=true "-p:WarningsNotAsErrors=NU1901%3BNU1902%3BNU1903%3BNU1904"`
- `dotnet test backend/BankOfDad.slnx --configuration Release --no-build`
- `docker compose build && docker compose up -d && curl -fsS http://localhost:8080/health`
- `cd ios && xcodegen generate`
- `cd ios && xcodebuild test -project BankOfDad.xcodeproj -scheme BankOfDad -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -skip-testing:BankOfDadUITests CODE_SIGNING_ALLOWED=NO`
- `cd ios && ./scripts/run-ui-tests.sh OnboardingTests`
- `cd ios && ./scripts/run-ui-tests.sh`
- `cd ios && UPLOAD=0 ./scripts/testflight.sh`

**Commit convention:**
- Concise imperative subjects are the project norm.
- Goal iteration commits use conventional commits with `[B]` or `[I]` role markers.
- Include `Assisted-by: OpenAI:GPT-5.6 Luna` for Builder commits and `Assisted-by: OpenAI:GPT-5.6 Sol` for Inspector commits.
- Include repository-required Copilot trailers where applicable.

**Guidelines:**
- `.github/workflows/ci.yml`
- `README.md`
- `ios/README.md`
- `deploy/README.md`
- `docs/app-store/metadata.md`

**Rules:**
- Preserve the dirty-worktree self-hosted implementation; do not reset or overwrite it.
- One family per server, stable configured server identity, HTTPS for public servers, restricted private HTTP, short-lived single-use QR enrollment tokens, and credential-based child login.
- Demo mode remains fully local and never contacts production services.
- Ordinary self-hosted deployments must not require Apple or APNs credentials.
- Use the iPhone 17 Pro Max simulator for iOS validation.
- Do not perform final Beta App Review submission without immediate user confirmation.
