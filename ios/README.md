# Bank of Dad iOS

Native SwiftUI iOS 17 app for parents ("the Bank") to manage family loans and for kids to view balances, schedules, fees, receipts, and reminders.

## Generate the Xcode project

```sh
brew install xcodegen
cd ios
xcodegen generate
open BankOfDad.xcodeproj
```

The app target is `BankOfDad` and tests live in `BankOfDadTests`. Swift is pinned to 5.10 to avoid strict concurrency surprises while still building cleanly in Xcode 16.

## Running against the local backend

1. From the repository root, start the backend stack with Docker according to the root README/backend instructions.
2. In Xcode, run the app on an iOS 17 simulator. The default `API_BASE_URL` build setting is `http://localhost:8080`, and the simulator can reach that directly.
3. On a physical device, override `API_BASE_URL` in an `.xcconfig` or scheme environment/build setting to your Mac LAN IP, for example `http://192.168.1.42:8080`.

## Push notifications

`BankOfDad.entitlements` enables Sign in with Apple, APNs development, and remote-notification background mode. Configure an Apple developer team, App ID, APNs key/certificate, and backend push provider before testing device push. APNs registration is skipped until a user is authenticated; tokens are posted to `/api/v1/devices` as sandbox in Debug and production otherwise.

## Pairing notes

Parents generate pairing codes from Family > Pair Child. Kids can type the code, scan the QR code, or open `bankofdad://pair?code=...`. Dashes/spaces are stripped and input is uppercased before calling `/api/v1/auth/pair`.
