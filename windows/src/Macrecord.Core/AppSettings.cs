using System.Text.Json;
using System.Text.Json.Serialization;

namespace Macrecord.Core;

/// <summary>Mouse buttons that may start the autoclicker. Left/right are never allowed (the mouse would be unusable).</summary>
public enum MouseTrigger { None, Middle, XButton1, XButton2 }

public sealed class AppSettings
{
    public AutoClickConfig AutoClick { get; set; } = new();
    /// <summary>Virtual-key code of the keyboard trigger (default F6).</summary>
    public int HotkeyVirtualKey { get; set; } = 0x75;
    public MouseTrigger MouseTrigger { get; set; } = MouseTrigger.None;
    public bool CheckForUpdates { get; set; } = true;
    public DateTimeOffset? LastUpdateCheck { get; set; }

    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    public static string DefaultPath =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "macrecord", "settings.json");

    /// <summary>Missing or unreadable files give defaults; fields missing from older files keep their defaults.</summary>
    public static AppSettings Load(string path)
    {
        try
        {
            return File.Exists(path)
                ? JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(path), Options) ?? new AppSettings()
                : new AppSettings();
        }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException)
        {
            return new AppSettings();
        }
    }

    public void Save(string path)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temp = path + ".tmp";
        File.WriteAllText(temp, JsonSerializer.Serialize(this, Options));
        File.Move(temp, path, overwrite: true);
    }
}
