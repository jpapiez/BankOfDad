namespace BankOfDad.Api.Tests;

using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using BankOfDad.Api.Models;
using BankOfDad.Api.Services;
using BankOfDad.Domain;
using BankOfDad.Infrastructure.Data;
using FluentAssertions;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Testcontainers.PostgreSql;

public sealed class OnboardingTests : IAsyncLifetime
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) }
    };

    private readonly PostgreSqlContainer _postgres = new PostgreSqlBuilder("postgres:16-alpine")
        .WithDatabase("bankofdad_onboarding_tests")
        .WithUsername("bankofdad")
        .WithPassword("bankofdad-dev")
        .Build();
    private OnboardingFactory? _factory;
    private HttpClient _client = null!;

    public async Task InitializeAsync()
    {
        await _postgres.StartAsync();
        _factory = new OnboardingFactory(_postgres.GetConnectionString());
        _client = _factory.CreateClient();
    }

    public async Task DisposeAsync()
    {
        _client.Dispose();
        if (_factory is not null) await _factory.DisposeAsync();
        await _postgres.DisposeAsync();
    }

    [Fact]
    public async Task Setup_code_reveals_qr_and_bootstrap_can_initialize_only_once()
    {
        var initial = await Get<ServerDescriptor>("/.well-known/bankofdad");
        initial.SetupState.Should().Be("uninitialized");
        initial.Origin.Should().Be("https://family.example");
        initial.Capabilities.Apple.Should().BeFalse();
        initial.Capabilities.Push.Should().BeFalse();

        var invalid = await _client.PostAsync("/setup/unlock", new FormUrlEncodedContent(new Dictionary<string, string> { ["code"] = "wrong" }));
        invalid.StatusCode.Should().Be(HttpStatusCode.Unauthorized);

        var unlocked = await _client.PostAsync("/setup/unlock", new FormUrlEncodedContent(new Dictionary<string, string> { ["code"] = "one-time-setup" }));
        unlocked.StatusCode.Should().Be(HttpStatusCode.OK);
        (await unlocked.Content.ReadAsStringAsync()).Should().Contain("<svg");

        var grant = await CreateEnrollment(EnrollmentKind.Bootstrap, null, null, TimeSpan.FromMinutes(15));
        var auth = await Post<AuthResponse>("/api/v1/setup/complete", new BootstrapCompleteRequest(grant.Token, "parent@example.com", "Password123!", "Parent", "Example Family", "UTC"), HttpStatusCode.Created);
        auth.User.Role.Should().Be(Role.Parent);

        var ready = await Get<ServerDescriptor>("/.well-known/bankofdad");
        ready.SetupState.Should().Be("ready");
        ready.FamilyName.Should().Be("Example Family");

        var secondGrant = await CreateEnrollment(EnrollmentKind.Bootstrap, null, null, TimeSpan.FromMinutes(15));
        var second = await _client.PostAsJsonAsync("/api/v1/setup/complete", new BootstrapCompleteRequest(secondGrant.Token, "other@example.com", "Password123!", "Other", "Other Family", "UTC"), Json);
        second.StatusCode.Should().Be(HttpStatusCode.Conflict);
    }

    [Fact]
    public async Task Parent_and_child_enrollments_are_server_aware_single_use_and_support_pin_login()
    {
        var parent = await Bootstrap();
        Use(parent.AccessToken);
        var invite = await Post<InviteResponse>("/api/v1/family/invites/enrollment", new InviteRequest("other@example.com"), HttpStatusCode.Created);
        invite.QrPayload.Should().StartWith("bankofdad://connect?");
        invite.QrPayload.Should().Contain("origin=https%3A%2F%2Ffamily.example");

        Use(null);
        var preview = await Post<EnrollmentPreview>("/api/v1/enrollment/inspect", new EnrollmentInspectRequest(invite.InviteCode));
        preview.Kind.Should().Be(EnrollmentKind.Parent);
        preview.FamilyName.Should().Be("Example Family");

        var other = await Post<AuthResponse>("/api/v1/auth/accept-enrollment", new AcceptInviteRequest(invite.InviteCode, "other@example.com", "Password123!", "Other Parent"), HttpStatusCode.Created);
        other.User.Role.Should().Be(Role.Parent);
        var reuse = await _client.PostAsJsonAsync("/api/v1/auth/accept-enrollment", new AcceptInviteRequest(invite.InviteCode, "third@example.com", "Password123!", "Third"), Json);
        reuse.StatusCode.Should().Be(HttpStatusCode.Unauthorized);

        Use(parent.AccessToken);
        var child = await Post<ChildDto>("/api/v1/family/children", new ChildRequest("Kid", null), HttpStatusCode.Created);
        var childInvite = await Post<PairingCodeResponse>($"/api/v1/family/children/{child.Id}/enrollment", new { }, HttpStatusCode.Created);
        Use(null);
        var childAuth = await Post<AuthResponse>("/api/v1/auth/complete-child-enrollment", new ChildEnrollmentRequest(childInvite.Code, "kid.one", "123456", ChildCredentialKind.Pin, "Kid's iPhone"));
        childAuth.User.Role.Should().Be(Role.Child);

        var login = await Post<AuthResponse>("/api/v1/auth/child-login", new ChildLoginRequest("KID.ONE", "123456", "Replacement phone"));
        login.User.Id.Should().Be(child.Id);
        var shortPinInvite = await CreateChildEnrollment(parent.AccessToken, child.Id);
        var shortPin = await _client.PostAsJsonAsync("/api/v1/auth/complete-child-enrollment", new ChildEnrollmentRequest(shortPinInvite.Code, "kid.one", "1234", ChildCredentialKind.Pin, null), Json);
        shortPin.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    private async Task<AuthResponse> Bootstrap()
    {
        var grant = await CreateEnrollment(EnrollmentKind.Bootstrap, null, null, TimeSpan.FromMinutes(15));
        return await Post<AuthResponse>("/api/v1/setup/complete", new BootstrapCompleteRequest(grant.Token, "parent@example.com", "Password123!", "Parent", "Example Family", "UTC"), HttpStatusCode.Created);
    }

    private async Task<PairingCodeResponse> CreateChildEnrollment(string accessToken, Guid childId)
    {
        Use(accessToken);
        var response = await Post<PairingCodeResponse>($"/api/v1/family/children/{childId}/enrollment", new { }, HttpStatusCode.Created);
        Use(null);
        return response;
    }

    private async Task<EnrollmentGrant> CreateEnrollment(EnrollmentKind kind, Guid? familyId, Guid? childId, TimeSpan lifetime)
    {
        using var scope = _factory!.Services.CreateScope();
        return await scope.ServiceProvider.GetRequiredService<OnboardingService>()
            .CreateEnrollmentAsync(kind, familyId, childId, null, null, lifetime, CancellationToken.None);
    }

    private void Use(string? token) => _client.DefaultRequestHeaders.Authorization = token is null ? null : new AuthenticationHeaderValue("Bearer", token);

    private async Task<T> Get<T>(string path)
    {
        var response = await _client.GetAsync(path);
        response.StatusCode.Should().Be(HttpStatusCode.OK, await response.Content.ReadAsStringAsync());
        return (await response.Content.ReadFromJsonAsync<T>(Json))!;
    }

    private async Task<T> Post<T>(string path, object body, HttpStatusCode expected = HttpStatusCode.OK)
    {
        var response = await _client.PostAsJsonAsync(path, body, Json);
        response.StatusCode.Should().Be(expected, await response.Content.ReadAsStringAsync());
        return (await response.Content.ReadFromJsonAsync<T>(Json))!;
    }

    private sealed class OnboardingFactory(string connectionString) : WebApplicationFactory<Program>
    {
        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            builder.UseEnvironment("Testing");
            builder.ConfigureAppConfiguration(config => config.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ConnectionStrings:Default"] = connectionString,
                ["Onboarding:PublicBaseUrl"] = "https://family.example",
                ["Onboarding:SetupCode"] = "one-time-setup",
                ["Onboarding:ChildPinMinimumLength"] = "6"
            }));
            builder.ConfigureServices(services =>
            {
                services.RemoveAll<DbContextOptions<BankOfDadDbContext>>();
                services.AddDbContext<BankOfDadDbContext>(options => options.UseNpgsql(connectionString));
            });
        }
    }
}
