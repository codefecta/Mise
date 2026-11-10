// Mise.exe - the launcher the desktop icon, the Start menu and the tray start.
// Starts the tray and the Mise window (PowerShell), then shows the start card: the B2 mark builds itself
// (counter, then the bowls drop in, then "Mise") and fades out as the Mise window fades in.
// Compiled once by install.ps1 with the .NET Framework csc (C# 5: no newer syntax here).
using System; using System.Diagnostics; using System.IO; using System.Threading; using System.Text.RegularExpressions;
using System.Drawing; using System.Drawing.Drawing2D; using System.Drawing.Text; using System.Windows.Forms; using System.Runtime.InteropServices;

class MiseLauncher {
  [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
  static void Run(string dir, string script) {
    ProcessStartInfo p = new ProcessStartInfo("powershell.exe", "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + Path.Combine(dir, script) + "\"");
    p.UseShellExecute = false; p.CreateNoWindow = true; Process.Start(p);
  }
  [STAThread] static void Main() {
    string dir = AppDomain.CurrentDomain.BaseDirectory;
    // the Mise window already open: just start it (it brings itself forward), no card
    bool homeOpen = false;
    try { Mutex m = Mutex.OpenExisting("Local\\MiseHome"); m.Close(); homeOpen = true; } catch { }
    EventWaitHandle shown = null;
    if (!homeOpen) { try { shown = new EventWaitHandle(false, EventResetMode.ManualReset, "Local\\MiseHomeShown"); shown.Reset(); } catch { shown = null; } }
    // both PowerShell processes start before the card, so the animation never delays loading
    Run(dir, "mise-tray.ps1"); Run(dir, "mise-home.ps1");
    if (homeOpen || shown == null) return;
    string txt = "";
    try { txt = File.ReadAllText(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Mise\\config.json")); } catch { return; }
    if (Regex.IsMatch(txt, "\"animations\"\\s*:\\s*false")) return;
    Color accent = Color.FromArgb(216, 137, 90);
    Match am = Regex.Match(txt, "\"accent\"\\s*:\\s*\"#([0-9A-Fa-f]{6})\"");
    if (am.Success) { try { accent = ColorTranslator.FromHtml("#" + am.Groups[1].Value); } catch { } }
    // the screen the Mise window opens on: where it was last dragged, else the main screen
    Screen scr = Screen.PrimaryScreen;
    Match hp = Regex.Match(txt, "\"homePos\"\\s*:\\s*\"(\\w+)\""), hx = Regex.Match(txt, "\"homeX\"\\s*:\\s*(-?\\d+)"), hy = Regex.Match(txt, "\"homeY\"\\s*:\\s*(-?\\d+)");
    if (hp.Success && hp.Groups[1].Value == "remember" && hx.Success && hy.Success) {
      int x = int.Parse(hx.Groups[1].Value), y = int.Parse(hy.Groups[1].Value);
      if (x >= 0 && y >= 0) { try { scr = Screen.FromPoint(new Point(x + 20, y + 20)); } catch { } }
    }
    try { SetProcessDPIAware(); } catch { }
    Application.EnableVisualStyles();
    Application.Run(new MiseStartCard(accent, scr, shown));
  }
}

class MiseStartCard : Form {
  [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int v, int size);
  static readonly Color CardC = Color.FromArgb(34, 34, 38), BorderC = Color.FromArgb(56, 56, 63), WordC = Color.FromArgb(238, 237, 234);
  Color accent; EventWaitHandle shown; Stopwatch clock = Stopwatch.StartNew(); System.Windows.Forms.Timer tick;
  float s = 1f; long fadeAt = -1; Font word;
  public MiseStartCard(Color accent, Screen scr, EventWaitHandle shown) {
    this.accent = accent; this.shown = shown;
    FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = false; TopMost = true; StartPosition = FormStartPosition.Manual;
    SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true);
    using (Graphics g = CreateGraphics()) { s = g.DpiX / 96f; }
    int w = (int)(176 * s), h = (int)(196 * s);
    Rectangle wa = scr.WorkingArea;
    Location = new Point(wa.X + (wa.Width - w) / 2, wa.Y + (wa.Height - h) / 2); Size = new Size(w, h);
    BackColor = CardC; Opacity = 0;
    word = new Font("Segoe UI Semibold", 13f);
    tick = new System.Windows.Forms.Timer(); tick.Interval = 15; tick.Tick += delegate { Step(); }; tick.Start();
  }
  // shown without taking focus from the window in front, no taskbar button
  protected override bool ShowWithoutActivation { get { return true; } }
  protected override CreateParams CreateParams { get { CreateParams cp = base.CreateParams; cp.ExStyle |= 0x08000000 | 0x80; return cp; } }
  protected override void OnLoad(EventArgs e) { try { int v = 2; DwmSetWindowAttribute(Handle, 33, ref v, 4); } catch { } base.OnLoad(e); }
  static float Ease(float k) { k = Math.Max(0f, Math.Min(1f, k)); float i = 1f - k; return 1f - i * i * i; }
  static float Span(long el, int a, int b) { return Math.Max(0f, Math.Min(1f, (el - a) / (float)(b - a))); }
  void Step() {
    long el = clock.ElapsedMilliseconds;
    if (fadeAt < 0) {
      Opacity = Ease(Span(el, 0, 170));
      bool ready = false; try { ready = shown.WaitOne(0); } catch { ready = true; }
      if ((el >= 1400 && ready) || el >= 8000) fadeAt = el;
    } else {
      float k = Span(el, (int)fadeAt, (int)fadeAt + 200);
      Opacity = 1f - Ease(k);
      if (k >= 1f) { tick.Stop(); Close(); Application.Exit(); return; }
    }
    Invalidate();
  }
  // a bowl drops 24 units from above, lands 2 units low and settles
  static float Drop(float k) {
    if (k <= 0f) return 24f;
    if (k < 0.75f) return 24f - 26f * Ease(k / 0.75f);
    return -2f + 2f * Ease((k - 0.75f) / 0.25f);
  }
  static GraphicsPath HalfDisc(float x1, float y, float r) { GraphicsPath p = new GraphicsPath(); p.AddArc(x1, y - r, 2 * r, 2 * r, 0, 180); p.CloseFigure(); return p; }
  static GraphicsPath RoundRect(float x, float y, float w, float h, float rad) {
    float d = rad * 2; GraphicsPath p = new GraphicsPath();
    p.AddArc(x, y, d, d, 180, 90); p.AddArc(x + w - d, y, d, d, 270, 90); p.AddArc(x + w - d, y + h - d, d, d, 0, 90); p.AddArc(x, y + h - d, d, d, 90, 90);
    p.CloseFigure(); return p;
  }
  protected override void OnPaint(PaintEventArgs pe) {
    Graphics g = pe.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias; g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
    g.Clear(CardC);
    using (Pen bp = new Pen(BorderC, 1f)) g.DrawRectangle(bp, 0, 0, Width - 1, Height - 1);
    long el = fadeAt >= 0 ? Math.Min(clock.ElapsedMilliseconds, 1400) : clock.ElapsedMilliseconds;
    // the mark without its tile, about 120 px wide (grid x 10..118), near the top of the card
    float k = 120f * s / 108f;
    GraphicsState st = g.Save();
    g.TranslateTransform(28f * s - 10f * k, 26f * s - 20f * k); g.ScaleTransform(k, k);
    float[] x1 = { 88.5f, 58f, 15f }; float[] yy = { 67.5f, 61f, 54f }; float[] rr = { 12.5f, 19f, 26f }; float[] baseA = { 0.5f, 0.74f, 1f };
    int[] start = { 600, 450, 300 };
    for (int i = 0; i < 3; i++) {
      float kk = Span(el, start[i], start[i] + 320); if (kk <= 0f) continue;
      float a = baseA[i] * Ease(Math.Min(1f, kk * 1.6f));
      float y = yy[i] - Drop(kk);
      using (GraphicsPath p = HalfDisc(x1[i], y, rr[i])) {
        if (i > 0) using (SolidBrush gb = new SolidBrush(CardC)) using (Pen gp = new Pen(CardC, 5f)) { gp.LineJoin = LineJoin.Round; g.FillPath(gb, p); g.DrawPath(gp, p); }
        using (SolidBrush b = new SolidBrush(Color.FromArgb((int)(255 * a), accent))) g.FillPath(b, p);
      }
    }
    float ck = Ease(Span(el, 150, 450));
    if (ck > 0.01f) {
      using (GraphicsPath c = RoundRect(10f, 81f, Math.Max(7f, 108f * ck), 7f, 3.5f)) {
        using (SolidBrush gb = new SolidBrush(CardC)) using (Pen gp = new Pen(CardC, 5f)) { gp.LineJoin = LineJoin.Round; g.FillPath(gb, c); g.DrawPath(gp, c); }
        using (SolidBrush cb = new SolidBrush(Color.FromArgb(128, accent))) g.FillPath(cb, c);
      }
    }
    g.Restore(st);
    // "Mise" fades in while rising 4 px
    float wk = Ease(Span(el, 750, 1050));
    if (wk > 0.01f) {
      StringFormat sf = new StringFormat(); sf.Alignment = StringAlignment.Center;
      using (SolidBrush wb = new SolidBrush(Color.FromArgb((int)(255 * wk), WordC))) g.DrawString("Mise", word, wb, new RectangleF(0, 140f * s + 4f * s * (1f - wk), Width, 40f * s), sf);
    }
  }
  protected override void Dispose(bool disposing) { if (disposing) { if (tick != null) tick.Dispose(); if (word != null) word.Dispose(); } base.Dispose(disposing); }
}
