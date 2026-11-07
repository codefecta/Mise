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
  try { [MiseBtn]::Animate = $script:Animate } catch {}
}
$script:fTitle = New-Object Drawing.Font('Segoe UI Semibold', 17)
$script:fBig   = New-Object Drawing.Font('Segoe UI Semibold', 11.5)
$script:fBtn   = New-Object Drawing.Font('Segoe UI Semibold', 9.5)
$script:fNorm  = New-Object Drawing.Font('Segoe UI', 9)
$script:fSmall = New-Object Drawing.Font('Segoe UI', 9)
$script:fTiny  = New-Object Drawing.Font('Segoe UI Semibold', 8)
$script:fStatus = New-Object Drawing.Font('Segoe UI', 10)

# ---------- the one custom button (rounded, anti-aliased, hover fade, press inset) ----------
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @"
using System; using System.Drawing; using System.Drawing.Drawing2D; using System.Drawing.Text; using System.Windows.Forms;
public class MiseBtn : Button {
  public string Kind = "tool";     // tool | primary | ghost | row | setting
  public string Num = "";          // row: number
  public string Sub = "";          // row: small grey text on the right
  public string Chip = "";         // row: region chip / setting: value
  public bool On = false;          // row: logged-in account / setting: switch is on
  public bool IsSwitch = false;    // setting: draw an ON / off switch instead of a value
  public Color Surface = Color.FromArgb(23, 23, 26);
  public Color PanelC = Color.FromArgb(33, 33, 37);
  public Color HoverC = Color.FromArgb(45, 45, 51);
  public Color LineC = Color.FromArgb(56, 56, 63);
  public Color Accent = Color.FromArgb(216, 137, 90);
  public static bool Animate = true;   // off: hover changes at once
  public Color TextC = Color.FromArgb(238, 237, 234);
  public Color MutedC = Color.FromArgb(138, 136, 132);
  public Font SmallFont = new Font("Segoe UI", 9f);
  public Font TinyFont = new Font("Segoe UI Semibold", 8.5f);
  bool hov, down;
  float hv = 0f;
  Timer fade;
  static Color Mix(Color a, Color b, float t) {
    return Color.FromArgb((int)(a.R + (b.R - a.R) * t), (int)(a.G + (b.G - a.G) * t), (int)(a.B + (b.B - a.B) * t));
  }
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
  public MiseBtn() {
    SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
    FlatStyle = FlatStyle.Flat; FlatAppearance.BorderSize = 0; TabStop = false; Cursor = Cursors.Hand;
  }
  protected override void OnMouseEnter(EventArgs e) { hov = true; Fade(); Invalidate(); base.OnMouseEnter(e); }
  protected override void OnMouseLeave(EventArgs e) { hov = false; down = false; Fade(); Invalidate(); base.OnMouseLeave(e); }
  protected override void OnMouseDown(MouseEventArgs e) { down = true; Invalidate(); base.OnMouseDown(e); }
  protected override void OnMouseUp(MouseEventArgs e) { down = false; Invalidate(); base.OnMouseUp(e); }
  protected override void OnEnabledChanged(EventArgs e) { Invalidate(); base.OnEnabledChanged(e); }
  static GraphicsPath Round(RectangleF r, float rad) {
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
  protected override void OnPaint(PaintEventArgs pe) {
    Graphics g = pe.Graphics;
    g.SmoothingMode = SmoothingMode.AntiAlias;
    g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
    g.Clear(Surface);
    float pd = down ? 1.5f : 0f;
    RectangleF rc = new RectangleF(0.5f + pd, 0.5f + pd, Width - 2 - 2 * pd, Height - 2 - 2 * pd);
    Color fill = PanelC, border = LineC, txt = TextC;
    if (Kind == "ghost") { fill = Surface; border = Surface; txt = Mix(MutedC, TextC, hv); }
    else {
      fill = Mix(PanelC, HoverC, hv);
      if (down) fill = LineC;
    }
    if (Kind == "primary") { border = Accent; txt = Accent; fill = Mix(fill, Mix(PanelC, Accent, 0.16f), hv); }
    if (Kind == "row" && On) { border = Mix(LineC, Accent, 0.55f); fill = Mix(Mix(PanelC, Accent, 0.10f), Mix(PanelC, Accent, 0.16f), hv); }
    if (!Enabled) { txt = Color.FromArgb(104, 102, 98); }
    using (GraphicsPath path = Round(rc, 9f)) {
      using (SolidBrush b = new SolidBrush(fill)) g.FillPath(b, path);
      if (Kind != "ghost") using (Pen pen = new Pen(border)) g.DrawPath(pen, path);
    }
    StringFormat sf = new StringFormat(StringFormatFlags.NoWrap);
    sf.LineAlignment = StringAlignment.Center; sf.Trimming = StringTrimming.EllipsisCharacter;
    using (SolidBrush tb = new SolidBrush(txt)) {
      if (Kind == "row") {
        if (On) using (SolidBrush ab = new SolidBrush(Accent)) using (GraphicsPath bar = Round(new RectangleF(0, 10, 4, Height - 20), 2f)) g.FillPath(ab, bar);
        using (SolidBrush nb = new SolidBrush(Enabled ? MutedC : Color.FromArgb(90, 88, 84))) g.DrawString(Num, SmallFont, nb, new RectangleF(16, 0, 22, Height), sf);
        float reserve = 14f;
        if (Chip.Length > 0) reserve = g.MeasureString(Chip, TinyFont).Width + 14f + 10f + 14f;
        if (Sub.Length > 0) reserve += 110f;
        g.DrawString(Text, Font, tb, new RectangleF(40, 0, Math.Max(20f, Width - 40 - reserve), Height), sf);
        float right = Width - 14;
        if (Chip.Length > 0) {
          SizeF cs = g.MeasureString(Chip, TinyFont);
          float cw = cs.Width + 14; RectangleF cr = new RectangleF(right - cw, (Height - 22) / 2f, cw, 22);
          Color chipC = !Enabled ? Color.FromArgb(104, 102, 98) : (On ? Accent : MutedC);
          Pill(g, cr, PanelC, chipC, false);
          StringFormat cf = new StringFormat(StringFormatFlags.NoWrap); cf.Alignment = StringAlignment.Center; cf.LineAlignment = StringAlignment.Center;
          using (SolidBrush cb = new SolidBrush(chipC)) g.DrawString(Chip, TinyFont, cb, cr, cf);
          right -= cw + 10;
        }
        if (Sub.Length > 0) {
          StringFormat rf = new StringFormat(StringFormatFlags.NoWrap); rf.Alignment = StringAlignment.Far; rf.LineAlignment = StringAlignment.Center;
          using (SolidBrush mb = new SolidBrush(MutedC)) g.DrawString(Sub, SmallFont, mb, new RectangleF(right - 110, 0, 110, Height), rf);
        }
      } else if (Kind == "setting") {
        g.DrawString(Text, Font, tb, new RectangleF(14, 0, Width - 130, Height), sf);
        float right = Width - 12;
        if (IsSwitch) {
          float pw = 46, ph = 22; RectangleF pr = new RectangleF(right - pw, (Height - ph) / 2f, pw, ph);
          StringFormat cf = new StringFormat(StringFormatFlags.NoWrap); cf.Alignment = StringAlignment.Center; cf.LineAlignment = StringAlignment.Center;
          if (On) {
            Pill(g, pr, Accent, Accent, true);
            using (SolidBrush db = new SolidBrush(Mix(Color.FromArgb(20, 20, 22), Accent, 0.12f))) g.DrawString("ON", TinyFont, db, pr, cf);
          } else {
            Pill(g, pr, PanelC, LineC, false);
            using (SolidBrush mb = new SolidBrush(MutedC)) g.DrawString("off", TinyFont, mb, pr, cf);
          }
        } else if (Chip.Length > 0) {
          SizeF cs = g.MeasureString(Chip, TinyFont);
          float cw = cs.Width + 22; RectangleF cr = new RectangleF(right - cw, (Height - 22) / 2f, cw, 22);
          Pill(g, cr, PanelC, LineC, false);
          StringFormat cf = new StringFormat(StringFormatFlags.NoWrap); cf.Alignment = StringAlignment.Center; cf.LineAlignment = StringAlignment.Center;
          using (SolidBrush cb = new SolidBrush(TextC)) g.DrawString(Chip, TinyFont, cb, cr, cf);
        }
      } else {
        sf.Alignment = StringAlignment.Center;
        g.DrawString(Text, Font, tb, new RectangleF(4, 0, Width - 8, Height), sf);
      }
    }
    sf.Dispose();
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

# the Mise mark: a rounded tile with three stacked prep bowls; shimmers slowly (faster while busy)
$script:logoPhase = 0.0; $script:logoSpeed = 0.07; $script:logoClock = [Diagnostics.Stopwatch]::StartNew(); $script:logoLast = 0
function New-Logo($x, $y) {
  $logo = New-Object Windows.Forms.PictureBox
  $logo.Location = New-Object Drawing.Point($x, $y); $logo.Size = New-Object Drawing.Size(32, 32); $logo.BackColor = $script:C.Bg
  $logo.Add_Paint({
    try {
    $g = $_.Graphics; $g.SmoothingMode = 'AntiAlias'; $k = 32 / 128.0; $acc = $script:C.Accent
    if ($null -eq $acc) { $acc = [Drawing.Color]::FromArgb(216, 137, 90) }
    $tile = New-Object Drawing.Drawing2D.GraphicsPath; $d = 16
    $tile.AddArc(0.5, 0.5, $d, $d, 180, 90); $tile.AddArc(31 - $d, 0.5, $d, $d, 270, 90); $tile.AddArc(31 - $d, 31 - $d, $d, $d, 0, 90); $tile.AddArc(0.5, 31 - $d, $d, $d, 90, 90); $tile.CloseFigure()
    $fillB = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(34, 34, 38)); $g.FillPath($fillB, $tile)
    $ph = $script:logoPhase
    $pa = [int](150 + 105 * (0.5 + 0.5 * [Math]::Sin($ph)))
    $pen = New-Object Drawing.Pen([Drawing.Color]::FromArgb($pa, $acc), 1); $g.DrawPath($pen, $tile)
    $alphas = @(255, 200, 143); $cx = @(30, 64, 98)
    for ($i = 0; $i -lt 3; $i++) {
      $wave = 0.72 + 0.28 * [Math]::Sin($ph * 1.6 - $i * 1.0)
      $br = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb([int]($alphas[$i] * $wave), $acc))
      $g.FillPie($br, [single](($cx[$i] - 16) * $k), [single]((46 - 16) * $k), [single](32 * $k), [single](32 * $k), 0, 180); $br.Dispose()
    }
    $sb = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(102, $acc)); $g.FillRectangle($sb, [single](12 * $k), [single](82 * $k), [single](104 * $k), [single](8 * $k))
    $sb.Dispose(); $pen.Dispose(); $fillB.Dispose(); $tile.Dispose()
    } catch { if (-not $script:logoErr) { $script:logoErr = $true; Write-Log "logo paint: $($_.Exception.Message) line $($_.InvocationInfo.ScriptLineNumber)" } }
  })
  if ($script:Animate) {
    $t = New-Object Windows.Forms.Timer; $t.Interval = 33; $t.Tag = $logo
    $t.Add_Tick({ param($s, $e) $now = $script:logoClock.ElapsedMilliseconds; $script:logoPhase += $script:logoSpeed * ($now - $script:logoLast) / 50.0; $script:logoLast = $now; $s.Tag.Invalidate() })
    $t.Start()
  }
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
    if ($l -match '^(Switching to|Checking the client|Arranging|Saving )') { if (-not $res.Head) { $res.Head = $l }; continue }
    if ($l -match "^\[([^\]]+)\] app doesn't exist") { $t = "!$($Matches[1]) is not installed - skipped" }
    elseif ($l -match "^\[([^\]]+)\] (Chrome or Edge doesn't exist)") { $t = "!Needs Chrome or Edge for $($Matches[1])" }
    elseif ($l -match 'opens when you pick a champion') { $t = 'u.gg opens when you pick a champion' }
    elseif ($l -match '^\[League\] starting') { $t = 'Starting League' }
    elseif ($l -match '^\[([^\]]+)\] (starting|opening)') { $t = "Opening $($Matches[1])" }
    elseif ($l -match '^\[([^\]]+)\] (placed|miniplayer placed|already open)') { $t = "$($Matches[1]) in place" }
    elseif ($l -match '^\[([^\]]+)\] open the miniplayer once') { $t = "!Open the Spotify miniplayer once, then press Arrange" }
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
    elseif ($l -match '^\[riot\] needs a look') { $t = '!League needs a look - try Fix client'; $res.Problem = $true }
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
