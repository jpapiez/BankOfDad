namespace BankOfDad.Api.Services;

using System.Net;
using System.Security.Cryptography;
using System.Text;
using BankOfDad.Api.Models;
using BankOfDad.Domain;
using BankOfDad.Domain.Entities;
using BankOfDad.Infrastructure.Data;
using BankOfDad.Infrastructure.Security;
using BankOfDad.Infrastructure.Time;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.EntityFrameworkCore;

public sealed class OnboardingOptions
{
    public const string SectionName = "Onboarding";

    public string PublicBaseUrl { get; set; } = "http://localhost:8080";
    public string SetupCode { get; set; } = string.Empty;
    public int ChildPinMinimumLength { get; set; } = 6;
}

public sealed class OnboardingService(
    BankOfDadDbContext db,
    IClock clock,
    IConfiguration configuration)
{
    public const int ProtocolVersion = 1;

    public Uri PublicOrigin => OriginPolicy.ParseAndValidate(configuration[$"{OnboardingOptions.SectionName}:PublicBaseUrl"] ?? "http://localhost:8080");

    public int ChildPinMinimumLength
    {
        get
        {
            var value = configuration.GetValue($"{OnboardingOptions.SectionName}:ChildPinMinimumLength", 6);
            if (value is < 4 or > 12) throw new InvalidOperationException("Onboarding:ChildPinMinimumLength must be between 4 and 12.");
            return value;
        }
    }

    public bool AppleEnabled =>
        HasValue("Apple:ClientId") &&
        HasValue("Apple:TeamId") &&
        HasValue("Apple:KeyId") &&
        HasValue("Apple:KeyPath") &&
        HasValue("Apple:TokenEncryptionKey");

    public bool PushEnabled => HasValue("Apns:KeyId") && HasValue("Apns:TeamId") && HasValue("Apns:BundleId");

    public async Task<ServerDescriptor> DescriptorAsync(CancellationToken ct)
    {
        var installation = await db.ServerInstallations.AsNoTracking().SingleAsync(ct).ConfigureAwait(false);
        var familyName = installation.FamilyId is null
            ? null
            : await db.Families.Where(x => x.Id == installation.FamilyId).Select(x => x.Name).SingleAsync(ct).ConfigureAwait(false);
        return new ServerDescriptor(
            ProtocolVersion,
            installation.Id,
            PublicOrigin.GetLeftPart(UriPartial.Authority),
            installation.InitializedAt is null ? "uninitialized" : "ready",
            familyName,
            new ServerCapabilities(true, true, true, AppleEnabled, PushEnabled),
            new ChildPinPolicy(ChildPinMinimumLength, 12));
    }

    public bool VerifySetupCode(string candidate)
    {
        var expected = configuration[$"{OnboardingOptions.SectionName}:SetupCode"];
        if (string.IsNullOrWhiteSpace(expected) || string.IsNullOrWhiteSpace(candidate)) return false;
        var expectedHash = SHA256.HashData(Encoding.UTF8.GetBytes(expected));
        var candidateHash = SHA256.HashData(Encoding.UTF8.GetBytes(candidate.Trim()));
        return CryptographicOperations.FixedTimeEquals(expectedHash, candidateHash);
    }

    public async Task<EnrollmentGrant> CreateEnrollmentAsync(
        EnrollmentKind kind,
        Guid? familyId,
        Guid? childUserId,
        string? email,
        Guid? createdByUserId,
        TimeSpan lifetime,
        CancellationToken ct)
    {
        var token = WebEncoders.Base64UrlEncode(RandomNumberGenerator.GetBytes(32));
        var entity = new EnrollmentToken
        {
            Kind = kind,
            TokenHash = SecretHasher.Sha256(token),
            FamilyId = familyId,
            ChildUserId = childUserId,
            Email = email,
            CreatedByUserId = createdByUserId,
            CreatedAt = clock.UtcNow,
            ExpiresAt = clock.UtcNow.Add(lifetime)
        };
        db.EnrollmentTokens.Add(entity);
        await db.SaveChangesAsync(ct).ConfigureAwait(false);
        return new EnrollmentGrant(token, ConnectionLink(kind, token), entity.ExpiresAt);
    }

    public async Task<EnrollmentPreview> InspectAsync(string token, CancellationToken ct)
    {
        var hash = SecretHasher.Sha256(token);
        var enrollment = await db.EnrollmentTokens
            .AsNoTracking()
            .Include(x => x.Family)
            .Include(x => x.ChildUser)
            .SingleOrDefaultAsync(x => x.TokenHash == hash, ct)
            .ConfigureAwait(false);
        ValidateEnrollment(enrollment);
        return new EnrollmentPreview(
            enrollment!.Kind,
            enrollment.Family?.Name,
            enrollment.ChildUser?.DisplayName,
            enrollment.Email,
            enrollment.ExpiresAt);
    }

    public string ConnectionLink(EnrollmentKind kind, string token)
    {
        var installationId = db.ServerInstallations.AsNoTracking().Select(x => x.Id).Single();
        return QueryHelpers.AddQueryString(
            "bankofdad://connect",
            new Dictionary<string, string?>
            {
                ["v"] = ProtocolVersion.ToString(System.Globalization.CultureInfo.InvariantCulture),
                ["origin"] = PublicOrigin.GetLeftPart(UriPartial.Authority),
                ["server"] = installationId.ToString(),
                ["kind"] = kind.ToString().ToLowerInvariant(),
                ["token"] = token
            });
    }

    public async Task<EnrollmentToken> LockEnrollmentAsync(string token, EnrollmentKind expectedKind, CancellationToken ct)
    {
        var hash = SecretHasher.Sha256(token);
        var enrollment = await db.EnrollmentTokens
            .FromSqlInterpolated($"SELECT * FROM \"EnrollmentTokens\" WHERE \"TokenHash\" = {hash} FOR UPDATE")
            .SingleOrDefaultAsync(ct)
            .ConfigureAwait(false);
        ValidateEnrollment(enrollment);
        if (enrollment!.Kind != expectedKind) throw new ApiException(401, "Invalid enrollment token.");
        return enrollment;
    }

    public void ValidatePin(string pin)
    {
        if (pin.Length < ChildPinMinimumLength || pin.Length > 12 || pin.Any(x => !char.IsAsciiDigit(x)))
        {
            throw new ApiException(400, $"PIN must contain {ChildPinMinimumLength} to 12 digits.");
        }
    }

    public static string NormalizeUsername(string value)
    {
        var username = value.Trim();
        if (username.Length is < 3 or > 50 || username.Any(x => !(char.IsAsciiLetterOrDigit(x) || x is '.' or '_' or '-')))
        {
            throw new ApiException(400, "Username must be 3 to 50 characters and use only letters, numbers, periods, underscores, or hyphens.");
        }
        return username.ToUpperInvariant();
    }

    private bool HasValue(string key) => !string.IsNullOrWhiteSpace(configuration[key]);

    private void ValidateEnrollment(EnrollmentToken? enrollment)
    {
        if (enrollment is null || enrollment.UsedAt is not null || enrollment.ExpiresAt <= clock.UtcNow)
        {
            throw new ApiException(401, "Invalid enrollment token.");
        }
    }
}

public static class OriginPolicy
{
    public static Uri ParseAndValidate(string value)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri) ||
            (uri.Scheme != Uri.UriSchemeHttps && uri.Scheme != Uri.UriSchemeHttp) ||
            !string.IsNullOrEmpty(uri.UserInfo) ||
            uri.Query.Length > 0 ||
            uri.Fragment.Length > 0 ||
            uri.AbsolutePath.Trim('/') is not "")
        {
            throw new InvalidOperationException("Onboarding:PublicBaseUrl must be an HTTP(S) origin without credentials, a path, query, or fragment.");
        }

        if (uri.Scheme == Uri.UriSchemeHttp && !IsPrivateHost(uri.Host))
        {
            throw new InvalidOperationException("Plain HTTP is allowed only for local or private hosts.");
        }

        return new Uri(uri.GetLeftPart(UriPartial.Authority));
    }

    public static bool IsPrivateHost(string host)
    {
        if (host.Equals("localhost", StringComparison.OrdinalIgnoreCase) ||
            host.EndsWith(".local", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }
        if (!IPAddress.TryParse(host, out var address)) return false;
        if (IPAddress.IsLoopback(address) || address.IsIPv6LinkLocal || address.IsIPv6SiteLocal) return true;
        var bytes = address.GetAddressBytes();
        if (address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)
        {
            return bytes[0] == 10 ||
                   bytes[0] == 127 ||
                   (bytes[0] == 169 && bytes[1] == 254) ||
                   (bytes[0] == 172 && bytes[1] is >= 16 and <= 31) ||
                   (bytes[0] == 192 && bytes[1] == 168);
        }
        return address.IsIPv6UniqueLocal;
    }
}

public sealed record EnrollmentGrant(string Token, string QrPayload, DateTimeOffset ExpiresAt);
