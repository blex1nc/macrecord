using Macrecord.Core;

namespace Macrecord.Windows;

/// <summary>The autoclicker window: settings, trigger assignment, start/stop and update notice.</summary>
internal sealed class MainForm : Form
{
    private static readonly string[] FunctionKeys = Enumerable.Range(1, 12).Select(i => $"F{i}").ToArray();
    private const int VkF1 = 0x70;

    private readonly AppSettings settings = AppSettings.Load(AppSettings.DefaultPath);
    private readonly Clicker clicker = new();
    private readonly InputHooks hooks = new();
    private readonly System.Windows.Forms.Timer ticker = new() { Interval = 100 };
    private readonly Label status = new() { AutoSize = true, Margin = new Padding(3, 8, 3, 3) };
    private readonly Button startStop = new() { AutoSize = true, Text = "Başlat (3 sn sonra)" };
    private readonly LinkLabel updateLink = new() { AutoSize = true, Visible = false, Margin = new Padding(3, 8, 3, 3) };
    private readonly object triggerGate = new();
    private UpdateChecker.Update? pendingUpdate;
    private bool countingDown;

    public MainForm()
    {
        Text = $"macrecord {UpdateChecker.CurrentVersion}";
        FormBorderStyle = FormBorderStyle.FixedSingle;
        MaximizeBox = false;
        AutoSize = true;
        AutoSizeMode = AutoSizeMode.GrowAndShrink;
        Padding = new Padding(12);
        Font = new Font("Segoe UI", 9f);
        StartPosition = FormStartPosition.CenterScreen;

        var config = settings.AutoClick;
        var grid = new TableLayoutPanel { ColumnCount = 2, AutoSize = true, Dock = DockStyle.Fill };
        void Row(string label, Control control)
        {
            grid.Controls.Add(new Label { Text = label, AutoSize = true, Anchor = AnchorStyles.Left, Margin = new Padding(3, 7, 16, 3) });
            grid.Controls.Add(control);
        }

        Row("Saniyede tık (CPS)", Number(0.1m, 2000m, 1, config.ClicksPerSecond, v => config.ClicksPerSecond = v));
        Row("Tuş", Choice(["Sol", "Sağ", "Orta"], (int)config.Button, i => config.Button = (ClickButton)i));
        Row("Tıklama türü", Choice(["Tek", "Çift"], (int)config.ClickType, i => config.ClickType = (ClickType)i));
        Row("Mod", Choice(["Aç / kapa", "Basılı tut"], (int)config.Mode, i => config.Mode = (TriggerMode)i));
        Row("Basılı tutma (ms)", Number(0, 1000, 0, config.HoldDurationMs, v => config.HoldDurationMs = v));
        Row("Zaman rastgeleliği (%)", Number(0, 50, 0, config.TimingJitter * 100, v => config.TimingJitter = v / 100));
        Row("Konum rastgeleliği (px)", Number(0, 30, 0, config.PositionJitter, v => config.PositionJitter = v));

        // Position: cursor (never moved) or a fixed screen point.
        var x = Number(-100_000, 100_000, 0, config.FixedX, v => config.FixedX = (int)v);
        var y = Number(-100_000, 100_000, 0, config.FixedY, v => config.FixedY = (int)v);
        var pick = new Button { Text = "Konumu al (3 sn)", AutoSize = true };
        pick.Click += async (_, _) =>
        {
            pick.Enabled = false;
            for (var i = 3; i > 0; i--)
            {
                pick.Text = $"İmleci götür… {i}";
                await Task.Delay(1000);
            }
            Native.GetCursorPos(out var p);
            x.Value = Math.Clamp(p.X, (int)x.Minimum, (int)x.Maximum);
            y.Value = Math.Clamp(p.Y, (int)y.Minimum, (int)y.Maximum);
            pick.Text = "Konumu al (3 sn)";
            pick.Enabled = true;
        };
        var point = Flow(new Label { Text = "X", AutoSize = true, Margin = new Padding(3, 7, 3, 3) }, x,
                         new Label { Text = "Y", AutoSize = true, Margin = new Padding(3, 7, 3, 3) }, y, pick);
        point.Enabled = config.Target == TargetKind.Fixed;
        Row("Konum", Choice(["İmleç", "Sabit nokta"], (int)config.Target, i =>
        {
            config.Target = (TargetKind)i;
            point.Enabled = config.Target == TargetKind.Fixed;
        }));
        Row("", point);

        // Limit: the number means clicks or seconds depending on the kind.
        var limitValue = new NumericUpDown { Minimum = 1, Maximum = 1_000_000, Width = 90 };
        void ShowLimit()
        {
            limitValue.Enabled = config.Limit != LimitKind.None;
            limitValue.DecimalPlaces = config.Limit == LimitKind.Seconds ? 1 : 0;
            var value = config.Limit == LimitKind.Seconds ? (decimal)config.LimitSeconds : config.LimitClicks;
            limitValue.Value = Math.Clamp(value, limitValue.Minimum, limitValue.Maximum);
        }
        ShowLimit();
        limitValue.ValueChanged += (_, _) =>
        {
            if (config.Limit == LimitKind.Seconds) config.LimitSeconds = (double)limitValue.Value;
            else if (config.Limit == LimitKind.Clicks) config.LimitClicks = (int)limitValue.Value;
            Save();
        };
        Row("Durdur", Flow(Choice(["Hiçbir zaman", "Tık sayısında", "Saniye sonra"], (int)config.Limit, i =>
        {
            config.Limit = (LimitKind)i;
            ShowLimit();
        }), limitValue));

        // Triggers.
        var keyIndex = Math.Clamp(settings.HotkeyVirtualKey - VkF1, 0, FunctionKeys.Length - 1);
        Row("Klavye kısayolu", Choice(FunctionKeys, keyIndex, i =>
        {
            settings.HotkeyVirtualKey = VkF1 + i;
            InstallHooks();
        }));
        Row("Fare tuşu", Choice(["Yok", "Orta tuş", "Yan tuş 1 (geri)", "Yan tuş 2 (ileri)"], (int)settings.MouseTrigger, i =>
        {
            settings.MouseTrigger = (MouseTrigger)i;
            InstallHooks();
        }));
        grid.Controls.Add(new Label
        {
            Text = "Atanan tuş yalnızca autoclicker'ı kontrol eder.\nRoblox gibi oyunlarda imleç hedefini kullan.",
            AutoSize = true,
            ForeColor = SystemColors.GrayText,
            Margin = new Padding(3, 4, 3, 6),
        });
        grid.SetColumnSpan(grid.Controls[^1], 2);

        var updates = new CheckBox { Text = "Güncellemeleri otomatik denetle", AutoSize = true, Checked = settings.CheckForUpdates };
        updates.CheckedChanged += (_, _) =>
        {
            settings.CheckForUpdates = updates.Checked;
            Save();
        };
        grid.Controls.Add(updates);
        grid.SetColumnSpan(updates, 2);

        startStop.Click += async (_, _) => await ToggleFromButton();
        grid.Controls.Add(startStop);
        grid.Controls.Add(status);
        updateLink.LinkClicked += async (_, _) => await ApplyUpdate();
        grid.Controls.Add(updateLink);
        grid.SetColumnSpan(updateLink, 2);
        Controls.Add(grid);

        hooks.Trigger += OnTrigger;
        ticker.Tick += (_, _) => RefreshStatus();
        ticker.Start();
        InstallHooks();
        RefreshStatus();
        Shown += async (_, _) => await CheckForUpdates();
        FormClosing += (_, _) =>
        {
            clicker.Stop();
            hooks.Dispose();
            ticker.Stop();
            Save();
        };
    }

    // MARK: Clicking

    /// <summary>Hook thread: must return quickly. Start/Stop only flip a flag or start a thread.</summary>
    private void OnTrigger(bool pressed)
    {
        lock (triggerGate)
        {
            if (settings.AutoClick.Mode == TriggerMode.Hold)
            {
                if (pressed) clicker.Start(settings.AutoClick);
                else clicker.Stop();
            }
            else if (pressed)
            {
                if (clicker.IsRunning) clicker.Stop();
                else clicker.Start(settings.AutoClick);
            }
        }
    }

    /// <summary>With the cursor target the button itself would be clicked, so give time to move away.</summary>
    private async Task ToggleFromButton()
    {
        if (clicker.IsRunning || countingDown)
        {
            countingDown = false;
            clicker.Stop();
            return;
        }
        countingDown = true;
        for (var i = 3; i > 0 && countingDown; i--)
        {
            startStop.Text = $"Başlıyor… {i} (iptal)";
            await Task.Delay(1000);
        }
        if (!countingDown) return;
        countingDown = false;
        clicker.Start(settings.AutoClick);
    }

    private void RefreshStatus()
    {
        var key = FunctionKeys[Math.Clamp(settings.HotkeyVirtualKey - VkF1, 0, FunctionKeys.Length - 1)];
        if (clicker.IsRunning)
        {
            status.Text = $"Tıklıyor… {clicker.ClickCount}";
            startStop.Text = "Durdur";
        }
        else if (!countingDown)
        {
            status.Text = $"Hazır — {key} ile başlat/durdur";
            startStop.Text = "Başlat (3 sn sonra)";
        }
    }

    private void InstallHooks()
    {
        Save();
        if (!hooks.Start(settings.HotkeyVirtualKey, settings.MouseTrigger))
        {
            MessageBox.Show(this, "Klavye/fare kısayolu kurulamadı. Uygulamayı yeniden başlatmayı dene.", "macrecord");
        }
    }

    // MARK: Updates

    private async Task CheckForUpdates()
    {
        if (!settings.CheckForUpdates) return;
        try
        {
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(30));
            pendingUpdate = await UpdateChecker.CheckAsync(timeout.Token);
            settings.LastUpdateCheck = DateTimeOffset.Now;
            Save();
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException or System.Text.Json.JsonException)
        {
            return; // offline or rate-limited: try again next launch
        }
        if (pendingUpdate is null) return;
        updateLink.Text = $"Yeni sürüm {pendingUpdate.Tag} hazır — güncellemek için tıkla";
        updateLink.Visible = true;
    }

    private async Task ApplyUpdate()
    {
        if (pendingUpdate is null) return;
        clicker.Stop();
        updateLink.Enabled = false;
        updateLink.Text = "İndiriliyor…";
        try
        {
            using var timeout = new CancellationTokenSource(TimeSpan.FromMinutes(5));
            await UpdateChecker.ApplyAsync(pendingUpdate, timeout.Token);
            Close();
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException or IOException
                                      or UnauthorizedAccessException or InvalidOperationException)
        {
            updateLink.Enabled = true;
            updateLink.Text = "Otomatik güncelleme olmadı — indirme sayfasını aç";
            pendingUpdate = null;
            updateLink.LinkClicked += (_, _) => UpdateChecker.OpenReleasesPage();
        }
    }

    // MARK: Helpers

    private void Save()
    {
        try
        {
            settings.Save(AppSettings.DefaultPath);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
    }

    private NumericUpDown Number(decimal min, decimal max, int decimals, double value, Action<double> apply)
    {
        var control = new NumericUpDown { Minimum = min, Maximum = max, DecimalPlaces = decimals, Width = 90 };
        control.Value = Math.Clamp((decimal)value, min, max);
        control.ValueChanged += (_, _) =>
        {
            apply((double)control.Value);
            Save();
        };
        return control;
    }

    private ComboBox Choice(string[] items, int selected, Action<int> apply)
    {
        var control = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 160 };
        control.Items.AddRange(items);
        control.SelectedIndex = Math.Clamp(selected, 0, items.Length - 1);
        control.SelectedIndexChanged += (_, _) =>
        {
            apply(control.SelectedIndex);
            Save();
        };
        return control;
    }

    private static FlowLayoutPanel Flow(params Control[] controls)
    {
        var panel = new FlowLayoutPanel { AutoSize = true, WrapContents = false, Margin = Padding.Empty };
        panel.Controls.AddRange(controls);
        return panel;
    }
}
