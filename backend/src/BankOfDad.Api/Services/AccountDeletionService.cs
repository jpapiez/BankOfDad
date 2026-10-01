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
        await using var transaction = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct).ConfigureAwait(false);

        var existing = await db.Users
            .SingleOrDefaultAsync(x => x.Id == userId && x.Role == Role.Parent, ct)
            .ConfigureAwait(false);
        if (existing is null) throw new ApiException(404, "Parent account not found.");

        var deletionStarted = false;
        try
        {
            var updated = await db.Users
                .Where(x => x.Id == userId && x.Role == Role.Parent && x.AppleDeletionStartedAt == null)
                .ExecuteUpdateAsync(s => s.SetProperty(x => x.AppleDeletionStartedAt, DateTimeOffset.UtcNow), ct)
                .ConfigureAwait(false);
            if (updated == 0)
            {
                throw new ApiException(409, "Account deletion is already in progress.");
            }

            existing.AppleDeletionStartedAt = DateTimeOffset.UtcNow;
            deletionStarted = true;

            if (existing.AppleSubject is not null)
            {
                var tokens = await db.AppleRefreshTokens
                    .Where(x => x.UserId == userId && x.RevokedAt == null)
                    .OrderBy(x => x.CreatedAt)
                    .Select(x => new { x.Id, x.TokenEncrypted })
                    .ToListAsync(ct)
                    .ConfigureAwait(false);
                if (tokens.Count == 0)
                {
                    throw new ApiException(409, "Sign in with Apple must be completed again before this account can be deleted.", "Sign out, sign in with Apple again, then retry account deletion.");
                }

                foreach (var token in tokens)
                {
                    try
                    {
                        await appleAuthorization.RevokeAsync(token.TokenEncrypted, ct).ConfigureAwait(false);
                    }
                    catch (AppleAuthorizationException)
                    {
                        throw new ApiException(503, "Apple authorization could not be revoked.", "Your account was not deleted. Please try again.");
                    }
                }

                foreach (var token in tokens)
                {
                    await db.AppleRefreshTokens
                        .Where(x => x.Id == token.Id)
                        .ExecuteUpdateAsync(s => s.SetProperty(x => x.RevokedAt, DateTimeOffset.UtcNow), ct)
                        .ConfigureAwait(false);
                }
            }
        }
        catch
        {
            if (deletionStarted)
            {
                existing.AppleDeletionStartedAt = null;
                await db.SaveChangesAsync(ct).ConfigureAwait(false);
            }
            throw;
        }

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
