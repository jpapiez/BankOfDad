namespace BankOfDad.Infrastructure.Push;

using System.IdentityModel.Tokens.Jwt;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Security.Cryptography;
using BankOfDad.Domain;
using BankOfDad.Domain.Entities;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Microsoft.IdentityModel.Tokens;

public record PushMessage(NotificationType Type, string Title, string Body, Guid? LoanId, Guid NotificationId, Guid? BillId = null);

public interface IPushSender
{
    Task SendAsync(DeviceToken deviceToken, PushMessage message, int badge, CancellationToken cancellationToken = default);
}

public sealed class LoggingPushSender(ILogger<LoggingPushSender> logger) : IPushSender
{
    public Task SendAsync(DeviceToken deviceToken, PushMessage message, int badge, CancellationToken cancellationToken = default)
    {
        logger.LogInformation("Push {Type} to user {UserId}: {Title} {Body}", message.Type, deviceToken.UserId, message.Title, message.Body);
        return Task.CompletedTask;
    }
}

public sealed class ApnsPushSender(HttpClient httpClient, IConfiguration configuration, ILogger<ApnsPushSender> logger) : IPushSender
{
    public async Task SendAsync(DeviceToken deviceToken, PushMessage message, int badge, CancellationToken cancellationToken = default)
    {
        var keyId = configuration["Apns:KeyId"];
        var teamId = configuration["Apns:TeamId"];
        var bundleId = configuration["Apns:BundleId"];
        var keyPath = configuration["Apns:KeyPath"];
        if (string.IsNullOrWhiteSpace(keyId) || string.IsNullOrWhiteSpace(teamId) || string.IsNullOrWhiteSpace(bundleId) || string.IsNullOrWhiteSpace(keyPath))
        {
            logger.LogInformation("APNs not configured; skipped push {NotificationId}", message.NotificationId);
            return;
        }

        var host = configuration.GetValue("Apns:UseSandbox", true) ? "api.sandbox.push.apple.com" : "api.push.apple.com";
        using var request = new HttpRequestMessage(HttpMethod.Post, $"https://{host}/3/device/{deviceToken.ApnsToken}")
        {
            Version = new Version(2, 0),
            Content = JsonContent.Create(new
            {
                aps = new { alert = new { title = message.Title, body = message.Body }, sound = "default", badge },
                type = ToCamel(message.Type.ToString()),
                loanId = message.LoanId,
                billId = message.BillId,
                notificationId = message.NotificationId
            })
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("bearer", CreateProviderToken(keyPath, keyId, teamId));
        request.Headers.TryAddWithoutValidation("apns-topic", bundleId);
        var response = await httpClient.SendAsync(request, cancellationToken).ConfigureAwait(false);
        response.EnsureSuccessStatusCode();
    }

    private static string CreateProviderToken(string keyPath, string keyId, string teamId)
    {
        var pem = File.ReadAllText(keyPath).Replace("-----BEGIN PRIVATE KEY-----", string.Empty).Replace("-----END PRIVATE KEY-----", string.Empty).Replace("\r", string.Empty).Replace("\n", string.Empty).Trim();
        var keyBytes = Convert.FromBase64String(pem);
        var ecdsa = ECDsa.Create();
        ecdsa.ImportPkcs8PrivateKey(keyBytes, out _);
        var credentials = new SigningCredentials(new ECDsaSecurityKey(ecdsa) { KeyId = keyId }, SecurityAlgorithms.EcdsaSha256);
        var token = new JwtSecurityToken(teamId, claims: [new Claim("iat", DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString())], signingCredentials: credentials);
        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    private static string ToCamel(string value) => char.ToLowerInvariant(value[0]) + value[1..];
}
