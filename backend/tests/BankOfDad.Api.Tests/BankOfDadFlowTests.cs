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

public sealed class BankOfDadFlowTests : IAsyncLifetime
{
    private readonly PostgreSqlContainer _postgres = new PostgreSqlBuilder("postgres:16-alpine")
        .WithDatabase("bankofdad_tests")
        .WithUsername("bankofdad")
        .WithPassword("bankofdad-dev")
        .Build();

    private TestFactory _factory = null!;
    private HttpClient _client = null!;
    private readonly FakeClock _clock = new(new DateTimeOffset(2026, 10, 17, 12, 0, 0, TimeSpan.Zero));
    private readonly CapturingPushSender _pushes = new();
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) }
    };

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
    public async Task Complete_parent_child_loan_flow_matches_contract()
    {
        var parentAuth = await Post<AuthResponse>("/api/v1/auth/register", new RegisterRequest("dad@example.com", "Password123!", "Dad", "Smith", "America/Los_Angeles"), HttpStatusCode.Created);
        Use(parentAuth.AccessToken);
        var child = await Post<ChildDto>("/api/v1/family/children", new ChildRequest("Sam", "#4F8EF7"), HttpStatusCode.Created);
        var code = await Post<PairingCodeResponse>($"/api/v1/family/children/{child.Id}/pairing-code", new { }, HttpStatusCode.Created);
        Use(null);
        var childAuth = await Post<AuthResponse>("/api/v1/auth/pair", new PairRequest(code.Code, "Sam's iPhone"));
        Use(childAuth.AccessToken);
        (await _client.PostAsJsonAsync("/api/v1/devices", new DeviceRequest("token-1", "sandbox"), Json)).StatusCode.Should().Be(HttpStatusCode.NoContent);

        Use(parentAuth.AccessToken);
        var terms = NewTerms(child.Id, new DateOnly(2026, 11, 1));
        var preview = await Post<SchedulePreview>("/api/v1/loans/preview", terms);
        preview.InstallmentAmount.Should().Be(50.73m);
        var loan = await Post<LoanDetailDto>("/api/v1/loans", terms, HttpStatusCode.Created);
        loan.TotalInterest.Should().Be(4.39m);

        Use(childAuth.AccessToken);
        var childLoans = await Get<List<LoanSummaryDto>>("/api/v1/me/loans");
        childLoans.Should().ContainSingle(x => x.Id == loan.Id);
        var forbidden = await _client.GetAsync("/api/v1/family");
        forbidden.StatusCode.Should().Be(HttpStatusCode.Forbidden);

        var other = await CreateOtherFamilyLoan();
        Use(childAuth.AccessToken);
        var hidden = await _client.GetAsync($"/api/v1/me/loans/{other}");
        hidden.StatusCode.Should().Be(HttpStatusCode.NotFound);

        await Sweep();
        var notifications = await Get<List<NotificationDto>>("/api/v1/notifications");
        notifications.Should().Contain(x => x.Type == NotificationType.Reminder);
        _pushes.Messages.Should().Contain(x => x.Message.Type == NotificationType.Reminder);

        Use(parentAuth.AccessToken);
        var partial = await Post<PaymentDto>($"/api/v1/loans/{loan.Id}/payments", new PaymentRequest(20m, new DateOnly(2026, 10, 17), "Allowance"), HttpStatusCode.Created);
        partial.Allocations.Select(x => x.Target).Should().Equal(AllocationTarget.Interest, AllocationTarget.Principal);
        _pushes.Messages.Should().Contain(x => x.Message.Type == NotificationType.Receipt);

        _clock.UtcNow = new DateTimeOffset(2026, 11, 5, 12, 0, 0, TimeSpan.Zero);
        await Sweep();
        await Sweep();
        var detail = await Get<LoanDetailDto>($"/api/v1/loans/{loan.Id}");
        detail.LateFees.Should().ContainSingle();
        var fee = detail.LateFees.Single();
        fee.Amount.Should().Be(8.07m);
        _pushes.Messages.Count(x => x.Message.Type == NotificationType.LateFee).Should().Be(1);

        var feePayment = await Post<PaymentDto>($"/api/v1/loans/{loan.Id}/payments", new PaymentRequest(1m, new DateOnly(2026, 11, 5), "Fee"), HttpStatusCode.Created);
        feePayment.Allocations.Should().ContainSingle(x => x.Target == AllocationTarget.LateFee);
        detail = await Post<LoanDetailDto>($"/api/v1/loans/{loan.Id}/late-fees/{fee.Id}/waive", new { });
        detail.OutstandingFees.Should().Be(0m);
        detail = await Get<LoanDetailDto>($"/api/v1/loans/{loan.Id}");
        var payoff = detail.Balance;
        var finalPayment = await Post<PaymentDto>($"/api/v1/loans/{loan.Id}/payments", new PaymentRequest(payoff, new DateOnly(2026, 11, 6), "Payoff"), HttpStatusCode.Created);
        finalPayment.Amount.Should().Be(payoff);
        detail = await Get<LoanDetailDto>($"/api/v1/loans/{loan.Id}");
        detail.Status.Should().Be(LoanStatus.PaidOff);
    }

    [Fact]
    public async Task Auth_invite_apple_edit_and_cancel_flows_work()
    {
        var parentAuth = await Post<AuthResponse>("/api/v1/auth/register", new RegisterRequest("mom@example.com", "Password123!", "Mom", "Jones", "America/Los_Angeles"), HttpStatusCode.Created);
        Use(parentAuth.AccessToken);
        var rotated = await Post<AuthResponse>("/api/v1/auth/refresh", new RefreshRequest(parentAuth.RefreshToken));
        Use(null);
        var oldRefresh = await _client.PostAsJsonAsync("/api/v1/auth/refresh", new RefreshRequest(parentAuth.RefreshToken), Json);
        oldRefresh.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
        Use(rotated.AccessToken);

        var invite = await Post<InviteResponse>("/api/v1/family/invites", new InviteRequest("coparent@example.com"), HttpStatusCode.Created);
        Use(null);
        var coparent = await Post<AuthResponse>("/api/v1/auth/accept-invite", new AcceptInviteRequest(invite.InviteCode, "coparent@example.com", "Password123!", "Co Parent"), HttpStatusCode.Created);
        coparent.User.Role.Should().Be(Role.Parent);

        Use(null);
        var apple = await Post<AuthResponse>("/api/v1/auth/apple", new AppleRequest("apple-subject-1", "Apple Dad", "Apple Family", "America/Los_Angeles", null), HttpStatusCode.Created);
        apple.User.Role.Should().Be(Role.Parent);

        Use(rotated.AccessToken);
        var child = await Post<ChildDto>("/api/v1/family/children", new ChildRequest("Alex", null), HttpStatusCode.Created);
        var loan = await Post<LoanDetailDto>("/api/v1/loans", NewTerms(child.Id, new DateOnly(2026, 12, 1)) with { InstallmentCount = 2 }, HttpStatusCode.Created);
        var badEdit = await _client.PatchAsJsonAsync($"/api/v1/loans/{loan.Id}/installments/{loan.Installments[0].Id}", new InstallmentPatchRequest(loan.Installments[1].DueDate), Json);
        badEdit.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        var cancelLoan = await Post<LoanDetailDto>("/api/v1/loans", NewTerms(child.Id, new DateOnly(2026, 12, 15)) with { InterestEnabled = false, AnnualRate = 0m }, HttpStatusCode.Created);
        var cancelled = await Post<LoanDetailDto>($"/api/v1/loans/{cancelLoan.Id}/cancel", new { });
        cancelled.Status.Should().Be(LoanStatus.Cancelled);
    }

    private async Task<Guid> CreateOtherFamilyLoan()
    {
        Use(null);
        var otherAuth = await Post<AuthResponse>("/api/v1/auth/register", new RegisterRequest("other@example.com", "Password123!", "Other", "Other", "America/Los_Angeles"), HttpStatusCode.Created);
        Use(otherAuth.AccessToken);
        var otherChild = await Post<ChildDto>("/api/v1/family/children", new ChildRequest("Other Kid", null), HttpStatusCode.Created);
        var otherLoan = await Post<LoanDetailDto>("/api/v1/loans", NewTerms(otherChild.Id, new DateOnly(2026, 11, 1)), HttpStatusCode.Created);
        return otherLoan.Id;
    }

    private static LoanTermsInput NewTerms(Guid childId, DateOnly firstDueDate) => new(childId, "New bike", 300m, true, 0.05m, Frequency.Monthly, 6, firstDueDate, 5m, 0.10m, 3, true, true);

    private async Task Sweep()
    {
        using var scope = _factory.Services.CreateScope();
        await scope.ServiceProvider.GetRequiredService<LoanSweeper>().SweepAsync();
    }

    private void Use(string? token) => _client.DefaultRequestHeaders.Authorization = token is null ? null : new AuthenticationHeaderValue("Bearer", token);

    private async Task<T> Post<T>(string url, object body, HttpStatusCode expected = HttpStatusCode.OK)
    {
        var response = await _client.PostAsJsonAsync(url, body, Json);
        var errorBody = await response.Content.ReadAsStringAsync();
        var authHeader = string.Join(" | ", response.Headers.WwwAuthenticate.Select(x => x.ToString()));
        response.StatusCode.Should().Be(expected, $"{errorBody} {authHeader}");
        return (await response.Content.ReadFromJsonAsync<T>(Json))!;
    }

    private async Task<T> Get<T>(string url)
    {
        var response = await _client.GetAsync(url);
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<T>(Json))!;
    }

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
                services.AddScoped<IAppleTokenValidator, FakeAppleTokenValidator>();
                services.RemoveAll<IPushSender>();
                services.AddSingleton<IPushSender>(pushes);
            });
        }
    }

    private sealed class FakeClock(DateTimeOffset now) : IClock
    {
        public DateTimeOffset UtcNow { get; set; } = now;
    }

    private sealed class FakeAppleTokenValidator : IAppleTokenValidator
    {
        public Task<AppleUser> ValidateAsync(string identityToken, CancellationToken cancellationToken = default) => Task.FromResult(new AppleUser(identityToken, $"{identityToken}@example.com"));
    }

    private sealed class CapturingPushSender : IPushSender
    {
        public List<(DeviceToken Device, PushMessage Message, int Badge)> Messages { get; } = [];
        public Task SendAsync(DeviceToken deviceToken, PushMessage message, int badge, CancellationToken cancellationToken = default)
        {
            Messages.Add((deviceToken, message, badge));
            return Task.CompletedTask;
        }
    }
}
