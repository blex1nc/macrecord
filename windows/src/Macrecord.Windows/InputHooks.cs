using System.Runtime.InteropServices;
using Macrecord.Core;

namespace Macrecord.Windows;

/// <summary>
/// Global keyboard/mouse triggers via low-level hooks on a dedicated message-loop thread. The trigger key/button is
/// consumed (so F6 or Back/Forward don't also reach the game or browser); every other event passes untouched. The
/// mouse hook is installed only when a mouse trigger is set, and callbacks return within microseconds: a slow hook
/// stalls all input system-wide (and Windows silently removes hooks that exceed LowLevelHooksTimeout).
/// </summary>
internal sealed class InputHooks : IDisposable
{
    /// <summary>Raised on the hook thread: true on press, false on release. Handlers must be quick.</summary>
    public event Action<bool>? Trigger;

    private Thread? thread;
    private uint threadId;
    private Native.HookProc? keyboardProc;
    private Native.HookProc? mouseProc;
    private IntPtr keyboardHook;
    private IntPtr mouseHook;
    private int hotkey;
    private MouseTrigger mouseTrigger;
    private bool keyHeld;
    private bool buttonHeld;

    /// <summary>(Re)installs the hooks; false if Windows refused one of them.</summary>
    public bool Start(int hotkeyVirtualKey, MouseTrigger trigger)
    {
        Stop();
        hotkey = hotkeyVirtualKey;
        mouseTrigger = trigger;
        keyHeld = buttonHeld = false;
        var ok = false;
        using var ready = new ManualResetEventSlim();
        thread = new Thread(() =>
        {
            threadId = Native.GetCurrentThreadId();
            var module = Native.GetModuleHandle(null);
            keyboardProc = KeyboardCallback;
            keyboardHook = Native.SetWindowsHookEx(Native.WH_KEYBOARD_LL, keyboardProc, module, 0);
            if (trigger != MouseTrigger.None)
            {
                mouseProc = MouseCallback;
                mouseHook = Native.SetWindowsHookEx(Native.WH_MOUSE_LL, mouseProc, module, 0);
            }
            ok = keyboardHook != IntPtr.Zero && (trigger == MouseTrigger.None || mouseHook != IntPtr.Zero);
            ready.Set();
            while (Native.GetMessage(out _, IntPtr.Zero, 0, 0) > 0) { }
            if (keyboardHook != IntPtr.Zero) Native.UnhookWindowsHookEx(keyboardHook);
            if (mouseHook != IntPtr.Zero) Native.UnhookWindowsHookEx(mouseHook);
            keyboardHook = mouseHook = IntPtr.Zero;
        })
        {
            IsBackground = true,
            Priority = ThreadPriority.Highest,
            Name = "macrecord.hooks",
        };
        thread.Start();
        ready.Wait();
        return ok;
    }

    public void Stop()
    {
        if (thread is null) return;
        Native.PostThreadMessage(threadId, Native.WM_QUIT, IntPtr.Zero, IntPtr.Zero);
        thread.Join(1000);
        thread = null;
    }

    public void Dispose() => Stop();

    private IntPtr KeyboardCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            var data = Marshal.PtrToStructure<Native.KBDLLHOOKSTRUCT>(lParam);
            var injected = (data.flags & Native.LLKHF_INJECTED) != 0 || data.dwExtraInfo == Clicker.Tag;
            if (!injected && data.vkCode == hotkey)
            {
                var message = (int)wParam;
                var down = message is Native.WM_KEYDOWN or Native.WM_SYSKEYDOWN;
                if (down != keyHeld) // key repeat sends more key-downs while held
                {
                    keyHeld = down;
                    Trigger?.Invoke(down);
                }
                return 1;
            }
        }
        return Native.CallNextHookEx(IntPtr.Zero, nCode, wParam, lParam);
    }

    private IntPtr MouseCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            var message = (int)wParam;
            if (message is Native.WM_MBUTTONDOWN or Native.WM_MBUTTONUP or Native.WM_XBUTTONDOWN or Native.WM_XBUTTONUP)
            {
                var data = Marshal.PtrToStructure<Native.MSLLHOOKSTRUCT>(lParam);
                var injected = (data.flags & Native.LLMHF_INJECTED) != 0 || data.dwExtraInfo == Clicker.Tag;
                if (!injected && Matches(message, data.mouseData, out var down))
                {
                    if (down != buttonHeld)
                    {
                        buttonHeld = down;
                        Trigger?.Invoke(down);
                    }
                    return 1;
                }
            }
        }
        return Native.CallNextHookEx(IntPtr.Zero, nCode, wParam, lParam);
    }

    private bool Matches(int message, uint mouseData, out bool down)
    {
        down = message is Native.WM_MBUTTONDOWN or Native.WM_XBUTTONDOWN;
        var xButton = (mouseData >> 16) & 0xFFFF;
        return mouseTrigger switch
        {
            MouseTrigger.Middle => message is Native.WM_MBUTTONDOWN or Native.WM_MBUTTONUP,
            MouseTrigger.XButton1 => message is Native.WM_XBUTTONDOWN or Native.WM_XBUTTONUP && xButton == 1,
            MouseTrigger.XButton2 => message is Native.WM_XBUTTONDOWN or Native.WM_XBUTTONUP && xButton == 2,
            _ => false,
        };
    }
}
