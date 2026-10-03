namespace BankOfDad.Api.Tests;

using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using BankOfDad.Api.Models;
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

public sealed class TestHooksTests : IAsyncLifetime
{
    private static readonly DateTimeOffset TestNow = new(2026, 10, 17, 12, 0, 0, TimeSpan.Zero);
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) }
    };

    private readonly PostgreSqlContainer _postgres = new PostgreSqlBuilder("postgres:16-alpine")
        .WithDatabase("bankofdad_hook_tests")
        .WithUsername("bankofdad")
        .WithPassword("bankofdad-dev")
        .Build();

    private readonly FakeClock _clock = new(TestNow);
    private readonly List<WebApplicationFactory<Program>> _factories = [];

    public Task InitializeAsync() => _postgres.StartAsync();

    public async Task DisposeAsync()
    {
        foreach (var factory in _factories) await factory.DisposeAsync();
        await _postgres.DisposeAsync();
    }

    [Theory]
    [InlineData("Development", null)]
    [InlineData("Development", "false")]
    [InlineData("Testing", "true")]
    [InlineData("Production", "true")]
    public async Task Hooks_are_not_mapped_unless_Development_and_flag_enabled(string environment, string? flag)
    {
        var client = CreateClient(environment, flag);
        var (parent, _, loan) = await SeedFamilyWithLoan(client, "off");

        Use(client, parent.AccessToken);
        (await client.PostAsJsonAsync($"/api/v1/testing/loans/{loan.Id}/backdate", new { days = 10 }, Json)).StatusCode.Should().Be(HttpStatusCode.NotFound);
        (await client.PostAsync("/api/v1/testing/sweep", null)).StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Backdate_and_sweep_make_installments_late_and_assess_fees_for_the_callers_family_only()
    {
        var client = CreateClient("Development", "true");
        var (parent, childAuth, loan) = await SeedFamilyWithLoan(client, "on");
        var (otherParent, _, otherLoan) = await SeedFamilyWithLoan(client, "other");

        Use(client, parent.AccessToken);
        var backdated = await Post<LoanDetailDto>(client, $"/api/v1/testing/loans/{loan.Id}/backdate", new { days = 10 });
        backdated.FirstDueDate.Should().Be(loan.FirstDueDate.AddDays(-10));
        backdated.Installments.Select(x => x.DueDate).Should().Equal(loan.Installments.Select(x => x.DueDate.AddDays(-10)));
        backdated.Installments[0].Status.Should().Be(InstallmentStatus.Late);
        backdated.LateInstallments.Should().Be(1);
        backdated.LateFees.Should().BeEmpty();

        Use(client, otherParent.AccessToken);
        await Post<LoanDetailDto>(client, $"/api/v1/testing/loans/{otherLoan.Id}/backdate", new { days = 10 });

        Use(client, parent.AccessToken);
        (await client.PostAsync("/api/v1/testing/sweep", null)).StatusCode.Should().Be(HttpStatusCode.NoContent);
        var detail = await Get<LoanDetailDto>(client, $"/api/v1/loans/{loan.Id}");
        detail.LateFees.Should().ContainSingle().Which.InstallmentSeq.Should().Be(1);

        Use(client, childAuth.AccessToken);
        var notifications = await Get<List<NotificationDto>>(client, "/api/v1/notifications");
        notifications.Should().Contain(x => x.Type == NotificationType.LateFee && x.LoanId == loan.Id);

        Use(client, otherParent.AccessToken);
        var untouched = await Get<LoanDetailDto>(client, $"/api/v1/loans/{otherLoan.Id}");
        untouched.LateFees.Should().BeEmpty("the sweep hook only processes the caller's family");
    }

    [Fact]
    public async Task Sweep_sends_reminders_for_installments_due_within_15_days()
    {
        var client = CreateClient("Development", "true");
        var (parent, childAuth, loan) = await SeedFamilyWithLoan(client, "remind");

        Use(client, childAuth.AccessToken);
        (await Get<List<NotificationDto>>(client, "/api/v1/notifications")).Should().NotContain(x => x.Type == NotificationType.Reminder);

        Use(client, parent.AccessToken);
        (await client.PostAsync("/api/v1/testing/sweep", null)).StatusCode.Should().Be(HttpStatusCode.NoContent);

        Use(client, childAuth.AccessToken);
        (await Get<List<NotificationDto>>(client, "/api/v1/notifications")).Should().ContainSingle(x => x.Type == NotificationType.Reminder && x.LoanId == loan.Id);
    }

    [Fact]
    public async Task Hooks_require_a_parent_of_the_loans_family_and_validate_input()
    {
        var client = CreateClient("Development", "true");
        var (parent, childAuth, loan) = await SeedFamilyWithLoan(client, "guard");
        var (otherParent, _, _) = await SeedFamilyWithLoan(client, "guard-other");

        Use(client, null);
        (await client.PostAsync("/api/v1/testing/sweep", null)).StatusCode.Should().Be(HttpStatusCode.Unauthorized);

        Use(client, childAuth.AccessToken);
        (await client.PostAsJsonAsync($"/api/v1/testing/loans/{loan.Id}/backdate", new { days = 10 }, Json)).StatusCode.Should().Be(HttpStatusCode.Forbidden);
        (await client.PostAsync("/api/v1/testing/sweep", null)).StatusCode.Should().Be(HttpStatusCode.Forbidden);

        Use(client, otherParent.AccessToken);
        (await client.PostAsJsonAsync($"/api/v1/testing/loans/{loan.Id}/backdate", new { days = 10 }, Json)).StatusCode.Should().Be(HttpStatusCode.NotFound);

        Use(client, parent.AccessToken);
        (await client.PostAsJsonAsync($"/api/v1/testing/loans/{loan.Id}/backdate", new { days = 0 }, Json)).StatusCode.Should().Be(HttpStatusCode.BadRequest);
        var unchanged = await Get<LoanDetailDto>(client, $"/api/v1/loans/{loan.Id}");
        unchanged.FirstDueDate.Should().Be(loan.FirstDueDate);
    }

    private HttpClient CreateClient(string environment, string? hooksEnabled)
    {
        var factory = new HookFactory(_postgres.GetConnectionString(), _clock, environment, hooksEnabled);
        _factories.Add(factory);
        return factory.CreateClient();
    }

    private static async Task<(AuthResponse Parent, AuthResponse Child, LoanDetailDto Loan)> SeedFamilyWithLoan(HttpClient client, string tag)
    {
        Use(client, null);
        var email = $"{tag}-{Guid.NewGuid():N}@example.com";
        var parent = await Post<AuthResponse>(client, "/api/v1/auth/register", new RegisterRequest(email, "Password123!", "Dad", "Hooks", "UTC"), HttpStatusCode.Created);
        Use(client, parent.AccessToken);
        var child = await Post<ChildDto>(client, "/api/v1/family/children", new ChildRequest("Sam", null), HttpStatusCode.Created);
        var loan = await Post<LoanDetailDto>(client, "/api/v1/loans", new LoanTermsInput(child.Id, "Bike", 300m, false, 0m, Frequency.Monthly, 3, DateOnly.FromDateTime(TestNow.UtcDateTime).AddDays(3), 5m, null, 3, true, true), HttpStatusCode.Created);
        var code = await Post<PairingCodeResponse>(client, $"/api/v1/family/children/{child.Id}/pairing-code", new { }, HttpStatusCode.Created);
        Use(client, null);
        var childAuth = await Post<AuthResponse>(client, "/api/v1/auth/pair", new PairRequest(code.Code, "Sam's iPhone"));
        return (parent, childAuth, loan);
    }

    private static void Use(HttpClient client, string? token) => client.DefaultRequestHeaders.Authorization = token is null ? null : new AuthenticationHeaderValue("Bearer", token);

    private static async Task<T> Post<T>(HttpClient client, string url, object body, HttpStatusCode expected = HttpStatusCode.OK)
    {
        var response = await client.PostAsJsonAsync(url, body, Json);
        response.StatusCode.Should().Be(expected, await response.Content.ReadAsStringAsync());
        return (await response.Content.ReadFromJsonAsync<T>(Json))!;
    }

    private static async Task<T> Get<T>(HttpClient client, string url)
    {
        var response = await client.GetAsync(url);
        response.StatusCode.Should().Be(HttpStatusCode.OK, await response.Content.ReadAsStringAsync());
        return (await response.Content.ReadFromJsonAsync<T>(Json))!;
    }

    private sealed class HookFactory(string connectionString, FakeClock clock, string environment, string? hooksEnabled) : WebApplicationFactory<Program>
    {
        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            builder.UseEnvironment(environment);
            // Program.cs reads the signing key while building, so it must be supplied as a host setting.
            builder.UseSetting("Jwt:SigningKey", "hook-tests-signing-key-0123456789abcdef0123456789");
            builder.ConfigureAppConfiguration(config => config.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ConnectionStrings:Default"] = connectionString,
                ["TestHooks:Enabled"] = hooksEnabled
            }));
            builder.ConfigureServices(services =>
            {
                services.RemoveAll<DbContextOptions<BankOfDadDbContext>>();
                services.AddDbContext<BankOfDadDbContext>(options => options.UseNpgsql(connectionString));
                services.RemoveAll<IClock>();
                services.AddSingleton<IClock>(clock);
                services.RemoveAll<IPushSender>();
                services.AddSingleton<IPushSender, NoopPushSender>();
            });
        }
    }

    private sealed class FakeClock(DateTimeOffset now) : IClock
    {
        public DateTimeOffset UtcNow { get; } = now;
    }

    private sealed class NoopPushSender : IPushSender
    {
        public Task SendAsync(DeviceToken deviceToken, PushMessage message, int badge, CancellationToken cancellationToken = default) => Task.CompletedTask;
    }
}
