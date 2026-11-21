using System.Diagnostics;
using System.Runtime.InteropServices;
using Macrecord.Core;

namespace Macrecord.Windows;

/// <summary>
/// High-rate clicker on its own thread. Schedules on absolute deadlines so the rate never drifts; sleeps on a
/// high-resolution waitable timer and spins the last fraction of a millisecond. With the cursor target it sends button
/// events without a MOVE flag, so the cursor (and a game's camera) is never pushed around.
/// </summary>
internal sealed class Clicker
{
    /// <summary>Marks our own input so the hooks ignore it ("macrec").</summary>
    public static readonly IntPtr Tag = new(0x6D6163726563);

    private static readonly int InputSize = Marshal.SizeOf<Native.INPUT>();
    private static readonly long SpinTicks = NsToTicks(600_000);
    private static readonly long SliceTicks = NsToTicks(20_000_000);
    private static readonly long ResyncTicks = NsToTicks(50_000_000);

    private readonly object gate = new();
    private volatile bool running;
    private int clicks;
    private int generation;

    /// <summary>Raised on the clicker thread when a session ends (limit reached or <see cref="Stop"/>).</summary>
    public event Action? Finished;

    public bool IsRunning => running;
    public int ClickCount => Volatile.Read(ref clicks);

    public void Start(AutoClickConfig config)
    {
        lock (gate)
        {
            if (running) return;
            running = true;
            Volatile.Write(ref clicks, 0);
            var session = ++generation;
            var snapshot = config.Clone();
            new Thread(() => Run(snapshot, session))
            {
                IsBackground = true,
                Priority = ThreadPriority.Highest,
                Name = "macrecord.clicker",
            }.Start();
        }
    }

    public void Stop() => running = false;

    private void Run(AutoClickConfig config, int session)
    {
        Native.timeBeginPeriod(1);
        var timer = Native.CreateWaitableTimerExW(IntPtr.Zero, null, Native.CREATE_WAITABLE_TIMER_HIGH_RESOLUTION,
                                                  Native.TIMER_ALL_ACCESS);
        try
        {
            var random = Random.Shared;
            var (down, up) = Flags(config.Button);
            var hold = NsToTicks(config.EffectiveHoldNs);
            var perAction = config.ClickType == ClickType.Double ? 2 : 1;
            var start = Stopwatch.GetTimestamp();
            var target = start;

            while (Active(session))
            {
                if (config.Limit == LimitKind.Clicks && ClickCount >= config.LimitClicks) break;
                if (config.Limit == LimitKind.Seconds && Stopwatch.GetElapsedTime(start).TotalSeconds >= config.LimitSeconds) break;
                if (!WaitUntil(target, timer, session)) break;

                var point = Position(config, random);
                for (var i = 0; i < perAction; i++)
                {
                    Send(down, point);
                    // The release is always sent, even if Stop() arrives during the hold.
                    if (hold > 0) WaitUntil(Stopwatch.GetTimestamp() + hold, timer, session: null);
                    Send(up, point);
                }
                Interlocked.Increment(ref clicks);

                var jitter = config.TimingJitter > 0 ? random.NextDouble() * 2 - 1 : 0;
                target += NsToTicks(config.JitteredIntervalNs(jitter));
                // Far behind after a system stall: resync instead of bursting to catch up.
                var now = Stopwatch.GetTimestamp();
                if (now > target + ResyncTicks) target = now;
            }
        }
        finally
        {
            bool current;
            lock (gate)
            {
                current = session == generation;
                if (current) running = false;
            }
            if (timer != IntPtr.Zero) Native.CloseHandle(timer);
            Native.timeEndPeriod(1);
            if (current) Finished?.Invoke();
        }
    }

    /// <summary>
    /// True while <paramref name="session"/> is the current one and not stopped. A Stop() followed by a quick Start()
    /// must not revive the previous session's thread, so the flag alone is not enough.
    /// </summary>
    private bool Active(int session) => running && Volatile.Read(ref generation) == session;

    /// <summary>Waits until <paramref name="deadline"/> (Stopwatch ticks); false if <paramref name="session"/> ended
    /// first. A null session waits unconditionally (used for the hold, so the release is always sent).</summary>
    private bool WaitUntil(long deadline, IntPtr timer, int? session)
    {
        while (true)
        {
            if (session is { } s && !Active(s)) return false;
            var remaining = deadline - Stopwatch.GetTimestamp();
            if (remaining <= 0) return true;
            if (remaining > SpinTicks)
            {
                var sleep = Math.Min(remaining - SpinTicks, SliceTicks);
                if (timer != IntPtr.Zero)
                {
                    long due = -Math.Max(1, sleep * 10_000_000 / Stopwatch.Frequency); // relative, 100 ns units
                    if (Native.SetWaitableTimer(timer, ref due, 0, IntPtr.Zero, IntPtr.Zero, false))
                    {
                        Native.WaitForSingleObject(timer, Native.INFINITE);
                        continue;
                    }
                }
                Thread.Sleep(1);
            }
            else
            {
                Thread.SpinWait(20);
            }
        }
    }

    /// <summary>Null means "where the cursor is", without moving it.</summary>
    private static Native.POINT? Position(AutoClickConfig config, Random random)
    {
        Native.POINT point;
        if (config.Target == TargetKind.Fixed)
        {
            point = new Native.POINT { X = config.FixedX, Y = config.FixedY };
        }
        else
        {
            if (config.PositionJitter <= 0) return null;
            Native.GetCursorPos(out point);
        }
        if (config.PositionJitter > 0)
        {
            var angle = random.NextDouble() * 2 * Math.PI;
            var radius = config.PositionJitter * Math.Sqrt(random.NextDouble());
            point.X += (int)Math.Round(radius * Math.Cos(angle));
            point.Y += (int)Math.Round(radius * Math.Sin(angle));
        }
        return point;
    }

    private static void Send(uint buttonFlags, Native.POINT? point)
    {
        var mouse = new Native.MOUSEINPUT { dwFlags = buttonFlags, dwExtraInfo = Tag };
        if (point is { } p)
        {
            var left = Native.GetSystemMetrics(Native.SM_XVIRTUALSCREEN);
            var top = Native.GetSystemMetrics(Native.SM_YVIRTUALSCREEN);
            var width = Math.Max(Native.GetSystemMetrics(Native.SM_CXVIRTUALSCREEN) - 1, 1);
            var height = Math.Max(Native.GetSystemMetrics(Native.SM_CYVIRTUALSCREEN) - 1, 1);
            mouse.dx = (int)Math.Round((p.X - left) * 65535.0 / width);
            mouse.dy = (int)Math.Round((p.Y - top) * 65535.0 / height);
            mouse.dwFlags |= Native.MOUSEEVENTF_MOVE | Native.MOUSEEVENTF_ABSOLUTE | Native.MOUSEEVENTF_VIRTUALDESK;
        }
        var input = new Native.INPUT { type = Native.INPUT_MOUSE, u = new Native.InputUnion { mi = mouse } };
        Native.SendInput(1, [input], InputSize);
    }

    private static (uint Down, uint Up) Flags(ClickButton button) => button switch
    {
        ClickButton.Right => (Native.MOUSEEVENTF_RIGHTDOWN, Native.MOUSEEVENTF_RIGHTUP),
        ClickButton.Middle => (Native.MOUSEEVENTF_MIDDLEDOWN, Native.MOUSEEVENTF_MIDDLEUP),
        _ => (Native.MOUSEEVENTF_LEFTDOWN, Native.MOUSEEVENTF_LEFTUP),
    };

    private static long NsToTicks(long ns) => (long)(ns * (double)Stopwatch.Frequency / 1_000_000_000);
}
