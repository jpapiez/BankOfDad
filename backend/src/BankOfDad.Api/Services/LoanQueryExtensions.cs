namespace BankOfDad.Api.Services;

using BankOfDad.Domain.Entities;
using Microsoft.EntityFrameworkCore;

public static class LoanQueryExtensions
{
    public static IQueryable<Loan> IncludeAll(this IQueryable<Loan> query) => query
        .Include(x => x.BorrowerChild)
        .Include(x => x.CreatedByParent)
        .Include(x => x.Installments)
        .Include(x => x.LateFees)
        .Include(x => x.Payments).ThenInclude(x => x.RecordedByUser)
        .Include(x => x.Payments).ThenInclude(x => x.Allocations).ThenInclude(x => x.Installment);
}
