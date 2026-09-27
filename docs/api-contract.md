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

## Enums
- `Role`: `parent`, `child`
- `Frequency`: `weekly`, `biweekly`, `monthly`
- `LoanStatus`: `active`, `paidOff`, `cancelled`
- `InstallmentStatus`: `upcoming` (due date in future), `due` (due today / within grace), `late` (past grace, not fully paid), `paid`
- `NotificationType`: `reminder`, `receipt`, `loanCreated`, `lateFee`
- `AllocationTarget`: `lateFee`, `interest`, `principal`

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
{ "id": "uuid", "displayName": "Sam", "avatarColor": "#4F8EF7", "pairedDeviceCount": 1 }

// LoanTermsInput (used by preview and create)
{ "childId": "uuid", "title": "New bike", "principal": 300.00,
  "interestEnabled": true, "annualRate": 0.05,            // treated as 0 when interestEnabled=false
  "frequency": "monthly", "installmentCount": 6, "firstDueDate": "2026-11-01",
  "lateFeeFlat": 5.00, "lateFeePercent": 0.10, "lateFeeGraceDays": 3,   // flat & percent nullable; grace default 0
  "sendReminders": true, "sendReceipts": true }

// SchedulePreview
{ "installmentAmount": 50.73, "totalInterest": 4.38, "totalRepayable": 304.38,
  "installments": [ { "seq": 1, "dueDate": "2026-11-01", "principalDue": 49.48, "interestDue": 1.25, "amountDue": 50.73 } ] }

// LoanSummaryDto
{ "id": "uuid", "title": "New bike", "childId": "uuid", "childName": "Sam", "principal": 300.00,
  "status": "active", "balance": 203.10, "amountPaid": 101.46, "nextDueDate": "2027-01-01", "nextAmountDue": 50.73,
  "lateInstallments": 0, "createdAt": "…" }
// nextDueDate / nextAmountDue are null when nothing remains.

// LoanDetailDto = all LoanSummaryDto fields plus:
{ "interestEnabled": true, "annualRate": 0.05, "frequency": "monthly", "installmentCount": 6, "firstDueDate": "2026-11-01",
  "lateFeeFlat": 5.00, "lateFeePercent": 0.10, "lateFeeGraceDays": 3, "sendReminders": true, "sendReceipts": true,
  "totalInterest": 4.38, "totalRepayable": 304.38, "outstandingFees": 0.00,
  "installments": [InstallmentDto], "payments": [PaymentDto], "lateFees": [LateFeeDto],
  "termsSummary": "Sam borrowed $300.00 for \"New bike\" at 5% APR, repaid in 6 monthly payments of $50.73 starting Nov 1, 2026. A late fee of $5.00 + 10% of the missed payment applies 3 days after a due date." }

// InstallmentDto
{ "id": "uuid", "seq": 1, "dueDate": "2026-11-01", "principalDue": 49.48, "interestDue": 1.25, "amountDue": 50.73,
  "principalPaid": 49.48, "interestPaid": 1.25, "remaining": 0.00, "status": "paid" }

// LateFeeDto
{ "id": "uuid", "installmentId": "uuid", "installmentSeq": 2, "amount": 10.07, "amountPaid": 0.00,
  "assessedAt": "…", "waivedAt": null }

// PaymentDto
{ "id": "uuid", "amount": 50.73, "paidOn": "2026-11-01", "note": "Cash", "recordedByName": "Dad", "createdAt": "…",
  "allocations": [ { "target": "interest", "installmentSeq": 1, "lateFeeId": null, "amount": 1.25 } ] }

// NotificationDto
{ "id": "uuid", "type": "receipt", "title": "Payment received", "body": "…", "loanId": "uuid", "createdAt": "…", "readAt": null }

// DashboardDto
{ "totalOutstanding": 203.10, "activeLoans": 1, "lateInstallments": 0,
  "upcoming": [ { "loanId": "uuid", "loanTitle": "New bike", "childName": "Sam", "dueDate": "2027-01-01", "amountDue": 50.73 } ] }
```

## Endpoints

### Auth (anonymous unless noted)
| Method | Route | Body | Response |
|---|---|---|---|
| POST | `/api/v1/auth/register` | `{ email, password, displayName, familyName, timeZone }` | 201 `AuthResponse` (creates family + parent) |
| POST | `/api/v1/auth/login` | `{ email, password }` | 200 `AuthResponse` |
| POST | `/api/v1/auth/apple` | `{ identityToken, displayName?, familyName?, timeZone?, inviteCode? }` | 200 `AuthResponse` (existing Apple user) / 201 (new user: creates family, or joins one via `inviteCode`) |
| POST | `/api/v1/auth/refresh` | `{ refreshToken }` | 200 `AuthResponse` |
| POST | `/api/v1/auth/logout` | `{ refreshToken }` | 204 (revokes) |
| POST | `/api/v1/auth/pair` | `{ code, deviceName }` | 200 `AuthResponse` for the child |
| POST | `/api/v1/auth/accept-invite` | `{ inviteCode, email, password, displayName }` | 201 `AuthResponse` (co-parent joins family) |
| GET | `/api/v1/auth/me` | — (auth) | 200 `UserDto` |

Password rules: min 8 chars. Emails unique, case-insensitive.

### Family (parent only)
| Method | Route | Body | Response |
|---|---|---|---|
| GET | `/api/v1/family` | — | `FamilyDto` |
| PATCH | `/api/v1/family` | `{ name?, timeZone? }` | `FamilyDto` |
| POST | `/api/v1/family/invites` | `{ email? }` | 201 `{ inviteCode, expiresAt }` (co-parent invite, 7 days, single use) |
| POST | `/api/v1/family/children` | `{ displayName, avatarColor? }` | 201 `ChildDto` |
| PATCH | `/api/v1/family/children/{childId}` | `{ displayName?, avatarColor? }` | `ChildDto` |
| POST | `/api/v1/family/children/{childId}/pairing-code` | — | 201 `{ code: "K7Q-4MZ-2P", qrPayload: "bankofdad://pair?code=K7Q4MZ2P", expiresAt }` (15 min, single use, 8 chars from an unambiguous alphabet; dashes/case ignored on input) |
| DELETE | `/api/v1/family/children/{childId}/devices` | — | 204 (revokes all the child's refresh tokens) |

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

## Business rules (authoritative)
1. **Amortization**: periods per year = 52 (weekly), 26 (biweekly), 12 (monthly). r = annualRate / periodsPerYear.
   Payment = P·r / (1 − (1+r)^−n), or P/n when r = 0 or interest disabled. Round payment to cents (MidpointRounding.AwayFromZero).
   For each installment: interest = round(balance·r, 2); principal = payment − interest; final installment's principal = remaining balance (absorbs rounding), amountDue = principal + interest.
2. **Due dates**: seq 1 = firstDueDate; weekly +7d·k, biweekly +14d·k, monthly `firstDueDate.AddMonths(k)` (clamps to month end).
3. **Validation**: principal 0.01–1,000,000; installmentCount 1–520; annualRate 0–1; lateFeeFlat ≥ 0; lateFeePercent 0–1; graceDays 0–60; firstDueDate ≥ today (family-local); title 1–100 chars; child must belong to caller's family.
4. **Installment status** (family-local "today"): `paid` if remaining = 0; else `upcoming` if today < dueDate; `due` if dueDate ≤ today ≤ dueDate + graceDays; `late` otherwise.
5. **Late fee**: when an installment is `late`, has no fee yet, and the loan has a flat and/or percent fee configured, assess one fee = round(flat + percent × installment remaining, 2) (skip if 0). Once per installment, ever. Waived fees are no longer owed. Notify child (`lateFee`).
6. **Payment allocation** (per payment, in order): (a) unpaid, unwaived late fees, oldest-assessed first; (b) then installments in seq order: interest remaining, then principal remaining; continue until the amount is exhausted. Amount must be > 0 and ≤ balance. When everything is settled the loan becomes `paidOff`.
7. **Balance** = Σ installment remaining + Σ outstanding (unpaid, unwaived) late fees. `amountPaid` = Σ payments.
8. **Reminders**: daily sweep (family-local). For active loans with `sendReminders`, for each unpaid installment with `reminderSentAt == null` and `dueDate − 15 days ≤ today ≤ dueDate`, create a `reminder` notification + push to the child and set `reminderSentAt`.
9. **Receipts**: when a payment is recorded and `sendReceipts`, create a `receipt` notification + push to the child with amount, allocation summary and remaining balance.
10. **Multi-tenancy**: every resource is scoped by the caller's `family_id`; cross-family access returns 404. Children can only see their own loans and notifications.

## Push payload (APNs)
```json
{ "aps": { "alert": { "title": "…", "body": "…" }, "sound": "default", "badge": 3 },
  "type": "reminder", "loanId": "uuid", "notificationId": "uuid" }
```
