namespace BankOfDad.Api.Services;

using System.Globalization;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using BankOfDad.Api.Models;
using BankOfDad.Domain;
using BankOfDad.Domain.Entities;
using BankOfDad.Domain.Services;
using BankOfDad.Infrastructure.Data;
using BankOfDad.Infrastructure.Push;
using BankOfDad.Infrastructure.Security;
using BankOfDad.Infrastructure.Time;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.IdentityModel.Tokens;

public sealed class ApiException(int status, string title, string? detail = null) : Exception(detail ?? title)
{
    public int Status { get; } = status;
    public string Title { get; } = title;
    public string? Detail { get; } = detail;
}

public static class ClaimsPrincipalExtensions
{
    public static Guid UserId(this ClaimsPrincipal user) => Guid.Parse(user.FindFirstValue(JwtRegisteredClaimNames.Sub) ?? user.FindFirstValue(ClaimTypes.NameIdentifier) ?? throw new InvalidOperationException("Missing sub claim."));
    public static Guid FamilyId(this ClaimsPrincipal user) => Guid.Parse(user.FindFirstValue("family_id") ?? throw new InvalidOperationException("Missing family_id claim."));
}

public sealed class AuthService(BankOfDadDbContext db, IPasswordService passwords, IClock clock, IConfiguration configuration)
{
    public async Task<AuthResponse> IssueAsync(User user, string? deviceName, CancellationToken ct)
    {
        var accessExpires = clock.UtcNow.AddMinutes(15);
        var refresh = Convert.ToBase64String(RandomNumberGenerator.GetBytes(64));
        db.RefreshTokens.Add(new RefreshToken
        {
            UserId = user.Id,
            TokenHash = SecretHasher.Sha256(refresh),
            DeviceName = deviceName,
            ExpiresAt = clock.UtcNow.AddDays(60)
        });
        await db.SaveChangesAsync(ct).ConfigureAwait(false);
        return new AuthResponse(CreateAccessToken(user, accessExpires), refresh, accessExpires, DtoMapper.User(user));
    }

    public async Task<AuthResponse> RotateAsync(string refreshToken, CancellationToken ct)
    {
        var hash = SecretHasher.Sha256(refreshToken);
        var token = await db.RefreshTokens.Include(x => x.User).SingleOrDefaultAsync(x => x.TokenHash == hash, ct).ConfigureAwait(false);
        if (token?.User is null || token.RevokedAt is not null || token.ExpiresAt <= clock.UtcNow) throw new ApiException(401, "Invalid refresh token.");
        token.RevokedAt = clock.UtcNow;
        var accessExpires = clock.UtcNow.AddMinutes(15);
        var replacement = Convert.ToBase64String(RandomNumberGenerator.GetBytes(64));
        var replacementEntity = new RefreshToken { UserId = token.UserId, TokenHash = SecretHasher.Sha256(replacement), DeviceName = token.DeviceName, ExpiresAt = clock.UtcNow.AddDays(60) };
        db.RefreshTokens.Add(replacementEntity);
        token.ReplacedByTokenId = replacementEntity.Id;
        await db.SaveChangesAsync(ct).ConfigureAwait(false);
        return new AuthResponse(CreateAccessToken(token.User, accessExpires), replacement, accessExpires, DtoMapper.User(token.User));
    }

    public async Task LogoutAsync(string refreshToken, CancellationToken ct)
    {
        var hash = SecretHasher.Sha256(refreshToken);
        var token = await db.RefreshTokens.SingleOrDefaultAsync(x => x.TokenHash == hash, ct).ConfigureAwait(false);
        if (token is not null && token.RevokedAt is null)
        {
            token.RevokedAt = clock.UtcNow;
            await db.SaveChangesAsync(ct).ConfigureAwait(false);
        }
    }

    public string HashPassword(User user, string password) => passwords.Hash(user, password);
    public bool Verify(User user, string password) => passwords.Verify(user, password);

    private string CreateAccessToken(User user, DateTimeOffset expires)
    {
        var key = configuration["Jwt:SigningKey"];
        if (string.IsNullOrWhiteSpace(key))
        {
            key = "testing-only-signing-key-change-me-0123456789";
        }
        var claims = new[]
        {
            new Claim(JwtRegisteredClaimNames.Sub, user.Id.ToString()),
            new Claim("family_id", user.FamilyId.ToString()),
            new Claim("role", ToCamel(user.Role.ToString())),
            new Claim("name", user.DisplayName)
        };
        var token = new JwtSecurityToken("bankofdad", "bankofdad", claims, null, expires.UtcDateTime, new SigningCredentials(new SymmetricSecurityKey(Encoding.UTF8.GetBytes(key)), SecurityAlgorithms.HmacSha256));
        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    private static string ToCamel(string value) => char.ToLowerInvariant(value[0]) + value[1..];
}

public sealed class NotificationService(BankOfDadDbContext db, IPushSender pushSender, IClock clock)
{
    public async Task<Notification> CreateAndPushAsync(Guid userId, NotificationType type, string title, string body, Guid? loanId, CancellationToken ct)
    {
        var notification = new Notification { UserId = userId, Type = type, Title = title, Body = body, LoanId = loanId, CreatedAt = clock.UtcNow };
        db.Notifications.Add(notification);
        await db.SaveChangesAsync(ct).ConfigureAwait(false);
        await PushAsync(notification, ct).ConfigureAwait(false);
        return notification;
    }

    public async Task PushAsync(Notification notification, CancellationToken ct)
    {
        var tokens = await db.DeviceTokens.Where(x => x.UserId == notification.UserId).ToListAsync(ct).ConfigureAwait(false);
        if (tokens.Count == 0) return;
        var badge = await db.Notifications.CountAsync(x => x.UserId == notification.UserId && x.ReadAt == null, ct).ConfigureAwait(false);
        var message = new PushMessage(notification.Type, notification.Title, notification.Body, notification.LoanId, notification.Id);
        foreach (var token in tokens)
        {
            await pushSender.SendAsync(token, message, badge, ct).ConfigureAwait(false);
        }
        notification.PushedAt = clock.UtcNow;
        await db.SaveChangesAsync(ct).ConfigureAwait(false);
    }
}

public sealed class LoanSweeper(BankOfDadDbContext db, LoanStateService state, NotificationService notifications, IClock clock)
{
    public Task SweepAsync(CancellationToken ct = default) => SweepCoreAsync(null, ct);

    public Task SweepFamilyAsync(Guid familyId, CancellationToken ct = default) => SweepCoreAsync(familyId, ct);

    private async Task SweepCoreAsync(Guid? familyId, CancellationToken ct)
    {
        var families = await db.Families.AsNoTracking().Where(x => familyId == null || x.Id == familyId).ToListAsync(ct).ConfigureAwait(false);
        foreach (var family in families)
        {
            var today = TodayFor(family.TimeZone);
            var loans = await db.Loans
                .Include(x => x.BorrowerChild)
                .Include(x => x.Installments)
                .Include(x => x.LateFees)
                .Include(x => x.Payments)
                .Where(x => x.FamilyId == family.Id && x.Status == LoanStatus.Active)
                .ToListAsync(ct).ConfigureAwait(false);
            foreach (var loan in loans)
            {
                foreach (var installment in loan.Installments.OrderBy(x => x.Seq))
                {
                    if (state.ShouldAssessLateFee(loan, installment, today))
                    {
                        var fee = new LateFee { LoanId = loan.Id, InstallmentId = installment.Id, Amount = state.ComputeLateFee(loan, installment), AssessedAt = clock.UtcNow };
                        db.LateFees.Add(fee);
                        await db.SaveChangesAsync(ct).ConfigureAwait(false);
                        await notifications.CreateAndPushAsync(loan.BorrowerChildId, NotificationType.LateFee, "Late fee assessed", $"A late fee of {Money.Format(fee.Amount)} was added to \"{loan.Title}\".", loan.Id, ct).ConfigureAwait(false);
                    }

                    if (loan.SendReminders && installment.ReminderSentAt is null && state.InstallmentRemaining(installment) > 0m && today >= installment.DueDate.AddDays(-15) && today <= installment.DueDate)
                    {
                        installment.ReminderSentAt = clock.UtcNow;
                        var amount = state.InstallmentRemaining(installment);
                        var due = installment.DueDate.ToDateTime(TimeOnly.MinValue).ToString("MMM d, yyyy", CultureInfo.GetCultureInfo("en-US"));
                        await notifications.CreateAndPushAsync(loan.BorrowerChildId, NotificationType.Reminder, "Payment due soon", $"Your {Money.Format(amount)} payment for \"{loan.Title}\" is due {due}.", loan.Id, ct).ConfigureAwait(false);
                    }
                }

                if (state.IsPaidOff(loan))
                {
                    loan.Status = LoanStatus.PaidOff;
                    loan.PaidOffAt = clock.UtcNow;
                }
            }
            await db.SaveChangesAsync(ct).ConfigureAwait(false);
        }
    }

    private DateOnly TodayFor(string timeZone)
    {
        var tz = TimeZoneInfo.FindSystemTimeZoneById(timeZone);
        return DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(clock.UtcNow, tz).DateTime);
    }
}

public sealed class DailySweepService(IServiceScopeFactory scopeFactory, ILogger<DailySweepService> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                using var scope = scopeFactory.CreateScope();
                await scope.ServiceProvider.GetRequiredService<LoanSweeper>().SweepAsync(stoppingToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { }
            catch (Exception ex) { logger.LogError(ex, "Daily loan sweep failed."); }
            await Task.Delay(TimeSpan.FromHours(1), stoppingToken).ConfigureAwait(false);
        }
    }
}

public static class DtoMapper
{
    private static readonly LoanStateService State = new();
    private static readonly TermsSummaryBuilder Terms = new();

    public static UserDto User(User user) => new(user.Id, user.FamilyId, user.Role, user.DisplayName, user.Email);
    public static ChildDto Child(User user, int pairedDevices = 0) => new(user.Id, user.DisplayName, user.AvatarColor, pairedDevices);

    public static FamilyDto Family(Family family, IReadOnlyDictionary<Guid, int> childDevices)
    {
        var parents = family.Users.Where(x => x.Role == Role.Parent).Select(User).ToList();
        var children = family.Users.Where(x => x.Role == Role.Child).Select(x => Child(x, childDevices.GetValueOrDefault(x.Id))).ToList();
        return new FamilyDto(family.Id, family.Name, family.TimeZone, family.Currency, parents, children);
    }

    public static SchedulePreview Preview(ScheduleResult result) => new(result.InstallmentAmount, result.TotalInterest, result.TotalRepayable, result.Installments.Select(x => new InstallmentPreviewDto(x.Seq, x.DueDate, x.PrincipalDue, x.InterestDue, x.AmountDue)).ToList());

    public static LoanSummaryDto LoanSummary(Loan loan, DateOnly today)
    {
        var childName = loan.BorrowerChild?.DisplayName ?? string.Empty;
        var next = loan.Installments.OrderBy(x => x.Seq).FirstOrDefault(x => State.InstallmentRemaining(x) > 0m);
        return new LoanSummaryDto(loan.Id, loan.Title, loan.BorrowerChildId, childName, loan.Principal, loan.Status, State.Balance(loan), State.AmountPaid(loan), next?.DueDate, next is null ? null : State.InstallmentRemaining(next), loan.Installments.Count(x => State.Status(x, today, loan.LateFeeGraceDays) == InstallmentStatus.Late), loan.CreatedAt);
    }

    public static LoanDetailDto LoanDetail(Loan loan, DateOnly today)
    {
        var summary = LoanSummary(loan, today);
        var totalInterest = Money.Round(loan.Installments.Sum(x => x.InterestDue));
        var installments = loan.Installments.OrderBy(x => x.Seq).Select(x => new InstallmentDto(x.Id, x.Seq, x.DueDate, x.PrincipalDue, x.InterestDue, Money.Round(x.PrincipalDue + x.InterestDue), x.PrincipalPaid, x.InterestPaid, State.InstallmentRemaining(x), State.Status(x, today, loan.LateFeeGraceDays))).ToList();
        var lateFees = loan.LateFees.OrderBy(x => x.AssessedAt).Select(x => new LateFeeDto(x.Id, x.InstallmentId, loan.Installments.Single(i => i.Id == x.InstallmentId).Seq, x.Amount, x.AmountPaid, x.AssessedAt, x.WaivedAt)).ToList();
        var payments = loan.Payments.OrderByDescending(x => x.CreatedAt).Select(Payment).ToList();
        return new LoanDetailDto(summary.Id, summary.Title, summary.ChildId, summary.ChildName, summary.Principal, summary.Status, summary.Balance, summary.AmountPaid, summary.NextDueDate, summary.NextAmountDue, summary.LateInstallments, summary.CreatedAt, loan.InterestEnabled, loan.AnnualRate, loan.Frequency, loan.InstallmentCount, loan.FirstDueDate, loan.LateFeeFlat, loan.LateFeePercent, loan.LateFeeGraceDays, loan.SendReminders, loan.SendReceipts, totalInterest, Money.Round(loan.Principal + totalInterest), loan.LateFees.Sum(State.FeeRemaining), installments, payments, lateFees, Terms.Build(loan, summary.ChildName));
    }

    public static PaymentDto Payment(Payment payment) => new(payment.Id, payment.Amount, payment.PaidOn, payment.Note, payment.RecordedByUser?.DisplayName ?? string.Empty, payment.CreatedAt, payment.Allocations.Select(a => new PaymentAllocationDto(a.Target, a.Installment?.Seq, a.LateFeeId, a.Amount)).ToList());
    public static NotificationDto Notification(Notification notification) => new(notification.Id, notification.Type, notification.Title, notification.Body, notification.LoanId, notification.CreatedAt, notification.ReadAt);
}
