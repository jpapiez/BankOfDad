namespace BankOfDad.Infrastructure.Security;

using System.IdentityModel.Tokens.Jwt;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Configuration;
using Microsoft.IdentityModel.Tokens;

public interface IAppleAuthorizationService
{
    Task<string> ExchangeCodeAsync(string authorizationCode, string expectedSubject, CancellationToken cancellationToken = default);
    Task RevokeAsync(string encryptedRefreshToken, CancellationToken cancellationToken = default);
}

public sealed class AppleAuthorizationException(string message, Exception? innerException = null) : Exception(message, innerException);

public sealed class AppleAuthorizationService(HttpClient httpClient, IConfiguration configuration, IAppleTokenValidator tokenValidator) : IAppleAuthorizationService
{
    private const string AppleAudience = "https://appleid.apple.com";

    public async Task<string> ExchangeCodeAsync(string authorizationCode, string expectedSubject, CancellationToken cancellationToken = default)
    {
        var settings = Settings();
        HttpResponseMessage response;
        try
        {
            response = await httpClient.PostAsync(
                "https://appleid.apple.com/auth/token",
                new FormUrlEncodedContent(new Dictionary<string, string>
                {
                    ["client_id"] = settings.ClientId,
                    ["client_secret"] = CreateClientSecret(settings),
                    ["code"] = authorizationCode,
                    ["grant_type"] = "authorization_code"
                }),
                cancellationToken).ConfigureAwait(false);
        }
        catch (HttpRequestException ex)
        {
            throw new AppleAuthorizationException("Apple authorization-code exchange could not reach Apple.", ex);
        }
        catch (TaskCanceledException ex) when (!cancellationToken.IsCancellationRequested)
        {
            throw new AppleAuthorizationException("Apple authorization-code exchange timed out.", ex);
        }
        using (response)
        {
            if (!response.IsSuccessStatusCode)
            {
                throw new AppleAuthorizationException($"Apple authorization-code exchange failed with HTTP {(int)response.StatusCode}.");
            }

            var tokens = await response.Content.ReadFromJsonAsync<AppleTokenResponse>(cancellationToken: cancellationToken).ConfigureAwait(false);
            if (string.IsNullOrWhiteSpace(tokens?.RefreshToken))
            {
                throw new AppleAuthorizationException("Apple did not return a refresh token.");
            }
            if (string.IsNullOrWhiteSpace(tokens.IdToken))
            {
                throw new AppleAuthorizationException("Apple did not return an identity token for the authorization code.");
            }
            var exchangedUser = await tokenValidator.ValidateAsync(tokens.IdToken, cancellationToken).ConfigureAwait(false);
            if (!string.Equals(exchangedUser.Subject, expectedSubject, StringComparison.Ordinal))
            {
                throw new AppleAuthorizationException("The Apple authorization code does not belong to the authenticated Apple user.");
            }

            return Protect(tokens.RefreshToken, settings.EncryptionKey);
        }
    }

    public async Task RevokeAsync(string encryptedRefreshToken, CancellationToken cancellationToken = default)
    {
        var settings = Settings();
        string refreshToken;
        try
        {
            refreshToken = Unprotect(encryptedRefreshToken, settings.EncryptionKey);
        }
        catch (Exception ex) when (ex is CryptographicException or FormatException)
        {
            throw new AppleAuthorizationException("The stored Apple authorization could not be decrypted.", ex);
        }

        HttpResponseMessage response;
        try
        {
            response = await httpClient.PostAsync(
                "https://appleid.apple.com/auth/revoke",
                new FormUrlEncodedContent(new Dictionary<string, string>
                {
                    ["client_id"] = settings.ClientId,
                    ["client_secret"] = CreateClientSecret(settings),
                    ["token"] = refreshToken,
                    ["token_type_hint"] = "refresh_token"
                }),
                cancellationToken).ConfigureAwait(false);
        }
        catch (HttpRequestException ex)
        {
            throw new AppleAuthorizationException("Apple token revocation could not reach Apple.", ex);
        }
        catch (TaskCanceledException ex) when (!cancellationToken.IsCancellationRequested)
        {
            throw new AppleAuthorizationException("Apple token revocation timed out.", ex);
        }
        using (response)
        {
            if (!response.IsSuccessStatusCode)
            {
                throw new AppleAuthorizationException($"Apple token revocation failed with HTTP {(int)response.StatusCode}.");
            }
        }
    }

    private AppleSettings Settings()
    {
        var clientId = Required("Apple:ClientId");
        var teamId = Required("Apple:TeamId");
        var keyId = Required("Apple:KeyId");
        var keyPath = Required("Apple:KeyPath");
        var encryptionKeyText = Required("Apple:TokenEncryptionKey");
        byte[] encryptionKey;
        try
        {
            encryptionKey = Convert.FromBase64String(encryptionKeyText);
        }
        catch (FormatException ex)
        {
            throw new AppleAuthorizationException("Apple:TokenEncryptionKey must be base64.", ex);
        }
        if (encryptionKey.Length != 32) throw new AppleAuthorizationException("Apple:TokenEncryptionKey must decode to exactly 32 bytes.");
        return new AppleSettings(clientId, teamId, keyId, keyPath, encryptionKey);
    }

    private string Required(string key)
    {
        var value = configuration[key];
        return !string.IsNullOrWhiteSpace(value)
            ? value
            : throw new AppleAuthorizationException($"{key} is required for Sign in with Apple.");
    }

    private static string CreateClientSecret(AppleSettings settings)
    {
        try
        {
            var pem = File.ReadAllText(settings.KeyPath);
            using var ecdsa = ECDsa.Create();
            ecdsa.ImportFromPem(pem);
            var securityKey = new ECDsaSecurityKey(ecdsa)
            {
                KeyId = settings.KeyId,
                CryptoProviderFactory = new CryptoProviderFactory { CacheSignatureProviders = false }
            };
            var credentials = new SigningCredentials(securityKey, SecurityAlgorithms.EcdsaSha256);
            var now = DateTimeOffset.UtcNow;
            var token = new JwtSecurityToken(
                issuer: settings.TeamId,
                audience: AppleAudience,
                claims:
                [
                    new Claim(JwtRegisteredClaimNames.Sub, settings.ClientId),
                    new Claim(JwtRegisteredClaimNames.Iat, now.ToUnixTimeSeconds().ToString(), ClaimValueTypes.Integer64)
                ],
                notBefore: now.UtcDateTime,
                expires: now.AddMinutes(5).UtcDateTime,
                signingCredentials: credentials);
            return new JwtSecurityTokenHandler().WriteToken(token);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or CryptographicException or SecurityTokenException)
        {
            throw new AppleAuthorizationException("The Apple private key could not be loaded.", ex);
        }
    }

    private static string Protect(string plaintext, byte[] key)
    {
        var nonce = RandomNumberGenerator.GetBytes(12);
        var ciphertext = new byte[System.Text.Encoding.UTF8.GetByteCount(plaintext)];
        var tag = new byte[16];
        using var aes = new AesGcm(key, tag.Length);
        aes.Encrypt(nonce, System.Text.Encoding.UTF8.GetBytes(plaintext), ciphertext, tag);
        return $"{Convert.ToBase64String(nonce)}.{Convert.ToBase64String(tag)}.{Convert.ToBase64String(ciphertext)}";
    }

    private static string Unprotect(string protectedValue, byte[] key)
    {
        var parts = protectedValue.Split('.');
        if (parts.Length != 3) throw new CryptographicException("Invalid protected Apple token.");
        var nonce = Convert.FromBase64String(parts[0]);
        var tag = Convert.FromBase64String(parts[1]);
        var ciphertext = Convert.FromBase64String(parts[2]);
        var plaintext = new byte[ciphertext.Length];
        using var aes = new AesGcm(key, tag.Length);
        aes.Decrypt(nonce, ciphertext, tag, plaintext);
        return System.Text.Encoding.UTF8.GetString(plaintext);
    }

    private sealed record AppleSettings(string ClientId, string TeamId, string KeyId, string KeyPath, byte[] EncryptionKey);
    private sealed record AppleTokenResponse(
        [property: JsonPropertyName("refresh_token")] string? RefreshToken,
        [property: JsonPropertyName("id_token")] string? IdToken);
}
