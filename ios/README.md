# Bank of Dad iOS

Native SwiftUI iOS 17 app for parents ("the Bank") to manage family loans and for kids to view balances, schedules, fees, receipts, and reminders.

## Generate the Xcode project

```sh
brew install xcodegen
cd ios
xcodegen generate
open BankOfDad.xcodeproj
```

The app target is `BankOfDad`. Unit tests live in `BankOfDadTests`, and end-to-end UI tests live in `BankOfDadUITests` (see below). Swift is pinned to 5.10 to avoid strict concurrency surprises while still building cleanly in Xcode 16.

## Running against the local backend

1. From the repository root, start the backend stack with Docker according to the root README/backend instructions.
2. In Xcode, run the app on an iOS 17 simulator. The default `API_BASE_URL` build setting is `http://localhost:8080`, and the simulator can reach that directly.
3. On a physical device, override `API_BASE_URL` in an `.xcconfig` or scheme environment/build setting to your Mac LAN IP, for example `http://192.168.1.42:8080`.

## Push notifications

`BankOfDad.entitlements` enables Sign in with Apple, APNs development, and remote-notification background mode. Configure an Apple developer team, App ID, APNs key/certificate, and backend push provider before testing device push. APNs registration is skipped until a user is authenticated; tokens are posted to `/api/v1/devices` as sandbox in Debug and production otherwise.

## Pairing notes

Parents generate pairing codes from Family > Pair Child. Kids can type the code, scan the QR code, or open `bankofdad://pair?code=...`. Dashes/spaces are stripped and input is uppercased before calling `/api/v1/auth/pair`.

## End-to-end UI tests

`BankOfDadUITests` is an XCUITest suite that drives the app on a simulator against the **real** Docker backend. Tests seed their preconditions (parents, children, loans, payments, pairing codes) through the API with a unique email per test. They exercise the feature under test through the UI and verify the result through both the UI and the API. Tests are independent and can run in any order.

Run the suite from `ios/`:

```sh
./scripts/run-ui-tests.sh                                  # whole suite
./scripts/run-ui-tests.sh LoansListTests                   # one class
./scripts/run-ui-tests.sh LoanDetailTests/testCancelLoanAfterConfirmation
```

The script does the following:
1. Runs `docker compose up -d --build` with `ASPNETCORE_ENVIRONMENT=Development` and `TEST_HOOKS_ENABLED=true`. It honors `NUGET_SOURCE` if that's set.
2. Waits for `/health` and checks that the test hooks are mapped.
3. Runs `xcodegen generate` and boots the simulator.
4. Runs `xcodebuild test -only-testing:BankOfDadUITests` with ad-hoc signing (`CODE_SIGN_IDENTITY=-`). Don't use `CODE_SIGNING_ALLOWED=NO`: it strips the entitlements, and the Keychain then fails with -34018.

| Variable | Default | Purpose |
|---|---|---|
| `SIMULATOR_ID` | first available iPhone 17 Pro Max | Simulator UDID to test on |
| `DESTINATION` | `id=$SIMULATOR_ID` | Full `xcodebuild -destination` override |
| `API_URL` | `http://localhost:8080` | Backend URL for both the app (`API_BASE_URL`) and the test runner's seeding client. Plain HTTP is only allowed to `localhost` and `127.0.0.1`. |
| `SKIP_BACKEND=1` | off | Don't touch docker compose (the stack is already running with hooks on) |
| `NO_BUILD=1` | off | `docker compose up` without `--build` |
| `XCODEBUILD_EXTRA_ARGS` | — | Extra arguments passed to `xcodebuild` |

CI skips this target (`-skip-testing:BankOfDadUITests`) because it needs the backend.

### How it works

- **Launch hooks** (`App/UITestHooks.swift`) are compiled only into Debug builds and honored only when the app is launched with `-UITests`:
  - `-UITestsResetKeychain` starts signed out.
  - The `UITESTS_ACCESS_TOKEN` / `UITESTS_REFRESH_TOKEN` environment variables start signed in as a seeded user.
  - The push-permission prompt is skipped, so the system alert never blocks a test.
- **Backend test hooks** (`/api/v1/testing/*`, Development only, opt-in) backdate a loan's due dates and run the reminder / late-fee sweep on demand. This is how late fees, late counts, reminders and waiving are tested.
- Views carry `accessibilityIdentifier`s (for example `loanRow.<LOANID>`, `loanDetail.balance`, `errorBanner`) wherever labels are ambiguous or dynamic.

### Not automated

- **Sign in with Apple**: the tests only assert that the button is offered.
- **QR scanning** needs a camera. The same `bankofdad://pair?code=` link is tested through deep links instead.
- **Real APNs delivery**: push registration is skipped under test. Notifications are verified through the in-app Inbox and the API.
