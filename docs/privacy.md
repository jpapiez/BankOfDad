# Bank of Dad privacy policy

**Effective date: October 1, 2026**

Bank of Dad is designed for one private family at a time. The family operates its own Bank of Dad service, commonly reachable only through Tailscale. This policy describes the data stored by that service and used by the iOS app.

## Data stored and why

- **Parent account data:** display name, email address, internal account identifier, Apple identifier and encrypted Apple refresh token when Sign in with Apple is used, and password authentication data. This is used to authenticate parents, identify the family account, and revoke Apple authorization during deletion.
- **Child profile data:** child display name and selected avatar color. This is used to show the child view and distinguish family members.
- **Family ledger data:** family name, time zone, currency, loan and recurring-bill terms, repayment schedules, payment history, late fees, receipts, and notes. This is the core service requested by the family.
- **Device and security data:** APNs device token, device name, token expiration/revocation state, hashed refresh tokens, and timestamps. These are used for notifications, session security, and device access control.
- **Operational data:** service logs and error information may be retained by the family-operated host for troubleshooting and security. Operators should configure host logging according to their retention needs.

Bank of Dad does **not** use advertising, analytics, cross-site tracking, tracking identifiers, data brokerage, or sale of personal information. The app does not sell family or children's data.

## Retention and deletion

Parents can use **Settings > Delete My Account**. For accounts that use Sign in with Apple, the service first revokes the retained Apple refresh token; if Apple revocation fails, deletion fails and local account data remains intact so the user can retry. After successful Apple revocation (when applicable), deleting the last parent deletes the family account and its private family data, including children, loans, bills, payments, notifications, invitations, device tokens, and refresh tokens, in one database transaction. Deleting one parent from a multi-parent family deletes that parent's credentials, tokens, notifications, invitations, Apple identifier, and encrypted Apple refresh token while preserving the shared family ledger for the remaining parent(s).

The family service operator controls backups and operational logs. They should remove deleted records from backups according to their documented backup-retention schedule and avoid retaining unnecessary logs.

## Children's data

Children's profiles and ledger entries are entered and controlled by the parent family. A child device receives only the paired child's permitted loan, bill, payment, and notification information. Children do not create parent accounts or see another family.

## Security

The service uses authenticated HTTPS deployments, signed short-lived access tokens, hashed refresh tokens, and revocable device tokens. Families should keep the service, Tailscale, Apple accounts, and hosting environment up to date; never share pairing codes or credentials in public issues.

## Contact

For general support or privacy questions, use the repository's public [issue tracker](https://github.com/jpapiez/BankOfDad/issues) and omit secrets and private family data. Account-specific deletion problems must use the private support channel supplied by the family's service operator, because GitHub issues are public. No personal email, phone number, or address is published here.
