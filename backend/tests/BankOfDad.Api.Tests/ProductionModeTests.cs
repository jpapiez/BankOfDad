namespace BankOfDad.Api.Tests;

using System.Net;
using System.Net.Http.Json;
using BankOfDad.Api.Models;
using BankOfDad.Domain;
using BankOfDad.Domain.Entities;
using BankOfDad.Infrastructure.Data;
using BankOfDad.Infrastructure.Security;
using FluentAssertions;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Testcontainers.PostgreSql;

public sealed class ProductionModeTests : IAsyncLifetime
{
    private readonly PostgreSqlContainer postgres = new PostgreSqlBuilder("postgres:16-alpine")
        .WithDatabase("bankofdad_production_tests")
        .WithUsername("bankofdad")
        .WithPassword("bankofdad-dev")
        .Build();

    private ProductionFactory factory = null!;
    private HttpClient client = null!;

    public async Task InitializeAsync()
    {
        await postgres.StartAsync();
        factory = new ProductionFactory(postgres.GetConnectionString());
        client = factory.CreateClient();
        await SeedChildAsync();
    }

    public async Task DisposeAsync()
    {
        client.Dispose();
        await factory.DisposeAsync();
        await postgres.DisposeAsync();
    }

    [Fact]
    public async Task Production_hides_legacy_registration_and_unconfigured_Apple()
    {
        var register = await client.PostAsJsonAsync("/api/v1/auth/register", new RegisterRequest(
            "production@example.com", "Password123!", "Parent", "Production", "UTC"));
        register.StatusCode.Should().Be(HttpStatusCode.NotFound);

        var apple = await client.PostAsJsonAsync("/api/v1/auth/apple", new { });
        apple.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Child_login_allows_ten_requests_then_returns_429()
    {
        for (var attempt = 1; attempt <= 10; attempt++)
        {
            var response = await client.PostAsJsonAsync(
                "/api/v1/auth/child-login",
                new ChildLoginRequest("production-kid", "123456", "Production test device"));
            response.StatusCode.Should().Be(HttpStatusCode.OK, $"attempt {attempt}: {await response.Content.ReadAsStringAsync()}");
        }

        var limited = await client.PostAsJsonAsync(
            "/api/v1/auth/child-login",
            new ChildLoginRequest("production-kid", "123456", "Production test device"));
        limited.StatusCode.Should().Be(HttpStatusCode.TooManyRequests);
    }

    private async Task SeedChildAsync()
    {
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<BankOfDadDbContext>();
        var family = new Family { Name = "Production Family", TimeZone = "UTC", CreatedAt = DateTimeOffset.UtcNow };
        var child = new User
        {
            Family = family,
            Role = Role.Child,
            DisplayName = "Production Kid",
            Username = "production-kid",
            NormalizedUsername = "PRODUCTION-KID",
            ChildCredentialKind = ChildCredentialKind.Pin,
            CreatedAt = DateTimeOffset.UtcNow
        };
        child.PasswordHash = new PasswordService().Hash(child, "123456");
        db.AddRange(family, child);
        await db.SaveChangesAsync();
    }

    private sealed class ProductionFactory(string connectionString) : WebApplicationFactory<Program>
    {
        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            builder.UseEnvironment("Production");
            builder.UseSetting("Jwt:SigningKey", "production-tests-signing-key-0123456789abcdef");
            builder.ConfigureAppConfiguration(config => config.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ConnectionStrings:Default"] = connectionString,
                ["Onboarding:PublicBaseUrl"] = "https://family.example"
            }));
            builder.ConfigureServices(services =>
            {
                services.RemoveAll<DbContextOptions<BankOfDadDbContext>>();
                services.AddDbContext<BankOfDadDbContext>(options => options.UseNpgsql(connectionString));
            });
        }
    }
}
