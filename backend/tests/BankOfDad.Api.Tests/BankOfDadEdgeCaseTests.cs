namespace BankOfDad.Api.Tests;

using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
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

public sealed class BankOfDadEdgeCaseTests : IAsyncLifetime
{
    private static readonly DateTimeOffset TestNow = new(2026, 10, 17, 12, 0, 0, TimeSpan.Zero);
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) }
    };

    private readonly PostgreSqlContainer _postgres = new PostgreSqlBuilder("postgres:16-alpine")
        .WithDatabase("bankofdad_edge_tests")
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
    public async Task CrossFamilyAccess_ForeignParent_GetsNotFoundAndLoanListsDoNotLeak()
    {
        ResetClock();
        var familyA = await CreateFamily("cross-a", childCount: 1);
        var familyALoan = await CreateLoan(familyA.Parent, familyA.Children[0].Id);
        var familyB = await CreateFamily("cross-b", childCount: 1);
        var familyBLoan = await CreateLoan(familyB.Parent, familyB.Children[0].Id);

        Use(familyB.Parent.AccessToken);
        (await _client.GetAsync($"/api/v1/loans/{familyALoan.Id}")).StatusCode.Should().Be(HttpStatusCode.NotFound);
        (await _client.GetAsync($"/api/v1/loans/{familyALoan.Id}/payments")).StatusCode.Should().Be(HttpStatusCode.NotFound);
        (await _client.PostAsJsonAsync($"/api/v1/loans/{familyALoan.Id}/payments", new PaymentRequest(1m, Today(), "foreign"), Json)).StatusCode.Should().Be(HttpStatusCode.NotFound);
        (await _client.PostAsJsonAsync($"/api/v1/family/children/{familyA.Children[0].Id}/pairing-code", new { }, Json)).StatusCode.Should().Be(HttpStatusCode.NotFound);
        (await _client.PatchAsJsonAsync($"/api/v1/family/children/{familyA.Children[0].Id}", new ChildPatchRequest("Nope", null), Json)).StatusCode.Should().Be(HttpStatusCode.NotFound);

        var visibleLoans = await Get<List<LoanSummaryDto>>("/api/v1/loans");
        visibleLoans.Should().ContainSingle(x => x.Id == familyBLoan.Id);
        visibleLoans.Should().NotContain(x => x.Id == familyALoan.Id);
    }

    [Fact]
    public async Task KidAccessLimits_PairedKidSeesOwnLoansOnlyAndParentEndpointsAreForbidden()
    {
        ResetClock();
        var family = await CreateFamily("kid-limits", childCount: 2);
        var ownLoan = await CreateLoan(family.Parent, family.Children[0].Id);
        var siblingLoan = await CreateLoan(family.Parent, family.Children[1].Id);
        var kidAuth = await PairChild(family.Parent, family.Children[0].Id, "kid phone");

        Use(kidAuth.AccessToken);
        var loans = await Get<List<LoanSummaryDto>>("/api/v1/me/loans");
        loans.Should().ContainSingle(x => x.Id == ownLoan.Id);
        loans.Should().NotContain(x => x.Id == siblingLoan.Id);
        (await Get<LoanDetailDto>($"/api/v1/me/loans/{ownLoan.Id}")).Id.Should().Be(ownLoan.Id);
        (await _client.GetAsync($"/api/v1/me/loans/{siblingLoan.Id}")).StatusCode.Should().Be(HttpStatusCode.NotFound);

        (await _client.PostAsJsonAsync("/api/v1/loans", NewTerms(family.Children[0].Id), Json)).StatusCode.Should().Be(HttpStatusCode.Forbidden);
        (await _client.PostAsJsonAsync($"/api/v1/loans/{ownLoan.Id}/payments", new PaymentRequest(1m, Today(), null), Json)).StatusCode.Should().Be(HttpStatusCode.Forbidden);
        (await _client.GetAsync("/api/v1/family")).StatusCode.Should().Be(HttpStatusCode.Forbidden);
        (await _client.PostAsJsonAsync("/api/v1/family/children", new ChildRequest("Sibling", null), Json)).StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }

    [Fact]
    public async Task Payments_InvalidAmountsFullPayoffAndInactiveLoans_FollowContract()
    {
        ResetClock();
        var family = await CreateFamily("payments", childCount: 1);
        var zeroLoan = await CreateLoan(family.Parent, family.Children[0].Id, NewTerms(family.Children[0].Id) with { Principal = 100m, InterestEnabled = false, AnnualRate = 0m, InstallmentCount = 1 });
        var zero = await _client.PostAsJsonAsync($"/api/v1/loans/{zeroLoan.Id}/payments", new PaymentRequest(0m, Today(), "zero"), Json);
        await AssertProblem(zero, HttpStatusCode.BadRequest);

        var tooLarge = await _client.PostAsJsonAsync($"/api/v1/loans/{zeroLoan.Id}/payments", new PaymentRequest(zeroLoan.Balance + 0.01m, Today(), "too much"), Json);
        tooLarge.StatusCode.Should().Be(HttpStatusCode.Conflict);

        var payoffLoan = await CreateLoan(family.Parent, family.Children[0].Id, NewTerms(family.Children[0].Id) with { Principal = 75m, InterestEnabled = false, AnnualRate = 0m, InstallmentCount = 1 });
        var payoff = await Post<PaymentDto>($"/api/v1/loans/{payoffLoan.Id}/payments", new PaymentRequest(payoffLoan.Balance, Today(), "payoff"), HttpStatusCode.Created);
        payoff.Amount.Should().Be(payoffLoan.Balance);
        var paid = await Get<LoanDetailDto>($"/api/v1/loans/{payoffLoan.Id}");
        paid.Status.Should().Be(LoanStatus.PaidOff);
        (await _client.PostAsJsonAsync($"/api/v1/loans/{payoffLoan.Id}/payments", new PaymentRequest(1m, Today(), "after payoff"), Json)).StatusCode.Should().Be(HttpStatusCode.Conflict);

        var cancelledLoan = await CreateLoan(family.Parent, family.Children[0].Id, NewTerms(family.Children[0].Id) with { Principal = 50m, InterestEnabled = false, AnnualRate = 0m, InstallmentCount = 1 });
        await Post<LoanDetailDto>($"/api/v1/loans/{cancelledLoan.Id}/cancel", new { });
        (await _client.PostAsJsonAsync($"/api/v1/loans/{cancelledLoan.Id}/payments", new PaymentRequest(1m, Today(), "cancelled"), Json)).StatusCode.Should().Be(HttpStatusCode.Conflict);
    }

    [Fact]
    public async Task Cancel_NonActiveLoan_ReturnsConflict()
    {
        ResetClock();
        var family = await CreateFamily("cancel", childCount: 1);
        var cancelledLoan = await CreateLoan(family.Parent, family.Children[0].Id);

        var cancelled = await Post<LoanDetailDto>($"/api/v1/loans/{cancelledLoan.Id}/cancel", new { });
        cancelled.Status.Should().Be(LoanStatus.Cancelled);
        (await _client.PostAsJsonAsync($"/api/v1/loans/{cancelledLoan.Id}/cancel", new { }, Json)).StatusCode.Should().Be(HttpStatusCode.Conflict);

        var paidLoan = await CreateLoan(family.Parent, family.Children[0].Id, NewTerms(family.Children[0].Id) with { Principal = 25m, InterestEnabled = false, AnnualRate = 0m, InstallmentCount = 1 });
        await Post<PaymentDto>($"/api/v1/loans/{paidLoan.Id}/payments", new PaymentRequest(paidLoan.Balance, Today(), "payoff"), HttpStatusCode.Created);
        (await _client.PostAsJsonAsync($"/api/v1/loans/{paidLoan.Id}/cancel", new { }, Json)).StatusCode.Should().Be(HttpStatusCode.Conflict);
    }

    [Fact]
    public async Task RevokeKidDevices_RevokesRefreshTokenAndReportsZeroPairedDevices()
    {
        ResetClock();
        var family = await CreateFamily("revoke", childCount: 1);
        var kidAuth = await PairChild(family.Parent, family.Children[0].Id, "kid phone");

        Use(family.Parent.AccessToken);
        var before = await Get<FamilyDto>("/api/v1/family");
        before.Children.Single(x => x.Id == family.Children[0].Id).PairedDeviceCount.Should().Be(1);

        var revoke = await _client.DeleteAsync($"/api/v1/family/children/{family.Children[0].Id}/devices");
        revoke.StatusCode.Should().Be(HttpStatusCode.NoContent);

        Use(null);
        (await _client.PostAsJsonAsync("/api/v1/auth/refresh", new RefreshRequest(kidAuth.RefreshToken), Json)).StatusCode.Should().Be(HttpStatusCode.Unauthorized);

        Use(family.Parent.AccessToken);
        var after = await Get<FamilyDto>("/api/v1/family");
        after.Children.Single(x => x.Id == family.Children[0].Id).PairedDeviceCount.Should().Be(0);
    }

    [Fact]
    public async Task RefreshTokenRotation_OldRefreshTokenCannotBeReused()
    {
        ResetClock();
        var parent = await RegisterParent("refresh");
        var oldRefresh = parent.RefreshToken;

        Use(null);
        var rotated = await Post<AuthResponse>("/api/v1/auth/refresh", new RefreshRequest(oldRefresh));
        rotated.RefreshToken.Should().NotBe(oldRefresh);
        (await _client.PostAsJsonAsync("/api/v1/auth/refresh", new RefreshRequest(oldRefresh), Json)).StatusCode.Should().Be(HttpStatusCode.Unauthorized);
        (await Post<AuthResponse>("/api/v1/auth/refresh", new RefreshRequest(rotated.RefreshToken))).User.Id.Should().Be(parent.User.Id);
    }

    [Fact]
    public async Task Validation_MalformedJsonAndMissingRequiredFields_ReturnBadRequestProblem()
    {
        ResetClock();
        Use(null);
        using var malformedBody = new StringContent("{", Encoding.UTF8, "application/json");
        var malformed = await _client.PostAsync("/api/v1/auth/register", malformedBody);
        await AssertProblem(malformed, HttpStatusCode.BadRequest);

        var missingPassword = await _client.PostAsJsonAsync("/api/v1/auth/register", new
        {
            email = UniqueEmail("missing-password"),
            displayName = "Dad",
            familyName = "Validation",
            timeZone = "America/Los_Angeles"
        }, Json);
        await AssertProblem(missingPassword, HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task FractionalRates_CreateAndGet_ReturnExactPersistedValues()
    {
        ResetClock();
        var family = await CreateFamily("fractional", childCount: 1);
        var terms = NewTerms(family.Children[0].Id) with { AnnualRate = 0.055m, LateFeePercent = 0.125m };
        var created = await CreateLoan(family.Parent, family.Children[0].Id, terms);

        var loaded = await Get<LoanDetailDto>($"/api/v1/loans/{created.Id}");
        loaded.AnnualRate.Should().Be(0.055m);
        loaded.LateFeePercent.Should().Be(0.125m);
    }

    [Fact]
    public async Task PairingCode_ExpiredOrReusedCode_IsRejected()
    {
        ResetClock();
        var family = await CreateFamily("pairing", childCount: 2);
        Use(family.Parent.AccessToken);
        var expiredCode = await Post<PairingCodeResponse>($"/api/v1/family/children/{family.Children[0].Id}/pairing-code", new { }, HttpStatusCode.Created);

        _clock.UtcNow = TestNow.AddMinutes(16);
        Use(null);
        (await _client.PostAsJsonAsync("/api/v1/auth/pair", new PairRequest(expiredCode.Code, "expired phone"), Json)).StatusCode.Should().Be(HttpStatusCode.Unauthorized);

        Use(family.Parent.AccessToken);
        var reusableCode = await Post<PairingCodeResponse>($"/api/v1/family/children/{family.Children[1].Id}/pairing-code", new { }, HttpStatusCode.Created);
        Use(null);
        var firstPair = await Post<AuthResponse>("/api/v1/auth/pair", new PairRequest(reusableCode.Code, "first phone"));
        firstPair.User.Id.Should().Be(family.Children[1].Id);
        (await _client.PostAsJsonAsync("/api/v1/auth/pair", new PairRequest(reusableCode.Code, "second phone"), Json)).StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    private async Task<FamilySetup> CreateFamily(string prefix, int childCount)
    {
        var parent = await RegisterParent(prefix);
        var children = new List<ChildDto>();
        Use(parent.AccessToken);
        for (var i = 0; i < childCount; i++)
        {
            children.Add(await Post<ChildDto>("/api/v1/family/children", new ChildRequest($"{prefix} kid {i + 1}", i == 0 ? "#4F8EF7" : null), HttpStatusCode.Created));
        }

        return new FamilySetup(parent, children);
    }

    private async Task<AuthResponse> RegisterParent(string prefix)
    {
        Use(null);
        return await Post<AuthResponse>("/api/v1/auth/register", new RegisterRequest(UniqueEmail(prefix), "Password123!", $"{prefix} parent", $"{prefix} family", "America/Los_Angeles"), HttpStatusCode.Created);
    }

    private async Task<AuthResponse> PairChild(AuthResponse parent, Guid childId, string deviceName)
    {
        Use(parent.AccessToken);
        var code = await Post<PairingCodeResponse>($"/api/v1/family/children/{childId}/pairing-code", new { }, HttpStatusCode.Created);
        Use(null);
        return await Post<AuthResponse>("/api/v1/auth/pair", new PairRequest(code.Code, deviceName));
    }

    private async Task<LoanDetailDto> CreateLoan(AuthResponse parent, Guid childId, LoanTermsInput? terms = null)
    {
        Use(parent.AccessToken);
        return await Post<LoanDetailDto>("/api/v1/loans", terms ?? NewTerms(childId), HttpStatusCode.Created);
    }

    private static LoanTermsInput NewTerms(Guid childId) => new(childId, "Edge loan", 300m, true, 0.05m, Frequency.Monthly, 6, new DateOnly(2026, 11, 17), 5m, 0.10m, 3, true, true);

    private static string UniqueEmail(string prefix) => $"{prefix}-{Guid.NewGuid():N}@example.com";

    private DateOnly Today() => DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(_clock.UtcNow, TimeZoneInfo.FindSystemTimeZoneById("America/Los_Angeles")).DateTime);

    private void ResetClock() => _clock.UtcNow = TestNow;

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
        var errorBody = await response.Content.ReadAsStringAsync();
        response.StatusCode.Should().Be(HttpStatusCode.OK, errorBody);
        return (await response.Content.ReadFromJsonAsync<T>(Json))!;
    }

    private static async Task AssertProblem(HttpResponseMessage response, HttpStatusCode expected)
    {
        var body = await response.Content.ReadAsStringAsync();
        response.StatusCode.Should().Be(expected, body);
        response.Content.Headers.ContentType?.MediaType.Should().Be("application/problem+json");
        using var problem = JsonDocument.Parse(body);
        problem.RootElement.GetProperty("status").GetInt32().Should().Be((int)expected);
    }

    private sealed record FamilySetup(AuthResponse Parent, IReadOnlyList<ChildDto> Children);

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
