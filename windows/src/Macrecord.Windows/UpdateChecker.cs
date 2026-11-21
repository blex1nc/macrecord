using System.Diagnostics;
using System.Text.Json;
using Macrecord.Core;

namespace Macrecord.Windows;

/// <summary>
/// The app's only network access: asks GitHub for the latest release and, on request, replaces the running exe.
/// Can be turned off in the settings. Sends no data beyond the HTTP request itself.
/// </summary>
internal static class UpdateChecker
{
    private const string LatestUrl = "https://api.github.com/repos/blex1nc/macrecord/releases/latest";
    public const string ReleasesPage = "https://github.com/blex1nc/macrecord/releases/latest";
    private const string AssetName = "macrecord-windows-x64.exe";

    public sealed record Update(string Tag, string DownloadUrl);

    public static string CurrentVersion
    {
        get
        {
            var v = typeof(UpdateChecker).Assembly.GetName().Version;
            return v is null ? "0.0.0" : $"{v.Major}.{v.Minor}.{Math.Max(v.Build, 0)}";
        }
    }

    /// <summary>Null when up to date or when the release has no Windows build.</summary>
    public static async Task<Update?> CheckAsync(CancellationToken cancel)
    {
        using var http = NewClient();
        using var json = JsonDocument.Parse(await http.GetStringAsync(LatestUrl, cancel));
        var root = json.RootElement;
        var tag = root.TryGetProperty("tag_name", out var t) ? t.GetString() : null;
        if (!ReleaseVersion.IsNewer(tag, CurrentVersion) || !root.TryGetProperty("assets", out var assets)) return null;
        foreach (var asset in assets.EnumerateArray())
        {
            if (asset.TryGetProperty("name", out var name) && name.GetString() == AssetName
                && asset.TryGetProperty("browser_download_url", out var url) && url.GetString() is { } link)
            {
                return new Update(tag!, link);
            }
        }
        return null;
    }

    /// <summary>
    /// Downloads next to the running exe, swaps the files (Windows allows renaming a running exe) and restarts.
    /// Throws if the folder is not writable; the caller then opens the releases page instead.
    /// </summary>
    public static async Task ApplyAsync(Update update, CancellationToken cancel)
    {
        var exe = Environment.ProcessPath ?? throw new InvalidOperationException("Unknown executable path.");
        var fresh = exe + ".new";
        var old = exe + ".old";
        using (var http = NewClient())
        await using (var download = await http.GetStreamAsync(update.DownloadUrl, cancel))
        await using (var file = File.Create(fresh))
        {
            await download.CopyToAsync(file, cancel);
        }
        if (File.Exists(old)) File.Delete(old);
        File.Move(exe, old);
        File.Move(fresh, exe);
        Process.Start(new ProcessStartInfo(exe) { UseShellExecute = true });
    }

    /// <summary>Removes the previous exe left behind by an update.</summary>
    public static void CleanUp()
    {
        try
        {
            if (Environment.ProcessPath is { } exe && File.Exists(exe + ".old")) File.Delete(exe + ".old");
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    public static void OpenReleasesPage() =>
        Process.Start(new ProcessStartInfo(ReleasesPage) { UseShellExecute = true });

    private static HttpClient NewClient()
    {
        var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
        http.DefaultRequestHeaders.UserAgent.ParseAdd($"macrecord-windows/{CurrentVersion}"); // GitHub requires one
        return http;
    }
}
