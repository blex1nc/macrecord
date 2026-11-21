using Macrecord.Core;
using Xunit;

public class AutoClickConfigTests
{
    [Fact]
    public void IntervalFollowsCpsAndIsClamped()
    {
        Assert.Equal(100_000_000, new AutoClickConfig { ClicksPerSecond = 10 }.IntervalNs);
        Assert.Equal(500_000, new AutoClickConfig { ClicksPerSecond = 99_999 }.IntervalNs);       // 2000 cps cap
        Assert.Equal(10_000_000_000, new AutoClickConfig { ClicksPerSecond = 0 }.IntervalNs);     // 0.1 cps floor
    }

    [Fact]
    public void JitterStaysWithinBounds()
    {
        var config = new AutoClickConfig { ClicksPerSecond = 10, TimingJitter = 0.5 };
        Assert.Equal(50_000_000, config.JitteredIntervalNs(-1));
        Assert.Equal(150_000_000, config.JitteredIntervalNs(1));
        Assert.Equal(150_000_000, config.JitteredIntervalNs(5));      // random clamped
        config.TimingJitter = 3;                                       // jitter clamped to 0.9
        Assert.InRange(config.JitteredIntervalNs(-1), 9_999_999, 10_000_000); // 0.1 × 100 ms, float truncation
    }

    [Fact]
    public void HoldNeverOverlapsNextClick()
    {
        var single = new AutoClickConfig { ClicksPerSecond = 10, HoldDurationMs = 500 };
        Assert.Equal(50_000_000, single.EffectiveHoldNs);              // half the interval
        var dbl = new AutoClickConfig { ClicksPerSecond = 10, HoldDurationMs = 500, ClickType = ClickType.Double };
        Assert.Equal(25_000_000, dbl.EffectiveHoldNs);                 // quarter for double clicks
        Assert.Equal(0, new AutoClickConfig { HoldDurationMs = -3 }.EffectiveHoldNs);
        Assert.Equal(15_000_000, new AutoClickConfig { ClicksPerSecond = 20, HoldDurationMs = 15 }.EffectiveHoldNs);
    }
}

public class AppSettingsTests
{
    [Fact]
    public void RoundTripsAndToleratesMissingOrBrokenFiles()
    {
        var dir = Directory.CreateTempSubdirectory("macrecord-tests");
        try
        {
            var path = Path.Combine(dir.FullName, "nested", "settings.json");
            Assert.Equal(0x75, AppSettings.Load(path).HotkeyVirtualKey);   // missing → defaults

            var settings = new AppSettings { MouseTrigger = MouseTrigger.XButton2, HotkeyVirtualKey = 0x70 };
            settings.AutoClick.ClicksPerSecond = 20;
            settings.AutoClick.Mode = TriggerMode.Hold;
            settings.Save(path);
            var loaded = AppSettings.Load(path);
            Assert.Equal(MouseTrigger.XButton2, loaded.MouseTrigger);
            Assert.Equal(0x70, loaded.HotkeyVirtualKey);
            Assert.Equal(20, loaded.AutoClick.ClicksPerSecond);
            Assert.Equal(TriggerMode.Hold, loaded.AutoClick.Mode);
            Assert.Contains("\"xButton2\"", File.ReadAllText(path));

            File.WriteAllText(path, "{ \"mouseTrigger\": \"middle\" }");     // older file: other fields default
            var partial = AppSettings.Load(path);
            Assert.Equal(MouseTrigger.Middle, partial.MouseTrigger);
            Assert.True(partial.CheckForUpdates);

            File.WriteAllText(path, "not json");
            Assert.Equal(MouseTrigger.None, AppSettings.Load(path).MouseTrigger);
        }
        finally
        {
            dir.Delete(recursive: true);
        }
    }
}

public class ReleaseVersionTests
{
    [Theory]
    [InlineData("v0.2.0", "0.1.0", true)]
    [InlineData("v0.1.0", "0.1.0", false)]
    [InlineData("v0.1", "0.1.0", false)]
    [InlineData("v1.0.0-beta", "0.9.9", true)]
    [InlineData("v0.1.0", "0.2.0", false)]
    [InlineData("garbage", "0.1.0", false)]
    [InlineData(null, "0.1.0", false)]
    [InlineData("v0.10.0", "0.9.0", true)]
    public void ComparesTags(string? latest, string current, bool newer)
    {
        Assert.Equal(newer, ReleaseVersion.IsNewer(latest, current));
    }
}
