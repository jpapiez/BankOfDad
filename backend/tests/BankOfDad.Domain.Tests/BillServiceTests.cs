namespace BankOfDad.Domain.Tests;

using BankOfDad.Domain;
using BankOfDad.Domain.Entities;
using BankOfDad.Domain.Services;
using FluentAssertions;

public sealed class BillServiceTests
{
    private readonly BillScheduler _scheduler = new();
    private readonly BillStateService _state = new();

    public static TheoryData<Frequency, string, string, string[]> Schedules => new()
    {
        { Frequency.Weekly, "2026-01-31", "2026-02-14", ["2026-01-31", "2026-02-07", "2026-02-14", "2026-02-21"] },
        { Frequency.Biweekly, "2026-01-31", "2026-02-28", ["2026-01-31", "2026-02-14", "2026-02-28", "2026-03-14"] },
        // Month-end clamps per period and recovers: Jan 31 -> Feb 28 -> Mar 31 -> Apr 30.
        { Frequency.Monthly, "2026-01-31", "2026-03-31", ["2026-01-31", "2026-02-28", "2026-03-31", "2026-04-30"] },
        { Frequency.Monthly, "2028-01-31", "2028-02-29", ["2028-01-31", "2028-02-29", "2028-03-31"] },
        { Frequency.Quarterly, "2026-01-31", "2026-07-31", ["2026-01-31", "2026-04-30", "2026-07-31", "2026-10-31"] },
        { Frequency.Yearly, "2028-02-29", "2029-02-28", ["2028-02-29", "2029-02-28", "2030-02-28"] },
    };

    [Theory]
    [MemberData(nameof(Schedules))]
    public void Generates_every_due_charge_plus_the_next_one_for_each_frequency(Frequency frequency, string first, string today, string[] expected)
    {
        var pending = _scheduler.PendingCharges(DateOnly.Parse(first), frequency, BillStatus.Active, 0, DateOnly.Parse(today));
        pending.Select(x => x.DueDate).Should().Equal(expected.Select(DateOnly.Parse));
        pending.Select(x => x.Seq).Should().Equal(Enumerable.Range(1, expected.Length));
    }

    [Fact]
    public void Generates_only_the_first_charge_before_it_is_due()
    {
        var pending = _scheduler.PendingCharges(new DateOnly(2026, 11, 1), Frequency.Monthly, BillStatus.Active, 0, new DateOnly(2026, 10, 17));
        pending.Should().Equal(new PendingCharge(1, new DateOnly(2026, 11, 1)));
    }

    [Fact]
    public void Generation_is_idempotent_and_resumes_after_the_last_charge()
    {
        var bill = MonthlyBill(new DateOnly(2026, 1, 31));
        var today = new DateOnly(2026, 2, 28);
        Materialize(bill, today);
        bill.Charges.Select(x => x.DueDate).Should().Equal(new DateOnly(2026, 1, 31), new DateOnly(2026, 2, 28), new DateOnly(2026, 3, 31));
        _scheduler.PendingCharges(bill, today).Should().BeEmpty();

        Materialize(bill, new DateOnly(2026, 3, 31));
        bill.Charges.Select(x => (x.Seq, x.DueDate)).Should().Equal((1, new DateOnly(2026, 1, 31)), (2, new DateOnly(2026, 2, 28)), (3, new DateOnly(2026, 3, 31)), (4, new DateOnly(2026, 4, 30)));
    }

    [Fact]
    public void Ended_bills_generate_nothing()
    {
        _scheduler.PendingCharges(new DateOnly(2026, 1, 1), Frequency.Weekly, BillStatus.Ended, 0, new DateOnly(2026, 6, 1)).Should().BeEmpty();
    }

    [Fact]
    public void Generation_is_capped_per_pass()
    {
        _scheduler.PendingCharges(new DateOnly(2000, 1, 1), Frequency.Weekly, BillStatus.Active, 0, new DateOnly(2026, 1, 1)).Should().HaveCount(BillScheduler.MaxChargesPerPass);
    }

    [Fact]
    public void Amount_change_applies_to_future_charges_only()
    {
        var bill = MonthlyBill(new DateOnly(2026, 1, 1), amount: 50m);
        var today = new DateOnly(2026, 2, 10);
        Materialize(bill, today);
        bill.Charges.Should().HaveCount(3);

        _scheduler.ChangeAmount(bill, 65m, today);

        bill.Amount.Should().Be(65m);
        bill.Charges.Select(x => x.Amount).Should().Equal(50m, 50m, 65m);
        Materialize(bill, new DateOnly(2026, 3, 1));
        bill.Charges.Last().Amount.Should().Be(65m, "charges generated after the change use the new amount");
    }

    [Fact]
    public void Amount_change_never_reprices_an_upcoming_charge_below_what_was_prepaid()
    {
        var bill = MonthlyBill(new DateOnly(2026, 1, 1), amount: 50m);
        var today = new DateOnly(2026, 1, 1);
        Materialize(bill, today);
        bill.Charges[1].AmountPaid = 40m;

        _scheduler.ChangeAmount(bill, 30m, today);

        bill.Charges.Select(x => x.Amount).Should().Equal(50m, 40m);
        _state.ChargeRemaining(bill.Charges[1]).Should().Be(0m);
    }

    [Fact]
    public void Amount_change_is_rejected_for_ended_bills()
    {
        var bill = MonthlyBill(new DateOnly(2026, 1, 1));
        bill.Status = BillStatus.Ended;
        var act = () => _scheduler.ChangeAmount(bill, 10m, new DateOnly(2026, 1, 1));
        act.Should().Throw<InvalidOperationException>();
    }

    [Fact]
    public void Ending_keeps_due_charges_drops_unpaid_upcoming_and_closes_prepaid_ones()
    {
        var bill = MonthlyBill(new DateOnly(2026, 1, 1), amount: 50m);
        var today = new DateOnly(2026, 1, 15);
        Materialize(bill, today);
        bill.Charges.Should().HaveCount(2);

        var now = DateTimeOffset.Parse("2026-01-15T12:00:00Z");
        var removed = _scheduler.End(bill, today, now);

        removed.Should().ContainSingle().Which.DueDate.Should().Be(new DateOnly(2026, 2, 1));
        bill.Status.Should().Be(BillStatus.Ended);
        bill.EndedAt.Should().Be(now);
        bill.Charges.Should().ContainSingle().Which.DueDate.Should().Be(new DateOnly(2026, 1, 1));
        _state.Balance(bill, today).Should().Be(50m, "ending doesn't forgive charges that were already due");

        var prepaid = MonthlyBill(new DateOnly(2026, 1, 1), amount: 50m);
        Materialize(prepaid, today);
        prepaid.Charges[1].AmountPaid = 20m;
        _scheduler.End(prepaid, today, now).Should().BeEmpty();
        prepaid.Charges[1].Amount.Should().Be(20m);
        _state.UpcomingAmount(prepaid, today).Should().Be(0m);
    }

    [Fact]
    public void Balance_counts_due_charges_and_fees_but_not_upcoming_charges()
    {
        var bill = BillWithFee();
        var today = new DateOnly(2026, 2, 10);
        _state.Balance(bill, today).Should().Be(105m);
        _state.UpcomingAmount(bill, today).Should().Be(60m);
        _state.Payable(bill).Should().Be(165m);
        _state.OutstandingFees(bill).Should().Be(5m);
        bill.LateFees[0].WaivedAt = DateTimeOffset.Parse("2026-02-10T00:00:00Z");
        _state.Balance(bill, today).Should().Be(100m, "waived fees are no longer owed");
    }

    [Fact]
    public void Allocates_to_late_fees_first_then_charges_oldest_first()
    {
        var bill = BillWithFee();
        var allocator = new BillPaymentAllocator(_state);

        var drafts = allocator.Allocate(bill, 70m);

        drafts.Select(x => (x.Target, x.Amount)).Should().Equal((AllocationTarget.LateFee, 5m), (AllocationTarget.Charge, 50m), (AllocationTarget.Charge, 15m));
        drafts[1].ChargeId.Should().Be(bill.Charges[0].Id);
        drafts[2].ChargeId.Should().Be(bill.Charges[1].Id);
        drafts.Should().OnlyContain(x => x.InstallmentId == null);
        bill.Charges.Select(x => x.AmountPaid).Should().Equal(50m, 15m, 0m);
        bill.LateFees[0].AmountPaid.Should().Be(5m);
    }

    [Fact]
    public void Allows_paying_the_upcoming_charge_early_but_not_more_than_generated()
    {
        var bill = BillWithFee();
        var allocator = new BillPaymentAllocator(_state);

        allocator.Allocate(bill, 165m).Last().Should().Be(new AllocationDraft(AllocationTarget.Charge, null, null, 60m, bill.Charges[2].Id));
        _state.Payable(bill).Should().Be(0m);

        var ex = Assert.Throws<InvalidOperationException>(() => allocator.Allocate(bill, 0.01m));
        ex.Message.Should().Contain("exceeds");
        Assert.Throws<InvalidOperationException>(() => allocator.Allocate(bill, 0m)).Message.Should().Contain("greater than zero");
    }

    [Fact]
    public void Assesses_one_late_fee_per_late_charge_including_on_ended_bills()
    {
        var bill = MonthlyBill(new DateOnly(2026, 1, 1), amount: 100m);
        bill.LateFeeFlat = 5m;
        bill.LateFeePercent = 0.10m;
        bill.LateFeeGraceDays = 3;
        Materialize(bill, new DateOnly(2026, 1, 5));
        var charge = bill.Charges[0];

        _state.ShouldAssessLateFee(bill, charge, new DateOnly(2026, 1, 4)).Should().BeFalse("still within the grace period");
        _state.ShouldAssessLateFee(bill, charge, new DateOnly(2026, 1, 5)).Should().BeTrue();
        _state.ComputeLateFee(bill, charge).Should().Be(15m);

        bill.Status = BillStatus.Ended;
        _state.ShouldAssessLateFee(bill, charge, new DateOnly(2026, 1, 5)).Should().BeTrue();

        bill.LateFees.Add(new BillLateFee { ChargeId = charge.Id, Amount = 15m });
        _state.ShouldAssessLateFee(bill, charge, new DateOnly(2026, 1, 5)).Should().BeFalse("a charge gets one fee, ever");

        var noRules = MonthlyBill(new DateOnly(2026, 1, 1));
        Materialize(noRules, new DateOnly(2026, 1, 5));
        _state.ShouldAssessLateFee(noRules, noRules.Charges[0], new DateOnly(2026, 2, 1)).Should().BeFalse();
    }

    [Fact]
    public void Loan_schedules_support_quarterly_and_yearly()
    {
        var calculator = new ScheduleCalculator();
        calculator.Calculate(400m, true, 0.04m, Frequency.Quarterly, 4, new DateOnly(2026, 1, 31)).Installments.Select(x => x.DueDate)
            .Should().Equal(new DateOnly(2026, 1, 31), new DateOnly(2026, 4, 30), new DateOnly(2026, 7, 31), new DateOnly(2026, 10, 31));
        var yearly = calculator.Calculate(100m, true, 0.10m, Frequency.Yearly, 2, new DateOnly(2026, 6, 1));
        yearly.Installments.Select(x => x.DueDate).Should().Equal(new DateOnly(2026, 6, 1), new DateOnly(2027, 6, 1));
        yearly.Installments[0].InterestDue.Should().Be(10m);
    }

    [Fact]
    public void Terms_summary_describes_the_bill_and_its_late_fee()
    {
        var bill = MonthlyBill(new DateOnly(2026, 11, 1), amount: 45m);
        bill.Title = "Cell phone";
        bill.LateFeeFlat = 2m;
        bill.LateFeeGraceDays = 1;
        var summary = new TermsSummaryBuilder().Build(bill, "Sam");
        summary.Should().Be("Sam pays $45.00 monthly for \"Cell phone\" starting Nov 1, 2026, until the bill is ended. A late fee of $2.00 applies 1 day after a missed due date.");
    }

    private void Materialize(Bill bill, DateOnly today)
    {
        foreach (var pending in _scheduler.PendingCharges(bill, today))
        {
            bill.Charges.Add(new BillCharge { Id = Guid.NewGuid(), BillId = bill.Id, Seq = pending.Seq, DueDate = pending.DueDate, Amount = bill.Amount });
        }
    }

    private static Bill MonthlyBill(DateOnly first, decimal amount = 50m) => new() { Title = "Phone", Amount = amount, Frequency = Frequency.Monthly, FirstDueDate = first, Status = BillStatus.Active };

    private static Bill BillWithFee()
    {
        var bill = MonthlyBill(new DateOnly(2026, 1, 1));
        var first = new BillCharge { Id = Guid.NewGuid(), Seq = 1, DueDate = new DateOnly(2026, 1, 1), Amount = 50m };
        var second = new BillCharge { Id = Guid.NewGuid(), Seq = 2, DueDate = new DateOnly(2026, 2, 1), Amount = 50m };
        var third = new BillCharge { Id = Guid.NewGuid(), Seq = 3, DueDate = new DateOnly(2026, 3, 1), Amount = 60m };
        bill.Charges = [first, second, third];
        bill.LateFees = [new BillLateFee { Id = Guid.NewGuid(), ChargeId = first.Id, Amount = 5m, AssessedAt = DateTimeOffset.Parse("2026-01-05T00:00:00Z") }];
        return bill;
    }
}
