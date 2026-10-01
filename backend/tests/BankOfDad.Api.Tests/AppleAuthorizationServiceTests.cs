namespace BankOfDad.Api.Tests;

using System.Net;
using System.Security.Cryptography;
using BankOfDad.Infrastructure.Security;
using FluentAssertions;
using Microsoft.Extensions.Configuration;

public sealed class AppleAuthorizationServiceTests : IDisposable
{
    private readonly string _keyPath;
    private readonly IConfiguration _configuration;

    public AppleAuthorizationServiceTests()
    {
        _keyPath = Path.GetTempFileName();
        using var key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        File.WriteAllText(_keyPath, key.ExportPkcs8PrivateKeyPem());
        _configuration = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["Apple:ClientId"] = "com.example.bankofdad",
            ["Apple:TeamId"] = "TEAM123",
            ["Apple:KeyId"] = "KEY123",
            ["Apple:KeyPath"] = _keyPath,
            ["Apple:TokenEncryptionKey"] = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32))
        }).Build();
    }

    [Fact]
    public async Task Exchanges_code_encrypts_refresh_token_and_revokes_the_decrypted_token()
    {
        var requests = new List<(string Path, string Body)>();
        var handler = new StubHandler(async request =>
        {
            var body = await request.Content!.ReadAsStringAsync();
            requests.Add((request.RequestUri!.AbsolutePath, body));
            if (request.RequestUri.AbsolutePath == "/auth/token")
            {
                return Json(HttpStatusCode.OK, """{"refresh_token":"apple-refresh-secret","id_token":"exchanged-user-a"}""");
            }
            return new HttpResponseMessage(HttpStatusCode.OK);
        });
        var service = new AppleAuthorizationService(new HttpClient(handler), _configuration, new StubTokenValidator());

        var encrypted = await service.ExchangeCodeAsync("one-time-code", "user-a");
        encrypted.Should().NotContain("apple-refresh-secret").And.NotBe("apple-refresh-secret");
        await service.RevokeAsync(encrypted);

        requests.Should().HaveCount(2);
        requests[0].Path.Should().Be("/auth/token");
        requests[0].Body.Should().Contain("code=one-time-code").And.Contain("grant_type=authorization_code");
        requests[1].Path.Should().Be("/auth/revoke");
        requests[1].Body.Should().Contain("token=apple-refresh-secret").And.Contain("token_type_hint=refresh_token");
    }

    [Fact]
    public async Task Revocation_failure_is_reported()
    {
        var handler = new StubHandler(request =>
            Task.FromResult(request.RequestUri!.AbsolutePath == "/auth/token"
                ? Json(HttpStatusCode.OK, """{"refresh_token":"apple-refresh-secret","id_token":"exchanged-user-a"}""")
                : new HttpResponseMessage(HttpStatusCode.BadGateway)));
        var service = new AppleAuthorizationService(new HttpClient(handler), _configuration, new StubTokenValidator());
        var encrypted = await service.ExchangeCodeAsync("one-time-code", "user-a");

        var action = () => service.RevokeAsync(encrypted);
        await action.Should().ThrowAsync<AppleAuthorizationException>().WithMessage("*HTTP 502*");
    }

    [Fact]
    public async Task Rejects_authorization_code_for_a_different_Apple_subject()
    {
        var handler = new StubHandler(_ => Task.FromResult(Json(
            HttpStatusCode.OK,
            """{"refresh_token":"apple-refresh-secret","id_token":"exchanged-user-b"}""")));
        var service = new AppleAuthorizationService(new HttpClient(handler), _configuration, new StubTokenValidator());

        var action = () => service.ExchangeCodeAsync("one-time-code", "user-a");

        await action.Should().ThrowAsync<AppleAuthorizationException>().WithMessage("*does not belong*");
    }

    public void Dispose() => File.Delete(_keyPath);

    private static HttpResponseMessage Json(HttpStatusCode status, string json) =>
        new(status) { Content = new StringContent(json, System.Text.Encoding.UTF8, "application/json") };

    private sealed class StubHandler(Func<HttpRequestMessage, Task<HttpResponseMessage>> handler) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) => handler(request);
    }

    private sealed class StubTokenValidator : IAppleTokenValidator
    {
        public Task<AppleUser> ValidateAsync(string identityToken, CancellationToken cancellationToken = default) =>
            Task.FromResult(new AppleUser(identityToken.Replace("exchanged-", string.Empty, StringComparison.Ordinal), null));
    }
}
