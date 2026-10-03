# Iteration 5 evidence

## Quality gates

All required local gates were rerun against the current worktree:

| Gate | Result |
|---|---|
| `dotnet restore backend/BankOfDad.slnx` | **PASS** — all projects up to date |
| Release backend build with warnings as errors | **PASS** — 0 warnings, 0 errors |
| `dotnet test backend/BankOfDad.slnx --configuration Release --no-build` | **PASS** — 77 tests |
| `docker compose build && docker compose up -d && curl -fsS http://localhost:8080/health` | **PASS** — `Healthy` |
| `cd ios && xcodegen generate` | **PASS** |
| iOS simulator unit tests on iPhone 17 Pro Max | **PASS** — 36 tests |
| `cd ios && ./scripts/run-ui-tests.sh OnboardingTests` | **PASS** — 10 tests, 0 failures |
| `cd ios && ./scripts/run-ui-tests.sh` | **PASS** — 71 tests, 0 failures |
| `cd ios && UPLOAD=0 ./scripts/testflight.sh` | **PASS** — signed Release export `20261003.0511` |

The complete UI result bundle is:

```text
ios/build/Logs/Test/Test-BankOfDad-2026.10.02_21-46-12--0700.xcresult
```

The exported IPA was independently checked:

- Bundle identifier: `com.jpapiez.bankofdad`
- Marketing version: `1.0`
- Build number: `20261003.0511`
- Signing identity: Apple Distribution for team `ZPKA84F3TY`
- Provisioning profile: `beta-reports-active=true`, `get-task-allow=false`

## App Store Connect verification

The live App Store Connect acceptance criteria remain blocked by the
environment, not by product or release-tooling failures:

- `ASC_KEY_PATH`, `ASC_KEY_ID`, and `ASC_ISSUER_ID` are unset.
- `$HOME/.appstoreconnect/private_keys` is absent.
- The existing Safari App Store Connect window exposes neither a verified URL
  nor an accessibility tree. The computer-use tool therefore fail-closed and
  did not infer or interact with page contents.
- No upload was attempted in this iteration because no safely usable
  authenticated account or transient API-key environment is available.
- No build selection, external-testing group selection, metadata, or Beta App
  Review submission was changed.

The previously recorded upload of build `20261002.2202` remains the only local
delivery evidence; this iteration adds no unsupported claim about its current
processing or availability state.

## Safety and history

- No credentials, private keys, personal data, or real family/server data were
  added or stored.
- The Builder commit for this iteration includes the required parsed trailers:
  `Assisted-by: OpenAI:GPT-5.6 Luna`,
  `Co-authored-by: Copilot App <223556219+Copilot@users.noreply.github.com>`,
  and `Copilot-Session: 66bfa029-1397-4f8e-be9a-65b6531f3367`.
- Earlier goal commits with inconsistent trailer parsing were not rewritten;
  doing so would violate the one-commit iteration and normal-push constraints.
