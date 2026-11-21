namespace Macrecord.Core;

public enum ClickButton { Left, Right, Middle }
public enum ClickType { Single, Double }
public enum TriggerMode { Toggle, Hold }
public enum TargetKind { Cursor, Fixed }
public enum LimitKind { None, Clicks, Seconds }

/// <summary>Autoclicker settings; same fields and rules as the macOS AutoClickConfig.</summary>
public sealed class AutoClickConfig
{
    public const double MinCps = 0.1;
    public const double MaxCps = 2000;

    public double ClicksPerSecond { get; set; } = 10;
    public ClickButton Button { get; set; } = ClickButton.Left;
    public ClickType ClickType { get; set; } = ClickType.Single;
    public TargetKind Target { get; set; } = TargetKind.Cursor;
    /// <summary>Screen pixels, used when <see cref="Target"/> is Fixed.</summary>
    public int FixedX { get; set; }
    public int FixedY { get; set; }
    /// <summary>Random timing variation as a fraction of the interval (0...0.9).</summary>
    public double TimingJitter { get; set; }
    /// <summary>Random position variation radius in pixels.</summary>
    public double PositionJitter { get; set; }
    /// <summary>Time the button stays down per click.</summary>
    public double HoldDurationMs { get; set; }
    public LimitKind Limit { get; set; } = LimitKind.None;
    public int LimitClicks { get; set; } = 100;
    public double LimitSeconds { get; set; } = 10;
    public TriggerMode Mode { get; set; } = TriggerMode.Toggle;

    /// <summary>Snapshot for the clicker thread, so edits in the UI never change a running session.</summary>
    public AutoClickConfig Clone() => (AutoClickConfig)MemberwiseClone();

    public long IntervalNs => (long)(1_000_000_000 / Math.Clamp(ClicksPerSecond, MinCps, MaxCps));

    /// <summary>Interval for one click, applying jitter from <paramref name="random"/> in [-1, 1].</summary>
    public long JitteredIntervalNs(double random)
    {
        var jitter = Math.Clamp(TimingJitter, 0, 0.9);
        var factor = 1 + jitter * Math.Clamp(random, -1, 1);
        return (long)(IntervalNs * factor);
    }

    /// <summary>Hold time is capped so a click never overlaps the next one.</summary>
    public long EffectiveHoldNs
    {
        get
        {
            var hold = (long)(Math.Max(HoldDurationMs, 0) * 1_000_000);
            var maxHold = IntervalNs / (ClickType == ClickType.Double ? 4 : 2);
            return Math.Min(hold, maxHold);
        }
    }
}
