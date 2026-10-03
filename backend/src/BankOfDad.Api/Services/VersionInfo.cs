namespace BankOfDad.Api.Services;

/// <summary>
/// Identifies this server build and the API contract it speaks.
/// Bump <see cref="ApiLevel"/> whenever the iOS app needs a matching change (added/renamed routes or fields);
/// bump <see cref="MinClientApiLevel"/> only when older apps would break against this server.
/// </summary>
public sealed record VersionInfo(string Version, string Commit, int ApiLevel, int MinClientApiLevel)
{
    public const int CurrentApiLevel = 2;
    public const int CurrentMinClientApiLevel = 1;

    public static VersionInfo FromConfiguration(IConfiguration configuration)
    {
        var version = configuration["BANKOFDAD_VERSION"];
        var commit = configuration["BANKOFDAD_COMMIT"];
        return new VersionInfo(
            string.IsNullOrWhiteSpace(version) ? "dev" : version,
            string.IsNullOrWhiteSpace(commit) ? "unknown" : commit,
            CurrentApiLevel,
            CurrentMinClientApiLevel);
    }
}
