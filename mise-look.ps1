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

# ---------- colours ----------
$script:AccentChoices = [ordered]@{ Copper = '#D8895A'; Amber = '#E0A43C'; Sage = '#8DB58A'; Teal = '#4FB3A9'; Sky = '#5FA8E8'; Iris = '#8E8CE6'; Rose = '#E07A93'; Silver = '#B8B8BE' }
function ConvertTo-Color([string]$hex) {
  try { $h = $hex.TrimStart('#'); return [Drawing.Color]::FromArgb([Convert]::ToInt32($h.Substring(0, 2), 16), [Convert]::ToInt32($h.Substring(2, 2), 16), [Convert]::ToInt32($h.Substring(4, 2), 16)) }
  catch { return [Drawing.Color]::FromArgb(216, 137, 90) }
}
function Update-MiseLook($cfg) {
  $script:C = @{
    Bg = [Drawing.Color]::FromArgb(23, 23, 26); Panel = [Drawing.Color]::FromArgb(33, 33, 37); Hover = [Drawing.Color]::FromArgb(45, 45, 51)
    Line = [Drawing.Color]::FromArgb(56, 56, 63); Accent = (ConvertTo-Color "$(Get-MiseSetting $cfg 'accent')")
    Text = [Drawing.Color]::FromArgb(238, 237, 234); Muted = [Drawing.Color]::FromArgb(138, 136, 132)
  }
  $script:Animate = [bool](Get-MiseSetting $cfg 'animations')
  try { [MiseBtn]::Animate = $script:Animate; [MiseLogo]::Animate = $script:Animate } catch {}
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
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @"
using System; using System.Drawing; using System.Drawing.Drawing2D; using System.Drawing.Text; using System.Windows.Forms; using System.Diagnostics;
// one eased value over time (driven by a Stopwatch, never by the timer's tick count)
public class MiseTween {
  public float From, To; public long Start; public int Dur;
  public MiseTween(float v) { From = v; To = v; Start = 0; Dur = 0; }
  public static float Ease(float k) { k = Math.Max(0f, Math.Min(1f, k)); float i = 1f - k; return 1f - i * i * i; }
  public float At(long now) { if (Dur <= 0) return To; float k = (now - Start) / (float)Dur; if (k >= 1f) return To; return From + (To - From) * Ease(k); }
  public bool Running(long now) { return Dur > 0 && now - Start < Dur; }
  public void Go(long now, float to, int dur, bool animate) { From = At(now); To = to; Start = now; Dur = animate ? dur : 0; }
}
public class MiseBtn : Button {
  public string Kind = "tool";     // tool | primary | ghost | row | setting | seg
  public string Num = "";          // row: number
  public string Sub = "";          // row: small grey text on the right
  public string Chip = "";         // row: region chip / setting: value
  public bool Dots = false;        // row: a ... at the right end (its own click zone, see DotsHit)
  public bool DotsHit(int x) { return Dots && x >= Width - 36; }
  public bool IsSwitch = false;    // setting: draw a sliding switch instead of a value
  public string Seg = "";          // setting / seg: two choices "A|B", On picks B
  public Color Surface = Color.FromArgb(23, 23, 26);
  public Color PanelC = Color.FromArgb(33, 33, 37);
  public Color HoverC = Color.FromArgb(45, 45, 51);
  public Color LineC = Color.FromArgb(56, 56, 63);
  public Color Accent = Color.FromArgb(216, 137, 90);
  public static bool Animate = true;   // off: every state jumps to its end
  public Color TextC = Color.FromArgb(238, 237, 234);
  public Color MutedC = Color.FromArgb(138, 136, 132);
  public Font SmallFont = new Font("Segoe UI", 9f);
  public Font TinyFont = new Font("Segoe UI Semibold", 8.5f);
  bool hov, on;
  float hv = 0f;
  Timer fade, anim;
  static Stopwatch clock = Stopwatch.StartNew();
  MiseTween press = new MiseTween(0f);   // 0..1.5 px inset
  MiseTween ring = new MiseTween(0f);    // click flash 1 -> 0
  MiseTween onT = new MiseTween(0f);     // On state 0 -> 1 (bar, switch knob, segment pill)
  // On: setting it animates once the button is on screen; before that it just jumps
  public bool On {
    get { return on; }
    set {
      if (on == value) return; on = value;
      long now = clock.ElapsedMilliseconds;
      bool live = Animate && IsHandleCreated && Visible;
      int dur = IsSwitch ? 160 : 180;
      onT.Go(now, value ? 1f : 0f, dur, live);
      Kick(); Invalidate();
    }
  }
  static Color Mix(Color a, Color b, float t) {
    t = Math.Max(0f, Math.Min(1f, t));
    return Color.FromArgb((int)(a.R + (b.R - a.R) * t), (int)(a.G + (b.G - a.G) * t), (int)(a.B + (b.B - a.B) * t));
  }
  static Color Alpha(Color c, float a) { return Color.FromArgb((int)(255 * Math.Max(0f, Math.Min(1f, a))), c.R, c.G, c.B); }
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
  // one timer for press, click flash and On changes; it stops as soon as nothing moves
  void Kick() {
    if (!Animate) return;
    if (anim == null) {
      anim = new Timer(); anim.Interval = 15;
      anim.Tick += delegate {
        long now = clock.ElapsedMilliseconds;
        if (!press.Running(now) && !ring.Running(now) && !onT.Running(now)) anim.Stop();
        Invalidate();
      };
    }
    if (!anim.Enabled) anim.Start();
  }
  public MiseBtn() {
    SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
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
  protected override void OnMouseDown(MouseEventArgs e) { press.Go(clock.ElapsedMilliseconds, 1.5f, 60, Animate); Kick(); Invalidate(); base.OnMouseDown(e); }
  protected override void OnMouseUp(MouseEventArgs e) { press.Go(clock.ElapsedMilliseconds, 0f, 200, Animate); Kick(); Invalidate(); base.OnMouseUp(e); }
  protected override void OnClick(EventArgs e) {
    // the click flash: a 2 px accent border inside the button that fades out
    if (Animate && Kind != "seg") { long now = clock.ElapsedMilliseconds; ring.From = 1f; ring.To = 0f; ring.Start = now; ring.Dur = 400; Kick(); }
    base.OnClick(e);
  }
  protected override void OnEnabledChanged(EventArgs e) { Invalidate(); base.OnEnabledChanged(e); }
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
  // the switch: a 16 px knob slides across a 44 x 22 track, "On" / "Off" written to its left
  void DrawSwitch(Graphics g, float right, float t) {
    float pw = 44, ph = 22; RectangleF pr = new RectangleF(right - pw, (Height - ph) / 2f, pw, ph);
    using (GraphicsPath tp = Round(pr, ph / 2f)) {
      using (SolidBrush tb = new SolidBrush(Mix(PanelC, Accent, t))) g.FillPath(tb, tp);
      using (Pen pen = new Pen(Mix(LineC, Accent, t))) g.DrawPath(pen, tp);
    }
    float kx = pr.X + 3 + (pw - 6 - 16) * t;
    using (SolidBrush kb = new SolidBrush(Mix(MutedC, Color.FromArgb(24, 24, 27), t))) g.FillEllipse(kb, kx, pr.Y + 3, 16, 16);
    StringFormat rf = new StringFormat(StringFormatFlags.NoWrap); rf.Alignment = StringAlignment.Far; rf.LineAlignment = StringAlignment.Center;
    using (SolidBrush wb = new SolidBrush(on ? TextC : MutedC)) g.DrawString(on ? "On" : "Off", TinyFont, wb, new RectangleF(pr.X - 48, 0, 42, Height), rf);
  }
  protected override void OnPaint(PaintEventArgs pe) {
    Graphics g = pe.Graphics;
    long now = clock.ElapsedMilliseconds;
    float t = onT.At(now), pd = press.At(now), rg = ring.At(now);
    g.SmoothingMode = SmoothingMode.AntiAlias;
    g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
    g.Clear(Surface);
    RectangleF rc = new RectangleF(0.5f + pd, 0.5f + pd, Width - 2 - 2 * pd, Height - 2 - 2 * pd);
    Color fill = PanelC, border = LineC, txt = TextC;
    if (Kind == "ghost" || Kind == "seg") { fill = Surface; border = Surface; txt = Mix(MutedC, TextC, hv); }
    else { fill = Mix(PanelC, HoverC, hv); fill = Mix(fill, LineC, pd / 1.5f); }
    if (Kind == "primary") { border = Accent; txt = Accent; fill = Mix(fill, Mix(PanelC, Accent, 0.16f), hv); }
    if (Kind == "tool" && t > 0f) { border = Mix(border, Accent, t); txt = Mix(txt, Accent, t); fill = Mix(fill, Mix(Mix(PanelC, Accent, 0.14f), Mix(PanelC, Accent, 0.22f), hv), t); }
    if (Kind == "row" && t > 0f) { border = Mix(border, Mix(LineC, Accent, 0.55f), t); fill = Mix(fill, Mix(Mix(PanelC, Accent, 0.10f), Mix(PanelC, Accent, 0.16f), hv), t); }
    if (!Enabled) { txt = Color.FromArgb(104, 102, 98); }
    using (GraphicsPath path = Round(rc, 9f)) {
      using (SolidBrush b = new SolidBrush(fill)) g.FillPath(b, path);
      if (Kind != "ghost" && Kind != "seg") using (Pen pen = new Pen(border)) g.DrawPath(pen, path);
    }
    if (rg > 0.01f && Kind != "ghost") {
      using (GraphicsPath rp = Round(new RectangleF(rc.X + 1f, rc.Y + 1f, rc.Width - 2f, rc.Height - 2f), 8f))
      using (Pen rpen = new Pen(Alpha(Accent, rg), 2f)) g.DrawPath(rpen, rp);
    }
    StringFormat sf = new StringFormat(StringFormatFlags.NoWrap);
    sf.LineAlignment = StringAlignment.Center; sf.Trimming = StringTrimming.EllipsisCharacter;
    using (SolidBrush tb = new SolidBrush(txt)) {
      if (Kind == "row") {
        // the accent edge bar grows from the middle
        float bh = (Height - 20) * t;
        if (bh > 0.5f) using (SolidBrush ab = new SolidBrush(Accent)) using (GraphicsPath bar = Round(new RectangleF(0, Height / 2f - bh / 2f, 4, bh), 2f)) g.FillPath(ab, bar);
        using (SolidBrush nb = new SolidBrush(Enabled ? MutedC : Color.FromArgb(90, 88, 84))) g.DrawString(Num, SmallFont, nb, new RectangleF(16, 0, 22, Height), sf);
        float reserve = 14f;
        if (Dots) reserve += 26f;
        if (Chip.Length > 0) reserve = g.MeasureString(Chip, TinyFont).Width + 14f + 10f + 14f;
        if (Sub.Length > 0) reserve += 110f;
        g.DrawString(Text, Font, tb, new RectangleF(40, 0, Math.Max(20f, Width - 40 - reserve), Height), sf);
        float right = Width - 14;
        if (Dots) {
          // three dots in the row's own colours; brighter while the row is hovered
          float dx = Width - 22, dy = Height / 2f;
          using (SolidBrush db = new SolidBrush(Mix(MutedC, TextC, hv))) { for (int k = -1; k <= 1; k++) g.FillEllipse(db, dx + k * 5f - 1.6f, dy - 1.6f, 3.2f, 3.2f); }
          using (Pen sp = new Pen(Mix(LineC, PanelC, 0.3f), 1f)) g.DrawLine(sp, Width - 36, 10, Width - 36, Height - 10);
          right = Width - 36 - 10;
        }
        if (Chip.Length > 0) {
          SizeF cs = g.MeasureString(Chip, TinyFont);
          float cw = cs.Width + 14; RectangleF cr = new RectangleF(right - cw, (Height - 22) / 2f, cw, 22);
          Color chipC = !Enabled ? Color.FromArgb(104, 102, 98) : Mix(MutedC, Accent, t);
          Pill(g, cr, PanelC, chipC, false);
          StringFormat cf = new StringFormat(StringFormatFlags.NoWrap); cf.Alignment = StringAlignment.Center; cf.LineAlignment = StringAlignment.Center;
          using (SolidBrush cb = new SolidBrush(chipC)) g.DrawString(Chip, TinyFont, cb, cr, cf);
          right -= cw + 10;
        }
        if (Sub.Length > 0) {
          StringFormat rf = new StringFormat(StringFormatFlags.NoWrap); rf.Alignment = StringAlignment.Far; rf.LineAlignment = StringAlignment.Center;
          using (SolidBrush mb = new SolidBrush(MutedC)) g.DrawString(Sub, SmallFont, mb, new RectangleF(right - 110, 0, 110, Height), rf);
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
          DrawSwitch(g, right, t);
        } else if (Chip.Length > 0) {
          SizeF cs = g.MeasureString(Chip, TinyFont);
          float cw = cs.Width + 22; RectangleF cr = new RectangleF(right - cw, (Height - 22) / 2f, cw, 22);
          Pill(g, cr, PanelC, Mix(LineC, Accent, t), false);
          StringFormat cf = new StringFormat(StringFormatFlags.NoWrap); cf.Alignment = StringAlignment.Center; cf.LineAlignment = StringAlignment.Center;
          using (SolidBrush cb = new SolidBrush(Mix(TextC, Accent, t))) g.DrawString(Chip, TinyFont, cb, cr, cf);
        }
      } else {
        sf.Alignment = StringAlignment.Center;
        g.DrawString(Text, Font, tb, new RectangleF(4, 0, Width - 8, Height), sf);
      }
    }
    sf.Dispose();
  }
}
// the Mise mark (logo B2): three bowls on a counter, each tucked behind the next larger one.
// States: 0 idle (still, no timer), 1 busy (bowls lift in turn), 2 done (one hop, border flash), 3 needs a look (small bowl tipped)
public class MiseLogo : Control {
  public Color Accent = Color.FromArgb(216, 137, 90);
  public Color TileC = Color.FromArgb(34, 34, 38);
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
      if (state == value && value != 2) return;
      state = value; since = clock.ElapsedMilliseconds;
      if (Animate && (state == 1 || state == 2 || state == 3)) {
        if (tick == null) { tick = new Timer(); tick.Interval = 15; tick.Tick += delegate { Step(); }; }
        if (!tick.Enabled) tick.Start();
      } else if (tick != null) tick.Stop();
      Invalidate();
    }
  }
  void Step() {
    long el = clock.ElapsedMilliseconds - since;
    if (state == 2 && el > 700) { state = 0; tick.Stop(); }
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
    float[] baseA = { 0.5f, 0.74f, 1f };
    float[] x1 = { 88.5f, 58f, 15f }; float[] yy = { 67.5f, 61f, 54f }; float[] rr = { 12.5f, 19f, 26f };
    float[] drops = { drop0, drop1, drop2 };
    for (int i = 0; i < 3; i++) {
      float a = baseA[i] * strength[i]; if (a <= 0.01f) continue;
      float y = yy[i] - lift[i] - drops[i];
      using (GraphicsPath p = HalfDisc(x1[i], y, rr[i])) {
        if (i > 0) using (SolidBrush gb = new SolidBrush(gapC)) using (Pen gp = new Pen(gapC, 5f)) { gp.LineJoin = LineJoin.Round; g.FillPath(gb, p); g.DrawPath(gp, p); }
        if (i == 0 && problem == 1) {
          GraphicsState st = g.Save();
          g.TranslateTransform(x1[i], y + rr[i]); g.RotateTransform(-tipDeg); g.TranslateTransform(-x1[i], -(y + rr[i]));
          using (Pen op = new Pen(Color.FromArgb((int)(255 * a), accent), 4f)) { op.LineJoin = LineJoin.Round; g.DrawPath(op, p); }
          g.Restore(st);
        } else {
          using (SolidBrush b = new SolidBrush(Color.FromArgb((int)(255 * Math.Min(1f, a)), accent))) g.FillPath(b, p);
        }
      }
    }
    if (counterK > 0.01f) {
      float w = 108f * counterK;
      using (GraphicsPath c = RoundRect(10f, 81f, Math.Max(7f, w), 7f, 3.5f)) {
        using (SolidBrush gb = new SolidBrush(gapC)) using (Pen gp = new Pen(gapC, 5f)) { gp.LineJoin = LineJoin.Round; g.FillPath(gb, c); g.DrawPath(gp, c); }
        using (SolidBrush cb = new SolidBrush(Color.FromArgb(128, accent))) g.FillPath(cb, c);
      }
    }
  }
  protected override void OnPaint(PaintEventArgs pe) {
    Graphics g = pe.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
    g.Clear(BackColor);
    float k = Math.Min(Width, Height) / 128f;
    GraphicsState st0 = g.Save(); g.ScaleTransform(k, k);
    long el = clock.ElapsedMilliseconds - since;
    float[] lift = { 0f, 0f, 0f }; float[] str = { 1f, 1f, 1f }; int problem = 0; float tip = 0f; Color border = BorderC;
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
      float bk = Animate ? Math.Min(1f, el / 700f) : 1f; border = Color.FromArgb(BorderC.R + (int)((Accent.R - BorderC.R) * (1 - bk)), BorderC.G + (int)((Accent.G - BorderC.G) * (1 - bk)), BorderC.B + (int)((Accent.B - BorderC.B) * (1 - bk)));
    } else if (state == 3) {
      problem = 1; tip = 24f;
      if (Animate && el < 900) { float kk = el / 900f; tip = 24f + 8f * (float)Math.Sin(2 * Math.PI * kk) * (1f - kk); }
    }
    if (ShowTile) {
      using (GraphicsPath tile = RoundRect(1f, 1f, 126f, 126f, 28f)) {
        using (SolidBrush tb = new SolidBrush(TileC)) g.FillPath(tb, tile);
        using (Pen bp = new Pen(border, 2f)) g.DrawPath(bp, tile);
      }
    }
    DrawMark(g, Accent, TileC, lift, str, problem, tip, 0f, 0f, 0f, 1f);
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
    Graphics g = pe.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias; g.Clear(BackColor);
    float cx = Width / 2f, cy = Height / 2f;
    GraphicsState st = g.Save();
    g.TranslateTransform(cx, cy); g.RotateTransform(ang.At(clock.ElapsedMilliseconds));
    using (SolidBrush b = new SolidBrush(Ink)) g.FillPolygon(b, new PointF[] { new PointF(-2.5f, -4f), new PointF(3.5f, 0f), new PointF(-2.5f, 4f) });
    g.Restore(st);
  }
}
"@
Update-MiseLook (Get-MiseConfig)

function New-Btn($text, $x = 0, $y = 0, $w = 100, $h = 34, $kind = 'tool', $font = $null) {
  $b = New-Object MiseBtn
  $b.Text = $text; $b.Font = $(if ($font) { $font } else { $script:fBtn }); $b.Kind = $kind
  $b.Accent = $script:C.Accent
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
  $f.Add_HandleCreated({ param($s, $e) try { $v = 2; [MiseUi]::DwmSetWindowAttribute($s.Handle, 33, [ref]$v, 4) | Out-Null; $bc = 0x3F3838; [MiseUi]::DwmSetWindowAttribute($s.Handle, 34, [ref]$bc, 4) | Out-Null } catch {} })
  $f.Add_Paint({ param($s, $e) $p = New-Object Drawing.Pen($script:C.Line, 1); $e.Graphics.DrawRectangle($p, 0, 0, $s.ClientSize.Width - 1, $s.ClientSize.Height - 1); $p.Dispose() })
  $f.Add_MouseDown({ param($s, $e) if ($e.Button -eq 'Left') { [MiseUi]::ReleaseCapture() | Out-Null; [MiseUi]::SendMessage($s.Handle, 0xA1, 2, 0) | Out-Null } })
}
function Add-DragHandle($ctrl, $form) {
  $ctrl.Tag = $form
  $ctrl.Add_MouseDown({ param($s, $e) if ($e.Button -eq 'Left') { $f = $s.FindForm(); [MiseUi]::ReleaseCapture() | Out-Null; [MiseUi]::SendMessage($f.Handle, 0xA1, 2, 0) | Out-Null } })
}

# fade in + slide down 16 px when a window opens (skipped when animations are off)
# fade in when a window opens: opacity only (moving the window stutters), timed by the clock so it stays smooth
function Start-OpenAnimation($f) {
  if (-not $script:Animate) { return }
  $f.Opacity = 0
  $t = New-Object Windows.Forms.Timer; $t.Interval = 10
  $t.Tag = @{ Form = $f; Clock = [Diagnostics.Stopwatch]::StartNew() }
  $t.Add_Tick({ param($s, $e)
    $st = $s.Tag; $k = [Math]::Min(1.0, $st.Clock.ElapsedMilliseconds / 170.0)
    $st.Form.Opacity = 1 - [Math]::Pow(1 - $k, 3)
    if ($k -ge 1.0) { $s.Stop(); $st.Form.Opacity = 1 }
  })
  $t.Start()
}

# the Mise mark (logo B2) as a compiled control; .State: 0 idle, 1 busy, 2 done, 3 needs a look
function New-Logo($x, $y, [int]$size = 32) {
  $logo = New-Object MiseLogo
  $logo.Location = New-Object Drawing.Point($x, $y); $logo.Size = New-Object Drawing.Size($size, $size)
  $logo.BackColor = $script:C.Bg; $logo.Accent = $script:C.Accent
  return $logo
}

# ---------- friendly progress text: turns the step log into plain steps ----------
$script:qNames = @{ 400 = 'Draft'; 420 = 'Ranked Solo/Duo'; 440 = 'Ranked Flex'; 450 = 'ARAM'; 480 = 'Swiftplay'; 1700 = 'Arena'; 1740 = 'Arena'; 2400 = 'ARAM Mayhem'; 4320 = 'Jade (event)' }
function Get-Friendly($lines) {
  $steps = New-Object System.Collections.Generic.List[string]
  $res = @{ Head = ''; Done = $false; Problem = $false; Steps = $steps }
  foreach ($raw in @($lines)) {
    $l = ("$raw" -replace '^\[\s*\d+s\]\s*', '').Trim()
    if ($l -eq '') { continue }
    $t = $null
    if ($l -match "^(Starting|Exiting) '(.+)'$") { if (-not $res.Head) { $res.Head = "$($Matches[1]) $($Matches[2])" } ; continue }
    if ($l -match '^(Switching to|Checking the client|Fixing the League client|Arranging|Saving )') { if (-not $res.Head) { $res.Head = $l }; continue }
    if ($l -match "^\[([^\]]+)\] app doesn't exist") { $t = "!$($Matches[1]) is not installed - skipped" }
    elseif ($l -match "^\[([^\]]+)\] (Chrome or Edge doesn't exist)") { $t = "!Needs Chrome or Edge for $($Matches[1])" }
    elseif ($l -match 'opens when you pick a champion') { $t = 'u.gg opens when you pick a champion' }
    elseif ($l -match '^\[League\] starting') { $t = 'Starting League' }
    elseif ($l -match '^\[([^\]]+)\] (starting|opening)') { $t = "Opening $($Matches[1])" }
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
    elseif ($l -match '^Mise stopped') { $t = '!Stopped - the saved login was rejected'; $res.Problem = $true; $res.Done = $true }
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
