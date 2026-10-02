# Bank of Dad iOS

Native SwiftUI iOS 17 app for parents ("the Bank") to manage family loans and for kids to view balances, schedules, fees, receipts, and reminders.

## Generate the Xcode project

```sh
brew install xcodegen
cd ios
xcodegen generate
open BankOfDad.xcodeproj
```

The app target is `BankOfDad`. Unit tests live in `BankOfDadTests`, and end-to-end UI tests live in `BankOfDadUITests` (see below). `BankOfDadUITests/DemoModeUITests.swift` is the exception: it drives demo mode and needs no backend. Swift is pinned to 5.10 to avoid strict concurrency surprises while still building cleanly in Xcode 16.

## Connecting to a backend

Production users select their family server at runtime. A fresh deployment prints a one-time setup code; its root page turns that code into a short-lived setup QR. Later co-parent and child invitations use the same versioned connection envelope with the server origin, stable installation ID, intended role, and a short-lived single-use token.

The app always fetches `/.well-known/bankofdad`, verifies that the descriptor's canonical origin and installation ID match the QR, and shows a confirmation before saving the profile. Tokens and server identity are stored together in the Keychain so credentials cannot be sent to another server.

For local development, `API_BASE_URL` remains a Debug/UI-test seed profile. The app verifies the descriptor before importing it. Public HTTP is rejected. HTTP is accepted only for loopback, `.local`, link-local, and private IP addresses and shows a prominent warning; HTTPS uses normal iOS certificate validation.

## Install on family devices (TestFlight)

TestFlight installs the app on real iPhones without an App Store listing. You need a paid Apple Developer Program membership. Every phone also needs [Tailscale](../deploy/README.md#family-devices) connected, because that's how it reaches the server.

### One-time setup

1. **Settings:** copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set:
   - `API_BASE_URL`: your server, e.g. `https:/$()/bankofdad.<tailnet>.ts.net`;
   - `BANKOFDAD_BUNDLE_ID`: a reverse-DNS ID you own, e.g. `com.yourname.bankofdad`. It's permanent once the app exists in App Store Connect;
   - `DEVELOPMENT_TEAM`: your team ID, from developer.apple.com > Account > Membership details.
2. **Xcode:** sign in under Xcode > Settings > Accounts. If your team has never had a device registered, connect your iPhone and run the app from Xcode once first. Archiving needs a development profile, and Apple only issues one when the team has at least one device.
3. **Register the bundle ID:** run `UPLOAD=0 ./scripts/testflight.sh` once. Xcode's automatic signing registers the ID with the Sign in with Apple and Push Notifications capabilities.
4. **App Store Connect:** under Apps, click + > New App. Choose iOS, pick your bundle ID, and enter any SKU. The name must be unique across the App Store, but the home-screen name stays "Bank of Dad".
5. **Server:** ordinary public self-hosted servers need no Apple private keys. Their descriptor hides Sign in with Apple, skips APNs registration, and keeps reminders/receipts in Inbox. Only an official/custom server may configure matching Sign in with Apple and APNs keys for this app ID.

### Upload a build

```sh
./scripts/testflight.sh
```

The script archives the Release configuration, signs it for App Store distribution and uploads it. The build number is the UTC time (`YYYYMMDD.HHMM`), so each upload is newer than the last. The build appears under TestFlight after processing, which usually takes 5 to 15 minutes. It refuses to run with the placeholder bundle ID or without a team; the family server is selected at runtime.

| Variable | Purpose |
|---|---|
| `BUILD_NUMBER` | Override the build number. |
| `UPLOAD=0` | Export a signed `.ipa` to `build/export` instead of uploading. |
| `ASC_KEY_PATH`, `ASC_KEY_ID`, `ASC_ISSUER_ID` | Use an App Store Connect API key instead of the Xcode account, e.g. on a build machine. |

### Invite testers

- **Adults (no review):** add each person under Users and Access with the Developer or Marketing role. Individual memberships allow up to 50 users. Then add them to an **Internal Testing** group on the app's TestFlight tab. They accept the email invite in the TestFlight app. Internal builds install right away and expire after 90 days, so upload a new build before then.
- **External testers:** create an **External Testing** group and invite by email or public link. The first build of each version goes through TestFlight App Review. Reviewers can't reach a tailnet-only server, so explain that in the review notes.
- **Children:** Apple IDs for children under 13 may not be able to redeem TestFlight invites. For a child's phone, connect it to the Mac and run the app from Xcode instead. That needs Developer Mode on the phone, and the signing profile lasts a year.

## Demo mode

"Explore Demo" on the Welcome screen opens the whole app — the real screens and view models — against sample data that lives only in memory on the device. It needs no account, no backend, and no network, which makes it usable for App Review, for trying the app before pairing a kid's phone, and for App Store screenshots.

How it works: every feature talks to the `FamilyService`, `LoanService`, `BillService` and `NotificationService` protocols in `Core/Services`. Normally `AppEnvironment` injects the `Live*` implementations that call the API; in demo mode it injects the `Demo*` implementations from `Core/Demo`, which are backed by one `DemoStore` actor wrapping the pure `DemoEngine`. The engine is a Swift port of the backend's loan and bill math, so balances, schedules, payment waterfalls, late fees and receipts behave exactly like the real thing.

Isolation is enforced, not merely implied:

- `APIClient` throws `APIError.demoModeNetworkBlocked` for any request raised while the demo is active, so no production call can escape.
- `PushManager` never asks for notification authorization, and device registration is a no-op.
- `AuthSession.beginDemo`/`endDemo` keep the demo user in memory; sign-out paths never touch the keychain, so leaving the demo cannot delete a real session.

Sample data ("The Parkers") is deterministic and expressed relative to the current date: two children, an active loan with an overdue installment and a late fee, a paid-off loan, a loan that just started, two recurring bills with charge and payment history, and an Inbox of reminders, receipts and late-fee notices. Seeded payments are replayed through the engine in chronological order so every balance and receipt is internally consistent.

In the demo a persistent banner sits above every screen. Tapping it (or the Demo section in Settings) switches between the parent and each kid, resets the data, or exits back to Welcome.

### Launch arguments (screenshots and UI tests)

| Argument | Effect |
|---|---|
| `-DemoMode` | Launches straight into the demo, skipping Welcome. |
| `-DemoRole parent\|kid` | Which side to open. Defaults to `parent`. |
| `-DemoDate YYYY-MM-DD` | Pins "today", so a run renders byte-identical content. |

Unlike `-UITests`, these work in Release builds too, because the demo is a shipping feature.

```sh
xcrun simctl launch --console booted com.example.bankofdad -DemoMode -DemoRole kid -DemoDate 2026-03-14
```

## Apple and push capabilities

`BankOfDad.entitlements` permits Sign in with Apple and APNs, but the connected server descriptor controls whether either feature appears. Public self-hosted servers normally advertise neither because distributing the App Store owner's private Apple keys would be unsafe. When push is unsupported, iOS never requests notification permission and Inbox continues to work.

## Enrollment notes

Connection links use `bankofdad://connect?v=1&origin=…&server=…&kind=…&token=…`. QR codes never contain a password, PIN, access token, or refresh token.

- Bootstrap creates the server's one family and first parent.
- Co-parent enrollment selects the server and creates an email/password account.
- Child enrollment is bound to an existing child and creates a unique username with either a password or numeric PIN.
- Generating a new child enrollment revokes existing child sessions and supersedes older unused enrollment links.
- Returning children sign in with username/password or username/PIN; there is no passwordless production pairing.

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
