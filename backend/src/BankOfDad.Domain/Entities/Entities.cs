namespace BankOfDad.Domain.Entities;

using BankOfDad.Domain;

public class Family
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = string.Empty;
    public string TimeZone { get; set; } = "America/Los_Angeles";
    public string Currency { get; set; } = "USD";
    public DateTimeOffset CreatedAt { get; set; }
    public List<User> Users { get; set; } = [];
}

public class User
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid FamilyId { get; set; }
    public Family? Family { get; set; }
    public Role Role { get; set; }
    public string DisplayName { get; set; } = string.Empty;
    public string? Email { get; set; }
    public string? NormalizedEmail { get; set; }
    public string? PasswordHash { get; set; }
    public string? AppleSubject { get; set; }
    public string? AppleRefreshTokenEncrypted { get; set; }
    public DateTimeOffset? AppleDeletionStartedAt { get; set; }
    public string? AvatarColor { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
}

public class AppleRefreshToken
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public User? User { get; set; }
    public string TokenEncrypted { get; set; } = string.Empty;
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset? RevokedAt { get; set; }
    public Guid? ReplacedByTokenId { get; set; }
}

public class FamilyInvite
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid FamilyId { get; set; }
    public Family? Family { get; set; }
    public string CodeHash { get; set; } = string.Empty;
    public string? Email { get; set; }
    public DateTimeOffset ExpiresAt { get; set; }
    public DateTimeOffset? UsedAt { get; set; }
    public Guid CreatedByUserId { get; set; }
}

public class PairingCode
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid ChildUserId { get; set; }
    public User? ChildUser { get; set; }
    public string CodeHash { get; set; } = string.Empty;
    public DateTimeOffset ExpiresAt { get; set; }
    public DateTimeOffset? UsedAt { get; set; }
}

public class RefreshToken
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public User? User { get; set; }
    public string TokenHash { get; set; } = string.Empty;
    public string? DeviceName { get; set; }
    public DateTimeOffset ExpiresAt { get; set; }
    public DateTimeOffset? RevokedAt { get; set; }
    public Guid? ReplacedByTokenId { get; set; }
}

public class DeviceToken
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public User? User { get; set; }
    public string ApnsToken { get; set; } = string.Empty;
    public string Environment { get; set; } = "sandbox";
    public DateTimeOffset UpdatedAt { get; set; }
}

public class Loan
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid FamilyId { get; set; }
    public Family? Family { get; set; }
    public Guid BorrowerChildId { get; set; }
    public User? BorrowerChild { get; set; }
    public Guid CreatedByParentId { get; set; }
    public User? CreatedByParent { get; set; }
    public string Title { get; set; } = string.Empty;
    public decimal Principal { get; set; }
    public bool InterestEnabled { get; set; }
    public decimal AnnualRate { get; set; }
    public Frequency Frequency { get; set; }
    public int InstallmentCount { get; set; }
    public DateOnly FirstDueDate { get; set; }
    public decimal InstallmentAmount { get; set; }
    public LoanStatus Status { get; set; } = LoanStatus.Active;
    public bool SendReminders { get; set; } = true;
    public bool SendReceipts { get; set; } = true;
    public decimal? LateFeeFlat { get; set; }
    public decimal? LateFeePercent { get; set; }
    public int LateFeeGraceDays { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset? CancelledAt { get; set; }
    public DateTimeOffset? PaidOffAt { get; set; }
    public Guid ConcurrencyToken { get; set; } = Guid.NewGuid();
    public List<Installment> Installments { get; set; } = [];
    public List<LateFee> LateFees { get; set; } = [];
    public List<Payment> Payments { get; set; } = [];
}

public class Installment
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid LoanId { get; set; }
    public Loan? Loan { get; set; }
    public int Seq { get; set; }
    public DateOnly DueDate { get; set; }
    public decimal PrincipalDue { get; set; }
    public decimal InterestDue { get; set; }
    public decimal PrincipalPaid { get; set; }
    public decimal InterestPaid { get; set; }
    public DateTimeOffset? ReminderSentAt { get; set; }
}

public class LateFee
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid InstallmentId { get; set; }
    public Installment? Installment { get; set; }
    public Guid LoanId { get; set; }
    public Loan? Loan { get; set; }
    public decimal Amount { get; set; }
    public decimal AmountPaid { get; set; }
    public DateTimeOffset AssessedAt { get; set; }
    public DateTimeOffset? WaivedAt { get; set; }
    public Guid? WaivedByUserId { get; set; }
}

public class Payment
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid LoanId { get; set; }
    public Loan? Loan { get; set; }
    public decimal Amount { get; set; }
    public DateOnly PaidOn { get; set; }
    public string? Note { get; set; }
    public Guid RecordedByUserId { get; set; }
    public User? RecordedByUser { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset? ReceiptSentAt { get; set; }
    public List<PaymentAllocation> Allocations { get; set; } = [];
}

public class PaymentAllocation
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid PaymentId { get; set; }
    public Payment? Payment { get; set; }
    public AllocationTarget Target { get; set; }
    public Guid? InstallmentId { get; set; }
    public Installment? Installment { get; set; }
    public Guid? LateFeeId { get; set; }
    public LateFee? LateFee { get; set; }
    public decimal Amount { get; set; }
}

/// <summary>A recurring, open-ended charge (cell phone, insurance, rent) a child owes every period until a parent ends it.</summary>
public class Bill
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid FamilyId { get; set; }
    public Family? Family { get; set; }
    public Guid ChildId { get; set; }
    public User? Child { get; set; }
    public Guid CreatedByParentId { get; set; }
    public User? CreatedByParent { get; set; }
    public string Title { get; set; } = string.Empty;
    /// <summary>The amount of each newly generated charge. Changing it never touches charges that are already due.</summary>
    public decimal Amount { get; set; }
    public Frequency Frequency { get; set; }
    public DateOnly FirstDueDate { get; set; }
    public BillStatus Status { get; set; } = BillStatus.Active;
    public bool SendReminders { get; set; } = true;
    public bool SendReceipts { get; set; } = true;
    public decimal? LateFeeFlat { get; set; }
    public decimal? LateFeePercent { get; set; }
    public int LateFeeGraceDays { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset? EndedAt { get; set; }
    public Guid ConcurrencyToken { get; set; } = Guid.NewGuid();
    public List<BillCharge> Charges { get; set; } = [];
    public List<BillLateFee> LateFees { get; set; } = [];
    public List<BillPayment> Payments { get; set; } = [];
}

public class BillCharge
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid BillId { get; set; }
    public Bill? Bill { get; set; }
    public int Seq { get; set; }
    public DateOnly DueDate { get; set; }
    public decimal Amount { get; set; }
    public decimal AmountPaid { get; set; }
    public DateTimeOffset? ReminderSentAt { get; set; }
}

public class BillLateFee
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid BillId { get; set; }
    public Bill? Bill { get; set; }
    public Guid ChargeId { get; set; }
    public BillCharge? Charge { get; set; }
    public decimal Amount { get; set; }
    public decimal AmountPaid { get; set; }
    public DateTimeOffset AssessedAt { get; set; }
    public DateTimeOffset? WaivedAt { get; set; }
    public Guid? WaivedByUserId { get; set; }
}

public class BillPayment
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid BillId { get; set; }
    public Bill? Bill { get; set; }
    public decimal Amount { get; set; }
    public DateOnly PaidOn { get; set; }
    public string? Note { get; set; }
    public Guid RecordedByUserId { get; set; }
    public User? RecordedByUser { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset? ReceiptSentAt { get; set; }
    public List<BillPaymentAllocation> Allocations { get; set; } = [];
}

public class BillPaymentAllocation
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid PaymentId { get; set; }
    public BillPayment? Payment { get; set; }
    public AllocationTarget Target { get; set; }
    public Guid? ChargeId { get; set; }
    public BillCharge? Charge { get; set; }
    public Guid? LateFeeId { get; set; }
    public BillLateFee? LateFee { get; set; }
    public decimal Amount { get; set; }
}

public class Notification
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public User? User { get; set; }
    public NotificationType Type { get; set; }
    public string Title { get; set; } = string.Empty;
    public string Body { get; set; } = string.Empty;
    public Guid? LoanId { get; set; }
    public Guid? BillId { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset? ReadAt { get; set; }
    public DateTimeOffset? PushedAt { get; set; }
}
