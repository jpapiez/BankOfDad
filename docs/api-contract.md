# Bank of Dad — API Contract (v1)

This is the shared contract between the backend (`backend/`) and the iOS app (`ios/`).
Any change here must be reflected on both sides.

## Conventions
- Base URL: `http://localhost:8080` in development. All routes are prefixed with `/api/v1`.
- JSON, `camelCase` property names. Enums serialized as **camelCase strings** (e.g. `"monthly"`, `"parent"`, `"paidOff"`).
- Money: JSON **number** with up to 2 decimals (e.g. `125.50`). Rates: decimal fraction (`0.05` = 5% APR). Percent late fee is also a fraction (`0.10` = 10%).
- Dates (calendar, family-local): `"yyyy-MM-dd"` strings. Timestamps: ISO-8601 UTC (`"2026-09-27T22:00:00Z"`).
- IDs: UUID strings.
- Auth: `Authorization: Bearer <accessToken>`. Access tokens live 15 minutes; refresh tokens 60 days (rotated on every refresh).
- Errors: RFC 7807 `application/problem+json` (`{ "title", "status", "detail", "errors"? }`). 400 validation, 401 unauthenticated, 403 wrong role, 404 not found (including resources in other families), 409 conflict.
- JWT claims: `sub` (userId), `family_id`, `role` (`parent`|`child`), `name`.
- One production deployment owns one family. Family creation uses the one-time bootstrap flow; anonymous legacy registration is limited to Development/Testing.
- Runtime clients discover a server through `GET /.well-known/bankofdad`. Public origins require HTTPS; plain HTTP is accepted only for local/private hosts.

## Enums
- `Role`: `parent`, `child`
- `Frequency`: `weekly`, `biweekly`, `monthly`, `quarterly`, `yearly` (`quarterly` and `yearly` are accepted for loans too)
- `LoanStatus`: `active`, `paidOff`, `cancelled`
- `BillStatus`: `active`, `ended`
- `InstallmentStatus`: `upcoming` (due date in future), `due` (due today / within grace), `late` (past grace, not fully paid), `paid` (also used for bill charges)
- `NotificationType`: `reminder`, `receipt`, `loanCreated`, `lateFee`, `billCreated`
- `AllocationTarget`: `lateFee`, `interest`, `principal`, `charge` (bill payments)

Clients must tolerate enum values they don't know yet.

## Shared shapes
```jsonc
// AuthResponse
{ "accessToken": "…", "refreshToken": "…", "expiresAt": "2026-09-27T22:15:00Z", "user": UserDto }

// UserDto
{ "id": "uuid", "familyId": "uuid", "role": "parent", "displayName": "Dad", "email": "dad@example.com" /* null for kids */ }

// FamilyDto
{ "id": "uuid", "name": "The Smiths", "timeZone": "America/Los_Angeles", "currency": "USD",
  "parents": [UserDto], "children": [ChildDto] }

// ChildDto
{ "id": "uuid", "displayName": "Sam", "avatarColor": "#4F8EF7", "pairedDeviceCount": 1 }  // count of active (unrevoked, unexpired) kid-device sessions

// LoanTermsInput (used by preview and create)
{ "childId": "uuid", "title": "New bike", "principal": 300.00,
  "interestEnabled": true, "annualRate": 0.05,            // treated as 0 when interestEnabled=false
  "frequency": "monthly", "installmentCount": 6, "firstDueDate": "2026-11-01",
  "lateFeeFlat": 5.00, "lateFeePercent": 0.10, "lateFeeGraceDays": 3,   // flat & percent nullable; grace default 0
  "sendReminders": true, "sendReceipts": true }

// SchedulePreview
{ "installmentAmount": 50.73, "totalInterest": 4.39, "totalRepayable": 304.39,
  "installments": [ { "seq": 1, "dueDate": "2026-11-01", "principalDue": 49.48, "interestDue": 1.25, "amountDue": 50.73 } ] }

// LoanSummaryDto
{ "id": "uuid", "title": "New bike", "childId": "uuid", "childName": "Sam", "principal": 300.00,
  "status": "active", "balance": 203.10, "amountPaid": 101.46, "nextDueDate": "2027-01-01", "nextAmountDue": 50.73,
  "lateInstallments": 0, "createdAt": "…" }
// nextDueDate / nextAmountDue are null when nothing remains.

// LoanDetailDto = all LoanSummaryDto fields plus:
{ "interestEnabled": true, "annualRate": 0.05, "frequency": "monthly", "installmentCount": 6, "firstDueDate": "2026-11-01",
  "lateFeeFlat": 5.00, "lateFeePercent": 0.10, "lateFeeGraceDays": 3, "sendReminders": true, "sendReceipts": true,
  "totalInterest": 4.39, "totalRepayable": 304.39, "outstandingFees": 0.00,
  "installments": [InstallmentDto], "payments": [PaymentDto], "lateFees": [LateFeeDto],
  "termsSummary": "Sam borrowed $300.00 for \"New bike\" at 5% APR, repaid in 6 monthly payments of $50.73 starting Nov 1, 2026. A late fee of $5.00 + 10% of the missed payment applies 3 days after a missed due date." }

// InstallmentDto
{ "id": "uuid", "seq": 1, "dueDate": "2026-11-01", "principalDue": 49.48, "interestDue": 1.25, "amountDue": 50.73,
  "principalPaid": 49.48, "interestPaid": 1.25, "remaining": 0.00, "status": "paid" }

// LateFeeDto
{ "id": "uuid", "installmentId": "uuid", "installmentSeq": 2, "amount": 10.07, "amountPaid": 0.00,
  "assessedAt": "…", "waivedAt": null }

// PaymentDto
{ "id": "uuid", "amount": 50.73, "paidOn": "2026-11-01", "note": "Cash", "recordedByName": "Dad", "createdAt": "…",
  "allocations": [ { "target": "interest", "installmentSeq": 1, "lateFeeId": null, "amount": 1.25 } ] }

// NotificationDto — exactly one of loanId / billId is set for loan and bill notifications
{ "id": "uuid", "type": "receipt", "title": "Payment received", "body": "…", "loanId": "uuid", "createdAt": "…", "readAt": null, "billId": null }

// DashboardDto — totalOutstanding = loan balances + bill balances (what is owed now)
{ "totalOutstanding": 248.10, "activeLoans": 1, "lateInstallments": 0,
  "upcoming": [ { "loanId": "uuid", "loanTitle": "New bike", "childName": "Sam", "dueDate": "2027-01-01", "amountDue": 50.73 } ],
  "activeBills": 1, "lateBillCharges": 0,
  "upcomingBills": [ { "billId": "uuid", "billTitle": "Cell phone", "childName": "Sam", "dueDate": "2027-01-01", "amountDue": 45.00 } ] }

// BillInput (create)
{ "childId": "uuid", "title": "Cell phone", "amount": 45.00, "frequency": "monthly", "firstDueDate": "2026-11-01",
  "lateFeeFlat": 2.00, "lateFeePercent": 0.10, "lateFeeGraceDays": 3,   // flat & percent nullable; grace default 0
  "sendReminders": true, "sendReceipts": true }

// BillSummaryDto
{ "id": "uuid", "title": "Cell phone", "childId": "uuid", "childName": "Sam", "amount": 45.00, "frequency": "monthly",
  "status": "active", "balance": 45.00, "upcomingAmount": 45.00, "amountPaid": 90.00,
  "nextDueDate": "2027-01-01", "nextAmountDue": 45.00, "lateCharges": 0, "createdAt": "…", "endedAt": null }
// amount = the current per-charge amount (applies to charges not yet generated / not yet due).
// balance = unpaid charges already due (due date ≤ today) + outstanding late fees: what is owed now.
// upcomingAmount = unpaid charges not yet due. nextDueDate / nextAmountDue = earliest unpaid charge (null when none).

// BillDetailDto = all BillSummaryDto fields plus:
{ "firstDueDate": "2026-11-01", "lateFeeFlat": 2.00, "lateFeePercent": 0.10, "lateFeeGraceDays": 3,
  "sendReminders": true, "sendReceipts": true, "outstandingFees": 0.00,
  "charges": [BillChargeDto],        // newest first
  "payments": [BillPaymentDto],      // newest first
  "lateFees": [BillLateFeeDto],
  "termsSummary": "Sam pays $45.00 monthly for \"Cell phone\" starting Nov 1, 2026, until the bill is ended. A late fee of $2.00 + 10% of the missed payment applies 3 days after a missed due date." }

// BillChargeDto
{ "id": "uuid", "seq": 3, "dueDate": "2027-01-01", "amount": 45.00, "amountPaid": 0.00, "remaining": 45.00, "status": "upcoming" }

// BillLateFeeDto
{ "id": "uuid", "chargeId": "uuid", "chargeDueDate": "2026-12-01", "amount": 6.50, "amountPaid": 0.00, "assessedAt": "…", "waivedAt": null }

// BillPaymentDto
{ "id": "uuid", "amount": 60.00, "paidOn": "2026-12-04", "note": "Allowance", "recordedByName": "Dad", "createdAt": "…",
  "allocations": [ { "target": "charge", "chargeId": "uuid", "chargeDueDate": "2026-11-01", "lateFeeId": null, "amount": 45.00 } ] }
```

## Endpoints

### Auth (anonymous unless noted)
| Method | Route | Body | Response |
|---|---|---|---|
| POST | `/api/v1/setup/complete` | `{ token, email, password, displayName, familyName, timeZone }` | 201 `AuthResponse` (consumes bootstrap token and creates the server's only family + first parent) |
| POST | `/api/v1/enrollment/inspect` | `{ token }` | 200 `{ kind, familyName?, childName?, email?, expiresAt }` (confirmation-safe details) |
| POST | `/api/v1/auth/register` | `{ email, password, displayName, familyName, timeZone }` | 201 `AuthResponse` (Development/Testing legacy flow only; 404 in production) |
| POST | `/api/v1/auth/login` | `{ email, password }` | 200 `AuthResponse` |
| POST | `/api/v1/auth/apple` | `{ identityToken, authorizationCode, displayName?, familyName?, timeZone?, inviteCode? }` | 200 `AuthResponse` (existing Apple user) / 201 (new user: creates family, or joins one via `inviteCode`). The authorization code is exchanged server-side and the resulting refresh token is encrypted for revocation during account deletion. |
| POST | `/api/v1/auth/refresh` | `{ refreshToken }` | 200 `AuthResponse` |
| POST | `/api/v1/auth/logout` | `{ refreshToken }` | 204 (revokes) |
| POST | `/api/v1/auth/pair` | `{ code, deviceName }` | 200 `AuthResponse` for the child |
| POST | `/api/v1/auth/accept-invite` | `{ inviteCode, email, password, displayName }` | 201 `AuthResponse` (co-parent joins family) |
| POST | `/api/v1/auth/accept-enrollment` | `{ inviteCode, email, password, displayName }` | 201 `AuthResponse` (consumes server-aware co-parent enrollment and enforces its optional email binding) |
| POST | `/api/v1/auth/complete-child-enrollment` | `{ token, username, secret, credentialKind, deviceName? }` | 200 `AuthResponse` (`credentialKind` = `password` or `pin`) |
| POST | `/api/v1/auth/child-login` | `{ username, secret, deviceName? }` | 200 `AuthResponse` (strictly rate-limited; generic invalid-credential failures) |
| GET | `/api/v1/auth/me` | — (auth) | 200 `UserDto` |

Password rules: min 8 chars. Emails unique, case-insensitive.

Child usernames are unique and case-insensitive, contain 3–50 letters, digits, periods, underscores, or hyphens, and are used with either a password or numeric PIN. PINs are at most 12 digits and must meet the deployment minimum (default 6, configurable from 4–12).

### Server discovery and ownership

`GET /.well-known/bankofdad` returns the protocol version, stable installation UUID, canonical origin, setup state, initialized family name, auth/push capabilities, and child PIN policy. The canonical origin comes from validated server configuration, not the request `Host` header. Clients must match both origin and installation ID before saving a server profile or sending credentials.

`GET /` serves setup/status. While uninitialized, rate-limited `POST /setup/unlock` accepts the setup code generated by `deploy/setup.sh` and renders a 15-minute bootstrap QR. Once family creation commits, setup closes.

Bootstrap, parent, and child QR codes use:

```text
bankofdad://connect?v=1&origin=<encoded-origin>&server=<uuid>&kind=<bootstrap|parent|child>&token=<opaque-token>
```

Only SHA-256 token hashes are stored. Enrollment tokens are random, role-bound, expiring, single-use, and consumed transactionally. They never contain passwords, PINs, access tokens, or refresh tokens.

### Family (parent only)
| Method | Route | Body | Response |
|---|---|---|---|
| GET | `/api/v1/family` | — | `FamilyDto` |
| PATCH | `/api/v1/family` | `{ name?, timeZone? }` | `FamilyDto` |
| POST | `/api/v1/family/invites` | `{ email? }` | 201 `{ inviteCode, expiresAt }` (co-parent invite, 7 days, single use) |
| POST | `/api/v1/family/invites/enrollment` | `{ email? }` | 201 `{ inviteCode, qrPayload, expiresAt }` (server-aware co-parent enrollment, 7 days, single use) |
| POST | `/api/v1/family/children` | `{ displayName, avatarColor? }` | 201 `ChildDto` |
| PATCH | `/api/v1/family/children/{childId}` | `{ displayName?, avatarColor? }` | `ChildDto` (omitted fields are unchanged) |
| POST | `/api/v1/family/children/{childId}/pairing-code` | — | 201 `{ code: "K7Q-4MZ-2P", qrPayload: "bankofdad://pair?code=K7Q4MZ2P", expiresAt }` (15 min, single use, 8 chars from an unambiguous alphabet; dashes/case ignored on input) |
| POST | `/api/v1/family/children/{childId}/enrollment` | — | 201 `{ code, qrPayload, expiresAt }` (revokes child sessions, supersedes unused enrollments, returns a 15-minute credential-setup QR) |
| DELETE | `/api/v1/family/children/{childId}/devices` | — | 204 (revokes all the child's refresh tokens) |

Child `displayName` is trimmed and must be 1–100 characters; `avatarColor` must be a `#RRGGBB` hex color (stored uppercase). Otherwise 400.

Legacy pairing-code routes remain temporarily for development compatibility. New production child enrollment is not passwordless.

### Loans — parent
| Method | Route | Body | Response |
|---|---|---|---|
| POST | `/api/v1/loans/preview` | `LoanTermsInput` | `SchedulePreview` |
| POST | `/api/v1/loans` | `LoanTermsInput` | 201 `LoanDetailDto` (notifies child: `loanCreated`) |
| GET | `/api/v1/loans?status=active&childId=` | — | `[LoanSummaryDto]` (filters optional) |
| GET | `/api/v1/loans/{loanId}` | — | `LoanDetailDto` |
| PATCH | `/api/v1/loans/{loanId}` | `{ title?, sendReminders?, sendReceipts? }` | `LoanDetailDto` |
| PATCH | `/api/v1/loans/{loanId}/installments/{installmentId}` | `{ dueDate }` | `LoanDetailDto` (only unpaid installments of active loans; must stay strictly after previous and strictly before next installment's due date; resets `reminderSentAt`) |
| POST | `/api/v1/loans/{loanId}/cancel` | — | `LoanDetailDto` |
| POST | `/api/v1/loans/{loanId}/payments` | `{ amount, paidOn, note? }` | 201 `PaymentDto` (409 if amount > balance or loan not active; sends receipt if enabled) |
| GET | `/api/v1/loans/{loanId}/payments` | — | `[PaymentDto]` |
| POST | `/api/v1/loans/{loanId}/late-fees/{lateFeeId}/waive` | — | `LoanDetailDto` |
| GET | `/api/v1/dashboard` | — | `DashboardDto` (upcoming = unpaid installments due in the next 30 days, plus late ones) |

### Bills (recurring charges such as a phone plan, car insurance or rent)
Any authenticated family member can read; children only ever see their own bills (other bills return 404, and `childId` is ignored for them). Mutations are parent only (403 for children).

| Method | Route | Body | Response |
|---|---|---|---|
| POST | `/api/v1/bills` | `BillInput` | 201 `BillDetailDto` (parent; notifies child: `billCreated`) |
| GET | `/api/v1/bills?status=active&childId=` | — | `[BillSummaryDto]` (`status` = `active` \| `ended`; filters optional) |
| GET | `/api/v1/bills/{billId}` | — | `BillDetailDto` |
| PATCH | `/api/v1/bills/{billId}` | `{ title?, amount?, sendReminders?, sendReceipts? }` | `BillDetailDto` (parent; `amount` requires an active bill, else 409, and only reprices charges not yet due) |
| POST | `/api/v1/bills/{billId}/end` | — | `BillDetailDto` (parent; 409 if already ended) |
| POST | `/api/v1/bills/{billId}/payments` | `{ amount, paidOn, note? }` | 201 `BillPaymentDto` (parent; 409 if amount exceeds everything generated so far, including the next upcoming charge; sends receipt if enabled) |
| GET | `/api/v1/bills/{billId}/payments` | — | `[BillPaymentDto]` |
| POST | `/api/v1/bills/{billId}/late-fees/{lateFeeId}/waive` | — | `BillDetailDto` (parent; idempotent) |

### Child (child only, own loans only)
| Method | Route | Response |
|---|---|---|
| GET | `/api/v1/me/loans` | `[LoanSummaryDto]` |
| GET | `/api/v1/me/loans/{loanId}` | `LoanDetailDto` |

### Notifications & devices (any authenticated user; own data)
| Method | Route | Body | Response |
|---|---|---|---|
| GET | `/api/v1/notifications?unreadOnly=false` | — | `[NotificationDto]` newest first |
| POST | `/api/v1/notifications/{id}/read` | — | 204 |
| POST | `/api/v1/notifications/read-all` | — | 204 |
| POST | `/api/v1/devices` | `{ apnsToken, environment: "sandbox" \| "production" }` | 204 (upsert) |
| DELETE | `/api/v1/devices/{apnsToken}` | — | 204 |

### Health
`GET /health` → 200 `Healthy` (checks DB).

### Testing hooks (Development only, parent only, caller's family only)
These routes exist **only** when `ASPNETCORE_ENVIRONMENT=Development` **and** `TestHooks:Enabled=true` (`TestHooks__Enabled` / `TEST_HOOKS_ENABLED` in docker compose, default `false`). In every other configuration they are not mapped, so requests get 404. The iOS UI test suite uses them. **Never enable them in production.**

| Method | Route | Body | Response |
|---|---|---|---|
| POST | `/api/v1/testing/loans/{loanId}/backdate` | `{ days }` (1–3650) | `LoanDetailDto`: shifts `firstDueDate` and every installment due date `days` earlier so installments become due or late. 404 if the loan is not in the caller's family. |
| POST | `/api/v1/testing/sweep` | — | 204: runs the reminder / late-fee sweep (normally the hourly background job) for the caller's family now. |

## Business rules (authoritative)
1. **Amortization**: periods per year = 52 (weekly), 26 (biweekly), 12 (monthly), 4 (quarterly), 1 (yearly). r = annualRate / periodsPerYear.
   Payment = P·r / (1 − (1+r)^−n), or P/n when r = 0 or interest disabled. Round payment to cents (MidpointRounding.AwayFromZero).
   For each installment: interest = round(balance·r, 2); principal = payment − interest; final installment's principal = remaining balance (absorbs rounding), amountDue = principal + interest.
2. **Due dates**: seq 1 = firstDueDate; weekly +7d·k, biweekly +14d·k, monthly `firstDueDate.AddMonths(k)`, quarterly `AddMonths(3k)`, yearly `AddYears(k)` — always offset from `firstDueDate`, clamping to month end (Jan 31 → Feb 28/29 → Mar 31; Feb 29 → Feb 28 in non-leap years).
3. **Validation**: principal 0.01–1,000,000; installmentCount 1–520; annualRate 0–1; lateFeeFlat ≥ 0; lateFeePercent 0–1; graceDays 0–60; firstDueDate ≥ today (family-local); title 1–100 chars; child must belong to caller's family.
4. **Installment status** (family-local "today"): `paid` if remaining = 0; else `upcoming` if today < dueDate; `due` if dueDate ≤ today ≤ dueDate + graceDays; `late` otherwise.
5. **Late fee**: when an installment is `late`, has no fee yet, and the loan has a flat and/or percent fee configured, assess one fee = round(flat + percent × installment remaining, 2) (skip if 0). Once per installment, ever. Waived fees are no longer owed. Notify child (`lateFee`).
6. **Payment allocation** (per payment, in order): (a) unpaid, unwaived late fees, oldest-assessed first; (b) then installments in seq order: interest remaining, then principal remaining; continue until the amount is exhausted. Amount must be > 0 and ≤ balance. When everything is settled the loan becomes `paidOff`.
7. **Balance** = Σ installment remaining + Σ outstanding (unpaid, unwaived) late fees. `amountPaid` = Σ payments.
8. **Reminders**: daily sweep (family-local). For active loans with `sendReminders`, for each unpaid installment with `reminderSentAt == null` and `dueDate − 15 days ≤ today ≤ dueDate`, create a `reminder` notification + push to the child and set `reminderSentAt`.
9. **Receipts**: when a payment is recorded and `sendReceipts`, create a `receipt` notification + push to the child with amount, allocation summary and remaining balance.
10. **Multi-tenancy**: every resource is scoped by the caller's `family_id`; cross-family access returns 404. Children can only see their own loans, bills and notifications.
11. **Bills** are open-ended: they recur on the rule-2 schedule until a parent ends them.
    - **Charges** are generated lazily and idempotently (on any bill read, on payment, and by the sweep): every charge due by today (family-local) plus the next upcoming one, each priced at the bill's amount at generation time. Unique `(billId, dueDate)` and `(billId, seq)` indexes make concurrent generation safe. A charge's status follows rule 4 with the bill's grace days.
    - **Amount changes** apply to future charges only: already-due charges keep their amount; generated charges not yet due are repriced (never below what was already paid on them).
    - **Ending** a bill stops generation. Charges already due remain owed and can still accrue late fees (ending is not forgiveness). An unpaid upcoming charge is removed; a partly prepaid one is closed at the amount paid. Payments and waivers are still allowed on ended bills; reminders stop.
    - **Late fees** follow rule 5 per charge. **Payments** allocate to outstanding late fees (oldest first), then charges in seq order (including prepaying the next upcoming charge). **Reminders** and **receipts** follow rules 8–9 (reminders for active bills only).

## Push payload (APNs)
```json
{ "aps": { "alert": { "title": "…", "body": "…" }, "sound": "default", "badge": 3 },
  "type": "reminder", "loanId": "uuid", "notificationId": "uuid" }
```
Bill notifications carry `"billId": "uuid"` instead of `loanId`.
