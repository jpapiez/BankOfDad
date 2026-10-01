namespace BankOfDad.Api.Services;

using System.Data;
using BankOfDad.Domain;
using BankOfDad.Infrastructure.Data;
using BankOfDad.Infrastructure.Security;
using Microsoft.EntityFrameworkCore;

public sealed class AccountDeletionService(BankOfDadDbContext db, IAppleAuthorizationService appleAuthorization)
{
    public async Task DeleteParentAsync(Guid userId, CancellationToken ct)
    {
        var parent = await db.Users.SingleOrDefaultAsync(x => x.Id == userId && x.Role == Role.Parent, ct).ConfigureAwait(false)
            ?? throw new ApiException(404, "Parent account not found.");
        if (parent.AppleSubject is not null)
        {
            if (string.IsNullOrWhiteSpace(parent.AppleRefreshTokenEncrypted))
            {
                throw new ApiException(409, "Sign in with Apple must be completed again before this account can be deleted.", "Sign out, sign in with Apple again, then retry account deletion.");
            }
            try
            {
                await appleAuthorization.RevokeAsync(parent.AppleRefreshTokenEncrypted, ct).ConfigureAwait(false);
            }
            catch (AppleAuthorizationException)
            {
                throw new ApiException(503, "Apple authorization could not be revoked.", "Your account was not deleted. Please try again.");
            }
        }

        await using var transaction = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct).ConfigureAwait(false);
        var familyId = parent.FamilyId;
        var remainingParentId = await db.Users
            .Where(x => x.FamilyId == familyId && x.Role == Role.Parent && x.Id != userId)
            .Select(x => (Guid?)x.Id)
            .FirstOrDefaultAsync(ct)
            .ConfigureAwait(false);

        // Invite codes belong to the account that created them and must not survive account deletion.
        await db.FamilyInvites.Where(x => x.CreatedByUserId == userId).ExecuteDeleteAsync(ct).ConfigureAwait(false);

        if (remainingParentId is null)
        {
            var family = await db.Families.SingleAsync(x => x.Id == familyId, ct).ConfigureAwait(false);
            db.Families.Remove(family);
        }
        else
        {
            // Family records remain shared. Transfer ownership/audit references before removing
            // the parent because those foreign keys are required and intentionally preserved.
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
            db.Users.Remove(parent);
        }

        await db.SaveChangesAsync(ct).ConfigureAwait(false);
        await transaction.CommitAsync(ct).ConfigureAwait(false);
    }
}
