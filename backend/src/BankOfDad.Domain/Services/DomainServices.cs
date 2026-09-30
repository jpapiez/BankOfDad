namespace BankOfDad.Domain.Services;

using BankOfDad.Domain.Entities;

public record LoanTerms(Guid ChildId, string Title, decimal Principal, bool InterestEnabled, decimal AnnualRate, Frequency Frequency, int InstallmentCount, DateOnly FirstDueDate, decimal? LateFeeFlat, decimal? LateFeePercent, int LateFeeGraceDays, bool SendReminders, bool SendReceipts);
public record ScheduledInstallment(int Seq, DateOnly DueDate, decimal PrincipalDue, decimal InterestDue)
{
    public decimal AmountDue => Money.Round(PrincipalDue + InterestDue);
}
public record ScheduleResult(decimal InstallmentAmount, decimal TotalInterest, decimal TotalRepayable, IReadOnlyList<ScheduledInstallment> Installments);
public record AllocationDraft(AllocationTarget Target, Guid? InstallmentId, Guid? LateFeeId, decimal Amount, Guid? ChargeId = null);
public record PendingCharge(int Seq, DateOnly DueDate);

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
        Frequency.Quarterly => 4,
        Frequency.Yearly => 1,
        _ => throw new ArgumentOutOfRangeException(nameof(frequency))
    };

    public static DateOnly DueDate(DateOnly firstDueDate, Frequency frequency, int seq) => frequency switch
    {
        Frequency.Weekly => firstDueDate.AddDays(7 * (seq - 1)),
        Frequency.Biweekly => firstDueDate.AddDays(14 * (seq - 1)),
        // Always offset from the first due date so month-end dates clamp per period (Jan 31 -> Feb 28 -> Mar 31).
        Frequency.Monthly => firstDueDate.AddMonths(seq - 1),
        Frequency.Quarterly => firstDueDate.AddMonths(3 * (seq - 1)),
        Frequency.Yearly => firstDueDate.AddYears(seq - 1),
        _ => throw new ArgumentOutOfRangeException(nameof(frequency))
    };
}

public static class DueStatus
{
    public static InstallmentStatus Of(decimal remaining, DateOnly dueDate, DateOnly today, int graceDays)
    {
        if (remaining <= 0m) return InstallmentStatus.Paid;
        if (today < dueDate) return InstallmentStatus.Upcoming;
        return today <= dueDate.AddDays(graceDays) ? InstallmentStatus.Due : InstallmentStatus.Late;
    }

    public static decimal LateFee(decimal? flat, decimal? percent, decimal remaining) => Money.Round((flat ?? 0m) + (percent ?? 0m) * remaining);

    public static bool HasLateFeeRule(decimal? flat, decimal? percent) => (flat ?? 0m) != 0m || (percent ?? 0m) != 0m;
}

public sealed class LoanStateService
{
    public decimal InstallmentRemaining(Installment installment) => Money.Round(installment.PrincipalDue - installment.PrincipalPaid + installment.InterestDue - installment.InterestPaid);
    public decimal InterestRemaining(Installment installment) => Money.Round(installment.InterestDue - installment.InterestPaid);
    public decimal PrincipalRemaining(Installment installment) => Money.Round(installment.PrincipalDue - installment.PrincipalPaid);
    public decimal FeeRemaining(LateFee fee) => fee.WaivedAt is null ? Money.Round(fee.Amount - fee.AmountPaid) : 0m;
    public decimal Balance(Loan loan) => Money.Round(loan.Installments.Sum(InstallmentRemaining) + loan.LateFees.Sum(FeeRemaining));
    public decimal AmountPaid(Loan loan) => Money.Round(loan.Payments.Sum(p => p.Amount));

    public InstallmentStatus Status(Installment installment, DateOnly today, int graceDays) => DueStatus.Of(InstallmentRemaining(installment), installment.DueDate, today, graceDays);

    public decimal ComputeLateFee(Loan loan, Installment installment) => DueStatus.LateFee(loan.LateFeeFlat, loan.LateFeePercent, InstallmentRemaining(installment));

    public bool ShouldAssessLateFee(Loan loan, Installment installment, DateOnly today)
    {
        if (loan.Status != LoanStatus.Active) return false;
        if (loan.LateFees.Any(x => x.InstallmentId == installment.Id)) return false;
        if (!DueStatus.HasLateFeeRule(loan.LateFeeFlat, loan.LateFeePercent)) return false;
        return Status(installment, today, loan.LateFeeGraceDays) == InstallmentStatus.Late && ComputeLateFee(loan, installment) > 0m;
    }

    public bool IsPaidOff(Loan loan) => loan.Status == LoanStatus.Active && Balance(loan) <= 0m;
}

public sealed class PaymentAllocator(LoanStateService state)
{
    public IReadOnlyList<AllocationDraft> Allocate(Loan loan, decimal amount)
    {
        var waterfall = AllocationWaterfall.Start(amount, state.Balance(loan), "Payment amount exceeds the loan balance.");
        foreach (var fee in loan.LateFees.Where(f => f.WaivedAt is null && state.FeeRemaining(f) > 0m).OrderBy(f => f.AssessedAt))
        {
            waterfall.Take(new AllocationDraft(AllocationTarget.LateFee, null, fee.Id, state.FeeRemaining(fee)), v => fee.AmountPaid = Money.Round(fee.AmountPaid + v));
            if (waterfall.Exhausted) return waterfall.Drafts;
        }

        foreach (var installment in loan.Installments.OrderBy(i => i.Seq))
        {
            waterfall.Take(new AllocationDraft(AllocationTarget.Interest, installment.Id, null, state.InterestRemaining(installment)), v => installment.InterestPaid = Money.Round(installment.InterestPaid + v));
            if (waterfall.Exhausted) return waterfall.Drafts;
            waterfall.Take(new AllocationDraft(AllocationTarget.Principal, installment.Id, null, state.PrincipalRemaining(installment)), v => installment.PrincipalPaid = Money.Round(installment.PrincipalPaid + v));
            if (waterfall.Exhausted) return waterfall.Drafts;
        }

        return waterfall.Drafts;
    }
}

/// <summary>Applies a payment to a sequence of owed amounts in order until it runs out. Shared by loans and bills.</summary>
internal sealed class AllocationWaterfall
{
    private readonly List<AllocationDraft> _drafts = [];
    private decimal _remaining;

    private AllocationWaterfall(decimal amount) => _remaining = amount;

    public IReadOnlyList<AllocationDraft> Drafts => _drafts;
    public bool Exhausted => _remaining <= 0m;

    public static AllocationWaterfall Start(decimal amount, decimal maximum, string exceedsMessage)
    {
        amount = Money.Round(amount);
        if (amount <= 0m) throw new InvalidOperationException("Payment amount must be greater than zero.");
        if (amount > maximum) throw new InvalidOperationException(exceedsMessage);
        return new AllocationWaterfall(amount);
    }

    /// <param name="owed">A draft whose <see cref="AllocationDraft.Amount"/> is the amount still owed on the target.</param>
    public void Take(AllocationDraft owed, Action<decimal> apply)
    {
        if (owed.Amount <= 0m || _remaining <= 0m) return;
        var amountToApply = Money.Round(Math.Min(owed.Amount, _remaining));
        apply(amountToApply);
        _drafts.Add(owed with { Amount = amountToApply });
        _remaining = Money.Round(_remaining - amountToApply);
    }
}

public sealed class BillStateService
{
    public decimal ChargeRemaining(BillCharge charge) => Money.Round(charge.Amount - charge.AmountPaid);
    public decimal FeeRemaining(BillLateFee fee) => fee.WaivedAt is null ? Money.Round(fee.Amount - fee.AmountPaid) : 0m;
    public decimal OutstandingFees(Bill bill) => Money.Round(bill.LateFees.Sum(FeeRemaining));

    /// <summary>What the child owes right now: unpaid charges that are due (today or earlier) plus outstanding late fees.</summary>
    public decimal Balance(Bill bill, DateOnly today) => Money.Round(bill.Charges.Where(c => c.DueDate <= today).Sum(ChargeRemaining) + OutstandingFees(bill));

    /// <summary>Unpaid amount on generated charges that are not due yet. It can be paid early but isn't owed yet.</summary>
    public decimal UpcomingAmount(Bill bill, DateOnly today) => Money.Round(bill.Charges.Where(c => c.DueDate > today).Sum(ChargeRemaining));

    /// <summary>The most a single payment can be: every generated charge plus outstanding late fees.</summary>
    public decimal Payable(Bill bill) => Money.Round(bill.Charges.Sum(ChargeRemaining) + OutstandingFees(bill));

    public decimal AmountPaid(Bill bill) => Money.Round(bill.Payments.Sum(p => p.Amount));

    public InstallmentStatus Status(BillCharge charge, DateOnly today, int graceDays) => DueStatus.Of(ChargeRemaining(charge), charge.DueDate, today, graceDays);

    public decimal ComputeLateFee(Bill bill, BillCharge charge) => DueStatus.LateFee(bill.LateFeeFlat, bill.LateFeePercent, ChargeRemaining(charge));

    /// <summary>
    /// A late charge gets one late fee, ever. Unlike a cancelled loan, an ended bill still assesses fees on charges
    /// that were already owed: ending a bill stops future charges, it doesn't forgive past ones.
    /// </summary>
    public bool ShouldAssessLateFee(Bill bill, BillCharge charge, DateOnly today)
    {
        if (bill.LateFees.Any(x => x.ChargeId == charge.Id)) return false;
        if (!DueStatus.HasLateFeeRule(bill.LateFeeFlat, bill.LateFeePercent)) return false;
        return Status(charge, today, bill.LateFeeGraceDays) == InstallmentStatus.Late && ComputeLateFee(bill, charge) > 0m;
    }
}

public sealed class BillScheduler
{
    /// <summary>Upper bound on charges generated in one pass, so a bad first due date can't run away.</summary>
    public const int MaxChargesPerPass = 520;

    /// <summary>
    /// The charges to generate after <paramref name="lastSeq"/>: every charge that is due by <paramref name="today"/>,
    /// plus the next upcoming one so the child can see (and be reminded about) what's coming.
    /// A charge exists once the charge before it is due. Ended bills never generate charges.
    /// </summary>
    public IReadOnlyList<PendingCharge> PendingCharges(DateOnly firstDueDate, Frequency frequency, BillStatus status, int lastSeq, DateOnly today)
    {
        var pending = new List<PendingCharge>();
        if (status != BillStatus.Active) return pending;
        for (var seq = lastSeq + 1; pending.Count < MaxChargesPerPass; seq++)
        {
            if (seq > 1 && ScheduleCalculator.DueDate(firstDueDate, frequency, seq - 1) > today) break;
            pending.Add(new PendingCharge(seq, ScheduleCalculator.DueDate(firstDueDate, frequency, seq)));
        }
        return pending;
    }

    public IReadOnlyList<PendingCharge> PendingCharges(Bill bill, DateOnly today) =>
        PendingCharges(bill.FirstDueDate, bill.Frequency, bill.Status, bill.Charges.Count == 0 ? 0 : bill.Charges.Max(c => c.Seq), today);

    /// <summary>
    /// Sets the amount for future charges. Charges already due keep their amount. Generated charges that aren't due
    /// yet are repriced, but never below what has already been paid toward them.
    /// </summary>
    public void ChangeAmount(Bill bill, decimal amount, DateOnly today)
    {
        if (bill.Status != BillStatus.Active) throw new InvalidOperationException("Only active bills can change their amount.");
        amount = Money.Round(amount);
        bill.Amount = amount;
        foreach (var charge in bill.Charges.Where(c => c.DueDate > today))
        {
            charge.Amount = Math.Max(amount, charge.AmountPaid);
        }
    }

    /// <summary>
    /// Ends the bill. Charges that are already due stay owed. Charges that aren't due yet are dropped, or, if the
    /// child already paid toward one, closed out at the amount paid. Returns the charges to delete.
    /// </summary>
    public IReadOnlyList<BillCharge> End(Bill bill, DateOnly today, DateTimeOffset now)
    {
        if (bill.Status != BillStatus.Active) throw new InvalidOperationException("Bill is not active.");
        bill.Status = BillStatus.Ended;
        bill.EndedAt = now;
        var removed = new List<BillCharge>();
        foreach (var charge in bill.Charges.Where(c => c.DueDate > today).ToList())
        {
            if (charge.AmountPaid > 0m)
            {
                charge.Amount = charge.AmountPaid;
                continue;
            }
            bill.Charges.Remove(charge);
            removed.Add(charge);
        }
        return removed;
    }
}

public sealed class BillPaymentAllocator(BillStateService state)
{
    /// <summary>Late fees first (oldest assessed first), then charges oldest first, including not-yet-due charges paid early.</summary>
    public IReadOnlyList<AllocationDraft> Allocate(Bill bill, decimal amount)
    {
        var waterfall = AllocationWaterfall.Start(amount, state.Payable(bill), "Payment amount exceeds the amount owed on this bill.");
        foreach (var fee in bill.LateFees.Where(f => state.FeeRemaining(f) > 0m).OrderBy(f => f.AssessedAt))
        {
            waterfall.Take(new AllocationDraft(AllocationTarget.LateFee, null, fee.Id, state.FeeRemaining(fee)), v => fee.AmountPaid = Money.Round(fee.AmountPaid + v));
            if (waterfall.Exhausted) return waterfall.Drafts;
        }

        foreach (var charge in bill.Charges.OrderBy(c => c.Seq))
        {
            waterfall.Take(new AllocationDraft(AllocationTarget.Charge, null, null, state.ChargeRemaining(charge), charge.Id), v => charge.AmountPaid = Money.Round(charge.AmountPaid + v));
            if (waterfall.Exhausted) return waterfall.Drafts;
        }

        return waterfall.Drafts;
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
        var feeText = LateFeeText(loan.LateFeeFlat, loan.LateFeePercent, loan.LateFeeGraceDays, currency);
        return string.IsNullOrEmpty(feeText) ? text : text + " " + feeText;
    }

    public string Build(Bill bill, string childName, string currency = "USD")
    {
        var freq = bill.Frequency.ToString().ToLowerInvariant();
        var first = bill.FirstDueDate.ToDateTime(TimeOnly.MinValue).ToString("MMM d, yyyy", System.Globalization.CultureInfo.GetCultureInfo("en-US"));
        var text = bill.Status == BillStatus.Ended
            ? $"{childName} paid {Money.Format(bill.Amount, currency)} {freq} for \"{bill.Title}\" starting {first}. This bill has ended."
            : $"{childName} pays {Money.Format(bill.Amount, currency)} {freq} for \"{bill.Title}\" starting {first}, until the bill is ended.";
        var feeText = LateFeeText(bill.LateFeeFlat, bill.LateFeePercent, bill.LateFeeGraceDays, currency);
        return string.IsNullOrEmpty(feeText) ? text : text + " " + feeText;
    }

    private static string LateFeeText(decimal? flat, decimal? percent, int graceDays, string currency)
    {
        var parts = new List<string>();
        if ((flat ?? 0m) > 0m) parts.Add(Money.Format(flat!.Value, currency));
        if ((percent ?? 0m) > 0m) parts.Add($"{Percent(percent!.Value)} of the missed payment");
        if (parts.Count == 0) return string.Empty;
        var when = graceDays switch
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
