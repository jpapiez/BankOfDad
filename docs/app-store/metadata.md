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

Bank of Dad helps families manage money they lend to their children and recurring expenses their children are responsible for. It provides a clear, shared ledger without turning family finances into a public service.

Parents can:

- Create family loans with optional interest, installment schedules, grace periods, and late fees.
- Track recurring bills children are responsible for, such as mobile phone service, car insurance, or shared subscriptions.
- Record payments and see payment history, balances, receipts, and repayment progress.
- Get reminders for upcoming payments and notifications when late fees are assessed.
- Connect the app to a family-operated Bank of Dad server.
- Invite another parent and securely set up child logins with short-lived QR codes.

Kids get a focused view of what they owe, upcoming payments, bills, payment history, and notifications on their paired device.

Bank of Dad is available to any family willing to operate its own Bank of Dad backend. One parent deploys the open-source server and connects the iOS app by scanning its protected setup QR or entering its address. Each family controls where its data is hosted and who can access it. Other parents and children join through short-lived invitation or setup QR codes.

The app also includes an offline Explore Demo with realistic sample loans, recurring bills, payments, reminders, and receipts. Demo data stays on the device and does not require a server or account.

## TestFlight Beta App Description

Bank of Dad helps families manage money they lend to their children and recurring expenses their children are responsible for.

Parents can create loans with installment schedules, optional interest, grace periods, and late fees; track recurring bills such as mobile phone service, car insurance, and shared subscriptions; record payments; and review balances, repayment progress, reminders, receipts, and payment history. Children get a simple view of what they owe and when payments are due.

The app is not limited to the developer's family. Any family can deploy the open-source Bank of Dad backend and connect the iOS app by scanning the server's protected setup QR or entering its address. Each family operates its own server and controls its own data. Parents and children join through short-lived setup or invitation QR codes.

For testing without a server, choose **Explore Demo** on the Welcome screen. The offline demo includes realistic sample loans, recurring bills, payments, reminders, and receipts and never contacts a production server.

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

> Bank of Dad is a client for a self-hosted family finance service. It is not limited to the developer's family: any family can deploy the open-source Bank of Dad backend, connect the iOS app by scanning the server's protected setup QR or entering its address, and invite parents or children with short-lived QR codes. Each family operates its own server and controls its own data.
>
> The app tracks both family loans and recurring bills that children are responsible for, such as mobile phone service, insurance, and shared subscriptions. Parents can define schedules, optional interest and late fees, record payments, and review balances, reminders, receipts, and payment history. Children receive a focused view of what they owe and when payments are due.
>
> The submitted build includes a fully local, offline **Explore Demo** containing realistic sample loans, recurring bills, payments, reminders, and receipts. It does not contact a production server and contains no real family or financial data. From **Welcome**, choose **Explore Demo**, then **Explore as a parent**. Tap the persistent **Demo mode** banner to switch between the parent experience and the child experiences for **Maya** or **Theo**. Review does not need production credentials because the demo is self-contained.

## Screenshots

Capture 6–8 portrait screenshots from the same deterministic demo build on Apple's current highest-resolution supported iPhone simulator: Welcome/Explore Demo, Parent Dashboard, Owed loans and bills, Child detail, Loan detail/payment progress, Bill detail, Kid What I Owe, and Inbox. Use only sample data and consistent simulator status-bar time. Do not fabricate screenshots or duplicate production UI.
