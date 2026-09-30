namespace BankOfDad.Api.Services;

using System.Data;
using System.Security.Claims;
using BankOfDad.Api.Models;
using BankOfDad.Domain;
using BankOfDad.Domain.Entities;
using BankOfDad.Domain.Services;
using BankOfDad.Infrastructure.Data;
using BankOfDad.Infrastructure.Time;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;

/// <summary>
/// Recurring bills. Parents manage bills for children in their family; children can only read their own bills.
/// Every handler generates due charges before loading, so reads and writes always see an up-to-date schedule.
/// </summary>
public static class BillEndpoints
{
    public static void MapBills(this RouteGroupBuilder api)
    {
        var bills = api.MapGroup("/bills").RequireAuthorization();

        bills.MapGet("/", async (string? status, Guid? childId, ClaimsPrincipal user, BankOfDadDbContext db, BillChargeGenerator generator, IClock clock, CancellationToken ct) =>
        {
            var statusFilter = ParseStatus(status);
            var familyId = user.FamilyId();
            var today = await FamilyClock.TodayAsync(db, familyId, clock, ct);
            await generator.EnsureChargesAsync(familyId, today, null, ct);
            var query = db.Bills.IncludeAll().Where(x => x.FamilyId == familyId);
            if (user.IsChild()) query = query.Where(x => x.ChildId == user.UserId());
            else if (childId is not null) query = query.Where(x => x.ChildId == childId);
            if (statusFilter is not null) query = query.Where(x => x.Status == statusFilter);
            var list = await query.OrderBy(x => x.CreatedAt).ToListAsync(ct);
            return Results.Ok(list.Select(x => DtoMapper.BillSummary(x, today)).ToList());
        });

        bills.MapPost("/", async (BillInput input, ClaimsPrincipal user, BankOfDadDbContext db, BillScheduler scheduler, NotificationService notifications, IClock clock, CancellationToken ct) =>
        {
            var familyId = user.FamilyId();
            var today = await FamilyClock.TodayAsync(db, familyId, clock, ct);
            var title = await ValidateAsync(input, familyId, today, db, ct);
            var bill = new Bill
            {
                FamilyId = familyId, ChildId = input.ChildId, CreatedByParentId = user.UserId(), Title = title, Amount = Money.Round(input.Amount),
                Frequency = input.Frequency, FirstDueDate = input.FirstDueDate, SendReminders = input.SendReminders, SendReceipts = input.SendReceipts,
                LateFeeFlat = input.LateFeeFlat, LateFeePercent = input.LateFeePercent, LateFeeGraceDays = input.LateFeeGraceDays, CreatedAt = clock.UtcNow
            };
            bill.Charges = scheduler.PendingCharges(bill, today).Select(x => new BillCharge { BillId = bill.Id, Seq = x.Seq, DueDate = x.DueDate, Amount = bill.Amount }).ToList();
            db.Bills.Add(bill);
            await db.SaveChangesAsync(ct);
            await notifications.CreateAndPushForBillAsync(bill.ChildId, NotificationType.BillCreated, "New bill", $"A new {bill.Frequency.ToString().ToLowerInvariant()} bill \"{bill.Title}\" of {Money.Format(bill.Amount)} was added.", bill.Id, ct);
            bill = await RequireBill(db, bill.Id, user, ct);
            return Results.Created($"/api/v1/bills/{bill.Id}", DtoMapper.BillDetail(bill, today));
        }).RequireAuthorization("Parent");

        bills.MapGet("/{billId:guid}", async (Guid billId, ClaimsPrincipal user, BankOfDadDbContext db, BillChargeGenerator generator, IClock clock, CancellationToken ct) =>
        {
            var (bill, today) = await LoadCurrentAsync(billId, user, db, generator, clock, ct);
            return Results.Ok(DtoMapper.BillDetail(bill, today));
        });

        bills.MapPatch("/{billId:guid}", async (Guid billId, BillPatchRequest request, ClaimsPrincipal user, BankOfDadDbContext db, BillChargeGenerator generator, BillScheduler scheduler, IClock clock, CancellationToken ct) =>
        {
            var (transaction, bill, today) = await LoadLockedAsync(billId, user, db, generator, clock, ct);
            await using var _ = transaction;
            if (!string.IsNullOrWhiteSpace(request.Title)) bill.Title = ValidateTitle(request.Title);
            if (request.Amount is not null)
            {
                ValidateAmount(request.Amount.Value);
                if (bill.Status != BillStatus.Active) throw new ApiException(409, "Only active bills can change their amount.");
                scheduler.ChangeAmount(bill, request.Amount.Value, today);
            }
            if (request.SendReminders is not null) bill.SendReminders = request.SendReminders.Value;
            if (request.SendReceipts is not null) bill.SendReceipts = request.SendReceipts.Value;
            await db.SaveChangesAsync(ct);
            await transaction.CommitAsync(ct);
            return Results.Ok(DtoMapper.BillDetail(bill, today));
        }).RequireAuthorization("Parent");

        bills.MapPost("/{billId:guid}/end", async (Guid billId, ClaimsPrincipal user, BankOfDadDbContext db, BillChargeGenerator generator, BillScheduler scheduler, IClock clock, CancellationToken ct) =>
        {
            var (transaction, bill, today) = await LoadLockedAsync(billId, user, db, generator, clock, ct);
            await using var _ = transaction;
            if (bill.Status != BillStatus.Active) throw new ApiException(409, "Bill is not active.");
            db.BillCharges.RemoveRange(scheduler.End(bill, today, clock.UtcNow));
            await db.SaveChangesAsync(ct);
            await transaction.CommitAsync(ct);
            return Results.Ok(DtoMapper.BillDetail(bill, today));
        }).RequireAuthorization("Parent");

        bills.MapPost("/{billId:guid}/payments", async (Guid billId, PaymentRequest request, ClaimsPrincipal user, BankOfDadDbContext db, BillChargeGenerator generator, BillPaymentAllocator allocator, BillStateService state, NotificationService notifications, IClock clock, CancellationToken ct) =>
        {
            if (request.Amount <= 0m) throw new ApiException(400, "Payment amount must be greater than zero.");
            if (request.Note is { Length: > 500 }) throw new ApiException(400, "Note is too long.");
            var familyId = user.FamilyId();
            var today = await FamilyClock.TodayAsync(db, familyId, clock, ct);
            await generator.EnsureChargesAsync(familyId, today, billId, ct);
            await using var transaction = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct);
            // Lock the bill before touching its charges, in the same order as end/amount changes, so they can't deadlock.
            await LockBillAsync(db, billId, familyId, ct);
            var bill = await RequireBill(db, billId, user, ct);
            var payment = new BillPayment { BillId = bill.Id, Amount = Money.Round(request.Amount), PaidOn = request.PaidOn, Note = request.Note, RecordedByUserId = user.UserId(), CreatedAt = clock.UtcNow };
            try
            {
                var drafts = allocator.Allocate(bill, payment.Amount);
                payment.Allocations = drafts.Select(x => new BillPaymentAllocation { PaymentId = payment.Id, Target = x.Target, ChargeId = x.ChargeId, LateFeeId = x.LateFeeId, Amount = x.Amount }).ToList();
            }
            catch (InvalidOperationException ex) { throw new ApiException(409, ex.Message); }
            db.BillPayments.Add(payment);
            bill.ConcurrencyToken = Guid.NewGuid();
            await db.SaveChangesAsync(ct);
            if (bill.SendReceipts)
            {
                payment.ReceiptSentAt = clock.UtcNow;
                await notifications.CreateAndPushForBillAsync(bill.ChildId, NotificationType.Receipt, "Payment received", $"We received your {Money.Format(payment.Amount)} payment for \"{bill.Title}\". You now owe {Money.Format(state.Balance(bill, today))}.", bill.Id, ct);
            }
            payment = await db.BillPayments.Include(x => x.RecordedByUser).Include(x => x.Allocations).ThenInclude(x => x.Charge).SingleAsync(x => x.Id == payment.Id, ct);
            await transaction.CommitAsync(ct);
            return Results.Created($"/api/v1/bills/{billId}/payments/{payment.Id}", DtoMapper.BillPayment(payment));
        }).RequireAuthorization("Parent");

        bills.MapGet("/{billId:guid}/payments", async (Guid billId, ClaimsPrincipal user, BankOfDadDbContext db, CancellationToken ct) =>
        {
            _ = await RequireBill(db, billId, user, ct);
            var payments = await db.BillPayments.Include(x => x.RecordedByUser).Include(x => x.Allocations).ThenInclude(x => x.Charge).Where(x => x.BillId == billId).OrderByDescending(x => x.CreatedAt).ToListAsync(ct);
            return Results.Ok(payments.Select(DtoMapper.BillPayment).ToList());
        });

        bills.MapPost("/{billId:guid}/late-fees/{lateFeeId:guid}/waive", async (Guid billId, Guid lateFeeId, ClaimsPrincipal user, BankOfDadDbContext db, BillChargeGenerator generator, IClock clock, CancellationToken ct) =>
        {
            var (bill, today) = await LoadCurrentAsync(billId, user, db, generator, clock, ct);
            var fee = bill.LateFees.SingleOrDefault(x => x.Id == lateFeeId) ?? throw new ApiException(404, "Late fee not found.");
            if (fee.WaivedAt is null)
            {
                fee.WaivedAt = clock.UtcNow;
                fee.WaivedByUserId = user.UserId();
                await db.SaveChangesAsync(ct);
            }
            return Results.Ok(DtoMapper.BillDetail(bill, today));
        }).RequireAuthorization("Parent");
    }

    public static IQueryable<Bill> IncludeAll(this IQueryable<Bill> query) => query
        .Include(x => x.Child)
        .Include(x => x.Charges)
        .Include(x => x.LateFees)
        .Include(x => x.Payments).ThenInclude(x => x.RecordedByUser)
        .Include(x => x.Payments).ThenInclude(x => x.Allocations).ThenInclude(x => x.Charge);

    private static async Task<(Bill Bill, DateOnly Today)> LoadCurrentAsync(Guid billId, ClaimsPrincipal user, BankOfDadDbContext db, BillChargeGenerator generator, IClock clock, CancellationToken ct)
    {
        var familyId = user.FamilyId();
        var today = await FamilyClock.TodayAsync(db, familyId, clock, ct);
        await generator.EnsureChargesAsync(familyId, today, billId, ct);
        return (await RequireBill(db, billId, user, ct), today);
    }

    /// <summary>
    /// Generates charges, then locks the bill row (FOR UPDATE) in a transaction before loading it. Concurrent charge
    /// generation takes FOR SHARE on the same row, so it can't slip in a charge that this request is about to
    /// drop (end) or that would miss a reprice (amount change).
    /// </summary>
    private static async Task<(IDbContextTransaction Transaction, Bill Bill, DateOnly Today)> LoadLockedAsync(Guid billId, ClaimsPrincipal user, BankOfDadDbContext db, BillChargeGenerator generator, IClock clock, CancellationToken ct)
    {
        var familyId = user.FamilyId();
        var today = await FamilyClock.TodayAsync(db, familyId, clock, ct);
        await generator.EnsureChargesAsync(familyId, today, billId, ct);
        var transaction = await db.Database.BeginTransactionAsync(ct);
        try
        {
            await LockBillAsync(db, billId, familyId, ct);
            return (transaction, await RequireBill(db, billId, user, ct), today);
        }
        catch
        {
            await transaction.DisposeAsync();
            throw;
        }
    }

    private static Task LockBillAsync(BankOfDadDbContext db, Guid billId, Guid familyId, CancellationToken ct) =>
        db.Database.ExecuteSqlInterpolatedAsync($"""SELECT 1 FROM "Bills" WHERE "Id" = {billId} AND "FamilyId" = {familyId} FOR UPDATE""", ct);

    // Other families' bills and, for children, other children's bills are indistinguishable from missing ones.
    private static async Task<Bill> RequireBill(BankOfDadDbContext db, Guid billId, ClaimsPrincipal user, CancellationToken ct)
    {
        var familyId = user.FamilyId();
        var query = db.Bills.IncludeAll().Where(x => x.Id == billId && x.FamilyId == familyId);
        if (user.IsChild())
        {
            var childId = user.UserId();
            query = query.Where(x => x.ChildId == childId);
        }
        return await query.SingleOrDefaultAsync(ct) ?? throw new ApiException(404, "Bill not found.");
    }

    private static async Task<string> ValidateAsync(BillInput input, Guid familyId, DateOnly today, BankOfDadDbContext db, CancellationToken ct)
    {
        ValidateAmount(input.Amount);
        if (!Enum.IsDefined(input.Frequency)) throw new ApiException(400, "Frequency is not supported.");
        if ((input.LateFeeFlat ?? 0m) is < 0m or > 1_000_000m) throw new ApiException(400, "Late fee flat is out of range.");
        if ((input.LateFeePercent ?? 0m) is < 0m or > 1m) throw new ApiException(400, "Late fee percent is out of range.");
        if (input.LateFeeGraceDays is < 0 or > 60) throw new ApiException(400, "Late fee grace days is out of range.");
        var title = ValidateTitle(input.Title);
        if (input.FirstDueDate < today) throw new ApiException(400, "First due date cannot be in the past.");
        if (!await db.Users.AnyAsync(x => x.Id == input.ChildId && x.FamilyId == familyId && x.Role == Role.Child, ct)) throw new ApiException(404, "Child not found.");
        return title;
    }

    private static void ValidateAmount(decimal amount)
    {
        if (amount is < 0.01m or > 1_000_000m) throw new ApiException(400, "Amount is out of range.");
    }

    private static string ValidateTitle(string? title)
    {
        if (string.IsNullOrWhiteSpace(title)) throw new ApiException(400, "title is required.");
        var trimmed = title.Trim();
        if (trimmed.Length > 100) throw new ApiException(400, "Title is too long.");
        return trimmed;
    }

    // Minimal API enum binding is case-sensitive; the contract uses camelCase.
    private static BillStatus? ParseStatus(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        var name = Enum.GetNames<BillStatus>().FirstOrDefault(x => string.Equals(x, value.Trim(), StringComparison.OrdinalIgnoreCase))
            ?? throw new ApiException(400, "status must be one of: active, ended.");
        return Enum.Parse<BillStatus>(name);
    }
}
