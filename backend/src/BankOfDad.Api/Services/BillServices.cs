namespace BankOfDad.Api.Services;

using System.Globalization;
using BankOfDad.Domain;
using BankOfDad.Domain.Entities;
using BankOfDad.Domain.Services;
using BankOfDad.Infrastructure.Data;
using BankOfDad.Infrastructure.Time;
using Microsoft.EntityFrameworkCore;

public static class FamilyClock
{
    public static DateOnly Today(string timeZone, IClock clock)
    {
        var tz = TimeZoneInfo.FindSystemTimeZoneById(timeZone);
        return DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(clock.UtcNow, tz).DateTime);
    }

    public static async Task<DateOnly> TodayAsync(BankOfDadDbContext db, Guid familyId, IClock clock, CancellationToken ct)
    {
        var family = await db.Families.AsNoTracking().SingleOrDefaultAsync(x => x.Id == familyId, ct).ConfigureAwait(false) ?? throw new ApiException(404, "Family not found.");
        return Today(family.TimeZone, clock);
    }
}

/// <summary>
/// Materializes bill charges lazily: every charge due by today plus the next upcoming one. Safe to call from any
/// request or the background sweep, concurrently: inserts use ON CONFLICT DO NOTHING against the unique
/// (BillId, DueDate) and (BillId, Seq) indexes, and read the bill's current amount and status at insert time.
/// The insert takes FOR SHARE on the bill row, so it waits for an in-flight end or amount change (which hold
/// FOR UPDATE, see <see cref="BillEndpoints"/>) and re-checks the committed status and amount.
/// Call it before loading bills into the change tracker so the loaded entities include the new charges.
/// </summary>
public sealed class BillChargeGenerator(BankOfDadDbContext db, BillScheduler scheduler)
{
    public async Task EnsureChargesAsync(Guid familyId, DateOnly today, Guid? billId, CancellationToken ct)
    {
        var bills = await db.Bills.AsNoTracking()
            .Where(b => b.FamilyId == familyId && b.Status == BillStatus.Active && (billId == null || b.Id == billId))
            .Select(b => new { b.Id, b.FirstDueDate, b.Frequency, b.Status, LastSeq = b.Charges.Max(c => (int?)c.Seq) ?? 0 })
            .ToListAsync(ct).ConfigureAwait(false);
        foreach (var bill in bills)
        {
            foreach (var charge in scheduler.PendingCharges(bill.FirstDueDate, bill.Frequency, bill.Status, bill.LastSeq, today))
            {
                await db.Database.ExecuteSqlInterpolatedAsync($"""
                    INSERT INTO "BillCharges" ("Id", "BillId", "Seq", "DueDate", "Amount", "AmountPaid")
                    SELECT {Guid.NewGuid()}, b."Id", {charge.Seq}, {charge.DueDate}, b."Amount", 0
                    FROM "Bills" b
                    WHERE b."Id" = {bill.Id} AND b."Status" = 'Active'
                    FOR SHARE
                    ON CONFLICT DO NOTHING
                    """, ct).ConfigureAwait(false);
            }
        }
    }
}

/// <summary>Generates charges, assesses late fees and sends reminders for one family's bills. Run by <see cref="LoanSweeper"/>.</summary>
public sealed class BillSweeper(BankOfDadDbContext db, BillChargeGenerator generator, BillStateService state, NotificationService notifications, IClock clock)
{
    public async Task SweepFamilyAsync(Guid familyId, DateOnly today, CancellationToken ct)
    {
        await generator.EnsureChargesAsync(familyId, today, null, ct).ConfigureAwait(false);
        // Ended bills can still owe charges that came due before they ended, and those still pick up late fees.
        var bills = await db.Bills
            .Include(x => x.Charges)
            .Include(x => x.LateFees)
            .Where(x => x.FamilyId == familyId && (x.Status == BillStatus.Active || x.Charges.Any(c => c.AmountPaid < c.Amount)))
            .ToListAsync(ct).ConfigureAwait(false);
        foreach (var bill in bills)
        {
            foreach (var charge in bill.Charges.OrderBy(x => x.Seq).ToList())
            {
                if (state.ShouldAssessLateFee(bill, charge, today))
                {
                    var fee = new BillLateFee { BillId = bill.Id, ChargeId = charge.Id, Amount = state.ComputeLateFee(bill, charge), AssessedAt = clock.UtcNow };
                    db.BillLateFees.Add(fee);
                    await db.SaveChangesAsync(ct).ConfigureAwait(false);
                    await notifications.CreateAndPushForBillAsync(bill.ChildId, NotificationType.LateFee, "Late fee assessed", $"A late fee of {Money.Format(fee.Amount)} was added to \"{bill.Title}\".", bill.Id, ct).ConfigureAwait(false);
                }

                if (bill.Status == BillStatus.Active && bill.SendReminders && charge.ReminderSentAt is null && state.ChargeRemaining(charge) > 0m && today >= charge.DueDate.AddDays(-15) && today <= charge.DueDate)
                {
                    charge.ReminderSentAt = clock.UtcNow;
                    var due = charge.DueDate.ToDateTime(TimeOnly.MinValue).ToString("MMM d, yyyy", CultureInfo.GetCultureInfo("en-US"));
                    await notifications.CreateAndPushForBillAsync(bill.ChildId, NotificationType.Reminder, "Bill due soon", $"Your {Money.Format(state.ChargeRemaining(charge))} payment for \"{bill.Title}\" is due {due}.", bill.Id, ct).ConfigureAwait(false);
                }
            }
        }
        await db.SaveChangesAsync(ct).ConfigureAwait(false);
    }
}
