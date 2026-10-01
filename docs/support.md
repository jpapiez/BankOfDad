# Bank of Dad support

Bank of Dad is a private family ledger for recording parent-to-child loans, recurring bills, repayment schedules, payments, reminders, and receipts. Parents manage the family account; children use a paired device to view what they owe.

## Installation and Tailscale

The app connects to the family's private Bank of Dad service. Family devices must have [Tailscale](https://tailscale.com/) connected and be allowed onto the family's tailnet. The app does not provide a public hosted banking service.

## Troubleshooting

- **The app cannot connect:** open Tailscale, confirm the device is connected to the correct tailnet, and try again. The service host must be running and reachable over HTTPS.
- **A child cannot pair:** ask a parent to generate a new pairing code. Codes expire and can be used only once.
- **Push notifications are missing:** confirm notifications are enabled for Bank of Dad and that the service has the current device registered.
- **Sign-in fails:** confirm the device has network access to the private service and use the same Apple ID or email account that was invited.

## Help and deletion requests

Please use the repository's public [issue tracker](https://github.com/jpapiez/BankOfDad/issues) to report a reproducible problem or request general help. Do not include passwords, authentication tokens, private family ledger data, or children's personal information in an issue.

Parents can delete an account from **Settings > Delete My Account**. GitHub issues are public and must not be used for account or data-deletion requests. If in-app deletion cannot be used, contact the operator through the private support channel provided when the family's service was installed; the operator will provide a safe deletion procedure. We do not publish a personal support email, phone number, or address.
