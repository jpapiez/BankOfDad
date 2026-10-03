namespace BankOfDad.Api.Services;

using System.Data;
using BankOfDad.Domain;
using BankOfDad.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;

public sealed class AccountDeletionService(BankOfDadDbContext db)
{
    public async Task DeleteParentAsync(Guid userId, CancellationToken ct)
    {
        await using var transaction = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct).ConfigureAwait(false);

        var existing = await db.Users
            .FromSqlRaw("SELECT * FROM \"Users\" WHERE \"Id\" = {0} AND \"Role\" = 'Parent' FOR UPDATE NOWAIT", userId)
            .SingleOrDefaultAsync(ct)
            .ConfigureAwait(false);
        if (existing is null) throw new ApiException(404, "Parent account not found.");

        var familyId = existing.FamilyId;
        var remainingParentId = await db.Users
            .Where(x => x.FamilyId == familyId && x.Role == Role.Parent && x.Id != userId)
            .Select(x => (Guid?)x.Id)
            .FirstOrDefaultAsync(ct)
            .ConfigureAwait(false);

        await db.FamilyInvites.Where(x => x.CreatedByUserId == userId).ExecuteDeleteAsync(ct).ConfigureAwait(false);

        if (remainingParentId is null)
        {
            var family = await db.Families.SingleAsync(x => x.Id == familyId, ct).ConfigureAwait(false);
            db.Families.Remove(family);
        }
        else
        {
            await db.Loans.Where(x => x.FamilyId == familyId && x.CreatedByParentId == userId)
                .ExecuteUpdateAsync(s => s.SetProperty(x => x.CreatedByParentId, remainingParentId.Value), ct).ConfigureAwait(false);
            await db.Bills.Where(x => x.FamilyId == familyId && x.CreatedByParentId == userId)
                .ExecuteUpdateAsync(s => s.SetProperty(x => x.CreatedByParentId, remainingParentId.Value), ct).ConfigureAwait(false);
            await db.Payments.Where(x => x.RecordedByUserId == userId && db.Loans.Where(loan => loan.FamilyId == familyId).Select(loan => loan.Id).Contains(x.LoanId))
                .ExecuteUpdateAsync(s => s.SetProperty(x => x.RecordedByUserId, remainingParentId.Value), ct).ConfigureAwait(false);
            await db.BillPayments.Where(x => x.RecordedByUserId == userId && db.Bills.Where(bill => bill.FamilyId == familyId).Select(bill => bill.Id).Contains(x.BillId))
                .ExecuteUpdateAsync(s => s.SetProperty(x => x.RecordedByUserId, remainingParentId.Value), ct).ConfigureAwait(false);
            await db.LateFees.Where(x => x.WaivedByUserId == userId && db.Loans.Where(loan => loan.FamilyId == familyId).Select(loan => loan.Id).Contains(x.LoanId))
                .ExecuteUpdateAsync(s => s.SetProperty(x => x.WaivedByUserId, (Guid?)null), ct).ConfigureAwait(false);
            await db.BillLateFees.Where(x => x.WaivedByUserId == userId && db.Bills.Where(bill => bill.FamilyId == familyId).Select(bill => bill.Id).Contains(x.BillId))
                .ExecuteUpdateAsync(s => s.SetProperty(x => x.WaivedByUserId, (Guid?)null), ct).ConfigureAwait(false);
            db.Users.Remove(existing);
        }

        await db.SaveChangesAsync(ct).ConfigureAwait(false);
        await transaction.CommitAsync(ct).ConfigureAwait(false);
    }
}
