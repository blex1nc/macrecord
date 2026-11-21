namespace Macrecord.Core;

/// <summary>Release tags look like "v1.2.3"; pre-release suffixes ("-beta") are ignored for ordering.</summary>
public static class ReleaseVersion
{
    public static Version? Parse(string? tag)
    {
        if (string.IsNullOrWhiteSpace(tag)) return null;
        var text = tag.Trim().TrimStart('v', 'V');
        var dash = text.IndexOfAny(['-', '+']);
        if (dash >= 0) text = text[..dash];
        if (!Version.TryParse(text, out var version)) return null;
        // Normalize so 1.2 == 1.2.0.
        return new Version(version.Major, version.Minor, Math.Max(version.Build, 0));
    }

    public static bool IsNewer(string? latestTag, string? currentVersion)
    {
        var latest = Parse(latestTag);
        var current = Parse(currentVersion);
        return latest is not null && current is not null && latest > current;
    }
}
