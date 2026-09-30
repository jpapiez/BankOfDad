namespace BankOfDad.Api.Models;

using BankOfDad.Domain;

public record AuthResponse(string AccessToken, string RefreshToken, DateTimeOffset ExpiresAt, UserDto User);
public record UserDto(Guid Id, Guid FamilyId, Role Role, string DisplayName, string? Email);
public record FamilyDto(Guid Id, string Name, string TimeZone, string Currency, IReadOnlyList<UserDto> Parents, IReadOnlyList<ChildDto> Children);
public record ChildDto(Guid Id, string DisplayName, string? AvatarColor, int PairedDeviceCount);
public record LoanTermsInput(Guid ChildId, string Title, decimal Principal, bool InterestEnabled, decimal AnnualRate, Frequency Frequency, int InstallmentCount, DateOnly FirstDueDate, decimal? LateFeeFlat, decimal? LateFeePercent, int LateFeeGraceDays, bool SendReminders, bool SendReceipts);
public record SchedulePreview(decimal InstallmentAmount, decimal TotalInterest, decimal TotalRepayable, IReadOnlyList<InstallmentPreviewDto> Installments);
public record InstallmentPreviewDto(int Seq, DateOnly DueDate, decimal PrincipalDue, decimal InterestDue, decimal AmountDue);
public record LoanSummaryDto(Guid Id, string Title, Guid ChildId, string ChildName, decimal Principal, LoanStatus Status, decimal Balance, decimal AmountPaid, DateOnly? NextDueDate, decimal? NextAmountDue, int LateInstallments, DateTimeOffset CreatedAt);
public record LoanDetailDto(Guid Id, string Title, Guid ChildId, string ChildName, decimal Principal, LoanStatus Status, decimal Balance, decimal AmountPaid, DateOnly? NextDueDate, decimal? NextAmountDue, int LateInstallments, DateTimeOffset CreatedAt, bool InterestEnabled, decimal AnnualRate, Frequency Frequency, int InstallmentCount, DateOnly FirstDueDate, decimal? LateFeeFlat, decimal? LateFeePercent, int LateFeeGraceDays, bool SendReminders, bool SendReceipts, decimal TotalInterest, decimal TotalRepayable, decimal OutstandingFees, IReadOnlyList<InstallmentDto> Installments, IReadOnlyList<PaymentDto> Payments, IReadOnlyList<LateFeeDto> LateFees, string TermsSummary);
public record InstallmentDto(Guid Id, int Seq, DateOnly DueDate, decimal PrincipalDue, decimal InterestDue, decimal AmountDue, decimal PrincipalPaid, decimal InterestPaid, decimal Remaining, InstallmentStatus Status);
public record LateFeeDto(Guid Id, Guid InstallmentId, int InstallmentSeq, decimal Amount, decimal AmountPaid, DateTimeOffset AssessedAt, DateTimeOffset? WaivedAt);
public record PaymentDto(Guid Id, decimal Amount, DateOnly PaidOn, string? Note, string RecordedByName, DateTimeOffset CreatedAt, IReadOnlyList<PaymentAllocationDto> Allocations);
public record PaymentAllocationDto(AllocationTarget Target, int? InstallmentSeq, Guid? LateFeeId, decimal Amount);
public record NotificationDto(Guid Id, NotificationType Type, string Title, string Body, Guid? LoanId, DateTimeOffset CreatedAt, DateTimeOffset? ReadAt, Guid? BillId);
// TotalOutstanding includes what's owed on bills; ActiveLoans, LateInstallments and Upcoming stay loan-only for older clients.
public record DashboardDto(decimal TotalOutstanding, int ActiveLoans, int LateInstallments, IReadOnlyList<UpcomingDto> Upcoming, int ActiveBills, int LateBillCharges, IReadOnlyList<UpcomingBillDto> UpcomingBills);
public record UpcomingDto(Guid LoanId, string LoanTitle, string ChildName, DateOnly DueDate, decimal AmountDue);
public record UpcomingBillDto(Guid BillId, string BillTitle, string ChildName, DateOnly DueDate, decimal AmountDue);

public record BillInput(Guid ChildId, string Title, decimal Amount, Frequency Frequency, DateOnly FirstDueDate, decimal? LateFeeFlat, decimal? LateFeePercent, int LateFeeGraceDays, bool SendReminders, bool SendReceipts);
public record BillPatchRequest(string? Title, decimal? Amount, bool? SendReminders, bool? SendReceipts);
public record BillSummaryDto(Guid Id, string Title, Guid ChildId, string ChildName, decimal Amount, Frequency Frequency, BillStatus Status, decimal Balance, decimal UpcomingAmount, decimal AmountPaid, DateOnly? NextDueDate, decimal? NextAmountDue, int LateCharges, DateTimeOffset CreatedAt, DateTimeOffset? EndedAt);
public record BillDetailDto(Guid Id, string Title, Guid ChildId, string ChildName, decimal Amount, Frequency Frequency, BillStatus Status, decimal Balance, decimal UpcomingAmount, decimal AmountPaid, DateOnly? NextDueDate, decimal? NextAmountDue, int LateCharges, DateTimeOffset CreatedAt, DateTimeOffset? EndedAt, DateOnly FirstDueDate, decimal? LateFeeFlat, decimal? LateFeePercent, int LateFeeGraceDays, bool SendReminders, bool SendReceipts, decimal OutstandingFees, IReadOnlyList<BillChargeDto> Charges, IReadOnlyList<BillPaymentDto> Payments, IReadOnlyList<BillLateFeeDto> LateFees, string TermsSummary);
public record BillChargeDto(Guid Id, int Seq, DateOnly DueDate, decimal Amount, decimal AmountPaid, decimal Remaining, InstallmentStatus Status);
public record BillLateFeeDto(Guid Id, Guid ChargeId, DateOnly ChargeDueDate, decimal Amount, decimal AmountPaid, DateTimeOffset AssessedAt, DateTimeOffset? WaivedAt);
public record BillPaymentDto(Guid Id, decimal Amount, DateOnly PaidOn, string? Note, string RecordedByName, DateTimeOffset CreatedAt, IReadOnlyList<BillPaymentAllocationDto> Allocations);
public record BillPaymentAllocationDto(AllocationTarget Target, Guid? ChargeId, DateOnly? ChargeDueDate, Guid? LateFeeId, decimal Amount);

public record RegisterRequest(string Email, string Password, string DisplayName, string FamilyName, string TimeZone);
public record LoginRequest(string Email, string Password);
public record AppleRequest(string IdentityToken, string? DisplayName, string? FamilyName, string? TimeZone, string? InviteCode);
public record RefreshRequest(string RefreshToken);
public record LogoutRequest(string RefreshToken);
public record PairRequest(string Code, string? DeviceName);
public record AcceptInviteRequest(string InviteCode, string Email, string Password, string DisplayName);
public record FamilyPatchRequest(string? Name, string? TimeZone);
public record InviteRequest(string? Email);
public record InviteResponse(string InviteCode, DateTimeOffset ExpiresAt);
public record ChildRequest(string DisplayName, string? AvatarColor);
public record ChildPatchRequest(string? DisplayName, string? AvatarColor);
public record PairingCodeResponse(string Code, string QrPayload, DateTimeOffset ExpiresAt);
public record LoanPatchRequest(string? Title, bool? SendReminders, bool? SendReceipts);
public record InstallmentPatchRequest(DateOnly DueDate);
public record PaymentRequest(decimal Amount, DateOnly PaidOn, string? Note);
public record DeviceRequest(string ApnsToken, string Environment);
