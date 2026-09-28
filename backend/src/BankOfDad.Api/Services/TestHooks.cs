namespace BankOfDad.Api.Services;

using System.Security.Claims;
using BankOfDad.Infrastructure.Data;
using BankOfDad.Infrastructure.Time;
using Microsoft.EntityFrameworkCore;

/// <summary>
/// Development-only endpoints used by the iOS UI test suite to reach time-dependent states
/// (overdue installments, late fees, reminders) without waiting for real time to pass.
/// Mapped only when the host environment is Development AND <c>TestHooks:Enabled</c> is true.
/// </summary>
public static class TestHooks
{
    public const string EnabledKey = "TestHooks:Enabled";

    public static bool IsEnabled(IHostEnvironment environment, IConfiguration configuration) =>
        environment.IsDevelopment() && configuration.GetValue<bool>(EnabledKey);

    public static void MapTestHooks(this RouteGroupBuilder api)
    {
        var testing = api.MapGroup("/testing").RequireAuthorization("Parent");

        // Shifts every installment (and the loan's first due date) of a loan in the caller's family `days` days earlier.
        testing.MapPost("/loans/{loanId:guid}/backdate", async (Guid loanId, BackdateRequest request, ClaimsPrincipal user, BankOfDadDbContext db, IClock clock, CancellationToken ct) =>
        {
            if (request.Days is < 1 or > 3650) throw new ApiException(400, "days must be between 1 and 3650.");
            var familyId = user.FamilyId();
            var loan = await db.Loans.IncludeAll().SingleOrDefaultAsync(x => x.Id == loanId && x.FamilyId == familyId, ct)
                ?? throw new ApiException(404, "Loan not found.");
            loan.FirstDueDate = loan.FirstDueDate.AddDays(-request.Days);
            foreach (var installment in loan.Installments) installment.DueDate = installment.DueDate.AddDays(-request.Days);
            loan.ConcurrencyToken = Guid.NewGuid();
            await db.SaveChangesAsync(ct);
            var family = await db.Families.AsNoTracking().SingleAsync(x => x.Id == familyId, ct);
            var tz = TimeZoneInfo.FindSystemTimeZoneById(family.TimeZone);
            var today = DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(clock.UtcNow, tz).DateTime);
            return Results.Ok(DtoMapper.LoanDetail(loan, today));
        });

        // Runs the reminder / late-fee sweep immediately, for the caller's family only.
        testing.MapPost("/sweep", async (ClaimsPrincipal user, LoanSweeper sweeper, CancellationToken ct) =>
        {
            await sweeper.SweepFamilyAsync(user.FamilyId(), ct);
            return Results.NoContent();
        });
    }

    public sealed record BackdateRequest(int Days);
}
