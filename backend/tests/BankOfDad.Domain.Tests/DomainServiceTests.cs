namespace BankOfDad.Domain.Tests;

using BankOfDad.Domain;
using BankOfDad.Domain.Entities;
using BankOfDad.Domain.Services;
using FluentAssertions;

public sealed class DomainServiceTests
{
    private readonly ScheduleCalculator _calculator = new();
    private readonly LoanStateService _state = new();

    [Fact]
    public void Amortizes_contract_example_by_rules()
    {
        var result = _calculator.Calculate(300m, true, 0.05m, Frequency.Monthly, 6, new DateOnly(2026, 11, 1));
        result.InstallmentAmount.Should().Be(50.73m);
        result.Installments[0].InterestDue.Should().Be(1.25m);
        result.Installments[0].PrincipalDue.Should().Be(49.48m);
        result.TotalInterest.Should().Be(4.39m);
        result.TotalRepayable.Should().Be(304.39m);
    }

    [Fact]
    public void Terms_summary_keeps_fractional_percentages()
    {
        var loan = new Loan
        {
            Title = "New bike", Principal = 300m, InterestEnabled = true, AnnualRate = 0.055m, Frequency = Frequency.Monthly,
            InstallmentCount = 6, FirstDueDate = new DateOnly(2026, 11, 1), InstallmentAmount = 50.73m,
            LateFeeFlat = 5m, LateFeePercent = 0.125m, LateFeeGraceDays = 3,
        };
        var summary = new TermsSummaryBuilder().Build(loan, "Sam");
        summary.Should().Contain("at 5.5% APR");
        summary.Should().Contain("$5.00 + 12.5% of the missed payment applies 3 days after a missed due date.");
    }

    [Fact]
    public void Splits_zero_interest_with_rounding_absorbed_by_final_installment()
    {
        var result = _calculator.Calculate(100m, false, 0m, Frequency.Monthly, 3, new DateOnly(2026, 1, 1));
        result.Installments.Select(x => x.PrincipalDue).Should().Equal(33.33m, 33.33m, 33.34m);
    }

    [Fact]
    public void Calculates_due_dates_for_supported_frequencies()
    {
        _calculator.Calculate(30m, false, 0m, Frequency.Weekly, 3, new DateOnly(2026, 1, 31)).Installments.Select(x => x.DueDate).Should().Equal(new DateOnly(2026, 1, 31), new DateOnly(2026, 2, 7), new DateOnly(2026, 2, 14));
        _calculator.Calculate(30m, false, 0m, Frequency.Biweekly, 3, new DateOnly(2026, 1, 31)).Installments.Select(x => x.DueDate).Should().Equal(new DateOnly(2026, 1, 31), new DateOnly(2026, 2, 14), new DateOnly(2026, 2, 28));
        _calculator.Calculate(30m, false, 0m, Frequency.Monthly, 3, new DateOnly(2026, 1, 31)).Installments.Select(x => x.DueDate).Should().Equal(new DateOnly(2026, 1, 31), new DateOnly(2026, 2, 28), new DateOnly(2026, 3, 31));
    }

    [Fact]
    public void Computes_status_boundaries_with_grace_days()
    {
        var installment = new Installment { DueDate = new DateOnly(2026, 1, 10), PrincipalDue = 10m };
        _state.Status(installment, new DateOnly(2026, 1, 9), 3).Should().Be(InstallmentStatus.Upcoming);
        _state.Status(installment, new DateOnly(2026, 1, 10), 3).Should().Be(InstallmentStatus.Due);
        _state.Status(installment, new DateOnly(2026, 1, 13), 3).Should().Be(InstallmentStatus.Due);
        _state.Status(installment, new DateOnly(2026, 1, 14), 3).Should().Be(InstallmentStatus.Late);
        installment.PrincipalPaid = 10m;
        _state.Status(installment, new DateOnly(2026, 1, 14), 3).Should().Be(InstallmentStatus.Paid);
    }

    [Theory]
    [InlineData(5, 0.10, 15)]
    [InlineData(5, 0, 5)]
    [InlineData(0, 0.10, 10)]
    [InlineData(0, 0, 0)]
    public void Computes_late_fees(decimal flat, decimal percent, decimal expected)
    {
        var loan = new Loan { LateFeeFlat = flat, LateFeePercent = percent, LateFeeGraceDays = 0 };
        var installment = new Installment { DueDate = new DateOnly(2026, 1, 1), PrincipalDue = 100m };
        loan.Installments.Add(installment);
        _state.ComputeLateFee(loan, installment).Should().Be(expected);
        _state.ShouldAssessLateFee(loan, installment, new DateOnly(2026, 1, 2)).Should().Be(expected > 0);
    }

    [Fact]
    public void Allocates_payment_to_fees_interest_and_principal_in_order()
    {
        var loan = TestLoan();
        var allocator = new PaymentAllocator(_state);
        var allocations = allocator.Allocate(loan, 12m);
        allocations.Select(x => (x.Target, x.Amount)).Should().Equal((AllocationTarget.LateFee, 5m), (AllocationTarget.Interest, 2m), (AllocationTarget.Principal, 5m));
        _state.Balance(loan).Should().Be(100m);
    }

    [Fact]
    public void Supports_partial_extra_payments_and_rejects_overpayment()
    {
        var loan = TestLoan();
        var allocator = new PaymentAllocator(_state);
        allocator.Allocate(loan, 57m);
        _state.Balance(loan).Should().Be(55m);
        allocator.Allocate(loan, 55m);
        _state.IsPaidOff(loan).Should().BeTrue();
        var ex = Assert.Throws<InvalidOperationException>(() => allocator.Allocate(loan, 0.01m));
        ex.Message.Should().Contain("exceeds");
    }

    private static Loan TestLoan()
    {
        var first = new Installment { Id = Guid.NewGuid(), Seq = 1, DueDate = new DateOnly(2026, 1, 1), PrincipalDue = 50m, InterestDue = 2m };
        var second = new Installment { Id = Guid.NewGuid(), Seq = 2, DueDate = new DateOnly(2026, 2, 1), PrincipalDue = 55m };
        var fee = new LateFee { Id = Guid.NewGuid(), InstallmentId = first.Id, Amount = 5m, AssessedAt = DateTimeOffset.Parse("2026-01-05T00:00:00Z") };
        var loan = new Loan { Status = LoanStatus.Active, Installments = [first, second], LateFees = [fee] };
        return loan;
    }
}
