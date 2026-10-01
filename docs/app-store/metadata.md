# App Store listing metadata

Source copy for App Store Connect. Do not paste secrets, real family data, or private server addresses into listing fields.

## Listing fields

- **Name:** Bank of Dad
- **Subtitle:** Family loans made simple
- **Promotional text:** Make family loans and recurring bills clear, friendly, and easy to follow.
- **Primary category:** Finance
- **Secondary category:** Lifestyle (if available and appropriate)
- **Keywords (under 100 characters):** `family loans,allowance,bills,debt,payments,repayment,kids,finance`
- **Copyright:** `© 2026 Jeff Papiez`
- **Support URL:** `https://github.com/jpapiez/BankOfDad/blob/main/docs/support.md`
- **Privacy policy URL:** `https://github.com/jpapiez/BankOfDad/blob/main/docs/privacy.md`
- **Marketing URL:** `https://github.com/jpapiez/BankOfDad`

### Description

Bank of Dad is a private family ledger that makes loans, recurring bills, and repayment progress easy to understand.

Parents can:

- Create family loans with optional interest, installment schedules, grace periods, and late fees.
- Set up recurring bills for expenses such as phones, insurance, or shared subscriptions.
- Record payments and see payment history, balances, receipts, and repayment progress.
- Get reminders for upcoming payments and notifications when late fees are assessed.
- Invite another parent and manage children, pairing codes, and family settings.

Kids get a focused view of what they owe, upcoming payments, bills, payment history, and notifications on their paired device.

Bank of Dad is designed for a specific family, not a public social network. Family members need an invitation or configured private access to the family's service. The production service may be reachable only through the family's private Tailscale network.

## App Privacy worksheet

Complete App Store Connect answers from the actual submitted build and the deployed service configuration:

| Category | Data type | Collected? | Linked to user? | Used for tracking? | Purpose |
|---|---|---:|---:|---:|---|
| Contact Info | Name, Email Address | Yes | Yes | No | Account and family access |
| Financial Info | Other Financial Info (family loans, bills, balances, debt, payments, fees, and repayment schedules) | Yes | Yes | No | Family ledger |
| User Content | Other User Content (payment and ledger notes) | Yes | Yes | No | Family ledger |
| Identifiers | User ID (internal account and Apple account identity) | Yes | Yes | No | Authentication and family access |
| Identifiers | Device ID (APNs device token and paired-device identity) | Yes | Yes | No | Push notifications and device access |
| Diagnostics | Other Diagnostic Data (retained service error/security logs, if enabled by the operator) | Operator-configured | Potentially | No | Security and troubleshooting |
| Other Data | Other Data Types (password hash, encrypted Apple refresh token, and session credential records) | Yes | Yes | No | Account security and authorization revocation |

Select **Data Used to Track You: No**. Do not select advertising, analytics, sale, or third-party tracking. Review the final answers against the production configuration before submission.

## Review Notes template

> Bank of Dad is intended for unlisted distribution to a specific family and should not appear in public search or charts. Please evaluate the submitted build as an Unlisted App.
>
> **[DEPENDENT ON #25 — replace before submission]** The submitted build includes **Explore Demo**, which is offline/local and does not contact the production family service. From the welcome screen, choose Explore Demo. Use the role switcher to inspect the parent and kid views. No real family or financial data is included.
>
> Production family access uses the family's private Tailscale service and requires configured access or an invitation. Review does not need production credentials because the demo is self-contained.

**Demo dependency:** issue #25 must land before the demo paragraph is used in App Store Connect. Replace the placeholder with the verified entry point and role-switching steps from the final screenshot build; do not claim demo-mode behavior before then.

## Screenshots

Capture 6–8 portrait screenshots from the same deterministic demo build on Apple's current highest-resolution supported iPhone simulator: Welcome/Explore Demo, Parent Dashboard, Owed loans and bills, Child detail, Loan detail/payment progress, Bill detail, Kid What I Owe, and Inbox. Use only sample data and consistent simulator status-bar time. Do not fabricate screenshots or duplicate production UI.
