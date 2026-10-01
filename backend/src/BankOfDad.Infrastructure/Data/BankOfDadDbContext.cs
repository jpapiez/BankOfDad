namespace BankOfDad.Infrastructure.Data;

using BankOfDad.Domain;
using BankOfDad.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage.ValueConversion;

public sealed class BankOfDadDbContext(DbContextOptions<BankOfDadDbContext> options) : DbContext(options)
{
    public DbSet<Family> Families => Set<Family>();
    public DbSet<User> Users => Set<User>();
    public DbSet<AppleRefreshToken> AppleRefreshTokens => Set<AppleRefreshToken>();
    public DbSet<FamilyInvite> FamilyInvites => Set<FamilyInvite>();
    public DbSet<PairingCode> PairingCodes => Set<PairingCode>();
    public DbSet<RefreshToken> RefreshTokens => Set<RefreshToken>();
    public DbSet<DeviceToken> DeviceTokens => Set<DeviceToken>();
    public DbSet<Loan> Loans => Set<Loan>();
    public DbSet<Installment> Installments => Set<Installment>();
    public DbSet<LateFee> LateFees => Set<LateFee>();
    public DbSet<Payment> Payments => Set<Payment>();
    public DbSet<PaymentAllocation> PaymentAllocations => Set<PaymentAllocation>();
    public DbSet<Notification> Notifications => Set<Notification>();
    public DbSet<Bill> Bills => Set<Bill>();
    public DbSet<BillCharge> BillCharges => Set<BillCharge>();
    public DbSet<BillLateFee> BillLateFees => Set<BillLateFee>();
    public DbSet<BillPayment> BillPayments => Set<BillPayment>();
    public DbSet<BillPaymentAllocation> BillPaymentAllocations => Set<BillPaymentAllocation>();

    public override Task<int> SaveChangesAsync(CancellationToken cancellationToken = default)
    {
        foreach (var entry in ChangeTracker.Entries<Loan>().Where(x => x.State == EntityState.Modified))
        {
            entry.Entity.ConcurrencyToken = Guid.NewGuid();
        }

        foreach (var entry in ChangeTracker.Entries<Bill>().Where(x => x.State == EntityState.Modified))
        {
            entry.Entity.ConcurrencyToken = Guid.NewGuid();
        }

        return base.SaveChangesAsync(cancellationToken);
    }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        var roleConverter = new EnumToStringConverter<Role>();
        var frequencyConverter = new EnumToStringConverter<Frequency>();
        var loanStatusConverter = new EnumToStringConverter<LoanStatus>();
        var billStatusConverter = new EnumToStringConverter<BillStatus>();
        var notificationConverter = new EnumToStringConverter<NotificationType>();
        var allocationConverter = new EnumToStringConverter<AllocationTarget>();

        modelBuilder.Entity<Family>(b =>
        {
            b.Property(x => x.Name).HasMaxLength(100).IsRequired();
            b.Property(x => x.TimeZone).HasMaxLength(100).IsRequired();
            b.Property(x => x.Currency).HasMaxLength(3).HasDefaultValue("USD").IsRequired();
        });

        modelBuilder.Entity<User>(b =>
        {
            b.Property(x => x.Role).HasConversion(roleConverter).HasMaxLength(20);
            b.Property(x => x.DisplayName).HasMaxLength(100).IsRequired();
            b.Property(x => x.Email).HasMaxLength(320);
            b.Property(x => x.NormalizedEmail).HasMaxLength(320);
            b.Property(x => x.AppleSubject).HasMaxLength(200);
            b.Property(x => x.AppleRefreshTokenEncrypted).HasMaxLength(2048);
            b.Property(x => x.AppleDeletionStartedAt);
            b.Property(x => x.AvatarColor).HasMaxLength(20);
            b.HasIndex(x => x.NormalizedEmail).IsUnique().HasFilter("\"NormalizedEmail\" IS NOT NULL");
            b.HasIndex(x => x.AppleSubject).IsUnique().HasFilter("\"AppleSubject\" IS NOT NULL");
            b.HasIndex(x => new { x.FamilyId, x.Role });
        });

        modelBuilder.Entity<AppleRefreshToken>(b =>
        {
            b.Property(x => x.TokenEncrypted).HasMaxLength(2048).IsRequired();
            b.HasIndex(x => new { x.UserId, x.RevokedAt }).HasDatabaseName("IX_AppleRefreshTokens_UserId_RevokedAt");
            b.HasIndex(x => x.UserId);
        });

        modelBuilder.Entity<FamilyInvite>(b =>
        {
            b.Property(x => x.CodeHash).HasMaxLength(64).IsRequired();
            b.Property(x => x.Email).HasMaxLength(320);
            b.HasIndex(x => x.CodeHash).IsUnique();
        });

        modelBuilder.Entity<PairingCode>(b =>
        {
            b.Property(x => x.CodeHash).HasMaxLength(64).IsRequired();
            b.HasIndex(x => x.CodeHash).IsUnique();
        });

        modelBuilder.Entity<RefreshToken>(b =>
        {
            b.Property(x => x.TokenHash).HasMaxLength(64).IsRequired();
            b.Property(x => x.DeviceName).HasMaxLength(100);
            b.HasIndex(x => x.TokenHash).IsUnique();
        });

        modelBuilder.Entity<DeviceToken>(b =>
        {
            b.Property(x => x.ApnsToken).HasMaxLength(512).IsRequired();
            b.Property(x => x.Environment).HasMaxLength(20).IsRequired();
            b.HasIndex(x => x.ApnsToken).IsUnique();
        });

        modelBuilder.Entity<Loan>(b =>
        {
            b.Property(x => x.Title).HasMaxLength(100).IsRequired();
            Money(b.Property(x => x.Principal));
            b.Property(x => x.AnnualRate).HasColumnType("numeric(9,6)");
            Money(b.Property(x => x.InstallmentAmount));
            Money(b.Property(x => x.LateFeeFlat));
            b.Property(x => x.LateFeePercent).HasColumnType("numeric(9,6)");
            b.Property(x => x.Frequency).HasConversion(frequencyConverter).HasMaxLength(20);
            b.Property(x => x.Status).HasConversion(loanStatusConverter).HasMaxLength(20);
            b.Property(x => x.ConcurrencyToken).IsConcurrencyToken();
            b.HasIndex(x => new { x.FamilyId, x.Status });
            b.HasIndex(x => x.BorrowerChildId);
        });

        modelBuilder.Entity<Installment>(b =>
        {
            Money(b.Property(x => x.PrincipalDue));
            Money(b.Property(x => x.InterestDue));
            Money(b.Property(x => x.PrincipalPaid));
            Money(b.Property(x => x.InterestPaid));
            b.HasIndex(x => new { x.LoanId, x.Seq }).IsUnique();
        });

        modelBuilder.Entity<LateFee>(b =>
        {
            Money(b.Property(x => x.Amount));
            Money(b.Property(x => x.AmountPaid));
            b.HasIndex(x => x.InstallmentId).IsUnique();
            b.HasIndex(x => new { x.LoanId, x.AssessedAt });
        });

        modelBuilder.Entity<Payment>(b =>
        {
            Money(b.Property(x => x.Amount));
            b.Property(x => x.Note).HasMaxLength(500);
            b.HasIndex(x => new { x.LoanId, x.CreatedAt });
        });

        modelBuilder.Entity<PaymentAllocation>(b =>
        {
            Money(b.Property(x => x.Amount));
            b.Property(x => x.Target).HasConversion(allocationConverter).HasMaxLength(20);
        });

        modelBuilder.Entity<Bill>(b =>
        {
            b.Property(x => x.Title).HasMaxLength(100).IsRequired();
            Money(b.Property(x => x.Amount));
            Money(b.Property(x => x.LateFeeFlat));
            b.Property(x => x.LateFeePercent).HasColumnType("numeric(9,6)");
            b.Property(x => x.Frequency).HasConversion(frequencyConverter).HasMaxLength(20);
            b.Property(x => x.Status).HasConversion(billStatusConverter).HasMaxLength(20);
            b.Property(x => x.ConcurrencyToken).IsConcurrencyToken();
            b.HasOne(x => x.Child).WithMany().HasForeignKey(x => x.ChildId);
            b.HasOne(x => x.CreatedByParent).WithMany().HasForeignKey(x => x.CreatedByParentId);
            b.HasIndex(x => new { x.FamilyId, x.Status });
            b.HasIndex(x => x.ChildId);
        });

        modelBuilder.Entity<BillCharge>(b =>
        {
            Money(b.Property(x => x.Amount));
            Money(b.Property(x => x.AmountPaid));
            // Charge generation relies on these to stay idempotent (INSERT ... ON CONFLICT DO NOTHING).
            b.HasIndex(x => new { x.BillId, x.DueDate }).IsUnique();
            b.HasIndex(x => new { x.BillId, x.Seq }).IsUnique();
        });

        modelBuilder.Entity<BillLateFee>(b =>
        {
            Money(b.Property(x => x.Amount));
            Money(b.Property(x => x.AmountPaid));
            b.HasOne(x => x.Charge).WithMany().HasForeignKey(x => x.ChargeId);
            b.HasIndex(x => x.ChargeId).IsUnique();
            b.HasIndex(x => new { x.BillId, x.AssessedAt });
        });

        modelBuilder.Entity<BillPayment>(b =>
        {
            Money(b.Property(x => x.Amount));
            b.Property(x => x.Note).HasMaxLength(500);
            b.HasIndex(x => new { x.BillId, x.CreatedAt });
        });

        modelBuilder.Entity<BillPaymentAllocation>(b =>
        {
            Money(b.Property(x => x.Amount));
            b.Property(x => x.Target).HasConversion(allocationConverter).HasMaxLength(20);
        });

        modelBuilder.Entity<Notification>(b =>
        {
            b.Property(x => x.Type).HasConversion(notificationConverter).HasMaxLength(20);
            b.Property(x => x.Title).HasMaxLength(100).IsRequired();
            b.Property(x => x.Body).HasMaxLength(500).IsRequired();
            b.HasIndex(x => new { x.UserId, x.CreatedAt });
        });

        static void Money<T>(Microsoft.EntityFrameworkCore.Metadata.Builders.PropertyBuilder<T> propertyBuilder) => propertyBuilder.HasColumnType("numeric(18,2)");
    }
}
