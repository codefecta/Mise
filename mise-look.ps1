# Mise (shared edition) - look: graphite theme with the user's accent colour, the custom button, animations, friendly progress text.
# Dot-sourced by mise-ui.ps1 (after mise-core.ps1).
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class MiseUi {
  [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int v, int size);
  [DllImport("user32.dll")] public static extern bool ReleaseCapture();
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, int m, int w, int l);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
}
"@

# Mise windows run inside powershell.exe: without this the taskbar shows them as PowerShell with its icon.
# Each window gets Mise's own app id, icon and name (the taskbar groups them as Mise).
try {
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class MiseAppId {
  [StructLayout(LayoutKind.Sequential)] public struct PROPERTYKEY { public Guid fmtid; public uint pid; public PROPERTYKEY(Guid g, uint p) { fmtid = g; pid = p; } }
  [StructLayout(LayoutKind.Explicit)] public struct PROPVARIANT { [FieldOffset(0)] public ushort vt; [FieldOffset(8)] public IntPtr p; [FieldOffset(16)] public IntPtr pad; }
  [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IPropertyStore {
    [PreserveSig] int GetCount(out uint c); [PreserveSig] int GetAt(uint i, out PROPERTYKEY k);
    [PreserveSig] int GetValue(ref PROPERTYKEY k, out PROPVARIANT v); [PreserveSig] int SetValue(ref PROPERTYKEY k, ref PROPVARIANT v); [PreserveSig] int Commit();
  }
  [DllImport("shell32.dll")] static extern int SHGetPropertyStoreForWindow(IntPtr hwnd, ref Guid iid, [MarshalAs(UnmanagedType.Interface)] out IPropertyStore store);
  [DllImport("ole32.dll")] static extern int PropVariantClear(ref PROPVARIANT v);
  static readonly Guid Fmt = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");
  static void Put(IPropertyStore st, uint pid, string val) {
    PROPERTYKEY k = new PROPERTYKEY(Fmt, pid); PROPVARIANT v = new PROPVARIANT(); v.vt = 31; v.p = Marshal.StringToCoTaskMemUni(val);
    try { st.SetValue(ref k, ref v); } finally { PropVariantClear(ref v); }
  }
  // 5 = app id, 2 = relaunch command, 3 = relaunch icon, 4 = relaunch name (the name and icon the taskbar shows)
  public static void Set(IntPtr hwnd, string appId, string icon, string command, string name) {
    Guid iid = new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"); IPropertyStore st;
    if (SHGetPropertyStoreForWindow(hwnd, ref iid, out st) != 0 || st == null) return;
    try {
      if (!string.IsNullOrEmpty(command)) { Put(st, 2, command); Put(st, 3, icon); Put(st, 4, name); }
      Put(st, 5, appId); st.Commit();
    } finally { Marshal.ReleaseComObject(st); }
  }
}
'@
} catch {}
function Set-MiseAppId($f) {
  $f.Add_HandleCreated({ param($s, $e)
    try {
      $exe = Join-Path $script:MiseDir 'Mise.exe'
      if (Test-Path -LiteralPath $exe) { [MiseAppId]::Set($s.Handle, 'Codefecta.Mise', "$exe,0", "`"$exe`"", 'Mise') }
      else { [MiseAppId]::Set($s.Handle, 'Codefecta.Mise', "$(Join-Path $script:MiseDir 'mise.ico'),0", 'powershell.exe -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $script:MiseDir 'mise-home.ps1') + '"', 'Mise') }
    } catch {} })
}

# ---------- colours ----------
$script:AccentChoices = [ordered]@{ Copper = '#D8895A'; Amber = '#E0A43C'; Sage = '#8DB58A'; Teal = '#4FB3A9'; Sky = '#5FA8E8'; Iris = '#8E8CE6'; Rose = '#E07A93'; Silver = '#B8B8BE' }
function ConvertTo-Color([string]$hex) {
  try { $h = $hex.TrimStart('#'); return [Drawing.Color]::FromArgb([Convert]::ToInt32($h.Substring(0, 2), 16), [Convert]::ToInt32($h.Substring(2, 2), 16), [Convert]::ToInt32($h.Substring(4, 2), 16)) }
  catch { return [Drawing.Color]::FromArgb(216, 137, 90) }
}
# looks: Ember is the solid graphite one; the glass looks paint a backdrop and use see-through panels over it.
# The logo stays copper in every look. Opaque colours (menus, text fields) are the glass colour over the backdrop.
$script:LogoCopper = [Drawing.Color]::FromArgb(216, 137, 90)
$script:Themes = [ordered]@{
  ember      = @{ Name = 'Ember';          Bg = '#17171A'; Panel = '#212125'; Hover = '#2D2D33'; Line = '#38383F'; Text = '#EEEDEA'; Muted = '#8A8884'; Glass = $false }
  midnight   = @{ Name = 'Midnight Glass'; Bg = '#0E1324'; Panel = '#182038'; Hover = '#222C48'; Line = '#2C3858'; Text = '#E8ECF6'; Muted = '#8D97B3'; Glass = $true }
  aurora     = @{ Name = 'Aurora';         Bg = '#0C1220'; Panel = '#172030'; Hover = '#212C3E'; Line = '#243044'; Text = '#E6EEF2'; Muted = '#93A3B8'; Glass = $true }
  emberglass = @{ Name = 'Ember Glass';    Bg = '#161113'; Panel = '#231B1A'; Hover = '#2E2423'; Line = '#3A2C26'; Text = '#F0E9E4'; Muted = '#A8968C'; Glass = $true }
  deepsea    = @{ Name = 'Deep Sea';       Bg = '#07161C'; Panel = '#0F2630'; Hover = '#17323D'; Line = '#1E4450'; Text = '#E4F1F3'; Muted = '#86A9B3'; Glass = $true }
  nebula     = @{ Name = 'Nebula';         Bg = '#110B1C'; Panel = '#1D1530'; Hover = '#281D3E'; Line = '#3A2850'; Text = '#EFE8F6'; Muted = '#A596C2'; Glass = $true }
}
function Get-MiseTheme($cfg) { $t = "$(Get-MiseSetting $cfg 'theme')".ToLower(); if (-not $script:Themes.Contains($t)) { $t = 'ember' }; return $t }
function Update-MiseLook($cfg) {
  $tk = Get-MiseTheme $cfg; $th = $script:Themes[$tk]
  $script:C = @{
    Bg = (ConvertTo-Color $th.Bg); Panel = (ConvertTo-Color $th.Panel); Hover = (ConvertTo-Color $th.Hover)
    Line = (ConvertTo-Color $th.Line); Accent = (ConvertTo-Color "$(Get-MiseSetting $cfg 'accent')")
    Text = (ConvertTo-Color $th.Text); Muted = (ConvertTo-Color $th.Muted); Theme = $tk; Glass = [bool]$th.Glass
  }
  if ($tk -eq 'ember') { $script:C.Bg = [Drawing.Color]::FromArgb(23, 23, 26); $script:C.Panel = [Drawing.Color]::FromArgb(33, 33, 37); $script:C.Hover = [Drawing.Color]::FromArgb(45, 45, 51) }
  # the see-through colours buttons use in the glass looks (white over the backdrop); Ember keeps its solid ones
  if ($th.Glass) {
    $script:C.GPanel = [Drawing.Color]::FromArgb(15, 255, 255, 255); $script:C.GHover = [Drawing.Color]::FromArgb(27, 255, 255, 255); $script:C.GLine = [Drawing.Color]::FromArgb(34, 255, 255, 255)
    $script:C.Surface = [Drawing.Color]::Transparent
  } else { $script:C.GPanel = $script:C.Panel; $script:C.GHover = $script:C.Hover; $script:C.GLine = $script:C.Line; $script:C.Surface = $script:C.Bg }
  $script:Animate = [bool](Get-MiseSetting $cfg 'animations')
  try { [MiseBtn]::Animate = $script:Animate; [MiseLogo]::Animate = $script:Animate; [MiseBtn]::Radius = $(if ($th.Glass) { 12 } else { 9 }) } catch {}
}
$script:fTitle = New-Object Drawing.Font('Segoe UI Semibold', 17)
$script:fBig   = New-Object Drawing.Font('Segoe UI Semibold', 11.5)
$script:fBtn   = New-Object Drawing.Font('Segoe UI Semibold', 9.5)
$script:fNorm  = New-Object Drawing.Font('Segoe UI', 9)
$script:fSmall = New-Object Drawing.Font('Segoe UI', 9)
$script:fTiny  = New-Object Drawing.Font('Segoe UI Semibold', 8)
$script:fStatus = New-Object Drawing.Font('Segoe UI', 10)

# ---------- the custom controls: button (hover, press, click flash, sliding switch and two-choice), logo, caret ----------
# all motion is drawn in compiled C#, timed by a Stopwatch, and stops when nothing moves (spec B2, 10 Nov 2026)
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System; using System.Drawing; using System.Drawing.Drawing2D; using System.Drawing.Imaging; using System.Drawing.Text; using System.Windows.Forms; using System.Diagnostics; using System.Collections.Generic; using System.Reflection;
// one eased value over time (driven by a Stopwatch, never by the timer's tick count)
public class MiseTween {
  public float From, To; public long Start; public int Dur;
  public MiseTween(float v) { From = v; To = v; Start = 0; Dur = 0; }
  public static float Ease(float k) { k = Math.Max(0f, Math.Min(1f, k)); float i = 1f - k; return 1f - i * i * i; }
  // a small overshoot at the end (the switch knob springs into place)
  public static float Spring(float k) { k = Math.Max(0f, Math.Min(1f, k)); float c1 = 1.5f, c3 = c1 + 1f, m = k - 1f; return 1f + c3 * m * m * m + c1 * m * m; }
  public float At(long now) { if (Dur <= 0) return To; float k = (now - Start) / (float)Dur; if (k >= 1f) return To; return From + (To - From) * Ease(k); }
  public float AtSpring(long now) { if (Dur <= 0) return To; float k = (now - Start) / (float)Dur; if (k >= 1f) return To; return From + (To - From) * Spring(k); }
  public bool Running(long now) { return Dur > 0 && now - Start < Dur; }
  public void Go(long now, float to, int dur, bool animate) { From = At(now); To = to; Start = now; Dur = animate ? dur : 0; }
}

// ---------- glass looks: a painted backdrop behind the window, translucent panels over it ----------
// WinForms has no real blur: the backdrop (gradient, soft glows, stars or a current line) is one bitmap as the form's
// background image; buttons and panels with a see-through colour show it through their fill.
public static class MiseGlass {
  public static bool IsGlass(string theme) { return theme == "midnight" || theme == "aurora" || theme == "emberglass" || theme == "deepsea" || theme == "nebula"; }
  static Color H(int rgb, int a) { return Color.FromArgb(a, (rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255); }
  // a radial wash: c0 in the middle, c1 from 'reach' of the radius outward (CSS: radial-gradient(rx ry at cx cy, c0, c1 reach))
  static void Radial(Graphics g, int w, int h, float cx, float cy, float rx, float ry, Color[] cols, float[] pos) {
    float x = cx * w, y = cy * h, a = rx * w, b = ry * h;
    using (GraphicsPath p = new GraphicsPath()) {
      p.AddEllipse(x - a, y - b, 2 * a, 2 * b);
      using (PathGradientBrush br = new PathGradientBrush(p)) {
        br.CenterPoint = new PointF(x, y);
        ColorBlend cb = new ColorBlend(cols.Length); cb.Colors = cols; cb.Positions = pos; br.InterpolationColors = cb;
        g.FillPath(br, p);
      }
    }
  }
  // a soft glow: full colour in the middle, gone at its edge
  static void Orb(Graphics g, int w, int h, float cx, float cy, float r, Color c) {
    float rr = r * (float)Math.Sqrt(w * (double)h) / 324f; float x = cx * w, y = cy * h;
    if (rr < 2f) return;
    using (GraphicsPath p = new GraphicsPath()) {
      p.AddEllipse(x - rr, y - rr, 2 * rr, 2 * rr);
      using (PathGradientBrush br = new PathGradientBrush(p)) {
        br.CenterPoint = new PointF(x, y);
        ColorBlend cb = new ColorBlend(3);
        cb.Colors = new Color[] { Color.FromArgb(0, c), Color.FromArgb(c.A / 3, c), c }; cb.Positions = new float[] { 0f, 0.45f, 1f };
        br.InterpolationColors = cb; g.FillPath(br, p);
      }
    }
  }
  static void Linear(Graphics g, int w, int h, float angle, Color[] cols, float[] pos) {
    g.Clear(cols[cols.Length - 1]);
    Rectangle r = new Rectangle(0, 0, Math.Max(1, w), Math.Max(1, h));
    using (LinearGradientBrush br = new LinearGradientBrush(r, cols[0], cols[cols.Length - 1], angle)) {
      ColorBlend cb = new ColorBlend(cols.Length); cb.Colors = cols; cb.Positions = pos; br.InterpolationColors = cb;
      g.FillRectangle(br, r);
    }
  }
  public static Bitmap Render(string theme, int w, int h) {
    w = Math.Max(1, w); h = Math.Max(1, h);
    Bitmap bmp = new Bitmap(w, h, PixelFormat.Format32bppPArgb);
    // the picture is laid out on a height tied to the width, so a window that grows or shrinks
    // (a list sliding open) keeps the same glows in the same places; below it the last colour continues
    int hh = Math.Max(1, Math.Min(h, (int)(w * 1.372f)));
    using (Graphics g = Graphics.FromImage(bmp)) {
      g.SmoothingMode = SmoothingMode.AntiAlias;
      switch (theme) {
        case "midnight":
          g.Clear(H(0x0b0f1c, 255));
          Radial(g, w, hh, 0.2f, 0f, 1.2f, 0.7f, new Color[] { H(0x0b0f1c, 255), H(0x0b0f1c, 255), H(0x1f2a4a, 255) }, new float[] { 0f, 0.4f, 1f });
          Orb(g, w, hh, 0.82f, 0.55f, 90f, H(0xD8895A, 85));
          break;
        case "aurora":
          Linear(g, w, hh, 70f, new Color[] { H(0x0d1424, 255), H(0x0a0f1a, 255) }, new float[] { 0f, 1f });
          Orb(g, w, hh, 0.22f, 0.18f, 105f, H(0x3fd6a8, 85));
          Orb(g, w, hh, 0.82f, 0.66f, 110f, H(0x8f6bff, 80));
          Orb(g, w, hh, 0.54f, 0.97f, 85f, H(0xD8895A, 64));
          break;
        case "emberglass":
          g.Clear(H(0x141012, 255));
          Radial(g, w, hh, 0.8f, 0f, 1.2f, 0.8f, new Color[] { H(0x141012, 255), H(0x141012, 255), H(0x3a2218, 255) }, new float[] { 0f, 0.4f, 1f });
          Orb(g, w, hh, 0.22f, 0.79f, 100f, H(0xD8895A, 69));
          break;
        case "deepsea":
          Linear(g, w, hh, 90f, new Color[] { H(0x0f3340, 255), H(0x071820, 255), H(0x050d12, 255) }, new float[] { 0f, 0.55f, 1f });
          Orb(g, w, hh, 0.58f, 0.03f, 110f, H(0x5fd0e0, 69));
          Orb(g, w, hh, 0.89f, 0.76f, 80f, H(0xD8895A, 53));
          // a faint current line low in the window
          using (Pen wp = new Pen(H(0x7fe0ee, 64), 1.5f)) {
            float y0 = hh * 0.79f; List<PointF> pts = new List<PointF>();
            for (float x = 0; x <= w + 4; x += 4) pts.Add(new PointF(x, y0 + 10f * (float)Math.Sin(x / 100f * Math.PI)));
            if (pts.Count > 1) g.DrawLines(wp, pts.ToArray());
          }
          break;
        case "nebula":
          g.Clear(H(0x0a0812, 255));
          Radial(g, w, hh, 0.7f, 0.2f, 0.9f, 0.7f, new Color[] { H(0x0a0812, 255), H(0x0a0812, 255), H(0x150c24, 255), H(0x3a1c52, 255) }, new float[] { 0f, 0.3f, 0.45f, 1f });
          Orb(g, w, hh, 0.18f, 0.68f, 105f, H(0xe0559a, 64));
          Orb(g, w, hh, 0.78f, 0.13f, 90f, H(0x6b7dff, 69));
          // tiny stars, always in the same places for the same size
          int n = Math.Min(140, Math.Max(10, (int)(26.0 * w * hh / (277.0 * 380.0))));
          for (int i = 0; i < n; i++) {
            float sx = ((i * 37) % 100) / 100f * w + (i * 13 % 7), sy = ((i * 53 + i / 100 * 17) % 100) / 100f * hh + (i * 7 % 5);
            using (SolidBrush sb = new SolidBrush(Color.FromArgb((int)(255 * (0.25f + (i % 4) * 0.15f)), 255, 255, 255))) g.FillEllipse(sb, sx, sy, 1.8f, 1.8f);
          }
          break;
        default:
          g.Clear(Color.FromArgb(23, 23, 26)); break;
      }
    }
    return bmp;
  }
  // the form gets the backdrop (redrawn when its size changes); controls in the theme's base colour become see-through
  static Dictionary<Form, string> looks = new Dictionary<Form, string>();
  // calling it again with another look (the tray's pop-up after the look changed) swaps the backdrop
  public static void Attach(Form f, string theme, Color bg) {
    bool had = looks.ContainsKey(f);
    if (f.BackgroundImage != null && (had || !IsGlass(theme))) { Image o = f.BackgroundImage; f.BackgroundImage = null; o.Dispose(); }
    if (!IsGlass(theme)) { if (had) looks.Remove(f); return; }
    looks[f] = theme;
    f.BackgroundImageLayout = ImageLayout.None;
    SetImage(f, theme);
    if (had) { f.Invalidate(true); return; }
    f.SizeChanged += delegate { string th; if (looks.TryGetValue(f, out th)) { SetImage(f, th); f.Invalidate(true); } };
    f.FormClosed += delegate { looks.Remove(f); };
    SetDouble(f);
    Watch(f, bg);
  }
  static void SetImage(Form f, string theme) {
    Size s = f.ClientSize; if (s.Width < 1 || s.Height < 1) return;
    Image old = f.BackgroundImage;
    if (old != null && old.Width >= s.Width && old.Height >= s.Height && old.Width < s.Width * 1.25 + 40 && old.Height < s.Height + 600) return;
    // drawn taller than the window, so a window that grows a little (a list opening) does not draw it again every frame
    f.BackgroundImage = Render(theme, s.Width, s.Height + 300);
    if (old != null) old.Dispose();
  }
  static void SetDouble(Control c) {
    try { PropertyInfo pi = typeof(Control).GetProperty("DoubleBuffered", BindingFlags.NonPublic | BindingFlags.Instance); if (pi != null) pi.SetValue(c, true, null); } catch { }
  }
  static void Apply(Control c, Color bg) {
    if (c is TextBoxBase || c is ListBox || c is ComboBox || c is ToolStrip) return;
    if (c.BackColor.ToArgb() != bg.ToArgb()) return;
    if (c is Panel || c is Label || c is CheckBox || c is RadioButton || c is PictureBox || c is MiseCaret || c is MiseLogo || c is TableLayoutPanel) {
      try { c.BackColor = Color.Transparent; } catch { }
      if (c is Panel) SetDouble(c);
    }
  }
  public static void Watch(Control root, Color bg) {
    foreach (Control c in root.Controls) { Apply(c, bg); Watch(c, bg); }
    root.ControlAdded += delegate(object s, ControlEventArgs e) { Apply(e.Control, bg); Watch(e.Control, bg); };
    ScrollableControl sc = root as ScrollableControl;
    if (sc != null && !(root is Form)) {
      // a scrolled panel moves its pixels: repaint so the backdrop stays fixed behind it
      sc.Scroll += delegate { sc.Invalidate(true); };
      sc.MouseWheel += delegate { sc.Invalidate(true); };
    }
  }
}

public class MiseBtn : Button {
  public string Kind = "tool";     // tool | primary | ghost | row | setting | seg
  public string Num = "";          // row: number
  public string Group = "";        // row: which list it belongs to (drag to reorder); "rt" rows get the play button on hover
  public Image[] Icons = null;     // row: small app icons after the name
  public string Sub = "";          // row: small grey text on the right
  public string Chip = "";         // row: region chip / setting: value
  public bool Dots = false;        // row: a ... at the right end (its own click zone, see DotsHit)
  public bool DotsHit(int x) { return Dots && x >= Width - 36; }
  public bool IsSwitch = false;    // setting: draw a sliding switch instead of a value
  public string Seg = "";          // setting / seg: two choices "A|B", On picks B
  public string Glyph = "";        // ghost: a drawn icon instead of text (close | gear), same size and weight for both
  public Color Surface = Color.FromArgb(23, 23, 26);   // see-through (alpha < 255) in the glass looks
  public Color PanelC = Color.FromArgb(33, 33, 37);
  public Color HoverC = Color.FromArgb(45, 45, 51);
  public Color LineC = Color.FromArgb(56, 56, 63);
  public Color Accent = Color.FromArgb(216, 137, 90);
  public static bool Animate = true;   // off: every state jumps to its end
  public static float Radius = 9f;     // corner radius: 9 today, rounder in the glass looks
  public Color TextC = Color.FromArgb(238, 237, 234);
  public Color MutedC = Color.FromArgb(138, 136, 132);
  public Font SmallFont = new Font("Segoe UI", 9f);
  public Font TinyFont = new Font("Segoe UI Semibold", 8.5f);
  // the account frame gliding from one row to the next: GlideOn hides this row's own "on" look and draws the frame at GlideOff (px from its top)
  public bool GlideOn = false; public float GlideOff = 0f;
  bool hov, on;
  float hv = 0f;
  Timer fade, anim;
  static Stopwatch clock = Stopwatch.StartNew();
  MiseTween press = new MiseTween(0f);   // 0..1.5 press squeeze
  MiseTween ring = new MiseTween(0f);    // click flash / ripple 1 -> 0
  MiseTween onT = new MiseTween(0f);     // On state 0 -> 1 (bar, switch knob, segment pill)
  MiseTween sweep = new MiseTween(0f);   // a light sweep across the row 0 -> 1
  PointF rip = new PointF(0, 0);
  long slideAt = -1;                     // slide-in start (ms on the clock), -1 = not sliding
  public bool On {
    get { return on; }
    set {
      if (on == value) return; on = value;
      long now = clock.ElapsedMilliseconds;
      bool live = Animate && IsHandleCreated && Visible;
      int dur = IsSwitch ? 260 : 180;
      onT.Go(now, value ? 1f : 0f, dur, live);
      Kick(); Invalidate();
    }
  }
  // set On without any motion (after the glide)
  public void SetOnNow(bool v) { on = v; onT = new MiseTween(v ? 1f : 0f); Invalidate(); }
  // the window opening: this row slides in from the left after 'delay' ms
  public void SlideIn(int delay) { if (!Animate) return; slideAt = clock.ElapsedMilliseconds + delay; Kick(); Invalidate(); }
  public void Sweep() { if (!Animate) return; long now = clock.ElapsedMilliseconds; sweep.From = 0f; sweep.To = 1f; sweep.Start = now; sweep.Dur = 380; Kick(); }
  public static Color Mix(Color a, Color b, float t) {
    t = Math.Max(0f, Math.Min(1f, t));
    return Color.FromArgb((int)(a.A + (b.A - a.A) * t), (int)(a.R + (b.R - a.R) * t), (int)(a.G + (b.G - a.G) * t), (int)(a.B + (b.B - a.B) * t));
  }
  public static Color Alpha(Color c, float a) { return Color.FromArgb((int)(255 * Math.Max(0f, Math.Min(1f, a))), c.R, c.G, c.B); }
  bool Glass { get { return PanelC.A < 255; } }
  void Fade() {
    if (!Animate) { hv = hov ? 1f : 0f; Invalidate(); return; }
    if (fade == null) {
      fade = new Timer(); fade.Interval = 15;
      fade.Tick += delegate {
        float target = hov ? 1f : 0f;
        if (Math.Abs(hv - target) < 0.08f) { hv = target; fade.Stop(); }
        else hv += (target - hv) * 0.35f;
        Invalidate();
      };
    }
    if (!fade.Enabled) fade.Start();
  }
  bool Sliding(long now) { return slideAt >= 0 && now - slideAt < 240; }
  // one timer for press, click flash, On changes, slide-in and sweep; it stops as soon as nothing moves
  void Kick() {
    if (!Animate) return;
    if (anim == null) {
      anim = new Timer(); anim.Interval = 15;
      anim.Tick += delegate {
        long now = clock.ElapsedMilliseconds;
        if (!press.Running(now) && !ring.Running(now) && !onT.Running(now) && !sweep.Running(now) && !Sliding(now)) { anim.Stop(); slideAt = -1; }
        Invalidate();
      };
    }
    if (!anim.Enabled) anim.Start();
  }
  public MiseBtn() {
    SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.SupportsTransparentBackColor, true);
    FlatStyle = FlatStyle.Flat; FlatAppearance.BorderSize = 0; TabStop = false; Cursor = Cursors.Hand;
  }
  protected override void Dispose(bool disposing) {
    if (disposing) { if (fade != null) { fade.Stop(); fade.Dispose(); } if (anim != null) { anim.Stop(); anim.Dispose(); } }
    base.Dispose(disposing);
  }
  protected override void OnMouseEnter(EventArgs e) { hov = true; Fade(); Invalidate(); base.OnMouseEnter(e); }
  protected override void OnMouseLeave(EventArgs e) {
    hov = false; Fade();
    if (press.To > 0f) { press.Go(clock.ElapsedMilliseconds, 0f, 200, Animate); Kick(); }
    Invalidate(); base.OnMouseLeave(e);
  }
  protected override void OnMouseDown(MouseEventArgs e) { rip = new PointF(e.X, e.Y); press.Go(clock.ElapsedMilliseconds, 1.5f, 60, Animate); Kick(); Invalidate(); base.OnMouseDown(e); }
  protected override void OnMouseUp(MouseEventArgs e) { press.Go(clock.ElapsedMilliseconds, 0f, 200, Animate); Kick(); Invalidate(); base.OnMouseUp(e); }
  protected override void OnClick(EventArgs e) {
    // the click: a ripple from the pointer on rows, a 2 px accent border that fades out on the rest
    if (Animate && Kind != "seg") { long now = clock.ElapsedMilliseconds; ring.From = 1f; ring.To = 0f; ring.Start = now; ring.Dur = Kind == "row" ? 520 : 400; Kick(); }
    base.OnClick(e);
  }
  protected override void OnEnabledChanged(EventArgs e) { Invalidate(); base.OnEnabledChanged(e); }
  // see-through looks: the parent (and through it the window's backdrop) is painted under the button first.
  // A Button is Opaque (Windows skips its background step), so this is done by hand in OnPaint.
  protected override void OnPaintBackground(PaintEventArgs e) { }
  void PaintParent(PaintEventArgs pe) {
    Control p = Parent; if (p == null) { pe.Graphics.Clear(Color.FromArgb(23, 23, 26)); return; }
    GraphicsState st = pe.Graphics.Save();
    pe.Graphics.TranslateTransform(-Left, -Top);
    Rectangle r = new Rectangle(Left, Top, Width, Height);
    using (PaintEventArgs pa = new PaintEventArgs(pe.Graphics, r)) { InvokePaintBackground(p, pa); InvokePaint(p, pa); }
    pe.Graphics.Restore(st);
  }
  static GraphicsPath Round(RectangleF r, float rad) {
    rad = Math.Max(0.5f, Math.Min(rad, Math.Min(r.Width, r.Height) / 2f));
    float d = rad * 2; GraphicsPath p = new GraphicsPath();
    p.AddArc(r.X, r.Y, d, d, 180, 90); p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
    p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90); p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
    p.CloseFigure(); return p;
  }
  void Pill(Graphics g, RectangleF r, Color fill, Color border, bool filled) {
    using (GraphicsPath p = Round(r, r.Height / 2f)) {
      if (filled) using (SolidBrush b = new SolidBrush(fill)) g.FillPath(b, p);
      using (Pen pen = new Pen(border)) g.DrawPath(pen, p);
    }
  }
  // two choices: the accent pill slides to the chosen half, the labels cross-fade
  void DrawSeg(Graphics g, RectangleF pr, float t) {
    string[] parts = Seg.Split('|'); if (parts.Length < 2) return;
    float half = pr.Width / 2f;
    Pill(g, pr, PanelC, LineC, false);
    RectangleF act = new RectangleF(pr.X + half * t, pr.Y, half, pr.Height);
    Pill(g, act, Accent, Accent, true);
    StringFormat cf = new StringFormat(StringFormatFlags.NoWrap); cf.Alignment = StringAlignment.Center; cf.LineAlignment = StringAlignment.Center;
    Color dark = Mix(Color.FromArgb(20, 20, 22), Accent, 0.12f);
    using (SolidBrush a1 = new SolidBrush(Mix(dark, MutedC, t))) g.DrawString(parts[0], TinyFont, a1, new RectangleF(pr.X, pr.Y, half, pr.Height), cf);
    using (SolidBrush a2 = new SolidBrush(Mix(MutedC, dark, t))) g.DrawString(parts[1], TinyFont, a2, new RectangleF(pr.X + half, pr.Y, half, pr.Height), cf);
  }
  // the switch: a 16 px knob springs across a 44 x 22 track, "On" / "Off" written to its left
  void DrawSwitch(Graphics g, float right, float t, float kt) {
    float pw = 44, ph = 22; RectangleF pr = new RectangleF(right - pw, (Height - ph) / 2f, pw, ph);
    using (GraphicsPath tp = Round(pr, ph / 2f)) {
      using (SolidBrush tb = new SolidBrush(Mix(PanelC, Accent, t))) g.FillPath(tb, tp);
      using (Pen pen = new Pen(Mix(LineC, Accent, t))) g.DrawPath(pen, tp);
    }
    float kx = pr.X + 3 + (pw - 6 - 16) * Math.Max(-0.08f, Math.Min(1.08f, kt));
    using (SolidBrush kb = new SolidBrush(Mix(Alpha(MutedC, 1f), Color.FromArgb(24, 24, 27), t))) g.FillEllipse(kb, kx, pr.Y + 3, 16, 16);
    StringFormat rf = new StringFormat(StringFormatFlags.NoWrap); rf.Alignment = StringAlignment.Far; rf.LineAlignment = StringAlignment.Center;
    using (SolidBrush wb = new SolidBrush(on ? TextC : MutedC)) g.DrawString(on ? "On" : "Off", TinyFont, wb, new RectangleF(pr.X - 48, 0, 42, Height), rf);
  }
  // header icons drawn as lines on a 16 x 16 grid in the middle of the button: the close cross and the settings gear match in size and weight
  void DrawGlyph(Graphics g, Color c) {
    float sz = 16f, ox = (Width - sz) / 2f, oy = (Height - sz) / 2f;
    GraphicsState st = g.Save(); g.TranslateTransform(ox, oy);
    using (Pen p = new Pen(c, 1.6f)) {
      p.StartCap = LineCap.Round; p.EndCap = LineCap.Round; p.LineJoin = LineJoin.Round;
      if (Glyph == "close") { g.DrawLine(p, 3.5f, 3.5f, 12.5f, 12.5f); g.DrawLine(p, 12.5f, 3.5f, 3.5f, 12.5f); }
      else if (Glyph == "gear") {
        // eight rounded teeth around a ring
        using (GraphicsPath gp = new GraphicsPath()) {
          int n = 8; float ro = 7.2f, ri = 5.4f; List<PointF> pts = new List<PointF>();
          for (int i = 0; i < n; i++) {
            double a0 = (i - 0.22) * 2 * Math.PI / n, a1 = (i + 0.22) * 2 * Math.PI / n, a2 = (i + 0.5) * 2 * Math.PI / n, a3 = (i + 0.78) * 2 * Math.PI / n;
            pts.Add(new PointF(8f + ro * (float)Math.Cos(a0), 8f + ro * (float)Math.Sin(a0))); pts.Add(new PointF(8f + ro * (float)Math.Cos(a1), 8f + ro * (float)Math.Sin(a1)));
            pts.Add(new PointF(8f + ri * (float)Math.Cos(a2 - 0.12), 8f + ri * (float)Math.Sin(a2 - 0.12))); pts.Add(new PointF(8f + ri * (float)Math.Cos(a2 + 0.12), 8f + ri * (float)Math.Sin(a2 + 0.12)));
            pts.Add(new PointF(8f + ro * (float)Math.Cos(a3), 8f + ro * (float)Math.Sin(a3)));
            pts.RemoveAt(pts.Count - 1);
          }
          gp.AddPolygon(pts.ToArray()); g.DrawPath(p, gp);
        }
        g.DrawEllipse(p, 5.6f, 5.6f, 4.8f, 4.8f);
      }
    }
    g.Restore(st);
  }
  protected override void OnPaint(PaintEventArgs pe) {
    Graphics g = pe.Graphics;
    long now = clock.ElapsedMilliseconds;
    if (Surface.A == 255) g.Clear(Surface); else PaintParent(pe);
    if (slideAt >= 0 && Animate) {
      // sliding in: the body is drawn off-screen, then placed with an offset and a fade
      float k = (now - slideAt) / 240f;
      if (k < 0f) return;
      if (k < 1f) {
        float e = MiseTween.Ease(k);
        using (Bitmap bmp = new Bitmap(Math.Max(1, Width), Math.Max(1, Height), PixelFormat.Format32bppPArgb)) {
          using (Graphics bg = Graphics.FromImage(bmp)) { bg.Clear(Color.Transparent); PaintBody(bg, now, false); }
          using (ImageAttributes ia = new ImageAttributes()) {
            ColorMatrix cm = new ColorMatrix(); cm.Matrix33 = e; ia.SetColorMatrix(cm);
            g.DrawImage(bmp, new Rectangle((int)Math.Round(-14f * (1f - e)), 0, Width, Height), 0, 0, Width, Height, GraphicsUnit.Pixel, ia);
          }
        }
        return;
      }
      slideAt = -1;
    }
    PaintBody(g, now, true);
  }
  void PaintBody(Graphics g, long now, bool clearType) {
    float t = onT.At(now), kt = IsSwitch ? onT.AtSpring(now) : t, pd = press.At(now), rg = ring.At(now), sw = sweep.At(now);
    if (GlideOn) { t = 0f; }
    g.SmoothingMode = SmoothingMode.AntiAlias;
    g.TextRenderingHint = clearType ? TextRenderingHint.ClearTypeGridFit : TextRenderingHint.AntiAliasGridFit;
    bool isRow = Kind == "row";
    // rows lift a pixel on hover (a soft shadow below) and squeeze a little while pressed
    float lift = isRow ? 1.2f * hv * (1f - pd / 1.5f) : 0f;
    float sqx = isRow ? pd * 2.2f : pd, sqy = isRow ? pd * 0.5f : pd;
    RectangleF rc = new RectangleF(0.5f + sqx, 1.5f - lift + sqy, Width - 2 - 2 * sqx, Height - 3 - 2 * sqy);
    if (!isRow) rc = new RectangleF(0.5f + pd, 0.5f + pd, Width - 2 - 2 * pd, Height - 2 - 2 * pd);
    Color fill = PanelC, border = LineC, txt = TextC;
    bool glass = Glass;
    if (Kind == "ghost" || Kind == "seg") { fill = Color.FromArgb(0, 0, 0, 0); border = fill; txt = Mix(MutedC, TextC, hv); }
    else { fill = Mix(PanelC, HoverC, hv); fill = Mix(fill, LineC, pd / 1.5f); }
    if (isRow && hv > 0f) border = Mix(border, Mix(LineC, MutedC, 0.35f), hv);
    if (Kind == "primary") { border = Accent; txt = Accent; fill = Mix(fill, glass ? Alpha(Accent, 0.16f) : Mix(PanelC, Accent, 0.16f), hv); }
    if (Kind == "tool" && t > 0f) { border = Mix(border, Accent, t); txt = Mix(txt, Accent, t); fill = Mix(fill, glass ? Alpha(Accent, 0.14f + 0.08f * hv) : Mix(Mix(PanelC, Accent, 0.14f), Mix(PanelC, Accent, 0.22f), hv), t); }
    if (isRow && t > 0f) { border = Mix(border, glass ? Alpha(Accent, 0.55f) : Mix(LineC, Accent, 0.55f), t); fill = Mix(fill, glass ? Alpha(Accent, 0.14f + 0.05f * hv) : Mix(Mix(PanelC, Accent, 0.10f), Mix(PanelC, Accent, 0.16f), hv), t); }
    if (!Enabled) { txt = Color.FromArgb(104, 102, 98); }
    if (isRow && lift > 0.05f) {
      using (GraphicsPath sp = Round(new RectangleF(rc.X + 3, rc.Y + 3, rc.Width - 6, rc.Height), Radius))
      using (SolidBrush sb = new SolidBrush(Color.FromArgb((int)(60 * hv), 0, 0, 0))) g.FillPath(sb, sp);
    }
    using (GraphicsPath path = Round(rc, Radius)) {
      if (fill.A > 0) using (SolidBrush b = new SolidBrush(fill)) g.FillPath(b, path);
      // the account frame passing over this row on its way to the new account
      if (GlideOn) {
        RectangleF fr = new RectangleF(rc.X, GlideOff + 1.5f, rc.Width, rc.Height);
        GraphicsState gs = g.Save(); g.SetClip(path, CombineMode.Intersect);
        using (GraphicsPath fp = Round(fr, Radius)) {
          using (SolidBrush fb = new SolidBrush(glass ? Alpha(Accent, 0.16f) : Mix(PanelC, Accent, 0.12f))) g.FillPath(fb, fp);
          using (Pen fpen = new Pen(glass ? Alpha(Accent, 0.55f) : Mix(LineC, Accent, 0.55f))) g.DrawPath(fpen, fp);
        }
        using (SolidBrush ab = new SolidBrush(Accent)) using (GraphicsPath bar = Round(new RectangleF(0, GlideOff + Height / 2f - (Height - 20) / 2f, 4, Height - 20), 2f)) g.FillPath(ab, bar);
        g.Restore(gs);
      }
      if (sw > 0.001f && sw < 0.999f) {
        // a light sweep runs across the row (account switch)
        float bw = Width * 0.55f, bx = -bw + (Width + bw) * sw;
        GraphicsState gs = g.Save(); g.SetClip(path, CombineMode.Intersect);
        using (LinearGradientBrush lb = new LinearGradientBrush(new RectangleF(bx - 1, 0, bw + 2, Height), Color.FromArgb(0, Accent), Color.FromArgb(0, Accent), 0f)) {
          ColorBlend cb = new ColorBlend(3); cb.Colors = new Color[] { Color.FromArgb(0, Accent), Color.FromArgb(70, Accent), Color.FromArgb(0, Accent) }; cb.Positions = new float[] { 0f, 0.5f, 1f };
          lb.InterpolationColors = cb; g.FillRectangle(lb, bx, 0, bw, Height);
        }
        g.Restore(gs);
      }
      if (isRow && rg > 0.01f) {
        // ripple from where the row was pressed
        float rr = (1f - rg) * Width * 0.75f;
        GraphicsState gs = g.Save(); g.SetClip(path, CombineMode.Intersect);
        using (SolidBrush rb = new SolidBrush(Alpha(Accent, 0.30f * rg))) g.FillEllipse(rb, rip.X - rr, rip.Y - rr, 2 * rr, 2 * rr);
        g.Restore(gs);
      }
      if (border.A > 0 && Kind != "ghost" && Kind != "seg") using (Pen pen = new Pen(border)) g.DrawPath(pen, path);
    }
    if (rg > 0.01f && Kind != "ghost" && !isRow) {
      using (GraphicsPath rp = Round(new RectangleF(rc.X + 1f, rc.Y + 1f, rc.Width - 2f, rc.Height - 2f), Radius - 1f))
      using (Pen rpen = new Pen(Alpha(Accent, rg), 2f)) g.DrawPath(rpen, rp);
    }
    StringFormat sf = new StringFormat(StringFormatFlags.NoWrap);
    sf.LineAlignment = StringAlignment.Center; sf.Trimming = StringTrimming.EllipsisCharacter;
    float oy = rc.Y - 1.5f;   // text moves with the lifted row
    using (SolidBrush tb = new SolidBrush(txt)) {
      if (isRow) {
        // the accent edge bar grows from the middle: half way on hover, full when on
        float bh = (Height - 20) * Math.Max(t, 0.5f * hv);
        if (bh > 0.5f) using (SolidBrush ab = new SolidBrush(Accent)) using (GraphicsPath bar = Round(new RectangleF(rc.X - 0.5f, oy + Height / 2f - bh / 2f, 4, bh), 2f)) g.FillPath(ab, bar);
        using (SolidBrush nb = new SolidBrush(Enabled ? MutedC : Color.FromArgb(90, 88, 84))) g.DrawString(Num, SmallFont, nb, new RectangleF(16, oy, 22, Height), sf);
        bool play = Group == "rt";
        float reserve = 14f + (play ? 30f : 0f);
        if (Dots) reserve += 26f;
        if (Chip.Length > 0) reserve += g.MeasureString(Chip, TinyFont).Width + 14f + 10f;
        bool hasIcons = Icons != null && Icons.Length > 0;
        if (Sub.Length > 0) reserve += hasIcons ? g.MeasureString(Sub, SmallFont).Width + 12f : 110f;
        float textMax = Math.Max(20f, Width - 40 - reserve - (hasIcons ? Math.Min(Icons.Length, 3) * 21f + 8f : 0f));
        g.DrawString(Text, Font, tb, new RectangleF(40, oy, textMax, Height), sf);
        if (hasIcons) {
          // the apps this routine opens: as many icons as fit, then "+n"
          float ix = 40 + Math.Min(g.MeasureString(Text, Font).Width, textMax) + 8f, lim = Width - reserve - 2f; int shown = 0;
          InterpolationMode om = g.InterpolationMode; g.InterpolationMode = InterpolationMode.HighQualityBicubic;
          for (int k = 0; k < Icons.Length; k++) {
            if (ix + 16f > lim - (k < Icons.Length - 1 ? 22f : 0f)) break;
            if (Icons[k] != null) g.DrawImage(Icons[k], new RectangleF(ix, oy + (Height - 16) / 2f, 16f, 16f));
            ix += 21f; shown++;
          }
          g.InterpolationMode = om;
          if (shown < Icons.Length && shown > 0) using (SolidBrush pb = new SolidBrush(MutedC)) g.DrawString("+" + (Icons.Length - shown), TinyFont, pb, new RectangleF(ix - 2f, oy, 30f, Height), sf);
        }
        float right = Width - 14;
        if (play) {
          // a small play button slides in while the row is hovered
          float a = Enabled ? hv : 0f;
          if (a > 0.02f) {
            float cx = right - 11f + (1f - a) * 6f, cy = oy + Height / 2f;
            using (SolidBrush pb = new SolidBrush(Alpha(Accent, a))) g.FillEllipse(pb, cx - 11f, cy - 11f, 22f, 22f);
            using (SolidBrush tri = new SolidBrush(Color.FromArgb((int)(255 * a), 23, 23, 26))) g.FillPolygon(tri, new PointF[] { new PointF(cx - 3f, cy - 5f), new PointF(cx - 3f, cy + 5f), new PointF(cx + 5f, cy) });
          }
          right -= 30f;
        }
        if (Dots) {
          // three dots in the row's own colours; brighter while the row is hovered
          float dx = Width - 22, dy = oy + Height / 2f;
          using (SolidBrush db = new SolidBrush(Mix(MutedC, TextC, hv))) { for (int k = -1; k <= 1; k++) g.FillEllipse(db, dx + k * 5f - 1.6f, dy - 1.6f, 3.2f, 3.2f); }
          using (Pen sp = new Pen(Mix(LineC, PanelC, 0.3f), 1f)) g.DrawLine(sp, Width - 36, oy + 10, Width - 36, oy + Height - 10);
          right = Width - 36 - 10;
        }
        if (Chip.Length > 0) {
          SizeF cs = g.MeasureString(Chip, TinyFont);
          float cw = cs.Width + 14; RectangleF cr = new RectangleF(right - cw, oy + (Height - 22) / 2f, cw, 22);
          // the hotkey / region chip lights up on hover
          Color chipC = !Enabled ? Color.FromArgb(104, 102, 98) : Mix(MutedC, Accent, Math.Max(t, hv));
          Pill(g, cr, PanelC, chipC, false);
          StringFormat cf = new StringFormat(StringFormatFlags.NoWrap); cf.Alignment = StringAlignment.Center; cf.LineAlignment = StringAlignment.Center;
          using (SolidBrush cb = new SolidBrush(chipC)) g.DrawString(Chip, TinyFont, cb, cr, cf);
          right -= cw + 10;
        }
        if (Sub.Length > 0) {
          StringFormat rf = new StringFormat(StringFormatFlags.NoWrap); rf.Alignment = StringAlignment.Far; rf.LineAlignment = StringAlignment.Center;
          using (SolidBrush mb = new SolidBrush(Sub == "switching..." ? Accent : MutedC)) g.DrawString(Sub, SmallFont, mb, new RectangleF(right - 110, oy, 110, Height), rf);
        }
      } else if (Kind == "seg") {
        DrawSeg(g, new RectangleF(2, 3, Width - 5, Height - 7), t);
      } else if (Kind == "setting") {
        float segW = Seg.Length > 0 ? 170f : 0f;
        g.DrawString(Text, Font, tb, new RectangleF(14, 0, Width - (Seg.Length > 0 ? segW + 30 : (IsSwitch ? 120 : 130)), Height), sf);
        float right = Width - 12;
        if (Seg.Length > 0) {
          DrawSeg(g, new RectangleF(right - segW, (Height - 24) / 2f, segW, 24), t);
        } else if (IsSwitch) {
          DrawSwitch(g, right, t, kt);
        } else if (Chip.Length > 0) {
          SizeF cs = g.MeasureString(Chip, TinyFont);
          float cw = cs.Width + 22; RectangleF cr = new RectangleF(right - cw, (Height - 22) / 2f, cw, 22);
          Pill(g, cr, PanelC, Mix(LineC, Accent, Math.Max(t, hv * 0.6f)), false);
          StringFormat cf = new StringFormat(StringFormatFlags.NoWrap); cf.Alignment = StringAlignment.Center; cf.LineAlignment = StringAlignment.Center;
          using (SolidBrush cb = new SolidBrush(Mix(TextC, Accent, t))) g.DrawString(Chip, TinyFont, cb, cr, cf);
        }
      } else if (Glyph.Length > 0) {
        DrawGlyph(g, txt);
      } else {
        sf.Alignment = StringAlignment.Center;
        g.DrawString(Text, Font, tb, new RectangleF(4, 0, Width - 8, Height), sf);
      }
    }
    sf.Dispose();
  }
}
// the account frame glides from the old account row to the new one; the rows draw the frame where it crosses them,
// the panel draws it in the gaps between rows. Without animations the switch is instant.
public static class MiseGlide {
  static Stopwatch clock = Stopwatch.StartNew();
  public static void Run(Control panel, MiseBtn[] rows, int from, int to) {
    if (rows == null || to < 0 || to >= rows.Length) return;
    if (!MiseBtn.Animate || from < 0 || from >= rows.Length || from == to) {
      for (int i = 0; i < rows.Length; i++) { rows[i].GlideOn = false; rows[i].SetOnNow(i == to); }
      if (!MiseBtn.Animate) return;
      rows[to].SetOnNow(false); rows[to].On = true; return;
    }
    float y0 = rows[from].Top, y1 = rows[to].Top; long start = clock.ElapsedMilliseconds; int dur = 360;
    PaintEventHandler ph = null; Timer tm = new Timer(); tm.Interval = 15;
    float cur = y0;
    ph = delegate(object s, PaintEventArgs e) {
      RectangleF fr = new RectangleF(rows[0].Left + 0.5f, cur + 1.5f, rows[0].Width - 2, rows[0].Height - 3);
      Region keep = e.Graphics.Clip; foreach (MiseBtn b in rows) e.Graphics.ExcludeClip(b.Bounds);
      using (Pen p = new Pen(MiseBtn.Mix(rows[0].LineC, rows[0].Accent, 0.6f))) using (SolidBrush ab = new SolidBrush(rows[0].Accent)) {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.DrawLine(p, fr.X, fr.Y + 4, fr.X, fr.Bottom - 4); e.Graphics.DrawLine(p, fr.Right, fr.Y + 4, fr.Right, fr.Bottom - 4);
        e.Graphics.FillRectangle(ab, fr.X - 0.5f, fr.Y + fr.Height / 2f - 12f, 4f, 24f);
      }
      e.Graphics.Clip = keep;
    };
    panel.Paint += ph;
    for (int i = 0; i < rows.Length; i++) { rows[i].GlideOn = true; rows[i].SetOnNow(false); }
    tm.Tick += delegate {
      float k = (clock.ElapsedMilliseconds - start) / (float)dur; if (k > 1f) k = 1f;
      float e = k < 0.5f ? 4f * k * k * k : 1f - (float)Math.Pow(-2f * k + 2f, 3) / 2f;   // ease in-out
      cur = y0 + (y1 - y0) * e;
      foreach (MiseBtn b in rows) { b.GlideOff = cur - b.Top; b.Invalidate(); }
      panel.Invalidate(false);
      if (k >= 1f) {
        tm.Stop(); tm.Dispose(); panel.Paint -= ph;
        for (int i = 0; i < rows.Length; i++) { rows[i].GlideOn = false; rows[i].SetOnNow(i == to); }
        panel.Invalidate(false);
      }
    };
    tm.Start();
  }
}
// the Mise mark (logo G3 "warm glow"): three bowls on a counter, each tucked behind the next larger one; copper always.
// States: 0 idle (still, no timer), 1 busy (bowls lift in turn), 2 done (one hop, border flash), 3 needs a look (small bowl tipped), 4 opening (counter grows, bowls drop in)
public class MiseLogo : Control {
  public Color Accent = Color.FromArgb(216, 137, 90);
  public Color TileC = Color.FromArgb(30, 30, 34);
  public Color BorderC = Color.FromArgb(56, 56, 63);
  public bool ShowTile = true;
  public static bool Animate = true;
  static Stopwatch clock = Stopwatch.StartNew();
  int state = 0; long since = 0;
  Timer tick;
  public MiseLogo() {
    SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.SupportsTransparentBackColor, true);
    Width = 32; Height = 32;
  }
  public int State {
    get { return state; }
    set {
      if (state == value && value != 2 && value != 4) return;
      if (value == 4 && !Animate) return;
      state = value; since = clock.ElapsedMilliseconds;
      if (Animate && (state >= 1 && state <= 4)) {
        if (tick == null) { tick = new Timer(); tick.Interval = 15; tick.Tick += delegate { Step(); }; }
        if (!tick.Enabled) tick.Start();
      } else if (tick != null) tick.Stop();
      Invalidate();
    }
  }
  public void Intro() { State = 4; }
  void Step() {
    long el = clock.ElapsedMilliseconds - since;
    if (state == 2 && el > 700) { state = 0; tick.Stop(); }
    else if (state == 4 && el > 760) { state = 0; tick.Stop(); }
    else if (state == 3 && el > 900) tick.Stop();
    else if (state == 0) tick.Stop();
    Invalidate();
  }
  protected override void Dispose(bool disposing) { if (disposing && tick != null) { tick.Stop(); tick.Dispose(); } base.Dispose(disposing); }
  static GraphicsPath HalfDisc(float x1, float y, float r) {
    GraphicsPath p = new GraphicsPath();
    p.AddArc(x1, y - r, 2 * r, 2 * r, 0, 180);
    p.CloseFigure(); return p;
  }
  static GraphicsPath RoundRect(float x, float y, float w, float h, float rad) {
    float d = rad * 2; GraphicsPath p = new GraphicsPath();
    p.AddArc(x, y, d, d, 180, 90); p.AddArc(x + w - d, y, d, d, 270, 90);
    p.AddArc(x + w - d, y + h - d, d, d, 0, 90); p.AddArc(x, y + h - d, d, d, 90, 90);
    p.CloseFigure(); return p;
  }
  static float Ease(float k) { k = Math.Max(0f, Math.Min(1f, k)); float i = 1f - k; return 1f - i * i * i; }
  // draws the mark on a 128 x 128 grid; lift[i] (units) and strength[i] (0..1) per bowl: 0 small, 1 middle, 2 big
  public static void DrawMark(Graphics g, Color accent, Color gapC, float[] lift, float[] strength, int problem, float tipDeg, float drop0, float drop1, float drop2, float counterK) {
    float[] baseA = { 0.6f, 0.85f, 1f };
    float[] x1 = { 88.5f, 58f, 15f }; float[] yy = { 67.5f, 61f, 54f }; float[] rr = { 12.5f, 19f, 26f };
    float[] drops = { drop0, drop1, drop2 };
    Color top = Color.FromArgb(0xE9, 0xA1, 0x74), bot = Color.FromArgb(0xB8, 0x6D, 0x43);
    for (int i = 0; i < 3; i++) {
      float a = baseA[i] * strength[i]; if (a <= 0.01f) continue;
      float y = yy[i] - lift[i] - drops[i];
      using (GraphicsPath p = HalfDisc(x1[i], y, rr[i])) {
        int ga = (int)(255 * (strength[i] < 0.34f ? strength[i] / 0.34f : 1f));
        if (i > 0) using (SolidBrush gb = new SolidBrush(Color.FromArgb(ga, gapC))) using (Pen gp = new Pen(Color.FromArgb(ga, gapC), 5f)) { gp.LineJoin = LineJoin.Round; g.FillPath(gb, p); g.DrawPath(gp, p); }
        if (i == 0 && problem == 1) {
          GraphicsState st = g.Save();
          g.TranslateTransform(x1[i], y + rr[i]); g.RotateTransform(-tipDeg); g.TranslateTransform(-x1[i], -(y + rr[i]));
          using (Pen op = new Pen(Color.FromArgb((int)(255 * a), accent), 4f)) { op.LineJoin = LineJoin.Round; g.DrawPath(op, p); }
          g.Restore(st);
        } else {
          // each bowl lit from above: a warm copper gradient
          int al = (int)(255 * Math.Min(1f, a));
          using (LinearGradientBrush b = new LinearGradientBrush(new RectangleF(x1[i], y - 0.5f, 2 * rr[i], rr[i] + 1f), Color.FromArgb(al, top), Color.FromArgb(al, bot), 90f)) g.FillPath(b, p);
        }
      }
    }
    if (counterK > 0.01f) {
      float w = 108f * counterK;
      using (GraphicsPath c = RoundRect(10f, 80f, Math.Max(10f, w), 10f, 5f)) {
        using (SolidBrush gb = new SolidBrush(gapC)) using (Pen gp = new Pen(gapC, 5f)) { gp.LineJoin = LineJoin.Round; g.FillPath(gb, c); g.DrawPath(gp, c); }
        using (SolidBrush cb = new SolidBrush(Color.FromArgb(153, accent))) g.FillPath(cb, c);
      }
    }
  }
  protected override void OnPaint(PaintEventArgs pe) {
    Graphics g = pe.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
    if (BackColor.A == 255) g.Clear(BackColor);
    float k = Math.Min(Width, Height) / 128f;
    GraphicsState st0 = g.Save(); g.ScaleTransform(k, k);
    long el = clock.ElapsedMilliseconds - since;
    float[] lift = { 0f, 0f, 0f }; float[] str = { 1f, 1f, 1f }; int problem = 0; float tip = 0f; float flash = 0f;
    float[] drop = { 0f, 0f, 0f }; float counterK = 1f;
    if (Animate && state == 1) {
      // bowls in turn (big, middle, small), 300 ms apart, 1500 ms loop, ease in-out
      for (int i = 0; i < 3; i++) {
        int order = 2 - i; double p = ((el - order * 300) % 1500 + 1500) % 1500 / 1500.0;
        float v = (float)(0.5 - 0.5 * Math.Cos(2 * Math.PI * p));
        lift[i] = 4f * v; str[i] = 0.35f + 0.65f * v;
      }
    } else if (state == 2) {
      float kk = Animate ? Math.Min(1f, el / 420f) : 1f; float hop = (float)Math.Sin(Math.PI * kk) * 6f;
      lift[0] = hop; lift[1] = hop; lift[2] = hop;
      flash = 1f - (Animate ? Math.Min(1f, el / 700f) : 1f);
    } else if (state == 3) {
      problem = 1; tip = 24f;
      if (Animate && el < 900) { float kk = el / 900f; tip = 24f + 8f * (float)Math.Sin(2 * Math.PI * kk) * (1f - kk); }
    } else if (state == 4) {
      // opening: the counter grows, then the bowls drop onto it one by one (big, middle, small) with a small bounce
      counterK = Ease(el / 160f);
      for (int i = 0; i < 3; i++) {
        int order = 2 - i; float kk = (el - 120f - order * 110f) / 300f;
        if (kk <= 0f) { str[i] = 0f; continue; }
        str[i] = Math.Min(1f, kk * 3f); drop[i] = 26f * (1f - MiseTween.Spring(kk));
      }
    }
    if (ShowTile) {
      using (GraphicsPath tile = RoundRect(2f, 2f, 124f, 124f, 27f)) {
        using (SolidBrush tb = new SolidBrush(TileC)) g.FillPath(tb, tile);
        // a warm glow behind the bowls
        using (GraphicsPath gl = new GraphicsPath()) {
          gl.AddEllipse(46f - 72f, 58f - 72f, 144f, 144f);
          using (PathGradientBrush gb = new PathGradientBrush(gl)) {
            gb.CenterPoint = new PointF(46f, 58f); gb.CenterColor = Color.FromArgb(56, Accent); gb.SurroundColors = new Color[] { Color.FromArgb(0, Accent) };
            GraphicsState gs = g.Save(); g.SetClip(tile, CombineMode.Intersect); g.FillPath(gb, gl); g.Restore(gs);
          }
        }
        // the edge: a copper gradient, bright at two corners
        using (LinearGradientBrush eb = new LinearGradientBrush(new RectangleF(0, 0, 128, 128), Color.FromArgb(0xF0, 0xAE, 0x84), Color.FromArgb(0xF0, 0xAE, 0x84), 45f)) {
          ColorBlend cb = new ColorBlend(3); cb.Colors = new Color[] { Color.FromArgb(0xF0, 0xAE, 0x84), Color.FromArgb(115, Accent), Color.FromArgb(0xF0, 0xAE, 0x84) }; cb.Positions = new float[] { 0f, 0.5f, 1f };
          eb.InterpolationColors = cb;
          using (Pen bp = new Pen(eb, 3.5f)) g.DrawPath(bp, tile);
        }
        if (flash > 0.01f) using (Pen fp = new Pen(Color.FromArgb((int)(255 * flash), Accent), 4f)) g.DrawPath(fp, tile);
      }
    }
    // bowls and counter at 110 % around the middle of the counter
    g.TranslateTransform(64f, 70f); g.ScaleTransform(1.1f, 1.1f); g.TranslateTransform(-64f, -70f);
    DrawMark(g, Accent, TileC, lift, str, problem, tip, drop[0], drop[1], drop[2], counterK);
    g.Restore(st0);
  }
}
// the small arrow next to a collapsible section: turns 90 degrees (right = closed, down = open)
public class MiseCaret : Control {
  public Color Ink = Color.FromArgb(138, 136, 132);
  static Stopwatch clock = Stopwatch.StartNew();
  MiseTween ang = new MiseTween(0f);
  bool open; Timer tick;
  public MiseCaret() { SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.SupportsTransparentBackColor, true); Width = 12; Height = 12; }
  public bool Open {
    get { return open; }
    set {
      if (open == value) return; open = value;
      bool live = MiseBtn.Animate && IsHandleCreated && Visible;
      ang.Go(clock.ElapsedMilliseconds, value ? 90f : 0f, 180, live);
      if (live) {
        if (tick == null) { tick = new Timer(); tick.Interval = 15; tick.Tick += delegate { if (!ang.Running(clock.ElapsedMilliseconds)) tick.Stop(); Invalidate(); }; }
        if (!tick.Enabled) tick.Start();
      }
      Invalidate();
    }
  }
  protected override void Dispose(bool disposing) { if (disposing && tick != null) { tick.Stop(); tick.Dispose(); } base.Dispose(disposing); }
  protected override void OnPaint(PaintEventArgs pe) {
    Graphics g = pe.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias; if (BackColor.A == 255) g.Clear(BackColor);
    float cx = Width / 2f, cy = Height / 2f;
    GraphicsState st = g.Save();
    g.TranslateTransform(cx, cy); g.RotateTransform(ang.At(clock.ElapsedMilliseconds));
    using (SolidBrush b = new SolidBrush(Ink)) g.FillPolygon(b, new PointF[] { new PointF(-2.5f, -4f), new PointF(3.5f, 0f), new PointF(-2.5f, 4f) });
    g.Restore(st);
  }
}

// ---------- a short pick list that drops down inside a window (the lobby list) ----------
// rounded box, rows with a soft hover, the chosen row in the accent with a check, smooth wheel scrolling, a thin scroll thumb
public class MiseList : Control {
  public string[] Names = new string[0];
  public string[] Notes = new string[0];      // small grey text at the right ("not available")
  public int Chosen = -1;
  public int RowH = 32;
  public int Picked = -1;                      // set just before Click: the row that was clicked
  public Color Fill = Color.FromArgb(33, 33, 37), LineC = Color.FromArgb(56, 56, 63), HoverC = Color.FromArgb(45, 45, 51), TextC = Color.FromArgb(238, 237, 234), MutedC = Color.FromArgb(138, 136, 132), Accent = Color.FromArgb(216, 137, 90);
  public Font RowFont = new Font("Segoe UI Semibold", 9.5f), NoteFont = new Font("Segoe UI", 9f);
  float scroll = 0f, target = 0f; int hot = -1; float hotY = -1f; Timer tm;
  public MiseList() {
    SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.SupportsTransparentBackColor, true);
    Cursor = Cursors.Hand;
  }
  float MaxScroll { get { return Math.Max(0f, Names.Length * RowH + 8 - Height); } }
  public void ScrollTo(int index) { scroll = target = Math.Max(0f, Math.Min(MaxScroll, (index - 2) * RowH)); Invalidate(); }
  void Kick() {
    if (tm == null) { tm = new Timer(); tm.Interval = 15; tm.Tick += delegate {
      float d = target - scroll; float hd = (hot >= 0 ? hot * RowH + 4 : -1) - hotY;
      if (Math.Abs(d) < 0.5f && (hot < 0 || Math.Abs(hd) < 0.5f)) { scroll = target; if (hot >= 0) hotY = hot * RowH + 4; tm.Stop(); }
      else { scroll += d * 0.3f; if (hot >= 0) hotY = hotY < 0 ? hot * RowH + 4 : hotY + hd * 0.45f; }
      Invalidate(); }; }
    if (!MiseBtn.Animate) { scroll = target; if (hot >= 0) hotY = hot * RowH + 4; Invalidate(); return; }
    if (!tm.Enabled) tm.Start();
  }
  protected override void Dispose(bool disposing) { if (disposing && tm != null) { tm.Stop(); tm.Dispose(); } base.Dispose(disposing); }
  protected override void OnMouseWheel(MouseEventArgs e) { target = Math.Max(0f, Math.Min(MaxScroll, target - e.Delta / 120f * RowH)); Kick(); base.OnMouseWheel(e); }
  int RowAt(int y) { int i = (int)Math.Floor((y + scroll - 4) / RowH); return (i >= 0 && i < Names.Length) ? i : -1; }
  protected override void OnMouseMove(MouseEventArgs e) { int h = RowAt(e.Y); if (h != hot) { if (hot < 0) hotY = h * RowH + 4; hot = h; Kick(); } base.OnMouseMove(e); }
  protected override void OnMouseLeave(EventArgs e) { hot = -1; Invalidate(); base.OnMouseLeave(e); }
  protected override void OnMouseDown(MouseEventArgs e) { Picked = RowAt(e.Y); base.OnMouseDown(e); }
  static GraphicsPath Round(RectangleF r, float rad) {
    rad = Math.Max(0.5f, Math.Min(rad, Math.Min(r.Width, r.Height) / 2f)); float d = rad * 2; GraphicsPath p = new GraphicsPath();
    p.AddArc(r.X, r.Y, d, d, 180, 90); p.AddArc(r.Right - d, r.Y, d, d, 270, 90); p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90); p.AddArc(r.X, r.Bottom - d, d, d, 90, 90); p.CloseFigure(); return p;
  }
  protected override void OnPaint(PaintEventArgs pe) {
    Graphics g = pe.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias; g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
    if (BackColor.A == 255) g.Clear(BackColor);
    RectangleF box = new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f);
    using (GraphicsPath bp = Round(box, MiseBtn.Radius)) {
      using (SolidBrush fb = new SolidBrush(Fill)) g.FillPath(fb, bp);
      GraphicsState st = g.Save(); g.SetClip(bp, CombineMode.Intersect);
      // the hover pill glides from row to row
      if (hot >= 0 && hotY >= 0) using (GraphicsPath hp = Round(new RectangleF(4, hotY - scroll, Width - 9, RowH), 7f)) using (SolidBrush hb = new SolidBrush(HoverC)) g.FillPath(hb, hp);
      StringFormat sf = new StringFormat(StringFormatFlags.NoWrap); sf.LineAlignment = StringAlignment.Center; sf.Trimming = StringTrimming.EllipsisCharacter;
      StringFormat rf = new StringFormat(StringFormatFlags.NoWrap); rf.LineAlignment = StringAlignment.Center; rf.Alignment = StringAlignment.Far;
      for (int i = 0; i < Names.Length; i++) {
        float y = i * RowH + 4 - scroll; if (y > Height || y + RowH < 0) continue;
        bool on = i == Chosen; string note = i < Notes.Length ? Notes[i] : "";
        if (on) using (SolidBrush ab = new SolidBrush(Accent)) using (GraphicsPath bar = Round(new RectangleF(5, y + 8, 3, RowH - 16), 1.5f)) g.FillPath(ab, bar);
        using (SolidBrush tb = new SolidBrush(on ? Accent : (note.Length > 0 ? MutedC : TextC))) g.DrawString(Names[i], RowFont, tb, new RectangleF(16, y, Width - 120, RowH), sf);
        if (note.Length > 0) using (SolidBrush mb = new SolidBrush(MutedC)) g.DrawString(note, NoteFont, mb, new RectangleF(Width - 140, y, 122, RowH), rf);
        else if (on) using (Pen cp = new Pen(Accent, 1.8f)) { cp.StartCap = LineCap.Round; cp.EndCap = LineCap.Round; float cx = Width - 30, cy = y + RowH / 2f; g.DrawLines(cp, new PointF[] { new PointF(cx - 5, cy), new PointF(cx - 1.5f, cy + 3.5f), new PointF(cx + 5, cy - 4) }); }
      }
      // a thin thumb shows where in the list you are
      float ms = MaxScroll;
      if (ms > 0) {
        float th = Math.Max(22f, Height * Height / (float)(Names.Length * RowH + 8)), ty = 3 + (Height - 6 - th) * (scroll / ms);
        using (GraphicsPath tp = Round(new RectangleF(Width - 7, ty, 3, th), 1.5f)) using (SolidBrush tb = new SolidBrush(Color.FromArgb(150, Accent))) g.FillPath(tb, tp);
      }
      g.Restore(st);
      using (Pen lp = new Pen(LineC)) g.DrawPath(lp, bp);
    }
  }
}

// ---------- the progress pop-up: a slim pill while all goes well; it unfolds into the step list for a problem,
// a League update, or while the mouse is over it (spec 13 Nov 2026: pill + timeline) ----------
public class MisePop : Control {
  public string Head = "", Count = "";
  public float Ring = -1f;                      // 0..1 how far (ready apps / all), -1 = unknown
  public bool Running = false, Done = false, Problem = false;
  public bool Needs = false;                    // a problem or a League update: stays unfolded
  public bool Pinned = false;                   // clicked open
  public bool AnchorBottom = false;             // grows upward (a bottom corner)
  public string[] Times = new string[0], Texts = new string[0], Kinds = new string[0];   // kind: done | now | warn | update
  public float[] Pcts = new float[0];           // update rows: 0..100, -1 unknown
  public int[] Fix = new int[0];                // index of the fix for a warn row, -1 none
  public int FixIndex = -1;
  public event EventHandler StopClick, HideClick, FixClick;
  public Color TextC = Color.FromArgb(238, 237, 234), MutedC = Color.FromArgb(138, 136, 132), LineC = Color.FromArgb(56, 56, 63), Accent = Color.FromArgb(216, 137, 90), Warn = Color.FromArgb(240, 192, 96), Fill = Color.FromArgb(23, 23, 26);
  public Font HeadFont = new Font("Segoe UI Semibold", 10f), RowFont = new Font("Segoe UI", 9f), SmallFont = new Font("Segoe UI", 8f), BtnFont = new Font("Segoe UI Semibold", 8.5f);
  public const int PillH = 44;
  static Stopwatch clock = Stopwatch.StartNew();
  bool hover; long leftAt = -1; float curH = PillH; Timer tm; Point mouse = new Point(-1, -1);
  MiseLogo logo;
  public MisePop() {
    SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.SupportsTransparentBackColor, true);
    logo = new MiseLogo(); logo.Size = new Size(26, 26); logo.Location = new Point(10, 9); logo.BackColor = Color.Transparent; logo.TileC = Color.FromArgb(30, 30, 34);
    logo.MouseEnter += delegate { OnMouseEnter(EventArgs.Empty); }; logo.Click += delegate { Pinned = !Pinned; Kick(); };
    logo.MouseLeave += delegate { if (!ClientRectangle.Contains(PointToClient(Cursor.Position))) { hover = false; leftAt = clock.ElapsedMilliseconds; Kick(); } };
    Controls.Add(logo);
  }
  public MiseLogo Logo { get { return logo; } }
  public bool Open { get { return Needs || Pinned || hover; } }
  int RowH(int i) { return (i < Kinds.Length && Kinds[i] == "update") ? 34 : 22; }
  public int FullHeight() {
    int h = PillH + 6; for (int i = 0; i < Texts.Length; i++) h += RowH(i);
    return h + 40;
  }
  public int TargetHeight() { return Open ? FullHeight() : PillH; }
  // called after new data: size and motion follow
  public void Kick() {
    if (tm == null) { tm = new Timer(); tm.Interval = 15; tm.Tick += delegate { Step(); }; }
    if (!tm.Enabled) tm.Start();
  }
  protected override void Dispose(bool disposing) { if (disposing && tm != null) { tm.Stop(); tm.Dispose(); } base.Dispose(disposing); }
  void Step() {
    long now = clock.ElapsedMilliseconds;
    // a short grace before folding when the mouse leaves
    float target = (hover || (leftAt >= 0 && now - leftAt < 350) || Needs || Pinned) ? FullHeight() : PillH;
    float d = target - curH;
    if (Math.Abs(d) < 0.6f || !MiseBtn.Animate) curH = target; else curH += d * 0.28f;
    Form f = FindForm();
    if (f != null) { int nh = (int)Math.Round(curH); if (f.Height != nh) { int dh = nh - f.Height; f.Height = nh; if (AnchorBottom) f.Top -= dh; } }
    Invalidate();
    bool moving = Math.Abs(target - curH) >= 0.6f;
    if (!moving && !Running && !(leftAt >= 0 && now - leftAt < 400)) tm.Stop();
  }
  protected override void OnMouseEnter(EventArgs e) { hover = true; leftAt = -1; Kick(); base.OnMouseEnter(e); }
  protected override void OnMouseLeave(EventArgs e) {
    // leaving onto the logo is not leaving
    Point p = PointToClient(Cursor.Position); if (ClientRectangle.Contains(p)) { base.OnMouseLeave(e); return; }
    hover = false; leftAt = clock.ElapsedMilliseconds; mouse = new Point(-1, -1); Kick(); base.OnMouseLeave(e);
  }
  protected override void OnMouseMove(MouseEventArgs e) { mouse = e.Location; Invalidate(); base.OnMouseMove(e); }
  RectangleF StopRect() { return new RectangleF(12, curH - 32, 56, 22); }
  RectangleF HideRect() { return new RectangleF(Running ? 74 : 12, curH - 32, 56, 22); }
  RectangleF FixRect(int y, int rh) { return new RectangleF(Width - 52, y + 2, 40, 18); }
  protected override void OnMouseUp(MouseEventArgs e) {
    base.OnMouseUp(e);
    if (e.Y < PillH) { Pinned = !Pinned; Kick(); return; }
    if (Running && StopRect().Contains(e.X, e.Y)) { if (StopClick != null) StopClick(this, EventArgs.Empty); return; }
    if (HideRect().Contains(e.X, e.Y)) { if (HideClick != null) HideClick(this, EventArgs.Empty); return; }
    int y = PillH + 6;
    for (int i = 0; i < Texts.Length; i++) {
      int rh = RowH(i);
      if (i < Fix.Length && Fix[i] >= 0 && FixRect(y, rh).Contains(e.X, e.Y)) { FixIndex = Fix[i]; if (FixClick != null) FixClick(this, EventArgs.Empty); return; }
      y += rh;
    }
  }
  static GraphicsPath Round(RectangleF r, float rad) {
    rad = Math.Max(0.5f, Math.Min(rad, Math.Min(r.Width, r.Height) / 2f)); float d = rad * 2; GraphicsPath p = new GraphicsPath();
    p.AddArc(r.X, r.Y, d, d, 180, 90); p.AddArc(r.Right - d, r.Y, d, d, 270, 90); p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90); p.AddArc(r.X, r.Bottom - d, d, d, 90, 90); p.CloseFigure(); return p;
  }
  void Chip(Graphics g, RectangleF r, string t, Color c, bool hot) {
    using (GraphicsPath p = Round(r, 6f)) {
      if (hot) using (SolidBrush hb = new SolidBrush(Color.FromArgb(40, c))) g.FillPath(hb, p);
      using (Pen pen = new Pen(Color.FromArgb(hot ? 255 : 170, c))) g.DrawPath(pen, p);
    }
    StringFormat cf = new StringFormat(StringFormatFlags.NoWrap); cf.Alignment = StringAlignment.Center; cf.LineAlignment = StringAlignment.Center;
    using (SolidBrush b = new SolidBrush(c)) g.DrawString(t, BtnFont, b, r, cf);
  }
  protected override void OnPaint(PaintEventArgs pe) {
    Graphics g = pe.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias; g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
    if (BackColor.A == 255) g.Clear(BackColor);
    long now = clock.ElapsedMilliseconds;
    StringFormat sf = new StringFormat(StringFormatFlags.NoWrap); sf.LineAlignment = StringAlignment.Center; sf.Trimming = StringTrimming.EllipsisCharacter;
    StringFormat rf = new StringFormat(StringFormatFlags.NoWrap); rf.LineAlignment = StringAlignment.Center; rf.Alignment = StringAlignment.Far;
    // the pill: logo, what is happening, how many are ready and a ring (a check when done)
    float right = Width - 14;
    RectangleF ringR = new RectangleF(right - 18, (PillH - 18) / 2f, 18, 18);
    if (Done && !Problem) {
      using (SolidBrush cb = new SolidBrush(Accent)) g.FillEllipse(cb, ringR);
      using (Pen ck = new Pen(Color.FromArgb(23, 23, 26), 2f)) { ck.StartCap = LineCap.Round; ck.EndCap = LineCap.Round; g.DrawLines(ck, new PointF[] { new PointF(ringR.X + 5, ringR.Y + 9.5f), new PointF(ringR.X + 8, ringR.Y + 12.5f), new PointF(ringR.X + 13.5f, ringR.Y + 6.5f) }); }
    } else if (Problem && Done) {
      using (Pen wp = new Pen(Warn, 2f)) g.DrawEllipse(wp, ringR.X + 1, ringR.Y + 1, 16, 16);
      using (SolidBrush wb = new SolidBrush(Warn)) { StringFormat cf = new StringFormat(); cf.Alignment = StringAlignment.Center; cf.LineAlignment = StringAlignment.Center; g.DrawString("!", BtnFont, wb, ringR, cf); }
    } else {
      using (Pen tp = new Pen(LineC, 2.5f)) g.DrawEllipse(tp, ringR.X + 1, ringR.Y + 1, 16, 16);
      float sweep = Ring >= 0 ? Math.Max(8f, 360f * Ring) : 90f, start = Ring >= 0 ? -90f : (now % 1000) * 0.36f;
      using (Pen ap = new Pen(Accent, 2.5f)) { ap.StartCap = LineCap.Round; ap.EndCap = LineCap.Round; g.DrawArc(ap, ringR.X + 1, ringR.Y + 1, 16, 16, start, sweep); }
    }
    float cw = Count.Length > 0 ? g.MeasureString(Count, RowFont).Width + 4 : 0;
    using (SolidBrush mb = new SolidBrush(MutedC)) g.DrawString(Count, RowFont, mb, new RectangleF(right - 24 - cw, 0, cw, PillH), rf);
    using (SolidBrush hb = new SolidBrush(Accent)) g.DrawString(Head, HeadFont, hb, new RectangleF(44, 0, right - 30 - cw - 44, PillH), sf);
    if (curH <= PillH + 2) { sf.Dispose(); rf.Dispose(); return; }
    // the step list: seconds, a dot (filled = done, open = now, open amber = needs a look or League updating), the step in plain words
    using (Pen sp = new Pen(Color.FromArgb(60, LineC))) g.DrawLine(sp, 12, PillH + 1, Width - 12, PillH + 1);
    int y = PillH + 6;
    float pulse = (float)(0.55 + 0.45 * Math.Sin(now / 160.0));
    for (int i = 0; i < Texts.Length; i++) {
      int rh = RowH(i); string k = i < Kinds.Length ? Kinds[i] : "done";
      Color tc = k == "warn" ? Warn : TextC, dc = (k == "warn" || k == "update") ? Warn : Accent;
      using (SolidBrush mb = new SolidBrush(MutedC)) g.DrawString(i < Times.Length ? Times[i] : "", SmallFont, mb, new RectangleF(4, y, 34, 22), rf);
      RectangleF dot = new RectangleF(46, y + 7, 9, 9);
      if (k == "done") using (SolidBrush db = new SolidBrush(dc)) g.FillEllipse(db, dot);
      else using (Pen dp = new Pen(Color.FromArgb(k == "now" ? (int)(255 * pulse) : 255, dc), 2f)) g.DrawEllipse(dp, dot.X + 1, dot.Y + 1, 7, 7);
      float tw = Width - 64 - 14 - ((i < Fix.Length && Fix[i] >= 0) ? 48 : 0);
      using (SolidBrush tb = new SolidBrush(tc)) g.DrawString(Texts[i], RowFont, tb, new RectangleF(62, y, tw, 22), sf);
      if (i < Fix.Length && Fix[i] >= 0) { RectangleF fr = FixRect(y, rh); Chip(g, fr, "Fix", Accent, fr.Contains(mouse)); }
      if (k == "update") {
        float pct = i < Pcts.Length ? Pcts[i] : -1f; RectangleF br = new RectangleF(62, y + 24, Width - 62 - 24, 3);
        using (GraphicsPath bp = Round(br, 1.5f)) using (SolidBrush bb = new SolidBrush(LineC)) g.FillPath(bb, bp);
        float bw = pct >= 0 ? br.Width * Math.Min(100f, pct) / 100f : br.Width * 0.3f, bx = pct >= 0 ? br.X : br.X + (br.Width - bw) * (float)(0.5 + 0.5 * Math.Sin(now / 400.0));
        if (bw > 1) using (GraphicsPath fp = Round(new RectangleF(bx, br.Y, bw, br.Height), 1.5f)) using (SolidBrush fb = new SolidBrush(Warn)) g.FillPath(fb, fp);
      }
      y += rh;
    }
    // footer: Stop while it runs, Hide always
    if (Running) Chip(g, StopRect(), "Stop", Accent, StopRect().Contains(mouse));
    Chip(g, HideRect(), "Hide", MutedC, HideRect().Contains(mouse));
    sf.Dispose(); rf.Dispose();
  }
}

// ---------- the tray menu: compact, drawn by Mise in the current look ----------
// Kind: item | label (small section title, not clickable) | card (what is running, with its Exit / Stop button)
public class MiseMenuItem : ToolStripItem {
  public string Kind = "item";
  public string Glyph = "";        // open | play | user | check | edit | restart | quit | update | feedback
  public string Right = "";        // small text at the right end (hotkey, region)
  public bool Strong = false;      // bold (Open Mise)
  public bool Lit = false;         // accent colour (the logged-in account)
  public string SubText = "";      // card: second line
  public string Action = "";       // card: button text (Exit / Stop)
  public event EventHandler ActionClick;
  public static Color TextC = Color.FromArgb(238, 237, 234), MutedC = Color.FromArgb(138, 136, 132), HoverC = Color.FromArgb(45, 45, 51), AccentC = Color.FromArgb(216, 137, 90), LineC = Color.FromArgb(56, 56, 63), CardC = Color.FromArgb(37, 34, 32), CardLine = Color.FromArgb(74, 56, 40);
  public static Font F = new Font("Segoe UI", 9f), FB = new Font("Segoe UI Semibold", 9f), FS = new Font("Segoe UI", 7.5f), FL = new Font("Segoe UI Semibold", 6.75f);
  bool actHot = false;
  // a fixed size: the menu takes its width from the items' sizes
  public MiseMenuItem(string text, string kind) : base() { Text = text; Kind = kind; AutoSize = false; Size = GetPreferredSize(Size.Empty); }
  public override bool CanSelect { get { return Kind == "item"; } }
  protected override bool DismissWhenClicked { get { return Kind == "item"; } }
  public override Size GetPreferredSize(Size constrainingSize) { return new Size(236, Kind == "card" ? 46 : Kind == "label" ? 19 : 25); }
  RectangleF ActRect() { return new RectangleF(Width - 64, (Height - 22) / 2f, 54, 22); }
  protected override void OnMouseMove(MouseEventArgs e) { if (Kind == "card") { bool h = ActRect().Contains(e.X, e.Y); if (h != actHot) { actHot = h; Invalidate(); } } base.OnMouseMove(e); }
  protected override void OnMouseLeave(EventArgs e) { if (actHot) { actHot = false; Invalidate(); } base.OnMouseLeave(e); }
  protected override void OnMouseUp(MouseEventArgs e) {
    base.OnMouseUp(e);
    if (Kind == "card" && Action.Length > 0 && ActRect().Contains(e.X, e.Y)) {
      ToolStripDropDown dd = Owner as ToolStripDropDown; if (dd != null) dd.Close(ToolStripDropDownCloseReason.ItemClicked);
      if (ActionClick != null) ActionClick(this, EventArgs.Empty);
    }
  }
  static GraphicsPath Round(RectangleF r, float rad) {
    rad = Math.Max(0.5f, Math.Min(rad, Math.Min(r.Width, r.Height) / 2f)); float d = rad * 2; GraphicsPath p = new GraphicsPath();
    p.AddArc(r.X, r.Y, d, d, 180, 90); p.AddArc(r.Right - d, r.Y, d, d, 270, 90); p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90); p.AddArc(r.X, r.Bottom - d, d, d, 90, 90); p.CloseFigure(); return p;
  }
  // small line icons on a 16 x 16 grid
  public static void DrawGlyph(Graphics g, string kind, RectangleF r, Color c) {
    GraphicsState st = g.Save(); g.TranslateTransform(r.X, r.Y); g.ScaleTransform(r.Width / 16f, r.Height / 16f);
    using (Pen p = new Pen(c, 1.4f)) using (SolidBrush b = new SolidBrush(c)) {
      p.StartCap = LineCap.Round; p.EndCap = LineCap.Round; p.LineJoin = LineJoin.Round;
      switch (kind) {
        case "open": using (GraphicsPath gp = Round(new RectangleF(2, 3, 12, 10), 2)) g.DrawPath(p, gp); g.DrawLine(p, 2, 6, 14, 6); break;
        case "play": g.FillPolygon(b, new PointF[] { new PointF(5, 3), new PointF(13, 8), new PointF(5, 13) }); break;
        case "user": g.DrawEllipse(p, 5.4f, 3.4f, 5.2f, 5.2f); g.DrawArc(p, 3f, 10.2f, 10f, 8f, 200, 140); break;
        case "check": using (Pen q = new Pen(c, 1.8f)) { q.StartCap = LineCap.Round; q.EndCap = LineCap.Round; g.DrawLines(q, new PointF[] { new PointF(3, 8.5f), new PointF(6, 11.5f), new PointF(13, 4.5f) }); } break;
        case "edit": g.DrawPolygon(p, new PointF[] { new PointF(3, 13), new PointF(4, 10), new PointF(11, 3), new PointF(13, 5), new PointF(6, 12) }); break;
        case "restart": g.DrawArc(p, 3, 3, 10, 10, -40, 300); g.DrawLines(p, new PointF[] { new PointF(13, 2.5f), new PointF(13, 5.5f), new PointF(10, 5.5f) }); break;
        case "quit": g.DrawLine(p, 8, 2, 8, 8); g.DrawArc(p, 3, 3.5f, 10, 10, -50, 280); break;
        case "update": g.DrawLine(p, 8, 2.5f, 8, 10.5f); g.DrawLines(p, new PointF[] { new PointF(4.5f, 7.5f), new PointF(8, 11), new PointF(11.5f, 7.5f) }); g.DrawLine(p, 3, 13.5f, 13, 13.5f); break;
        case "arrange": using (GraphicsPath a1 = Round(new RectangleF(2.5f, 2.5f, 4.8f, 4.8f), 1.2f)) g.DrawPath(p, a1); using (GraphicsPath a2 = Round(new RectangleF(8.7f, 2.5f, 4.8f, 4.8f), 1.2f)) g.DrawPath(p, a2); using (GraphicsPath a3 = Round(new RectangleF(2.5f, 8.7f, 4.8f, 4.8f), 1.2f)) g.DrawPath(p, a3); using (GraphicsPath a4 = Round(new RectangleF(8.7f, 8.7f, 4.8f, 4.8f), 1.2f)) g.DrawPath(p, a4); break;
        case "feedback": using (GraphicsPath gp = Round(new RectangleF(2, 3, 12, 8), 2)) g.DrawPath(p, gp); g.DrawLines(p, new PointF[] { new PointF(5, 11), new PointF(5, 14), new PointF(8, 11) }); break;
      }
    }
    g.Restore(st);
  }
  protected override void OnPaint(PaintEventArgs e) {
    Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias; g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
    StringFormat sf = new StringFormat(StringFormatFlags.NoWrap); sf.LineAlignment = StringAlignment.Center; sf.Trimming = StringTrimming.EllipsisCharacter;
    if (Kind == "label") {
      using (SolidBrush b = new SolidBrush(MutedC)) g.DrawString(Text.ToUpper(), FL, b, new RectangleF(10, 3, Width - 14, Height - 3), sf);
    } else if (Kind == "card") {
      RectangleF cr = new RectangleF(4.5f, 2.5f, Width - 9, Height - 5);
      using (GraphicsPath p = Round(cr, 8)) { using (SolidBrush b = new SolidBrush(CardC)) g.FillPath(b, p); using (Pen pen = new Pen(CardLine)) g.DrawPath(pen, p); }
      using (SolidBrush d = new SolidBrush(AccentC)) g.FillEllipse(d, 13, Height / 2f - 3.5f, 7, 7);
      float tw = Width - 28 - 70;
      using (SolidBrush b = new SolidBrush(TextC)) g.DrawString(Text, FB, b, new RectangleF(27, 6, tw, 17), sf);
      using (SolidBrush b = new SolidBrush(MutedC)) g.DrawString(SubText, FS, b, new RectangleF(27, 23, tw, 15), sf);
      if (Action.Length > 0) {
        RectangleF ar = ActRect();
        using (GraphicsPath ap = Round(ar, 6)) {
          if (actHot) using (SolidBrush hb = new SolidBrush(Color.FromArgb(46, AccentC))) g.FillPath(hb, ap);
          using (Pen ap2 = new Pen(Color.FromArgb(actHot ? 255 : 150, AccentC))) g.DrawPath(ap2, ap);
        }
        StringFormat cf = new StringFormat(StringFormatFlags.NoWrap); cf.Alignment = StringAlignment.Center; cf.LineAlignment = StringAlignment.Center;
        using (SolidBrush ab = new SolidBrush(AccentC)) g.DrawString(Action, FB, ab, ar, cf);
      }
    } else {
      if (Selected && Enabled) using (GraphicsPath p = Round(new RectangleF(4, 1, Width - 8, Height - 2), 6)) using (SolidBrush b = new SolidBrush(HoverC)) g.FillPath(b, p);
      Color c = Lit ? AccentC : TextC;
      if (Glyph.Length > 0) DrawGlyph(g, Glyph, new RectangleF(12, (Height - 14) / 2f, 14, 14), Lit ? AccentC : Color.FromArgb(185, c));
      float rw = Right.Length > 0 ? g.MeasureString(Right, FS).Width + 6 : 0;
      using (SolidBrush b = new SolidBrush(c)) g.DrawString(Text, Strong ? FB : F, b, new RectangleF(33, 0, Width - 33 - rw - 12, Height), sf);
      if (Right.Length > 0) {
        StringFormat rf = new StringFormat(StringFormatFlags.NoWrap); rf.Alignment = StringAlignment.Far; rf.LineAlignment = StringAlignment.Center;
        using (SolidBrush b = new SolidBrush(Lit ? AccentC : MutedC)) g.DrawString(Right, FS, b, new RectangleF(Width - rw - 12, 0, rw, Height), rf);
      }
    }
    sf.Dispose();
  }
}
public class MiseMenuRenderer : ToolStripProfessionalRenderer {
  public string Theme = "ember"; public Color Bg = Color.FromArgb(27, 27, 31), Line = Color.FromArgb(56, 56, 63), Sep = Color.FromArgb(44, 44, 49);
  Bitmap back; Size backSize; string backTheme = "";
  public MiseMenuRenderer() : base() { RoundedEdges = false; }
  protected override void OnRenderToolStripBackground(ToolStripRenderEventArgs e) {
    Size s = e.ToolStrip.Size;
    if (MiseGlass.IsGlass(Theme)) {
      if (back == null || backSize != s || backTheme != Theme) { if (back != null) back.Dispose(); back = MiseGlass.Render(Theme, s.Width, s.Height); backSize = s; backTheme = Theme; }
      e.Graphics.DrawImageUnscaled(back, 0, 0);
    } else using (SolidBrush b = new SolidBrush(Bg)) e.Graphics.FillRectangle(b, 0, 0, s.Width, s.Height);
  }
  protected override void OnRenderToolStripBorder(ToolStripRenderEventArgs e) { using (Pen p = new Pen(Line)) e.Graphics.DrawRectangle(p, 0, 0, e.ToolStrip.Width - 1, e.ToolStrip.Height - 1); }
  protected override void OnRenderImageMargin(ToolStripRenderEventArgs e) { }
  protected override void OnRenderSeparator(ToolStripSeparatorRenderEventArgs e) { int y = e.Item.Height / 2; using (Pen p = new Pen(Sep)) e.Graphics.DrawLine(p, 10, y, e.Item.Width - 10, y); }
}
'@
Update-MiseLook (Get-MiseConfig)

# ---------- small app icons for routine rows ----------
# Store apps have no exe to read an icon from: the shell hands out their icon by app id. Optional: without it a letter badge is drawn.
try {
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System; using System.Drawing; using System.Drawing.Imaging; using System.Runtime.InteropServices;
public static class MiseShellIcon {
  [StructLayout(LayoutKind.Sequential)] public struct SIZE { public int cx; public int cy; }
  [ComImport, Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  public interface IShellItemImageFactory { [PreserveSig] int GetImage(SIZE size, int flags, out IntPtr phbm); }
  [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
  static extern int SHCreateItemFromParsingName(string path, IntPtr pbc, ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out IShellItemImageFactory item);
  [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr h);
  public static Bitmap Get(string parsingName, int px) {
    Guid iid = new Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b"); IShellItemImageFactory f;
    if (SHCreateItemFromParsingName(parsingName, IntPtr.Zero, ref iid, out f) != 0 || f == null) return null;
    SIZE s; s.cx = px; s.cy = px; IntPtr hb;
    if (f.GetImage(s, 4, out hb) != 0 || hb == IntPtr.Zero) return null;   // 4 = icon only
    try {
      using (Bitmap raw = Image.FromHbitmap(hb)) {
        // FromHbitmap drops the alpha channel: read the same pixels again as premultiplied ARGB
        Rectangle r = new Rectangle(0, 0, raw.Width, raw.Height);
        BitmapData d = raw.LockBits(r, ImageLockMode.ReadOnly, PixelFormat.Format32bppRgb);
        try {
          int n = d.Stride * d.Height; byte[] buf = new byte[n]; Marshal.Copy(d.Scan0, buf, 0, n);
          bool anyAlpha = false; for (int i = 3; i < n; i += 4) if (buf[i] != 0) { anyAlpha = true; break; }
          Bitmap outB = new Bitmap(raw.Width, raw.Height, anyAlpha ? PixelFormat.Format32bppPArgb : PixelFormat.Format32bppRgb);
          BitmapData o = outB.LockBits(r, ImageLockMode.WriteOnly, outB.PixelFormat);
          for (int y = 0; y < d.Height; y++) Marshal.Copy(buf, y * d.Stride, new IntPtr(o.Scan0.ToInt64() + (long)y * o.Stride), Math.Min(d.Stride, o.Stride));
          outB.UnlockBits(o); return outB;
        } finally { raw.UnlockBits(d); }
      }
    } finally { DeleteObject(hb); }
  }
}
"@
} catch {}
$script:tileIcons = @{}
function New-LetterIcon([string]$name) {
  $bmp = New-Object Drawing.Bitmap(32, 32); $g = [Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'
  $bg = New-Object Drawing.SolidBrush($script:C.Line); $g.FillEllipse($bg, 1, 1, 30, 30); $bg.Dispose()
  $ch = '?'; $n = "$name".Trim(); if ($n) { $ch = $n.Substring(0, 1).ToUpper() }
  $sf = New-Object Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
  $f = New-Object Drawing.Font('Segoe UI Semibold', 13); $tb = New-Object Drawing.SolidBrush($script:C.Text)
  $g.DrawString($ch, $f, $tb, (New-Object Drawing.RectangleF(0, 1, 32, 32)), $sf); $f.Dispose(); $tb.Dispose(); $sf.Dispose(); $g.Dispose()
  return $bmp
}
function Get-ExeIcon([string]$exe) {
  if (-not $exe -or -not (Test-Path -LiteralPath $exe)) { return $null }
  try { $ic = [Drawing.Icon]::ExtractAssociatedIcon($exe); if ($ic) { return $ic.ToBitmap() } } catch {}
  return $null
}
# the icon of the app a tile opens (cached while the window is open); never fails: a letter badge is the fallback
function Get-TileIcon($tile, $browser) {
  $key = "$($tile.kind)|$($tile.exe)|$($tile.appid)|$($tile.name)"
  if ($script:tileIcons.ContainsKey($key)) { return $script:tileIcons[$key] }
  $img = $null
  try {
    switch ("$($tile.kind)") {
      { $_ -in 'web', 'ugg' } { if ($browser -and $browser.Exe) { $img = Get-ExeIcon $browser.Exe } }
      'league' { $ld = Get-LeagueDir; if ($ld) { $img = Get-ExeIcon (Join-Path $ld 'LeagueClient.exe') }; if (-not $img) { $img = Get-ExeIcon (Get-RiotClientExe) } }
      'spotify' { $img = Get-ExeIcon (Join-Path $env:APPDATA 'Spotify\Spotify.exe') }
      'stream' { $dc = Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'Discord\app-*\Discord.exe') -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1; if ($dc) { $img = Get-ExeIcon $dc.FullName } }
    }
    if (-not $img -and $tile.exe) { $img = Get-ExeIcon (Resolve-TileExe "$($tile.exe)") }
    if (-not $img -and $tile.appid) { try { $img = [MiseShellIcon]::Get("shell:AppsFolder\$($tile.appid)", 32) } catch {} }
    if (-not $img -and "$($tile.kind)" -eq 'spotify') { try { $sa = Get-StartApps | Where-Object { $_.Name -eq 'Spotify' } | Select-Object -First 1; if ($sa) { $img = [MiseShellIcon]::Get("shell:AppsFolder\$($sa.AppID)", 32) } } catch {} }
  } catch {}
  if (-not $img) { $img = New-LetterIcon "$($tile.name)" }
  $script:tileIcons[$key] = $img
  return $img
}

function New-Btn($text, $x = 0, $y = 0, $w = 100, $h = 34, $kind = 'tool', $font = $null) {
  $b = New-Object MiseBtn
  $b.Text = $text; $b.Font = $(if ($font) { $font } else { $script:fBtn }); $b.Kind = $kind
  $b.Accent = $script:C.Accent; $b.TextC = $script:C.Text; $b.MutedC = $script:C.Muted
  $b.PanelC = $script:C.GPanel; $b.HoverC = $script:C.GHover; $b.LineC = $script:C.GLine; $b.Surface = $script:C.Surface
  if ($script:C.Glass) { $b.BackColor = [Drawing.Color]::Transparent }
  $b.Location = New-Object Drawing.Point($x, $y); $b.Size = New-Object Drawing.Size($w, $h)
  return $b
}
function New-Label($text, $font, $color, $x, $y, $w, $h) {
  $l = New-Object Windows.Forms.Label
  $l.Text = $text; $l.Font = $font; $l.ForeColor = $color; $l.BackColor = [Drawing.Color]::Transparent
  $l.Location = New-Object Drawing.Point($x, $y); $l.Size = New-Object Drawing.Size($w, $h)
  return $l
}

# borderless Mise window: rounded corners + graphite border on Windows 11, thin frame elsewhere, drag anywhere on empty space
function Set-MiseFrame($f) {
  $f.FormBorderStyle = 'None'; $f.BackColor = $script:C.Bg; $f.ForeColor = $script:C.Text
  $f.Add_HandleCreated({ param($s, $e) try { $v = 2; [MiseUi]::DwmSetWindowAttribute($s.Handle, 33, [ref]$v, 4) | Out-Null; $l = $script:C.Line; $bc = [int]$l.R + 256 * [int]$l.G + 65536 * [int]$l.B; [MiseUi]::DwmSetWindowAttribute($s.Handle, 34, [ref]$bc, 4) | Out-Null } catch {} })
  $f.Add_Paint({ param($s, $e) $p = New-Object Drawing.Pen($script:C.Line, 1); $e.Graphics.DrawRectangle($p, 0, 0, $s.ClientSize.Width - 1, $s.ClientSize.Height - 1); $p.Dispose() })
  $f.Add_MouseDown({ param($s, $e) if ($e.Button -eq 'Left') { [MiseUi]::ReleaseCapture() | Out-Null; [MiseUi]::SendMessage($s.Handle, 0xA1, 2, 0) | Out-Null } })
  Set-MiseBackdrop $f; Set-MiseAppId $f
}
# glass looks: the backdrop behind the window; panels and labels in the base colour turn see-through (also ones added later)
function Set-MiseBackdrop($f) { if ($script:C.Glass) { try { [MiseGlass]::Attach($f, $script:C.Theme, $script:C.Bg) } catch {} } }
function Add-DragHandle($ctrl, $form) {
  $ctrl.Tag = $form
  $ctrl.Add_MouseDown({ param($s, $e) if ($e.Button -eq 'Left') { $f = $s.FindForm(); [MiseUi]::ReleaseCapture() | Out-Null; [MiseUi]::SendMessage($f.Handle, 0xA1, 2, 0) | Out-Null } })
}

# a window opens: it fades in and rises 10 px, timed by the clock (skipped when animations are off)
function Start-OpenAnimation($f) {
  if (-not $script:Animate) { return }
  $f.Opacity = 0
  $t = New-Object Windows.Forms.Timer; $t.Interval = 10
  $t.Tag = @{ Form = $f; Clock = [Diagnostics.Stopwatch]::StartNew(); Top = $f.Top }
  $f.Top = $f.Top + 10
  $t.Add_Tick({ param($s, $e)
    $st = $s.Tag; $k = [Math]::Min(1.0, $st.Clock.ElapsedMilliseconds / 200.0); $ek = 1 - [Math]::Pow(1 - $k, 3)
    $st.Form.Opacity = $ek; $st.Form.Top = $st.Top + [int][Math]::Round(10 * (1 - $ek))
    if ($k -ge 1.0) { $s.Stop(); $st.Form.Opacity = 1; $st.Form.Top = $st.Top }
  })
  $t.Start()
}
# the opening of the Mise window: the bowls drop onto the counter, then the rows slide in top to bottom
function Start-RowsIn($logo, $rows) {
  if (-not $script:Animate) { return }
  if ($logo) { try { $logo.Intro() } catch {} }
  $d = 260; foreach ($b in @($rows)) { if ($b -is [MiseBtn] -and $b.Visible) { $b.SlideIn($d); $d += 45 } }
}

# the Mise mark (logo G3, warm glow) as a compiled control; .State: 0 idle, 1 busy, 2 done, 3 needs a look
function New-Logo($x, $y, [int]$size = 32) {
  $logo = New-Object MiseLogo
  $logo.Location = New-Object Drawing.Point($x, $y); $logo.Size = New-Object Drawing.Size($size, $size)
  $logo.BackColor = $script:C.Bg; $logo.Accent = $script:LogoCopper   # the logo is copper in every look
  return $logo
}

# ---------- friendly progress text: turns the step log into plain steps ----------
$script:qNames = @{ 400 = 'Draft'; 420 = 'Ranked Solo/Duo'; 440 = 'Ranked Flex'; 450 = 'ARAM'; 480 = 'Swiftplay'; 1700 = 'Arena'; 1740 = 'Arena'; 2400 = 'ARAM Mayhem'; 4320 = 'Jade (event)' }
function Get-Friendly($lines) {
  $steps = New-Object System.Collections.Generic.List[string]
  $items = New-Object System.Collections.Specialized.OrderedDictionary   # app name -> busy | ok | bad (the pop-up's step list)
  $why = @{}   # app name -> what went wrong: missing | nobrowser | nowindow | noscreen | mini | league | login (the pop-up's fix buttons)
  $res = @{ Head = ''; Done = $false; Problem = $false; Steps = $steps; Items = $items; Why = $why; Updating = $null }
  foreach ($raw in @($lines)) {
    $l = ("$raw" -replace '^\[\s*\d+s\]\s*', '').Trim()
    if ($l -eq '') { continue }
    if ($l -match '^\[([^\]]+)\] (.+)$') {
      $who = $Matches[1]; $what = $Matches[2]
      if ($who -in 'riot', 'League') {
        if ($what -match '^(switching to|starting|updating|update finished)') { if ("$($items['League'])" -ne 'ok') { $items['League'] = 'busy' } }
        elseif ($what -match '^(ready|running in the background)') { $items['League'] = 'ok' }
        elseif ($what -match '^needs a look') { $items['League'] = 'bad'; $why['League'] = 'league' }
      } elseif ($who -notin 'taskbar', 'desktop', 'wait', 'Routes', 'Health check', 'Play', 'stream', 'switch') {
        if ($what -match "^app doesn't exist") { $items[$who] = 'bad'; $why[$who] = 'missing' }
        elseif ($what -match "^(Chrome or Edge doesn't exist|no browser found)") { $items[$who] = 'bad'; $why[$who] = 'nobrowser' }
        elseif ($what -match '^no (Spotify )?window found') { $items[$who] = 'bad'; $why[$who] = 'nowindow' }
        elseif ($what -match '^its screen is not connected') { $items[$who] = 'bad'; $why[$who] = 'noscreen' }
        elseif ($what -match '^open the miniplayer once') { $items[$who] = 'bad'; $why[$who] = 'mini' }
        elseif ($what -match '^(starting|opening)') { if ("$($items[$who])" -ne 'ok') { $items[$who] = 'busy' } }
        elseif ($what -match '^(placed|miniplayer placed|already open|closed|put back)') { $items[$who] = 'ok' }
      }
    } elseif ($items.Contains('League')) {
      if ($l -match '^client OK|lobby open \(queue|already in Lobby') { $items['League'] = 'ok' }
      elseif ($l -match 'login rejected|^Mise stopped') { $items['League'] = 'bad'; $why['League'] = 'login' }
      elseif ($l -match 'could not open a lobby|^Mise finished, but') { $items['League'] = 'bad'; $why['League'] = 'league' }
    }
    $t = $null
    if ($l -match "^\[switch\] leaving '(.+)'$") { $t = "Leaving $($Matches[1])" }
    if ($l -match "^(Starting|Exiting) '(.+)'$") { if (-not $res.Head) { $res.Head = "$($Matches[1]) $($Matches[2])" } ; continue }
    if ($l -match '^(Switching to|Checking the client|Fixing the League client|Arranging|Saving )') { if (-not $res.Head) { $res.Head = $l }; continue }
    if ($t) { }
    elseif ($l -match "^\[([^\]]+)\] app doesn't exist") { $t = "!$($Matches[1]) is not installed - skipped" }
    elseif ($l -match "^\[([^\]]+)\] (Chrome or Edge doesn't exist)") { $t = "!Needs Chrome or Edge for $($Matches[1])" }
    elseif ($l -match 'opens when you pick a champion') { $t = 'u.gg opens when you pick a champion' }
    elseif ($l -match '^\[League\] updating( \d+%)?') { $t = "League is updating$($Matches[1]) - waiting, not pressing Play"; $res.Updating = "$($Matches[1])".Trim() }
    elseif ($l -match '^\[League\] update finished') { $t = 'League updated - starting it'; $res.Updating = '' }
    elseif ($l -match '^\[League\] starting') { $t = 'Starting League' }
    elseif ($l -match '^\[(?!riot\])([^\]]+)\] (starting|opening)') { $t = "Opening $($Matches[1])" }
    elseif ($l -match '^\[([^\]]+)\] (placed|miniplayer placed|already open)') { $t = "$($Matches[1]) in place" }
    elseif ($l -match '^\[([^\]]+)\] open the miniplayer once') { $t = "!Open the Spotify miniplayer once, then press Re-arrange" }
    elseif ($l -match '^\[([^\]]+)\] no (Spotify )?window found') { $t = "!$($Matches[1]) did not open a window" }
    elseif ($l -match '^\[([^\]]+)\] (closed|put back)') { $t = "$($Matches[1]) $($Matches[2])" }
    elseif ($l -match '^\[taskbar\] hidden') { $t = 'Taskbar hidden on the side screen' }
    elseif ($l -match '^\[taskbar\] restored') { $t = 'Taskbars back' }
    elseif ($l -match '^\[wait\] (\d+)') { $t = "Waiting $($Matches[1]) s" }
    elseif ($l -match '^\[riot\] switching to (.+)$') { $t = "Switching to $($Matches[1])" }
    elseif ($l -match '^\[riot\] starting with the current login') { $t = 'Starting League' }
    elseif ($l -match 'Closing Riot Client so the login') { $t = 'Saving the login' }
    elseif ($l -match 'kept the login of') { $t = 'Saved the previous login' }
    elseif ($l -match 'region set to (\w+)') { $t = "Region set to $($Matches[1])" }
    elseif ($l -match '\[League\] starting') { $t = 'Starting League' }
    elseif ($l -match '^\[Health check\]') { $t = 'Waiting for the client to open' }
    elseif ($l -match 'Play button is ready|pressing Play') { $t = 'Pressing Play in Riot Client' }
    elseif ($l -match 'fix 1/3') { $t = 'Client is stuck - reloading it' }
    elseif ($l -match 'fix 2/3') { $t = 'Client is stuck - restarting League' }
    elseif ($l -match 'fix 3/3|still not opening - restarting Riot') { $t = 'Client is stuck - restarting Riot Client' }
    elseif ($l -match 'client broke after Play') { $t = 'Client hiccup after Play - repairing it' }
    elseif ($l -match '^client OK') { $t = 'Client is ready' }
    elseif ($l -match 'checking which lobbies work') { $t = 'Lobby did not open as expected - testing the lobbies' }
    elseif ($l -match '\[Routes\] updated') { $t = 'Lobby routes updated' }
    elseif ($l -match 'lobby open \(queue (\d+)\)') { $q = [int]$Matches[1]; $n = $script:qNames[$q]; if (-not $n) { $n = "queue $q" }; $t = "Lobby open: $n" }
    elseif ($l -match 'already in Lobby') { $t = 'Already in a lobby' }
    elseif ($l -match 'could not open a lobby') { $t = '!Could not open a lobby'; $res.Problem = $true }
    elseif ($l -match 'login rejected') { $t = "!Login rejected. Log in by hand in Riot Client, then save the account again in League accounts."; $res.Problem = $true; $res.Done = $true }
    elseif ($l -match '^\[riot\] (ready|running in the background)') { }
    elseif ($l -match '^\[riot\] needs a look') { $t = '!League needs a look - try Fix League client (Settings)'; $res.Problem = $true }
    elseif ($l -match 'game is running') { $t = '!A game is running - finish it first'; $res.Problem = $true; $res.Done = $true }
    elseif ($l -match '^Saved the current login') { $t = 'Login saved' }
    elseif ($l -match "^No routine called") { $t = "!$l"; $res.Problem = $true; $res.Done = $true }
    elseif ($l -match "step '.+' failed") { $t = '!A step failed - see the log'; $res.Problem = $true }
    elseif ($l -match '^Mise ready') { $t = 'Ready'; $res.Done = $true }
    elseif ($l -match '^Mise finished, but') { $t = '!Finished - League needs a look (try Fix League client)'; $res.Problem = $true; $res.Done = $true }
    elseif ($l -match '^Stopped by you') { $t = 'Stopped'; $res.Done = $true }
    elseif ($l -match '^Mise stopped') { $t = '!Stopped - the saved login was rejected'; $res.Problem = $true; $res.Done = $true }
    if ($t -and $t.StartsWith('League is updating')) { for ($k = $steps.Count - 1; $k -ge 0; $k--) { if ($steps[$k].StartsWith('League is updating')) { $steps.RemoveAt($k) } } }
    if ($t -and -not $steps.Contains($t)) { [void]$steps.Add($t) }
  }
  return $res
}
function Format-Friendly($fr) {
  $o = New-Object System.Collections.Generic.List[string]
  if ($fr.Head) { [void]$o.Add($fr.Head); [void]$o.Add('') }
  $n = $fr.Steps.Count
  for ($i = 0; $i -lt $n; $i++) {
    $s = $fr.Steps[$i]
    if ($s.StartsWith('!')) { [void]$o.Add(([string][char]0x26A0) + '  ' + $s.Substring(1)) }
    elseif ($i -eq $n - 1 -and -not $fr.Done) { [void]$o.Add(([string][char]0x203A) + '  ' + $s + ' ...') }
    else { [void]$o.Add(([string][char]0x2713) + '  ' + $s) }
  }
  return ($o -join "`r`n")
}
