namespace BankOfDad.Api.Tests;

using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using BankOfDad.Api.Models;
using BankOfDad.Api.Services;
using BankOfDad.Domain;
using BankOfDad.Domain.Entities;
using BankOfDad.Infrastructure.Data;
using BankOfDad.Infrastructure.Push;
using BankOfDad.Infrastructure.Security;
using BankOfDad.Infrastructure.Time;
using FluentAssertions;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Testcontainers.PostgreSql;

public sealed class BillFlowTests : IAsyncLifetime
{
    // 2026-10-17 05:00 in Los Angeles, so the family-local date is Oct 17.
    private static readonly DateTimeOffset TestNow = new(2026, 10, 17, 12, 0, 0, TimeSpan.Zero);
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) }
    };

    private readonly PostgreSqlContainer _postgres = new PostgreSqlBuilder("postgres:16-alpine")
        .WithDatabase("bankofdad_bill_tests")
        .WithUsername("bankofdad")
        .WithPassword("bankofdad-dev")
        .Build();

    private readonly FakeClock _clock = new(TestNow);
    private readonly CapturingPushSender _pushes = new();
    private TestFactory _factory = null!;
    private HttpClient _client = null!;

    public async Task InitializeAsync()
    {
        await _postgres.StartAsync();
        _factory = new TestFactory(_postgres.GetConnectionString(), _clock, _pushes);
        _client = _factory.CreateClient();
    }

    public async Task DisposeAsync()
    {
        _client.Dispose();
        await _factory.DisposeAsync();
        await _postgres.DisposeAsync();
    }

    [Fact]
    public async Task Parent_creates_edits_pays_and_ends_a_bill_while_the_child_reads_along()
    {
        var family = await CreateFamily("flow");
        Use(family.Kid.AccessToken);
        (await _client.PostAsJsonAsync("/api/v1/devices", new DeviceRequest("kid-token", "sandbox"), Json)).StatusCode.Should().Be(HttpStatusCode.NoContent);

        Use(family.Parent.AccessToken);
        var bill = await Post<BillDetailDto>("/api/v1/bills", NewBill(family.ChildId, new DateOnly(2026, 10, 31)), HttpStatusCode.Created);
        bill.Status.Should().Be(BillStatus.Active);
        bill.Charges.Should().ContainSingle().Which.Should().Match<BillChargeDto>(c => c.DueDate == new DateOnly(2026, 10, 31) && c.Amount == 45m && c.Status == InstallmentStatus.Upcoming);
        bill.Balance.Should().Be(0m, "nothing is due yet");
        bill.UpcomingAmount.Should().Be(45m);
        bill.NextDueDate.Should().Be(new DateOnly(2026, 10, 31));
        bill.TermsSummary.Should().Contain("Sam pays $45.00 monthly for \"Cell phone\"");
        _pushes.Messages.Should().Contain(x => x.Message.Type == NotificationType.BillCreated && x.Message.BillId == bill.Id);

        // The child sees the bill and the reminder, read-only.
        await Sweep();
        Use(family.Kid.AccessToken);
        (await Get<List<BillSummaryDto>>("/api/v1/bills")).Should().ContainSingle(x => x.Id == bill.Id);
        (await Get<BillDetailDto>($"/api/v1/bills/{bill.Id}")).Charges.Should().ContainSingle();
        var notifications = await Get<List<NotificationDto>>("/api/v1/notifications");
        notifications.Should().Contain(x => x.Type == NotificationType.Reminder && x.BillId == bill.Id && x.LoanId == null);
        _pushes.Messages.Should().Contain(x => x.Message.Type == NotificationType.Reminder && x.Message.BillId == bill.Id);

        // A month later: Oct 31 and Nov 30 are past due (beyond the 3-day grace) and Dec 31 is next, all at the original price.
        _clock.UtcNow = new DateTimeOffset(2026, 12, 4, 12, 0, 0, TimeSpan.Zero);
        Use(family.Parent.AccessToken);
        bill = await Get<BillDetailDto>($"/api/v1/bills/{bill.Id}");
        bill.Charges.Select(x => x.DueDate).Should().Equal(new DateOnly(2026, 12, 31), new DateOnly(2026, 11, 30), new DateOnly(2026, 10, 31));
        bill.Balance.Should().Be(90m);
        bill.LateCharges.Should().Be(2);

        // The price goes up: only the charge that isn't due yet changes.
        bill = await Patch<BillDetailDto>($"/api/v1/bills/{bill.Id}", new BillPatchRequest(null, 55m, null, null));
        bill.Amount.Should().Be(55m);
        bill.Charges.Select(x => x.Amount).Should().Equal(55m, 45m, 45m);

        // Late fees are assessed once per late charge and can be waived.
        await Sweep();
        await Sweep();
        bill = await Get<BillDetailDto>($"/api/v1/bills/{bill.Id}");
        bill.LateFees.Should().HaveCount(2);
        bill.LateFees.Select(x => x.Amount).Should().Equal(6.5m, 6.5m);
        bill.OutstandingFees.Should().Be(13m);
        bill.Balance.Should().Be(103m);
        _pushes.Messages.Count(x => x.Message.Type == NotificationType.LateFee && x.Message.BillId == bill.Id).Should().Be(2);
        bill = await Post<BillDetailDto>($"/api/v1/bills/{bill.Id}/late-fees/{bill.LateFees[1].Id}/waive", new { });
        bill.OutstandingFees.Should().Be(6.5m);

        // A payment pays the fee first, then charges oldest first, and sends a receipt.
        var payment = await Post<BillPaymentDto>($"/api/v1/bills/{bill.Id}/payments", new PaymentRequest(60m, new DateOnly(2026, 12, 4), "Allowance"), HttpStatusCode.Created);
        payment.Allocations.Select(x => (x.Target, x.ChargeDueDate, x.Amount)).Should().Equal(
            (AllocationTarget.LateFee, (DateOnly?)null, 6.5m),
            (AllocationTarget.Charge, new DateOnly(2026, 10, 31), 45m),
            (AllocationTarget.Charge, new DateOnly(2026, 11, 30), 8.5m));
        payment.RecordedByName.Should().Be("Dad");
        _pushes.Messages.Should().Contain(x => x.Message.Type == NotificationType.Receipt && x.Message.BillId == bill.Id && x.Message.Body.Contains("You now owe $36.50"));
        bill = await Get<BillDetailDto>($"/api/v1/bills/{bill.Id}");
        bill.Balance.Should().Be(36.5m);
        bill.AmountPaid.Should().Be(60m);
        (await Get<List<BillPaymentDto>>($"/api/v1/bills/{bill.Id}/payments")).Should().ContainSingle(x => x.Id == payment.Id);

        // Paying more than every generated charge is a conflict, but paying the next charge early is fine.
        (await _client.PostAsJsonAsync($"/api/v1/bills/{bill.Id}/payments", new PaymentRequest(91.51m, new DateOnly(2026, 12, 4), null), Json)).StatusCode.Should().Be(HttpStatusCode.Conflict);
        await Post<BillPaymentDto>($"/api/v1/bills/{bill.Id}/payments", new PaymentRequest(91.5m, new DateOnly(2026, 12, 4), "Paid ahead"), HttpStatusCode.Created);

        var dashboard = await Get<DashboardDto>("/api/v1/dashboard");
        dashboard.ActiveBills.Should().Be(1);
        dashboard.TotalOutstanding.Should().Be(0m);

        // Ending stops future charges; nothing new appears later.
        _clock.UtcNow = new DateTimeOffset(2026, 12, 10, 12, 0, 0, TimeSpan.Zero);
        bill = await Post<BillDetailDto>($"/api/v1/bills/{bill.Id}/end", new { });
        bill.Status.Should().Be(BillStatus.Ended);
        bill.EndedAt.Should().NotBeNull();
        bill.Charges.Should().HaveCount(3, "the prepaid Dec 31 charge is closed out, not dropped");
        (await _client.PostAsJsonAsync($"/api/v1/bills/{bill.Id}/end", new { }, Json)).StatusCode.Should().Be(HttpStatusCode.Conflict);
        (await _client.PatchAsJsonAsync($"/api/v1/bills/{bill.Id}", new BillPatchRequest(null, 10m, null, null), Json)).StatusCode.Should().Be(HttpStatusCode.Conflict);
        _clock.UtcNow = new DateTimeOffset(2027, 3, 1, 12, 0, 0, TimeSpan.Zero);
        (await Get<BillDetailDto>($"/api/v1/bills/{bill.Id}")).Charges.Should().HaveCount(3);
        (await Get<List<BillSummaryDto>>("/api/v1/bills?status=ended")).Should().ContainSingle(x => x.Id == bill.Id);
        (await Get<List<BillSummaryDto>>("/api/v1/bills?status=active")).Should().BeEmpty();
    }

    [Fact]
    public async Task Ending_a_bill_drops_its_unpaid_upcoming_charge_but_keeps_what_is_owed()
    {
        var family = await CreateFamily("end");
        Use(family.Parent.AccessToken);
        var bill = await Post<BillDetailDto>("/api/v1/bills", NewBill(family.ChildId, new DateOnly(2026, 10, 17)) with { Frequency = Frequency.Weekly }, HttpStatusCode.Created);
        bill.Charges.Select(x => x.DueDate).Should().Equal(new DateOnly(2026, 10, 24), new DateOnly(2026, 10, 17));
        bill.Balance.Should().Be(45m);

        bill = await Post<BillDetailDto>($"/api/v1/bills/{bill.Id}/end", new { });
        bill.Charges.Should().ContainSingle().Which.DueDate.Should().Be(new DateOnly(2026, 10, 17));
        bill.Balance.Should().Be(45m);
        var payment = await Post<BillPaymentDto>($"/api/v1/bills/{bill.Id}/payments", new PaymentRequest(45m, new DateOnly(2026, 10, 17), null), HttpStatusCode.Created);
        payment.Amount.Should().Be(45m);
        (await Get<BillDetailDto>($"/api/v1/bills/{bill.Id}")).Balance.Should().Be(0m);
    }

    [Theory]
    [InlineData(Frequency.Weekly, "2026-10-31", "2026-11-14", new[] { "2026-10-31", "2026-11-07", "2026-11-14", "2026-11-21" })]
    [InlineData(Frequency.Biweekly, "2026-10-31", "2026-11-28", new[] { "2026-10-31", "2026-11-14", "2026-11-28", "2026-12-12" })]
    [InlineData(Frequency.Monthly, "2027-01-31", "2027-03-31", new[] { "2027-01-31", "2027-02-28", "2027-03-31", "2027-04-30" })]
    [InlineData(Frequency.Quarterly, "2026-10-31", "2027-04-30", new[] { "2026-10-31", "2027-01-31", "2027-04-30", "2027-07-31" })]
    [InlineData(Frequency.Yearly, "2028-02-29", "2029-02-28", new[] { "2028-02-29", "2029-02-28", "2030-02-28" })]
    public async Task Charges_appear_on_schedule_for_every_frequency(Frequency frequency, string first, string later, string[] expected)
    {
        var family = await CreateFamily($"sched-{frequency}");
        Use(family.Parent.AccessToken);
        var bill = await Post<BillDetailDto>("/api/v1/bills", NewBill(family.ChildId, DateOnly.Parse(first)) with { Frequency = frequency }, HttpStatusCode.Created);
        bill.Charges.Should().ContainSingle();

        _clock.UtcNow = new DateTimeOffset(DateOnly.Parse(later).ToDateTime(new TimeOnly(20, 0)), TimeSpan.Zero);
        bill = await Get<BillDetailDto>($"/api/v1/bills/{bill.Id}");
        bill.Charges.Select(x => x.DueDate).Reverse().Should().Equal(expected.Select(DateOnly.Parse));
        bill.Charges.Select(x => x.Seq).Reverse().Should().Equal(Enumerable.Range(1, expected.Length));
    }

    [Fact]
    public async Task Concurrent_requests_generate_each_charge_exactly_once()
    {
        var family = await CreateFamily("race");
        Use(family.Parent.AccessToken);
        var bill = await Post<BillDetailDto>("/api/v1/bills", NewBill(family.ChildId, new DateOnly(2026, 10, 18)) with { Frequency = Frequency.Weekly }, HttpStatusCode.Created);
        _clock.UtcNow = new DateTimeOffset(2027, 1, 1, 20, 0, 0, TimeSpan.Zero);

        var responses = await Task.WhenAll(Enumerable.Range(0, 8).Select(i => i % 2 == 0 ? _client.GetAsync($"/api/v1/bills/{bill.Id}") : _client.GetAsync("/api/v1/dashboard")));
        responses.Should().OnlyContain(x => x.StatusCode == HttpStatusCode.OK);
        await Sweep();

        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<BankOfDadDbContext>();
        var dueDates = await db.BillCharges.Where(x => x.BillId == bill.Id).Select(x => x.DueDate).ToListAsync();
        dueDates.Should().OnlyHaveUniqueItems();
        dueDates.Should().HaveCount(12, "Oct 18 through Dec 27 are due, and Jan 3 is next");
        dueDates.Max().Should().Be(new DateOnly(2027, 1, 3));
    }

    [Fact]
    public async Task Ending_a_bill_during_concurrent_reads_payments_and_edits_leaves_no_upcoming_charge()
    {
        var family = await CreateFamily("end-race");
        Use(family.Parent.AccessToken);
        for (var i = 0; i < 5; i++)
        {
            _clock.UtcNow = TestNow;
            var bill = await Post<BillDetailDto>("/api/v1/bills", NewBill(family.ChildId, new DateOnly(2026, 10, 18)) with { Frequency = Frequency.Weekly, Title = $"Race {i}" }, HttpStatusCode.Created);
            _clock.UtcNow = new DateTimeOffset(2026, 11, 20, 20, 0, 0, TimeSpan.Zero);
            var requests = Enumerable.Range(0, 6).Select(_ => _client.GetAsync($"/api/v1/bills/{bill.Id}"))
                .Append(_client.PostAsJsonAsync($"/api/v1/bills/{bill.Id}/end", new { }, Json))
                .Append(_client.PostAsJsonAsync($"/api/v1/bills/{bill.Id}/payments", new PaymentRequest(45m, new DateOnly(2026, 11, 20), null), Json))
                .Append(_client.PatchAsJsonAsync($"/api/v1/bills/{bill.Id}", new BillPatchRequest(null, 50m, null, null), Json));
            var responses = await Task.WhenAll(requests);
            responses.Take(7).Should().OnlyContain(x => x.StatusCode == HttpStatusCode.OK);
            responses[7].StatusCode.Should().BeOneOf(HttpStatusCode.Created, HttpStatusCode.Conflict);
            responses[8].StatusCode.Should().BeOneOf(HttpStatusCode.OK, HttpStatusCode.Conflict);

            using var scope = _factory.Services.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<BankOfDadDbContext>();
            var dueDates = await db.BillCharges.Where(x => x.BillId == bill.Id).Select(x => x.DueDate).ToListAsync();
            dueDates.Should().NotContain(d => d > new DateOnly(2026, 11, 20), "ending drops the unpaid upcoming charge and stops generation");
            dueDates.Should().HaveCount(5, "Oct 18 through Nov 15 were due before the bill ended");
        }
    }

    [Fact]
    public async Task Children_only_read_their_own_bills_and_parents_only_see_their_family()
    {
        var family = await CreateFamily("authz");
        Use(family.Parent.AccessToken);
        var sibling = await Post<ChildDto>("/api/v1/family/children", new ChildRequest("Riley", null), HttpStatusCode.Created);
        var mine = await Post<BillDetailDto>("/api/v1/bills", NewBill(family.ChildId, new DateOnly(2026, 11, 1)), HttpStatusCode.Created);
        var theirs = await Post<BillDetailDto>("/api/v1/bills", NewBill(sibling.Id, new DateOnly(2026, 11, 1)) with { Title = "Rent" }, HttpStatusCode.Created);
        (await Get<List<BillSummaryDto>>($"/api/v1/bills?childId={sibling.Id}")).Should().ContainSingle(x => x.Id == theirs.Id);

        Use(family.Kid.AccessToken);
        var visible = await Get<List<BillSummaryDto>>($"/api/v1/bills?childId={sibling.Id}");
        visible.Should().ContainSingle().Which.Id.Should().Be(mine.Id);
        (await _client.GetAsync($"/api/v1/bills/{theirs.Id}")).StatusCode.Should().Be(HttpStatusCode.NotFound);
        (await _client.GetAsync($"/api/v1/bills/{theirs.Id}/payments")).StatusCode.Should().Be(HttpStatusCode.NotFound);
        (await _client.GetAsync($"/api/v1/bills/{mine.Id}/payments")).StatusCode.Should().Be(HttpStatusCode.OK);
        (await _client.PostAsJsonAsync("/api/v1/bills", NewBill(family.ChildId, new DateOnly(2026, 11, 1)), Json)).StatusCode.Should().Be(HttpStatusCode.Forbidden);
        (await _client.PatchAsJsonAsync($"/api/v1/bills/{mine.Id}", new BillPatchRequest(null, 1m, null, null), Json)).StatusCode.Should().Be(HttpStatusCode.Forbidden);
        (await _client.PostAsJsonAsync($"/api/v1/bills/{mine.Id}/end", new { }, Json)).StatusCode.Should().Be(HttpStatusCode.Forbidden);
        (await _client.PostAsJsonAsync($"/api/v1/bills/{mine.Id}/payments", new PaymentRequest(1m, new DateOnly(2026, 10, 17), null), Json)).StatusCode.Should().Be(HttpStatusCode.Forbidden);
        (await _client.PostAsJsonAsync($"/api/v1/bills/{mine.Id}/late-fees/{Guid.NewGuid()}/waive", new { }, Json)).StatusCode.Should().Be(HttpStatusCode.Forbidden);

        Use(null);
        (await _client.GetAsync("/api/v1/bills")).StatusCode.Should().Be(HttpStatusCode.Unauthorized);

        var other = await CreateFamily("authz-other");
        Use(other.Parent.AccessToken);
        (await Get<List<BillSummaryDto>>("/api/v1/bills")).Should().BeEmpty();
        (await _client.GetAsync($"/api/v1/bills/{mine.Id}")).StatusCode.Should().Be(HttpStatusCode.NotFound);
        (await _client.PatchAsJsonAsync($"/api/v1/bills/{mine.Id}", new BillPatchRequest("Mine now", null, null, null), Json)).StatusCode.Should().Be(HttpStatusCode.NotFound);
        (await _client.PostAsJsonAsync($"/api/v1/bills/{mine.Id}/payments", new PaymentRequest(1m, new DateOnly(2026, 10, 17), null), Json)).StatusCode.Should().Be(HttpStatusCode.NotFound);
        (await _client.PostAsJsonAsync($"/api/v1/bills/{mine.Id}/end", new { }, Json)).StatusCode.Should().Be(HttpStatusCode.NotFound);
        (await _client.PostAsJsonAsync("/api/v1/bills", NewBill(family.ChildId, new DateOnly(2026, 11, 1)), Json)).StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Rejects_invalid_bills()
    {
        var family = await CreateFamily("invalid");
        Use(family.Parent.AccessToken);
        var valid = NewBill(family.ChildId, new DateOnly(2026, 10, 17));
        var invalid = new[]
        {
            valid with { Amount = 0m },
            valid with { Amount = 1_000_000.01m },
            valid with { Title = " " },
            valid with { Title = new string('x', 101) },
            valid with { FirstDueDate = new DateOnly(2026, 10, 16) },
            valid with { LateFeeFlat = -1m },
            valid with { LateFeePercent = 1.5m },
            valid with { LateFeeGraceDays = 61 },
            valid with { Frequency = (Frequency)42 },
        };
        foreach (var input in invalid)
        {
            var response = await _client.PostAsJsonAsync("/api/v1/bills", input, Json);
            response.StatusCode.Should().Be(HttpStatusCode.BadRequest, JsonSerializer.Serialize(input, Json));
        }

        var bill = await Post<BillDetailDto>("/api/v1/bills", valid, HttpStatusCode.Created);
        (await _client.PatchAsJsonAsync($"/api/v1/bills/{bill.Id}", new BillPatchRequest(null, 0m, null, null), Json)).StatusCode.Should().Be(HttpStatusCode.BadRequest);
        (await _client.PostAsJsonAsync($"/api/v1/bills/{bill.Id}/payments", new PaymentRequest(0m, new DateOnly(2026, 10, 17), null), Json)).StatusCode.Should().Be(HttpStatusCode.BadRequest);
        (await _client.GetAsync("/api/v1/bills?status=bogus")).StatusCode.Should().Be(HttpStatusCode.BadRequest);
        (await _client.PostAsJsonAsync($"/api/v1/bills/{bill.Id}/late-fees/{Guid.NewGuid()}/waive", new { }, Json)).StatusCode.Should().Be(HttpStatusCode.NotFound);

        var edited = await Patch<BillDetailDto>($"/api/v1/bills/{bill.Id}", new BillPatchRequest("  Car insurance  ", null, false, false));
        edited.Title.Should().Be("Car insurance");
        edited.SendReminders.Should().BeFalse();
        edited.SendReceipts.Should().BeFalse();
    }

    [Fact]
    public async Task Disabled_reminders_and_receipts_stay_quiet()
    {
        var family = await CreateFamily("quiet");
        Use(family.Parent.AccessToken);
        var bill = await Post<BillDetailDto>("/api/v1/bills", NewBill(family.ChildId, new DateOnly(2026, 10, 20)) with { SendReminders = false, SendReceipts = false }, HttpStatusCode.Created);
        await Sweep();
        _clock.UtcNow = new DateTimeOffset(2026, 10, 20, 20, 0, 0, TimeSpan.Zero);
        await Post<BillPaymentDto>($"/api/v1/bills/{bill.Id}/payments", new PaymentRequest(45m, new DateOnly(2026, 10, 20), null), HttpStatusCode.Created);

        Use(family.Kid.AccessToken);
        var notifications = await Get<List<NotificationDto>>("/api/v1/notifications");
        notifications.Should().ContainSingle().Which.Type.Should().Be(NotificationType.BillCreated);
    }

    [Fact]
    public async Task Dashboard_counts_bills_in_the_total_owed()
    {
        var family = await CreateFamily("dash");
        Use(family.Parent.AccessToken);
        var loan = await Post<LoanDetailDto>("/api/v1/loans", new LoanTermsInput(family.ChildId, "Bike", 100m, false, 0m, Frequency.Monthly, 2, new DateOnly(2026, 11, 1), null, null, 0, false, false), HttpStatusCode.Created);
        var bill = await Post<BillDetailDto>("/api/v1/bills", NewBill(family.ChildId, new DateOnly(2026, 10, 17)), HttpStatusCode.Created);

        var dashboard = await Get<DashboardDto>("/api/v1/dashboard");
        dashboard.TotalOutstanding.Should().Be(145m);
        dashboard.ActiveLoans.Should().Be(1);
        dashboard.ActiveBills.Should().Be(1);
        dashboard.Upcoming.Should().ContainSingle(x => x.LoanId == loan.Id);
        // Nov 17 is 31 days out, beyond the dashboard's 30-day window.
        dashboard.UpcomingBills.Should().Equal(new UpcomingBillDto(bill.Id, "Cell phone", "Sam", new DateOnly(2026, 10, 17), 45m));

        _clock.UtcNow = new DateTimeOffset(2026, 10, 30, 20, 0, 0, TimeSpan.Zero);
        (await Get<DashboardDto>("/api/v1/dashboard")).LateBillCharges.Should().Be(1);
    }

    private static BillInput NewBill(Guid childId, DateOnly firstDueDate) => new(childId, "Cell phone", 45m, Frequency.Monthly, firstDueDate, 2m, 0.10m, 3, true, true);

    private async Task<TestFamily> CreateFamily(string prefix)
    {
        Use(null);
        var parent = await Post<AuthResponse>("/api/v1/auth/register", new RegisterRequest($"{prefix}@example.com", "Password123!", "Dad", prefix, "America/Los_Angeles"), HttpStatusCode.Created);
        Use(parent.AccessToken);
        var child = await Post<ChildDto>("/api/v1/family/children", new ChildRequest("Sam", null), HttpStatusCode.Created);
        var code = await Post<PairingCodeResponse>($"/api/v1/family/children/{child.Id}/pairing-code", new { }, HttpStatusCode.Created);
        Use(null);
        var kid = await Post<AuthResponse>("/api/v1/auth/pair", new PairRequest(code.Code, "Sam's iPhone"));
        Use(parent.AccessToken);
        return new TestFamily(parent, kid, child.Id);
    }

    private async Task Sweep()
    {
        using var scope = _factory.Services.CreateScope();
        await scope.ServiceProvider.GetRequiredService<LoanSweeper>().SweepAsync();
    }

    private void Use(string? token) => _client.DefaultRequestHeaders.Authorization = token is null ? null : new AuthenticationHeaderValue("Bearer", token);

    private async Task<T> Post<T>(string url, object body, HttpStatusCode expected = HttpStatusCode.OK)
    {
        var response = await _client.PostAsJsonAsync(url, body, Json);
        response.StatusCode.Should().Be(expected, await response.Content.ReadAsStringAsync());
        return (await response.Content.ReadFromJsonAsync<T>(Json))!;
    }

    private async Task<T> Patch<T>(string url, object body)
    {
        var response = await _client.PatchAsJsonAsync(url, body, Json);
        response.StatusCode.Should().Be(HttpStatusCode.OK, await response.Content.ReadAsStringAsync());
        return (await response.Content.ReadFromJsonAsync<T>(Json))!;
    }

    private async Task<T> Get<T>(string url)
    {
        var response = await _client.GetAsync(url);
        response.StatusCode.Should().Be(HttpStatusCode.OK, await response.Content.ReadAsStringAsync());
        return (await response.Content.ReadFromJsonAsync<T>(Json))!;
    }

    private sealed record TestFamily(AuthResponse Parent, AuthResponse Kid, Guid ChildId);

    private sealed class TestFactory(string connectionString, FakeClock clock, CapturingPushSender pushes) : WebApplicationFactory<Program>
    {
        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            builder.UseEnvironment("Testing");
            builder.ConfigureAppConfiguration(config => config.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ConnectionStrings:Default"] = connectionString,
                ["Apple:ClientId"] = "com.example.bankofdad"
            }));
            builder.ConfigureServices(services =>
            {
                services.RemoveAll<DbContextOptions<BankOfDadDbContext>>();
                services.AddDbContext<BankOfDadDbContext>(options => options.UseNpgsql(connectionString));
                services.RemoveAll<IClock>();
                services.AddSingleton<IClock>(clock);
                services.RemoveAll<IAppleTokenValidator>();
                services.AddScoped<IAppleTokenValidator, NoAppleTokenValidator>();
                services.RemoveAll<IPushSender>();
                services.AddSingleton<IPushSender>(pushes);
            });
        }
    }

    private sealed class FakeClock(DateTimeOffset now) : IClock
    {
        public DateTimeOffset UtcNow { get; set; } = now;
    }

    private sealed class NoAppleTokenValidator : IAppleTokenValidator
    {
        public Task<AppleUser> ValidateAsync(string identityToken, CancellationToken cancellationToken = default) => throw new InvalidOperationException("Not used.");
    }

    private sealed class CapturingPushSender : IPushSender
    {
        private readonly object _gate = new();
        private readonly List<(DeviceToken Device, PushMessage Message)> _messages = [];
        public IReadOnlyList<(DeviceToken Device, PushMessage Message)> Messages { get { lock (_gate) return _messages.ToList(); } }
        public Task SendAsync(DeviceToken deviceToken, PushMessage message, int badge, CancellationToken cancellationToken = default)
        {
            lock (_gate) _messages.Add((deviceToken, message));
            return Task.CompletedTask;
        }
    }
}
