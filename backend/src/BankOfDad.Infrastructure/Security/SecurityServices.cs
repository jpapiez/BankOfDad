namespace BankOfDad.Infrastructure.Security;

using System.Security.Cryptography;
using System.Text;
using BankOfDad.Domain.Entities;
using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.Configuration;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;
using System.IdentityModel.Tokens.Jwt;

public interface IPasswordService
{
    string Hash(User user, string password);
    bool Verify(User user, string password);
}

public sealed class PasswordService : IPasswordService
{
    private readonly PasswordHasher<User> _hasher = new();
    public string Hash(User user, string password) => _hasher.HashPassword(user, password);
    public bool Verify(User user, string password) => _hasher.VerifyHashedPassword(user, user.PasswordHash ?? string.Empty, password) != PasswordVerificationResult.Failed;
}

public static class SecretHasher
{
    public static string Sha256(string value)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(value));
        return Convert.ToHexString(bytes).ToLowerInvariant();
    }
}

public static class CodeGenerator
{
    private const string Alphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

    public static string Generate(int length = 8)
    {
        Span<byte> bytes = stackalloc byte[length];
        RandomNumberGenerator.Fill(bytes);
        var chars = new char[length];
        for (var i = 0; i < length; i++) chars[i] = Alphabet[bytes[i] % Alphabet.Length];
        return new string(chars);
    }

    public static string FormatPairingCode(string code) => $"{code[..3]}-{code.Substring(3, 3)}-{code.Substring(6, 2)}";
    public static string NormalizeCode(string code) => new(code.Where(char.IsLetterOrDigit).Select(char.ToUpperInvariant).ToArray());
}

public record AppleUser(string Subject, string? Email);

public interface IAppleTokenValidator
{
    Task<AppleUser> ValidateAsync(string identityToken, CancellationToken cancellationToken = default);
}

public sealed class AppleTokenValidator(IConfiguration configuration) : IAppleTokenValidator
{
    private readonly ConfigurationManager<OpenIdConnectConfiguration> _configurationManager = new(
        "https://appleid.apple.com/.well-known/openid-configuration",
        new OpenIdConnectConfigurationRetriever());

    public async Task<AppleUser> ValidateAsync(string identityToken, CancellationToken cancellationToken = default)
    {
        var appleConfig = await _configurationManager.GetConfigurationAsync(cancellationToken).ConfigureAwait(false);
        var validation = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = "https://appleid.apple.com",
            ValidateAudience = true,
            ValidAudience = configuration["Apple:ClientId"],
            ValidateIssuerSigningKey = true,
            IssuerSigningKeys = appleConfig.SigningKeys,
            ValidateLifetime = true,
            ClockSkew = TimeSpan.FromMinutes(2)
        };
        var principal = new JwtSecurityTokenHandler().ValidateToken(identityToken, validation, out _);
        var sub = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value ?? principal.FindFirst("sub")?.Value;
        if (string.IsNullOrWhiteSpace(sub)) throw new SecurityTokenException("Apple token missing subject.");
        var email = principal.FindFirst(JwtRegisteredClaimNames.Email)?.Value ?? principal.FindFirst("email")?.Value;
        return new AppleUser(sub, email);
    }
}
