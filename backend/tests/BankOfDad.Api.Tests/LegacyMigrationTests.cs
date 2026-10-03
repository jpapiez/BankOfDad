namespace BankOfDad.Api.Tests;

using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using BankOfDad.Api.Models;
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
using Npgsql;
using Testcontainers.PostgreSql;

public sealed class LegacyMigrationTests : IAsyncLifetime
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) }
    };

    private readonly PostgreSqlContainer _postgres = new PostgreSqlBuilder("postgres:16-alpine")
        .WithDatabase("bankofdad_legacy_migration_tests")
        .WithUsername("bankofdad")
        .WithPassword("bankofdad-dev")
        .Build();

    public async Task InitializeAsync()
    {
        await _postgres.StartAsync();
        await SeedLegacyDatabaseAsync();
    }

    public Task DisposeAsync() => _postgres.DisposeAsync().AsTask();

    [Fact]
    public async Task Multi_family_database_migrates_and_starts_in_legacy_mode()
    {
        await using var factory = new LegacyFactory(_postgres.GetConnectionString());
        using var client = factory.CreateClient();

        (await client.GetAsync("/health")).StatusCode.Should().Be(HttpStatusCode.OK);

        var descriptor = (await client.GetFromJsonAsync<ServerDescriptor>("/.well-known/bankofdad", Json))!;
        descriptor.SetupState.Should().Be("legacy-multi-family");
        descriptor.FamilyName.Should().BeNull();

        var root = await client.GetStringAsync("/");
        root.Should().Contain("Existing multi-family server");
        root.Should().Contain("self-hosted bootstrap is disabled");

        var unlock = await client.PostAsync(
            "/setup/unlock",
            new FormUrlEncodedContent(new Dictionary<string, string> { ["code"] = "legacy-setup" }));
        unlock.StatusCode.Should().Be(HttpStatusCode.Conflict);
        (await unlock.Content.ReadAsStringAsync()).Should().Contain("legacy multi-family");

        var login = await client.PostAsJsonAsync(
            "/api/v1/auth/login",
            new LoginRequest("legacy-one@example.com", "Password123!"),
            Json);
        login.StatusCode.Should().Be(HttpStatusCode.OK, await login.Content.ReadAsStringAsync());
        var auth = (await login.Content.ReadFromJsonAsync<AuthResponse>(Json))!;
        auth.User.FamilyId.Should().NotBeEmpty();

        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<BankOfDadDbContext>();
        (await db.Families.CountAsync()).Should().Be(2);
        (await db.ServerInstallations.CountAsync()).Should().Be(1);
        var installation = await db.ServerInstallations.SingleAsync();
        installation.FamilyId.Should().BeNull();
        installation.LegacyMultiFamily.Should().BeTrue();
    }

    private async Task SeedLegacyDatabaseAsync()
    {
        var options = new DbContextOptionsBuilder<BankOfDadDbContext>()
            .UseNpgsql(_postgres.GetConnectionString())
            .Options;
        await using (var db = new BankOfDadDbContext(options))
        {
            await db.Database.MigrateAsync("20260927234121_InitialCreate");
        }

        var familyOne = Guid.NewGuid();
        var familyTwo = Guid.NewGuid();
        var userOne = Guid.NewGuid();
        var userTwo = Guid.NewGuid();
        var createdAt = new DateTimeOffset(2026, 10, 3, 0, 0, 0, TimeSpan.Zero);
        var passwordHash = new PasswordService().Hash(new User(), "Password123!");

        await using var connection = new NpgsqlConnection(_postgres.GetConnectionString());
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(
            """
            INSERT INTO "Families" ("Id", "Name", "TimeZone", "Currency", "CreatedAt")
            VALUES (@familyOne, 'Legacy One', 'UTC', 'USD', @createdAt),
                   (@familyTwo, 'Legacy Two', 'UTC', 'USD', @createdAt);

            INSERT INTO "Users" ("Id", "FamilyId", "Role", "DisplayName", "Email", "NormalizedEmail", "PasswordHash", "AppleSubject", "AvatarColor", "CreatedAt")
            VALUES (@userOne, @familyOne, 'Parent', 'Legacy One Parent', 'legacy-one@example.com', 'legacy-one@example.com', @passwordHash, NULL, NULL, @createdAt),
                   (@userTwo, @familyTwo, 'Parent', 'Legacy Two Parent', 'legacy-two@example.com', 'legacy-two@example.com', @passwordHash, NULL, NULL, @createdAt);
            """,
            connection);
        command.Parameters.AddWithValue("familyOne", familyOne);
        command.Parameters.AddWithValue("familyTwo", familyTwo);
        command.Parameters.AddWithValue("userOne", userOne);
        command.Parameters.AddWithValue("userTwo", userTwo);
        command.Parameters.AddWithValue("createdAt", createdAt);
        command.Parameters.AddWithValue("passwordHash", passwordHash);
        await command.ExecuteNonQueryAsync();
    }

    private sealed class LegacyFactory(string connectionString) : WebApplicationFactory<Program>
    {
        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            builder.UseEnvironment("Production");
            builder.UseSetting("Jwt:SigningKey", "legacy-migration-tests-signing-key-0123456789");
            builder.ConfigureAppConfiguration(config => config.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ConnectionStrings:Default"] = connectionString,
                ["Onboarding:PublicBaseUrl"] = "https://family.example",
                ["Onboarding:SetupCode"] = "legacy-setup"
            }));
            builder.ConfigureServices(services =>
            {
                services.RemoveAll<DbContextOptions<BankOfDadDbContext>>();
                services.AddDbContext<BankOfDadDbContext>(options => options.UseNpgsql(connectionString));
            });
        }
    }
}
