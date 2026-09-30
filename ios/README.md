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
3. To use another backend, for example the [Tailscale-hosted server](../deploy/README.md) on a physical device, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` (gitignored) and set `API_BASE_URL = https:/$()/bankofdad.<tailnet>.ts.net`. The next build uses it. `API_BASE_URL` defaults to `http://localhost:8080` in `Config/App.xcconfig`. App Transport Security only allows plain HTTP to `localhost` and `127.0.0.1`, so remote servers must use HTTPS, which the Tailscale setup provides.

## Install on family devices (TestFlight)

TestFlight installs the app on real iPhones without an App Store listing. You need a paid Apple Developer Program membership. Every phone also needs [Tailscale](../deploy/README.md#family-devices) connected, because that's how it reaches the server.

### One-time setup

1. **Settings:** copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set:
   - `API_BASE_URL`: your server, e.g. `https:/$()/bankofdad.<tailnet>.ts.net`;
   - `BANKOFDAD_BUNDLE_ID`: a reverse-DNS ID you own, e.g. `com.yourname.bankofdad`. It's permanent once the app exists in App Store Connect;
   - `DEVELOPMENT_TEAM`: your team ID, from developer.apple.com > Account > Membership details.
2. **Xcode:** sign in under Xcode > Settings > Accounts.
3. **Register the bundle ID:** run `UPLOAD=0 ./scripts/testflight.sh` once. Xcode's automatic signing registers the ID with the Sign in with Apple and Push Notifications capabilities.
4. **App Store Connect:** under Apps, click + > New App. Choose iOS, pick your bundle ID, and enter any SKU. The name must be unique across the App Store, but the home-screen name stays "Bank of Dad".
5. **Server:** set `APPLE_CLIENT_ID` and `APNS_BUNDLE_ID` to the bundle ID. For push, create an APNs key (Certificates, IDs & Profiles > Keys, choosing Sandbox & Production). Set `APNS_KEY_ID`, set `APNS_TEAM_ID`, and install the `.p8`. Set `APNS_USE_SANDBOX=false`, because TestFlight builds register production push tokens.

### Upload a build

```sh
./scripts/testflight.sh
```

The script archives the Release configuration, signs it for App Store distribution and uploads it. The build number is the UTC time (`YYYYMMDD.HHMM`), so each upload is newer than the last. The build appears under TestFlight after processing, which usually takes 5 to 15 minutes. It refuses to run with the placeholder bundle ID, without a team, or with a non-HTTPS `API_BASE_URL`.

| Variable | Purpose |
|---|---|
| `BUILD_NUMBER` | Override the build number. |
| `UPLOAD=0` | Export a signed `.ipa` to `build/export` instead of uploading. |
| `ASC_KEY_PATH`, `ASC_KEY_ID`, `ASC_ISSUER_ID` | Use an App Store Connect API key instead of the Xcode account, e.g. on a build machine. |

### Invite testers

- **Adults (no review):** add each person under Users and Access with the Developer or Marketing role. Individual memberships allow up to 50 users. Then add them to an **Internal Testing** group on the app's TestFlight tab. They accept the email invite in the TestFlight app. Internal builds install right away and expire after 90 days, so upload a new build before then.
- **External testers:** create an **External Testing** group and invite by email or public link. The first build of each version goes through TestFlight App Review. Reviewers can't reach a tailnet-only server, so explain that in the review notes.
- **Children:** Apple IDs for children under 13 may not be able to redeem TestFlight invites. For a child's phone, connect it to the Mac and run the app from Xcode instead. That needs Developer Mode on the phone, and the signing profile lasts a year.

## Push notifications

`BankOfDad.entitlements` enables Sign in with Apple, APNs (development; distribution signing switches it to production), and remote-notification background mode. Configure an Apple developer team, App ID, APNs key/certificate, and backend push provider before testing device push. APNs registration is skipped until a user is authenticated; tokens are posted to `/api/v1/devices` as sandbox in Debug and production otherwise.

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
