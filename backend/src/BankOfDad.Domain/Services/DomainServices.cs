namespace BankOfDad.Domain.Services;

using BankOfDad.Domain.Entities;

public record LoanTerms(Guid ChildId, string Title, decimal Principal, bool InterestEnabled, decimal AnnualRate, Frequency Frequency, int InstallmentCount, DateOnly FirstDueDate, decimal? LateFeeFlat, decimal? LateFeePercent, int LateFeeGraceDays, bool SendReminders, bool SendReceipts);
public record ScheduledInstallment(int Seq, DateOnly DueDate, decimal PrincipalDue, decimal InterestDue)
{
    public decimal AmountDue => Money.Round(PrincipalDue + InterestDue);
}
public record ScheduleResult(decimal InstallmentAmount, decimal TotalInterest, decimal TotalRepayable, IReadOnlyList<ScheduledInstallment> Installments);
public record AllocationDraft(AllocationTarget Target, Guid? InstallmentId, Guid? LateFeeId, decimal Amount);

public sealed class ScheduleCalculator
{
    public ScheduleResult Calculate(LoanTerms terms) => Calculate(terms.Principal, terms.InterestEnabled, terms.AnnualRate, terms.Frequency, terms.InstallmentCount, terms.FirstDueDate);

    public ScheduleResult Calculate(decimal principal, bool interestEnabled, decimal annualRate, Frequency frequency, int installmentCount, DateOnly firstDueDate)
    {
        var periods = PeriodsPerYear(frequency);
        var rate = interestEnabled ? annualRate / periods : 0m;
        var payment = rate == 0m
            ? Money.Round(principal / installmentCount)
            : Money.Round(principal * rate / (1m - (decimal)Math.Pow((double)(1m + rate), -installmentCount)));

        var balance = principal;
        var rows = new List<ScheduledInstallment>(installmentCount);
        for (var i = 1; i <= installmentCount; i++)
        {
            var interest = rate == 0m ? 0m : Money.Round(balance * rate);
            var principalDue = i == installmentCount ? Money.Round(balance) : Money.Round(payment - interest);
            if (principalDue > balance || i == installmentCount)
            {
                principalDue = Money.Round(balance);
            }
            rows.Add(new ScheduledInstallment(i, DueDate(firstDueDate, frequency, i), principalDue, interest));
            balance = Money.Round(balance - principalDue);
        }

        var totalInterest = Money.Round(rows.Sum(x => x.InterestDue));
        return new ScheduleResult(payment, totalInterest, Money.Round(principal + totalInterest), rows);
    }

    public static int PeriodsPerYear(Frequency frequency) => frequency switch
    {
        Frequency.Weekly => 52,
        Frequency.Biweekly => 26,
        Frequency.Monthly => 12,
        _ => throw new ArgumentOutOfRangeException(nameof(frequency))
    };

    public static DateOnly DueDate(DateOnly firstDueDate, Frequency frequency, int seq) => frequency switch
    {
        Frequency.Weekly => firstDueDate.AddDays(7 * (seq - 1)),
        Frequency.Biweekly => firstDueDate.AddDays(14 * (seq - 1)),
        Frequency.Monthly => firstDueDate.AddMonths(seq - 1),
        _ => throw new ArgumentOutOfRangeException(nameof(frequency))
    };
}

public sealed class LoanStateService
{
    public decimal InstallmentRemaining(Installment installment) => Money.Round(installment.PrincipalDue - installment.PrincipalPaid + installment.InterestDue - installment.InterestPaid);
    public decimal InterestRemaining(Installment installment) => Money.Round(installment.InterestDue - installment.InterestPaid);
    public decimal PrincipalRemaining(Installment installment) => Money.Round(installment.PrincipalDue - installment.PrincipalPaid);
    public decimal FeeRemaining(LateFee fee) => fee.WaivedAt is null ? Money.Round(fee.Amount - fee.AmountPaid) : 0m;
    public decimal Balance(Loan loan) => Money.Round(loan.Installments.Sum(InstallmentRemaining) + loan.LateFees.Sum(FeeRemaining));
    public decimal AmountPaid(Loan loan) => Money.Round(loan.Payments.Sum(p => p.Amount));

    public InstallmentStatus Status(Installment installment, DateOnly today, int graceDays)
    {
        if (InstallmentRemaining(installment) <= 0m) return InstallmentStatus.Paid;
        if (today < installment.DueDate) return InstallmentStatus.Upcoming;
        return today <= installment.DueDate.AddDays(graceDays) ? InstallmentStatus.Due : InstallmentStatus.Late;
    }

    public decimal ComputeLateFee(Loan loan, Installment installment)
    {
        var flat = loan.LateFeeFlat ?? 0m;
        var percent = loan.LateFeePercent ?? 0m;
        return Money.Round(flat + percent * InstallmentRemaining(installment));
    }

    public bool ShouldAssessLateFee(Loan loan, Installment installment, DateOnly today)
    {
        if (loan.Status != LoanStatus.Active) return false;
        if (loan.LateFees.Any(x => x.InstallmentId == installment.Id)) return false;
        if ((loan.LateFeeFlat ?? 0m) == 0m && (loan.LateFeePercent ?? 0m) == 0m) return false;
        return Status(installment, today, loan.LateFeeGraceDays) == InstallmentStatus.Late && ComputeLateFee(loan, installment) > 0m;
    }

    public bool IsPaidOff(Loan loan) => loan.Status == LoanStatus.Active && Balance(loan) <= 0m;
}

public sealed class PaymentAllocator(LoanStateService state)
{
    public IReadOnlyList<AllocationDraft> Allocate(Loan loan, decimal amount)
    {
        amount = Money.Round(amount);
        if (amount <= 0m) throw new InvalidOperationException("Payment amount must be greater than zero.");
        var balance = state.Balance(loan);
        if (amount > balance) throw new InvalidOperationException("Payment amount exceeds the loan balance.");

        var remainingPayment = amount;
        var drafts = new List<AllocationDraft>();
        foreach (var fee in loan.LateFees.Where(f => f.WaivedAt is null && state.FeeRemaining(f) > 0m).OrderBy(f => f.AssessedAt))
        {
            Take(AllocationTarget.LateFee, null, fee.Id, state.FeeRemaining(fee), v => fee.AmountPaid = Money.Round(fee.AmountPaid + v));
            if (remainingPayment <= 0m) return drafts;
        }

        foreach (var installment in loan.Installments.OrderBy(i => i.Seq))
        {
            Take(AllocationTarget.Interest, installment.Id, null, state.InterestRemaining(installment), v => installment.InterestPaid = Money.Round(installment.InterestPaid + v));
            if (remainingPayment <= 0m) return drafts;
            Take(AllocationTarget.Principal, installment.Id, null, state.PrincipalRemaining(installment), v => installment.PrincipalPaid = Money.Round(installment.PrincipalPaid + v));
            if (remainingPayment <= 0m) return drafts;
        }

        return drafts;

        void Take(AllocationTarget target, Guid? installmentId, Guid? lateFeeId, decimal owed, Action<decimal> apply)
        {
            if (owed <= 0m || remainingPayment <= 0m) return;
            var amountToApply = Money.Round(Math.Min(owed, remainingPayment));
            apply(amountToApply);
            drafts.Add(new AllocationDraft(target, installmentId, lateFeeId, amountToApply));
            remainingPayment = Money.Round(remainingPayment - amountToApply);
        }
    }
}

public sealed class TermsSummaryBuilder
{
    public string Build(Loan loan, string childName, string currency = "USD")
    {
        var rate = loan.InterestEnabled ? $" at {Percent(loan.AnnualRate)} APR" : " with no interest";
        var freq = loan.Frequency.ToString().ToLowerInvariant();
        var first = loan.FirstDueDate.ToDateTime(TimeOnly.MinValue).ToString("MMM d, yyyy", System.Globalization.CultureInfo.GetCultureInfo("en-US"));
        var text = $"{childName} borrowed {Money.Format(loan.Principal, currency)} for \"{loan.Title}\"{rate}, repaid in {loan.InstallmentCount} {freq} payments of {Money.Format(loan.InstallmentAmount, currency)} starting {first}.";
        var feeText = LateFeeText(loan, currency);
        return string.IsNullOrEmpty(feeText) ? text : text + " " + feeText;
    }

    private static string LateFeeText(Loan loan, string currency)
    {
        var parts = new List<string>();
        if ((loan.LateFeeFlat ?? 0m) > 0m) parts.Add(Money.Format(loan.LateFeeFlat!.Value, currency));
        if ((loan.LateFeePercent ?? 0m) > 0m) parts.Add($"{Percent(loan.LateFeePercent!.Value)} of the missed payment");
        if (parts.Count == 0) return string.Empty;
        var when = loan.LateFeeGraceDays switch
        {
            0 => "after a missed due date",
            1 => "1 day after a missed due date",
            var days => $"{days} days after a missed due date",
        };
        return $"A late fee of {string.Join(" + ", parts)} applies {when}.";
    }

    private static string Percent(decimal fraction) =>
        (fraction * 100m).ToString("0.##", System.Globalization.CultureInfo.InvariantCulture) + "%";
}
