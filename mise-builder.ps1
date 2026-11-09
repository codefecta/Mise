<# Mise builder: one window for new and existing routines.
   Copy my screen (or + Add app) puts tiles on a map of your screens; fine-tune them there; Save.
   mise-builder.ps1 [-New] [-Routine <id>] #>
param([switch]$New, [string]$Routine = '')
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'mise-ui.ps1')
try { Start-Transcript -Path (Join-Path $script:DataDir 'builder.log') -Force | Out-Null } catch {}
trap { try { Add-Content -LiteralPath (Join-Path $script:DataDir 'builder-error.log') -Value ("{0}  {1}  line {2}: {3}" -f (Get-Date -Format s), $_.Exception.Message, $_.InvocationInfo.ScriptLineNumber, $_.InvocationInfo.Line.Trim()) } catch {}; continue }
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class MiseHk { [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr h, int id, uint m, uint vk); [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr h, int id); }'

$first = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\MiseBuilder', [ref]$first)
if (-not $first) { exit }

$script:cfg = Get-MiseConfig
if (-not $script:cfg.firstRunDone) { $script:cfg = Show-FirstRun $script:cfg }
$script:browser = Get-DefaultBrowser
$script:R = $null            # the routine being edited (a working copy)
$script:dirty = $false
$script:sel = ''             # selected tile id ('card' = the Mise tile)
$script:undo = New-UndoStack
$script:drag = $null
$script:hover = $null
$script:helper = ''          # one line on the map after Copy my screen ("Tidied: ...")
$script:marks = @{}          # Test run result per tile id
$script:checks = @()         # check-on-save lines
$script:hkCapture = $false
$runner = Join-Path $script:MiseDir 'mise-run.ps1'
$homeUi = Join-Path $script:MiseDir 'mise-home.ps1'

# ======================= helpers =======================
function Copy-Routine($r) { return ((ConvertTo-Json $r -Depth 10) | ConvertFrom-Json) }
function New-BlankRoutine {
  return [pscustomobject]@{ id = (New-Id); name = 'My routine'; hotkey = (Get-FreeHotkey $script:cfg ''); league = [bool](Test-RiotInstalled); taskbar = @(); card = $null; tiles = @() }
}
function Get-Tiles { return @($script:R.tiles) }
function Get-Tile([string]$id) { return (@($script:R.tiles) | Where-Object { $_.id -eq $id } | Select-Object -First 1) }
function Save-UndoPoint { Push-Undo $script:undo @{ tiles = @($script:R.tiles); card = $script:R.card; taskbar = @($script:R.taskbar) } }
function Restore-Undo {
  $s = Pop-Undo $script:undo; if (-not $s) { return }
  $script:R.tiles = @($s.tiles | Where-Object { $_ }); $script:R.card = $s.card; $script:R.taskbar = @($s.taskbar | Where-Object { $_ })
  $script:dirty = $true; $script:helper = ''; Update-Side; $canvas.Invalidate()
}
function Set-Dirty { $script:dirty = $true; $script:marks = @{}; $script:checks = @() }
# a Mise-styled yes/no (no grey Windows boxes)
function Show-MiseAsk([string]$title, [string]$text, [string]$yes, [string]$no) {
  $W = 380; $M = 18
  $f = New-MiseDialog $title $W 190
  $f.Controls.Add((New-Label $text $script:fSmall $script:C.Text $M 54 ($W - 2 * $M) 60))
  $by = New-Btn $yes ($W - $M - 130) 126 130 34 'primary'; $bn = New-Btn $no ($W - $M - 270) 126 130 34
  $script:askAnswer = $null
  $by.Add_Click({ param($s, $e) $script:askAnswer = 'yes'; $s.FindForm().Close() }); $bn.Add_Click({ param($s, $e) $script:askAnswer = 'no'; $s.FindForm().Close() })
  $f.Controls.AddRange(@($by, $bn)); $f.ClientSize = New-Object Drawing.Size($W, 176)
  $owners = @([Windows.Forms.Application]::OpenForms | Where-Object { $_.Visible -and $_.TopMost -and $_ -ne $f }); foreach ($o in $owners) { $o.TopMost = $false }
  [void]$f.ShowDialog()
  foreach ($o in $owners) { try { $o.TopMost = $true } catch {} }
  return $script:askAnswer
}
function Test-HotkeyFree([string]$text) {
  $h = ConvertTo-Hotkey $text; if (-not $h) { return $false }
  $ok = [MiseHk]::RegisterHotKey($form.Handle, 9001, [uint32]$h.Mods, [uint32]$h.Vk)
  if ($ok) { [void][MiseHk]::UnregisterHotKey($form.Handle, 9001) }
  return $ok
}
# Start-menu apps: a known-folder id like {6D809377-...}\Steam\steam.exe is a real path
$script:KnownFolders = @{ '{6D809377-6AF0-444B-8957-A3773F02200E}' = $env:ProgramFiles; '{7C5A40EF-A0FB-4BFC-874A-C0F2E0B9FA8E}' = ${env:ProgramFiles(x86)}; '{F38BF404-1D43-42F2-9305-67DE0B28FC23}' = $env:WINDIR; '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}' = "$env:WINDIR\System32" }
function Resolve-AppIdPath([string]$appId) {
  if ($appId -match '^(\{[0-9A-Fa-f-]+\})\\(.+)$' -and $script:KnownFolders.ContainsKey($Matches[1].ToUpper())) { $p = Join-Path $script:KnownFolders[$Matches[1].ToUpper()] $Matches[2]; if (Test-Path -LiteralPath $p) { return $p } }
  if ($appId -match '^[A-Za-z]:\\.+\.exe$' -and (Test-Path -LiteralPath $appId)) { return $appId }
  return ''
}

# ======================= the window =======================
$form = New-Object Windows.Forms.Form
$form.Text = 'Mise - routines'; $form.StartPosition = 'CenterScreen'; $form.KeyPreview = $true
$wa = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.ClientSize = New-Object Drawing.Size([Math]::Max(1240, [int]($wa.Width * 0.8)), [Math]::Max(760, [int]($wa.Height * 0.82))); $form.MinimumSize = New-Object Drawing.Size(1000, 640)
if (Test-Path $script:Icon) { try { $form.Icon = New-Object Drawing.Icon($script:Icon) } catch {} }
$form.BackColor = $script:C.Bg; $form.ForeColor = $script:C.Text
$form.Add_HandleCreated({ param($s, $e) try { $v = 2; [MiseUi]::DwmSetWindowAttribute($s.Handle, 33, [ref]$v, 4) | Out-Null; $v = 1; [MiseUi]::DwmSetWindowAttribute($s.Handle, 20, [ref]$v, 4) | Out-Null } catch {} })
$tip = New-Object Windows.Forms.ToolTip

# header
$logo = New-Logo 18 16; $form.Controls.Add($logo)
$hdr = New-Label 'Routines' $script:fTitle $script:C.Accent 58 12 150 34; $form.Controls.Add($hdr)
$nameBox = New-MiseText 220 18 260; $form.Controls.Add($nameBox.Panel)
$nameBox.Box.Add_TextChanged({ if ($script:R -and $nameBox.Box.Text -ne $script:R.name) { $script:R.name = $nameBox.Box.Text; $script:dirty = $true; Update-List } })
$bCopy = New-Btn 'Copy my screen' 0 16 150 34 'primary'
$bAdd = New-Btn '+ Add app' 0 16 110 34
$bUndo = New-Btn 'Undo' 0 16 80 34
$bPrev = New-Btn 'Preview on screen' 0 16 160 34
$bTest = New-Btn 'Test run' 0 16 100 34
$bSave = New-Btn 'Save' 0 16 90 34 'primary'
$form.Controls.AddRange(@($bCopy, $bAdd, $bUndo, $bPrev, $bTest, $bSave))
$tip.SetToolTip($bCopy, 'Put your apps roughly in place first. Mise lists the open windows; tick the ones for this routine.')
$tip.SetToolTip($bUndo, 'Undo the last change on the map (Ctrl+Z)')
$tip.SetToolTip($bPrev, 'Move your open windows to this layout once, so you see the real result')
$tip.SetToolTip($bTest, 'Run the routine now (League with the current login) and mark each tile passed or failed')

# left: routines
$lblR = New-Label 'ROUTINES' $script:fTiny $script:C.Muted 18 76 200 14; $form.Controls.Add($lblR)
$listPanel = New-Object Windows.Forms.Panel; $listPanel.BackColor = $script:C.Bg; $listPanel.Location = New-Object Drawing.Point(18, 96); $listPanel.AutoScroll = $true
$form.Controls.Add($listPanel)
$bNewR = New-Btn '+ New routine' 18 0 200 34; $bDelR = New-Btn 'Delete routine' 18 0 200 30 'ghost'
$bHome = New-Btn 'Back to Mise' 18 0 200 30 'ghost'
$form.Controls.AddRange(@($bNewR, $bDelR, $bHome))

# centre: the map
$canvas = New-Object Windows.Forms.Panel; $canvas.BackColor = [Drawing.Color]::FromArgb(18, 18, 21)
[Windows.Forms.Control].GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic,Instance').SetValue($canvas, $true, $null)
$form.Controls.Add($canvas)

# right: settings
$side = New-Object Windows.Forms.Panel; $side.BackColor = $script:C.Bg; $side.AutoScroll = $true
$form.Controls.Add($side)

function Do-Layout {
  $script:lives = @(Get-LiveMonitors $script:cfg)   # screens are read once per layout, not on every repaint
  $W = $form.ClientSize.Width; $H = $form.ClientSize.Height
  $x = $W - 18
  foreach ($b in @($bSave, $bTest, $bPrev, $bUndo, $bAdd, $bCopy)) { $x -= $b.Width; $b.Left = $x; $x -= 8 }
  $listPanel.Size = New-Object Drawing.Size(212, ($H - 96 - 130))
  $bNewR.Top = $H - 126; $bDelR.Top = $H - 86; $bHome.Top = $H - 50
  $canvas.Bounds = New-Object Drawing.Rectangle(238, 76, ($W - 238 - 360), ($H - 76 - 18))
  $side.Bounds = New-Object Drawing.Rectangle(($W - 344), 76, 330, ($H - 76 - 18))
  $canvas.Invalidate()
}
$form.Add_Resize({ Do-Layout })

# ======================= routine list =======================
function Update-List {
  $listPanel.Controls.Clear(); $y = 0; $i = 0
  $all = @($script:cfg.routines)
  if ($script:R -and -not ($all | Where-Object { $_.id -eq $script:R.id })) { $all += $script:R }
  foreach ($r in $all) {
    $i++
    $nm = if ($script:R -and $r.id -eq $script:R.id) { $script:R.name } else { $r.name }
    $b = New-Btn $nm 0 $y 196 40 'row'; $b.Num = "$i"; $b.Tag = $r.id; $b.Chip = $(if ($r.league) { 'LoL' } else { '' })
    $b.On = ($script:R -and $r.id -eq $script:R.id)
    $b.Add_Click({ param($s, $e) Open-Routine $s.Tag })
    $b.Add_MouseUp({ param($s, $e) if ($e.Button -eq 'Right') { Show-RoutineMenu $s.Tag $s } })
    $listPanel.Controls.Add($b); $y += 46
  }
}
# right-click a routine in the list: duplicate it
function Show-RoutineMenu([string]$id, $ctl) {
  $m = New-Object Windows.Forms.ContextMenuStrip
  $m.BackColor = $script:C.Panel; $m.ForeColor = $script:C.Text; $m.ShowImageMargin = $false
  $iD = $m.Items.Add('Duplicate'); $iD.Tag = $id; $iD.Add_Click({ param($s, $e) Copy-RoutineEntry $s.Tag })
  $m.Show($ctl, (New-Object Drawing.Point(20, $ctl.Height - 6)))
}
function Copy-RoutineEntry([string]$id) {
  if (-not (Confirm-Leave)) { return }
  $cf = Get-MiseConfig
  $src = @($cf.routines) | Where-Object { $_.id -eq $id } | Select-Object -First 1; if (-not $src) { return }
  $d = $src | ConvertTo-Json -Depth 12 | ConvertFrom-Json
  $d.id = New-Id; if ($d.PSObject.Properties.Name -contains 'hotkey') { $d.hotkey = '' }
  $names = @($cf.routines | ForEach-Object { $_.name }); $n = "$($src.name) copy"; $k = 2; while ($names -contains $n) { $n = "$($src.name) copy $k"; $k++ }
  $d.name = $n
  foreach ($t in @($d.tiles)) { $t.id = New-Id }
  $cf.routines = @($cf.routines) + $d; Save-MiseConfig $cf; $script:cfg = Get-MiseConfig
  $script:dirty = $false
  Set-Routine (Copy-Routine (@($script:cfg.routines) | Where-Object { $_.id -eq $d.id } | Select-Object -First 1))
}
function Confirm-Leave {
  if (-not $script:dirty) { return $true }
  $a = Show-MiseAsk 'Unsaved changes' "Save the changes to '$($script:R.name)' first?" 'Save' "Don't save"
  if ($a -eq 'yes') { return (Save-Routine) }
  return ($a -eq 'no')
}
function Open-Routine([string]$id) {
  if ($script:R -and $id -eq $script:R.id) { return }
  if (-not (Confirm-Leave)) { return }
  $r = @($script:cfg.routines) | Where-Object { $_.id -eq $id } | Select-Object -First 1
  if (-not $r) { return }
  Set-Routine (Copy-Routine $r)
}
function Set-Routine($r) {
  $script:R = $r
  foreach ($k in @('tiles', 'taskbar')) { $script:R.$k = @($script:R.$k | Where-Object { $_ }) }
  $script:dirty = $false; $script:sel = ''; $script:undo = New-UndoStack; $script:marks = @{}; $script:checks = @(); $script:helper = ''
  $nameBox.Box.Text = $script:R.name
  Update-List; Update-Side; $canvas.Invalidate()
}

# ======================= map geometry =======================
$script:pad = 28; $script:gap = 22; $script:hdrH = 54
$script:lives = @()
function Get-View {
  $lives = @($script:lives)
  if (-not $lives.Count) { return @() }
  $minX = ($lives | ForEach-Object { $_.X } | Measure-Object -Minimum).Minimum; $minY = ($lives | ForEach-Object { $_.Y } | Measure-Object -Minimum).Minimum
  $maxX = ($lives | ForEach-Object { $_.X + $_.W } | Measure-Object -Maximum).Maximum; $maxY = ($lives | ForEach-Object { $_.Y + $_.H } | Measure-Object -Maximum).Maximum
  $order = @($lives | Sort-Object { $_.X })
  $cw = $canvas.ClientSize.Width - 2 * $script:pad - ($order.Count - 1) * $script:gap; $ch = $canvas.ClientSize.Height - 2 * $script:pad - $script:hdrH - 30
  $s = [Math]::Min($cw / [double]($maxX - $minX), $ch / [double]($maxY - $minY))
  $out = @()
  for ($i = 0; $i -lt $order.Count; $i++) {
    $l = $order[$i]
    $area = Get-TileArea $l $script:R
    $mx = $script:pad + ($l.X - $minX) * $s + $i * $script:gap; $my = $script:pad + $script:hdrH + ($l.Y - $minY) * $s
    $ax = $mx + ($area.X - $l.X) * $s; $ay = $my + ($area.Y - $l.Y) * $s
    $out += @{ Live = $l; Area = $area; Mon = (New-Object Drawing.RectangleF([single]$mx, [single]$my, [single]($l.W * $s), [single]($l.H * $s)))
               A = (New-Object Drawing.RectangleF([single]$ax, [single]$ay, [single]($area.W * $s), [single]($area.H * $s))); S = $s }
  }
  return $out
}
function Get-ViewFor([string]$monId) { return ($script:view | Where-Object { $_.Live.id -eq $monId } | Select-Object -First 1) }
function Get-TileBox($v, $rect) { return (New-Object Drawing.RectangleF([single]($v.A.X + [double]$rect.x * $v.A.Width), [single]($v.A.Y + [double]$rect.y * $v.A.Height), [single]([double]$rect.w * $v.A.Width), [single]([double]$rect.h * $v.A.Height))) }
function Get-ViewAt($pt) { return ($script:view | Where-Object { $_.Mon.Contains([single]$pt.X, [single]$pt.Y) } | Select-Object -First 1) }
function Get-CardRect($v) {
  if (-not $script:R.card) { return $null }
  return @{ x = [double]$script:R.card.rect.x; y = [double]$script:R.card.rect.y; w = 320.0 / $v.Area.W; h = 96.0 / $v.Area.H }
}
# what is under the mouse: a monitor header button, the shared-edge grip, a tile edge, a tile, the Mise tile
function Get-Hit($pt) {
  foreach ($v in $script:view) {
    $hy = $v.Mon.Y - $script:hdrH
    if ($pt.Y -ge $hy -and $pt.Y -lt $v.Mon.Y -and $pt.X -ge $v.Mon.X -and $pt.X -le $v.Mon.Right) {
      # three rows: name, taskbar, layout. On wide screens taskbar and layout share the second row
      $row = [int][Math]::Floor(($pt.Y - $hy) / ($script:hdrH / 3.0))
      if ($v.Mon.Width -ge 200) {
        if ($row -ge 1) { if ($pt.X -ge $v.Mon.Right - 70) { return @{ Kind = 'layout'; V = $v } }; if ($pt.X -ge $v.Mon.Right - 190) { return @{ Kind = 'taskbar'; V = $v } } }
      } else {
        if ($row -eq 1) { return @{ Kind = 'taskbar'; V = $v } }
        if ($row -ge 2) { return @{ Kind = 'layout'; V = $v } }
      }
      return @{ Kind = 'header'; V = $v }
    }
  }
  $v = Get-ViewAt $pt; if (-not $v) { return @{ Kind = 'none' } }
  if ($script:R.card -and $script:R.card.monitor -eq $v.Live.id) { $cb = Get-TileBox $v (Get-CardRect $v); if ($cb.Contains([single]$pt.X, [single]$pt.Y)) { return @{ Kind = 'card'; V = $v } } }
  $mine = @(Get-Tiles | Where-Object { $_.monitor -eq $v.Live.id -and $_.kind -ne 'league' })
  foreach ($ed in @(Get-SharedEdges $mine 0.004)) {
    $ids = @($ed.before) + @($ed.after); $span = @($mine | Where-Object { $ids -contains $_.id })
    if ($ed.axis -eq 'x') {
      $lx = $v.A.X + $ed.pos * $v.A.Width; $y0 = ($span | ForEach-Object { $v.A.Y + $_.rect.y * $v.A.Height } | Measure-Object -Minimum).Minimum; $y1 = ($span | ForEach-Object { $v.A.Y + ($_.rect.y + $_.rect.h) * $v.A.Height } | Measure-Object -Maximum).Maximum
      if ([Math]::Abs($pt.X - $lx) -le 5 -and $pt.Y -ge $y0 -and $pt.Y -le $y1) { return @{ Kind = 'grip'; V = $v; Edge = $ed; Mine = $mine } }
    } else {
      $ly = $v.A.Y + $ed.pos * $v.A.Height; $x0 = ($span | ForEach-Object { $v.A.X + $_.rect.x * $v.A.Width } | Measure-Object -Minimum).Minimum; $x1 = ($span | ForEach-Object { $v.A.X + ($_.rect.x + $_.rect.w) * $v.A.Width } | Measure-Object -Maximum).Maximum
      if ([Math]::Abs($pt.Y - $ly) -le 5 -and $pt.X -ge $x0 -and $pt.X -le $x1) { return @{ Kind = 'grip'; V = $v; Edge = $ed; Mine = $mine } }
    }
  }
  $all = @(Get-Tiles | Where-Object { $_.monitor -eq $v.Live.id }); [array]::Reverse($all)
  foreach ($t in $all) {
    $b = Get-TileBox $v $t.rect
    if (-not $b.Contains([single]$pt.X, [single]$pt.Y)) { continue }
    if ($t.kind -ne 'league') {
      $e = 6
      if ($pt.X - $b.Left -le $e) { return @{ Kind = 'edge'; Edge = 'l'; Tile = $t; V = $v } }
      if ($b.Right - $pt.X -le $e) { return @{ Kind = 'edge'; Edge = 'r'; Tile = $t; V = $v } }
      if ($pt.Y - $b.Top -le $e) { return @{ Kind = 'edge'; Edge = 't'; Tile = $t; V = $v } }
      if ($b.Bottom - $pt.Y -le $e) { return @{ Kind = 'edge'; Edge = 'b'; Tile = $t; V = $v } }
    }
    return @{ Kind = 'tile'; Tile = $t; V = $v }
  }
  return @{ Kind = 'empty'; V = $v }
}

# ======================= drawing =======================
$script:KindColors = @{
  app = @([Drawing.Color]::FromArgb(51, 48, 74), [Drawing.Color]::FromArgb(140, 134, 200)); web = @([Drawing.Color]::FromArgb(43, 58, 74), [Drawing.Color]::FromArgb(110, 143, 176))
  ugg = @([Drawing.Color]::FromArgb(43, 58, 74), [Drawing.Color]::FromArgb(110, 143, 176)); spotify = @([Drawing.Color]::FromArgb(36, 64, 47), [Drawing.Color]::FromArgb(111, 174, 134))
  league = @([Drawing.Color]::FromArgb(58, 44, 34), [Drawing.Color]::FromArgb(200, 134, 90))
}
$canvas.Add_Paint({
  param($s, $e)
  $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'ClearTypeGridFit'
  $script:view = @(Get-View)
  $muted = New-Object Drawing.SolidBrush($script:C.Muted); $text = New-Object Drawing.SolidBrush($script:C.Text); $acc = New-Object Drawing.SolidBrush($script:C.Accent)
  if (-not $script:view.Count) { $g.DrawString('No named screens are connected. Name your screens in Mise settings.', $script:fSmall, $muted, 24, 24); return }
  foreach ($v in $script:view) {
    # screen, its header (name, taskbar, layout) and the work area
    $hy = $v.Mon.Y - $script:hdrH + 2
    $rowH = $script:hdrH / 3.0
    $g.DrawString($v.Live.name, $script:fBtn, $text, $v.Mon.X, $hy)
    $tbHidden = @($script:R.taskbar) -contains $v.Live.id
    $tbText = $(if ($tbHidden) { 'Taskbar: hidden' } else { 'Taskbar: shown' }); $tbBrush = $(if ($tbHidden) { $acc } else { $muted })
    $pill = New-Object Drawing.Pen([Drawing.Color]::FromArgb(110, 108, 100), 1)
    if ($v.Mon.Width -ge 200) {
      $g.DrawRectangle($pill, ($v.Mon.Right - 190), ($hy + $rowH), 120, 18); $g.DrawString($tbText + ' ' + [char]0x25BE, $script:fSmall, $(if ($tbHidden) { $acc } else { $text }), ($v.Mon.Right - 187), ($hy + $rowH + 1))
      $g.DrawRectangle($pill, ($v.Mon.Right - 66), ($hy + $rowH), 64, 18); $g.DrawString('Layout ' + [char]0x25BE, $script:fSmall, $text, ($v.Mon.Right - 63), ($hy + $rowH + 1))
    } else {
      $g.DrawRectangle($pill, $v.Mon.X, ($hy + $rowH), ($v.Mon.Width - 1), 17); $g.DrawString($tbText + ' ' + [char]0x25BE, $script:fSmall, $(if ($tbHidden) { $acc } else { $text }), ($v.Mon.X + 3), ($hy + $rowH))
      $g.DrawRectangle($pill, $v.Mon.X, ($hy + 2 * $rowH), ($v.Mon.Width - 1), 17); $g.DrawString('Layout ' + [char]0x25BE, $script:fSmall, $text, ($v.Mon.X + 3), ($hy + 2 * $rowH))
    }
    $pill.Dispose()
    $fill = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(29, 29, 33)); $g.FillRectangle($fill, $v.Mon); $fill.Dispose()
    $pen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(74, 74, 82), 1); $g.DrawRectangle($pen, $v.Mon.X, $v.Mon.Y, $v.Mon.Width, $v.Mon.Height); $pen.Dispose()
    if (-not $tbHidden) { $tb = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(38, 38, 43)); $g.FillRectangle($tb, $v.Mon.X, $v.A.Bottom, $v.Mon.Width, [Math]::Max(0, $v.Mon.Bottom - $v.A.Bottom)); $tb.Dispose() }
    # tiles
    foreach ($t in @(Get-Tiles | Where-Object { $_.monitor -eq $v.Live.id })) {
      $b = Get-TileBox $v $t.rect
      $cols = $script:KindColors[$t.kind]; if (-not $cols) { $cols = $script:KindColors.app }
      $fb = New-Object Drawing.SolidBrush($cols[0]); $g.FillRectangle($fb, $b); $fb.Dispose()
      $isSel = ($script:sel -eq $t.id)
      $tp = New-Object Drawing.Pen($(if ($isSel) { $script:C.Accent } else { $cols[1] }), $(if ($isSel) { 2.5 } else { 1.2 })); $g.DrawRectangle($tp, $b.X, $b.Y, $b.Width, $b.Height); $tp.Dispose()
      $label = $t.name; if ($t.kind -eq 'spotify' -and $t.mini) { $label = 'Spotify mini' }
      $sf = New-Object Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'; $sf.Trimming = 'EllipsisCharacter'
      $g.DrawString($label, $script:fBtn, $text, $b, $sf)
      $mk = $script:marks[$t.id]
      if ($mk) { $mb = New-Object Drawing.SolidBrush($(if ($mk -eq 'Passed') { $script:C.Accent } else { [Drawing.Color]::FromArgb(240, 192, 96) })); $g.DrawString($mk, $script:fTiny, $mb, ($b.X + 4), ($b.Y + 3)); $mb.Dispose() }
      if ($t.kind -eq 'league') { $g.DrawString('size set by League', $script:fTiny, $muted, ($b.X + 4), ($b.Bottom - 16)) }
    }
    # the Mise tile (where the progress pop-up shows)
    if ($script:R.card -and $script:R.card.monitor -eq $v.Live.id) {
      $cb = Get-TileBox $v (Get-CardRect $v)
      $cp = New-Object Drawing.Pen($script:C.Accent, 1.5); $cp.DashStyle = 'Dash'; $g.DrawRectangle($cp, $cb.X, $cb.Y, $cb.Width, $cb.Height); $cp.Dispose()
      $g.DrawString('Mise', $script:fTiny, $acc, ($cb.X + 3), ($cb.Y + 2))
    }
  }
  # the grip under the mouse: the shared line lights up with what dragging it does
  if ($script:hover -and $script:hover.Kind -eq 'grip') {
    $v = $script:hover.V; $ed = $script:hover.Edge
    $gp = New-Object Drawing.Pen($script:C.Accent, 3)
    if ($ed.axis -eq 'x') { $lx = $v.A.X + $ed.pos * $v.A.Width; $g.DrawLine($gp, $lx, $v.A.Y, $lx, $v.A.Bottom) } else { $ly = $v.A.Y + $ed.pos * $v.A.Height; $g.DrawLine($gp, $v.A.X, $ly, $v.A.Right, $ly) }
    $gp.Dispose()
    $p = $canvas.PointToClient([Windows.Forms.Cursor]::Position)
    $g.DrawString('drag to resize both', $script:fSmall, $acc, ($p.X + 14), ($p.Y + 10))
  }
  # helper: the empty map says how to start; after a copy it says what Mise tidied
  if (-not @(Get-Tiles).Count) {
    $box = New-Object Drawing.RectangleF(([single]($canvas.ClientSize.Width / 2 - 190)), ([single]($canvas.ClientSize.Height / 2 - 70)), 380, 140)
    $bb = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(36, 32, 28)); $g.FillRectangle($bb, $box); $bb.Dispose()
    $bp = New-Object Drawing.Pen($script:C.Accent, 1.5); $g.DrawRectangle($bp, $box.X, $box.Y, $box.Width, $box.Height); $bp.Dispose()
    $g.DrawString('Start here', $script:fBig, $acc, ($box.X + 16), ($box.Y + 12))
    $g.DrawString("1. Open your apps and put them roughly in place.`n2. Press Copy my screen.`n3. Fine-tune here on the map.", $script:fSmall, $text, (New-Object Drawing.RectangleF(($box.X + 16), ($box.Y + 44), ($box.Width - 32), 90)))
  } elseif ($script:helper) { $g.DrawString($script:helper, $script:fSmall, $acc, 12, ($canvas.ClientSize.Height - 26)) } else { $g.DrawString('Right-click a tile for rename and more. Ctrl+Z undoes, Delete removes the selected tile.', $script:fSmall, $muted, 12, ($canvas.ClientSize.Height - 26)) }
  $g.DrawString('Ctrl+Z undo', $script:fTiny, $muted, ($canvas.ClientSize.Width - 80), 6)
  $muted.Dispose(); $text.Dispose(); $acc.Dispose()
})

# ======================= mouse =======================
function Set-CursorFor($hit) {
  $cur = switch ($hit.Kind) {
    'grip' { if ($hit.Edge.axis -eq 'x') { 'SizeWE' } else { 'SizeNS' } }
    'edge' { if ($hit.Edge -eq 'l' -or $hit.Edge -eq 'r') { 'SizeWE' } else { 'SizeNS' } }
    'tile' { 'SizeAll' }
    'card' { 'SizeAll' }
    'taskbar' { 'Hand' }
    'layout' { 'Hand' }
    default { 'Default' }
  }
  $canvas.Cursor = [Windows.Forms.Cursors]::$cur
}
$canvas.Add_MouseDown({
  param($s, $e)
  try { $form.ActiveControl = $null } catch {}
  if ($e.Button -eq 'Right' -and $script:R) { $hit = Get-Hit $e.Location; if ($hit.Tile) { $script:sel = $hit.Tile.id; Update-Side; $canvas.Invalidate(); Show-TileMenu $hit.Tile $e.Location }; return }
  if ($e.Button -ne 'Left' -or -not $script:R) { return }
  $hit = Get-Hit $e.Location
  switch ($hit.Kind) {
    'taskbar' { Save-UndoPoint; $id = $hit.V.Live.id; if (@($script:R.taskbar) -contains $id) { $script:R.taskbar = @($script:R.taskbar | Where-Object { $_ -ne $id }) } else { $script:R.taskbar = @($script:R.taskbar) + $id }; Set-Dirty; $canvas.Invalidate(); return }
    'layout' { Show-PresetMenu $hit.V $e.Location; return }
    'grip' { Save-UndoPoint; $script:drag = @{ Mode = 'grip'; Hit = $hit }; return }
    'edge' { Save-UndoPoint; $script:sel = $hit.Tile.id; $script:drag = @{ Mode = 'edge'; Hit = $hit }; Update-Side; return }
    'tile' { Save-UndoPoint; $script:sel = $hit.Tile.id; $b = Get-TileBox $hit.V $hit.Tile.rect; $script:drag = @{ Mode = 'move'; Hit = $hit; Dx = $e.X - $b.X; Dy = $e.Y - $b.Y }; Update-Side; $canvas.Invalidate(); return }
    'card' { Save-UndoPoint; $script:sel = 'card'; $b = Get-TileBox $hit.V (Get-CardRect $hit.V); $script:drag = @{ Mode = 'card'; Hit = $hit; Dx = $e.X - $b.X; Dy = $e.Y - $b.Y }; Update-Side; $canvas.Invalidate(); return }
    default { $script:sel = ''; Update-Side; $canvas.Invalidate() }
  }
})
$canvas.Add_MouseMove({
  param($s, $e)
  if (-not $script:R) { return }
  $d = $script:drag
  if (-not $d) {
    # repaint only when what is under the mouse changes (or a grip follows the mouse), not on every pixel
    $old = $script:hover; $script:hover = Get-Hit $e.Location; Set-CursorFor $script:hover
    $was = if ($old) { "$($old.Kind)|$($old.Tile.id)|$($old.Edge)" } else { '' }; $now = "$($script:hover.Kind)|$($script:hover.Tile.id)|$($script:hover.Edge)"
    if ($was -ne $now -or $script:hover.Kind -eq 'grip') { $canvas.Invalidate() }
    return
  }
  switch ($d.Mode) {
    'grip' {
      $v = $d.Hit.V; $ed = $d.Hit.Edge
      $val = if ($ed.axis -eq 'x') { ($e.X - $v.A.X) / $v.A.Width } else { ($e.Y - $v.A.Y) / $v.A.Height }
      Move-SharedEdge $d.Hit.Mine $ed $val $v.Area | Out-Null
    }
    'edge' {
      $v = $d.Hit.V; $t = $d.Hit.Tile; $axis = if ($d.Hit.Edge -in 'l', 'r') { 'x' } else { 'y' }
      $others = @(Get-Tiles | Where-Object { $_.monitor -eq $v.Live.id })
      $val = if ($axis -eq 'x') { ($e.X - $v.A.X) / $v.A.Width } else { ($e.Y - $v.A.Y) / $v.A.Height }
      $tol = if ($axis -eq 'x') { 10 / $v.A.Width } else { 10 / $v.A.Height }
      $mf = Get-MinFrac $t $v.Area
      $t.rect = Get-ResizedRect $t.rect $d.Hit.Edge $val (Get-Guides $others $axis $t.id) $tol $mf.w $mf.h
    }
    'move' {
      $t = $d.Hit.Tile
      $v = Get-ViewAt $e.Location; if (-not $v) { $v = Get-ViewFor $t.monitor }; if (-not $v) { return }
      if ($v.Live.id -ne $t.monitor) {   # dragged onto another screen: keep the size in pixels
        $old = Get-ViewFor $t.monitor
        $wPx = [double]$t.rect.w * $old.Area.W; $hPx = [double]$t.rect.h * $old.Area.H
        $t.monitor = $v.Live.id; $t.rect = @{ x = 0; y = 0; w = [Math]::Min(1.0, $wPx / $v.Area.W); h = [Math]::Min(1.0, $hPx / $v.Area.H) }
        $d.Dx = [Math]::Min($d.Dx, $t.rect.w * $v.A.Width / 2); $d.Dy = [Math]::Min($d.Dy, $t.rect.h * $v.A.Height / 2)
      }
      $others = @(Get-Tiles | Where-Object { $_.monitor -eq $v.Live.id })
      $r = Copy-Rect $t.rect; $r.x = ($e.X - $d.Dx - $v.A.X) / $v.A.Width; $r.y = ($e.Y - $d.Dy - $v.A.Y) / $v.A.Height
      $t.rect = Get-SnappedMove $r (Get-Guides $others 'x' $t.id) (Get-Guides $others 'y' $t.id) (10 / $v.A.Width) (10 / $v.A.Height)
    }
    'card' {
      $v = Get-ViewAt $e.Location; if (-not $v) { return }
      $script:R.card.monitor = $v.Live.id
      $cr = Get-CardRect $v; $cr.x = ($e.X - $d.Dx - $v.A.X) / $v.A.Width; $cr.y = ($e.Y - $d.Dy - $v.A.Y) / $v.A.Height
      $others = @(Get-Tiles | Where-Object { $_.monitor -eq $v.Live.id })
      $cr = Get-SnappedMove $cr (Get-Guides $others 'x' '') (Get-Guides $others 'y' '') (10 / $v.A.Width) (10 / $v.A.Height)
      $script:R.card.rect = @{ x = $cr.x; y = $cr.y; w = $cr.w; h = $cr.h }
    }
  }
  Set-Dirty; $canvas.Invalidate()
})
$canvas.Add_MouseUp({ param($s, $e) if ($script:drag) { $script:drag = $null; Update-Side; $canvas.Invalidate() } })
$canvas.Add_MouseLeave({ $script:hover = $null; $canvas.Invalidate() })

function Rename-Tile($t) {
  $form.TopMost = $false
  $n = Show-MiseInput 'Rename tile' 'Name shown on the map and in the progress pop-up' "$($t.name)"
  # Store apps are found by their window title: keep the original name as the match before renaming
  if ($n) { Save-UndoPoint; if ($t.kind -eq 'app' -and $t.appid -and -not $t.exe -and -not $t.hint) { $t.hint = $t.name }; $t.name = $n; Set-Dirty; Update-Side; $canvas.Invalidate() }
}
# right-click a tile: the common actions in one place
function Show-TileMenu($t, $pt) {
  $m = New-Object Windows.Forms.ContextMenuStrip
  $m.BackColor = $script:C.Panel; $m.ForeColor = $script:C.Text; $m.ShowImageMargin = $false
  $iR = $m.Items.Add('Rename...'); $iR.Tag = $t.id; $iR.Add_Click({ param($s, $e) $tt = Get-Tile $s.Tag; if ($tt) { Rename-Tile $tt } })
  if ($t.kind -ne 'league' -and $t.kind -ne 'ugg') {
    $iE = $m.Items.Add($(if ($t.exit -eq 'close') { 'On exit: Closes (click for Stays open)' } else { 'On exit: Stays open (click for Closes)' })); $iE.Tag = $t.id
    $iE.Add_Click({ param($s, $e) Save-UndoPoint; $tt = Get-Tile $s.Tag; $tt.exit = $(if ($tt.exit -eq 'close') { 'leave' } else { 'close' }); Set-Dirty; Update-Side; $canvas.Invalidate() })
  }
  $iF = $m.Items.Add('Bring to front'); $iF.Tag = $t.id
  $iF.Add_Click({ param($s, $e) Save-UndoPoint; $tt = Get-Tile $s.Tag; $script:R.tiles = @(@(Get-Tiles | Where-Object { $_.id -ne $s.Tag }) + $tt); Set-Dirty; $canvas.Invalidate() })
  $iB = $m.Items.Add('Send to back'); $iB.Tag = $t.id
  $iB.Add_Click({ param($s, $e) Save-UndoPoint; $tt = Get-Tile $s.Tag; $script:R.tiles = @(@($tt) + @(Get-Tiles | Where-Object { $_.id -ne $s.Tag })); Set-Dirty; $canvas.Invalidate() })
  [void]$m.Items.Add('-')
  $iX = $m.Items.Add('Remove from routine'); $iX.Tag = $t.id
  $iX.Add_Click({ param($s, $e) Save-UndoPoint; $script:R.tiles = @(Get-Tiles | Where-Object { $_.id -ne $s.Tag }); $script:sel = ''; Set-Dirty; Update-Side; $canvas.Invalidate() })
  $m.Show($canvas, $pt)
}

function Show-PresetMenu($v, $pt) {
  $m = New-Object Windows.Forms.ContextMenuStrip
  $m.BackColor = $script:C.Panel; $m.ForeColor = $script:C.Text; $m.ShowImageMargin = $false
  $presets = Get-Presets ([bool]$v.Live.Vertical)
  foreach ($k in $presets.Keys) {
    $it = $m.Items.Add($k); $it.Tag = @{ Slots = $presets[$k]; Mon = $v.Live.id }
    $it.Add_Click({ param($s, $e) Save-UndoPoint; $mine = @(Get-Tiles | Where-Object { $_.monitor -eq $s.Tag.Mon -and $_.kind -ne 'league' -and -not ($_.kind -eq 'spotify' -and $_.mini) }); $mini = @(Get-Tiles | Where-Object { $_.monitor -eq $s.Tag.Mon -and $_.kind -eq 'spotify' -and $_.mini })[0]; $lim = if ($mini -and [double]$mini.rect.y -gt 0.5) { [double]$mini.rect.y } else { 1.0 }; $sl = @($s.Tag.Slots | ForEach-Object { @{ x = [double]$_.x; y = [double]$_.y * $lim; w = [double]$_.w; h = [double]$_.h * $lim } }); Set-Preset $mine $sl | Out-Null; $script:R.tiles = @(@(Get-Tiles | Where-Object { -not ($_.kind -eq 'spotify' -and $_.mini) }) + @(Get-Tiles | Where-Object { $_.kind -eq 'spotify' -and $_.mini })); Set-Dirty; $canvas.Invalidate() })
  }
  $m.Show($canvas, $pt)
}

# ======================= side panel =======================
function Add-Side($ctl, [int]$h) { $ctl.Location = New-Object Drawing.Point(0, $script:sy); $ctl.Width = 310; $side.Controls.Add($ctl); $script:sy += $h }
function Add-SideLabel([string]$t, $font, $color, [int]$h) { $l = New-Label $t $font $color 0 0 310 ($h - 4); Add-Side $l $h; return $l }
function Update-Side {
  $side.SuspendLayout(); $side.Controls.Clear(); $script:sy = 0
  if (-not $script:R) { $side.ResumeLayout(); return }
  $null = Add-SideLabel 'ROUTINE' $script:fTiny $script:C.Muted 20
  $bL = New-Btn 'Log in to League' 0 0 310 38 'setting'; $bL.IsSwitch = $true; $bL.On = [bool]$script:R.league
  $bL.Add_Click({ param($s, $e) $script:R.league = -not [bool]$script:R.league; $s.On = $script:R.league; $s.Invalidate(); Set-Dirty })
  Add-Side $bL 44
  if ($script:R.league) { $null = Add-SideLabel 'Starting it asks which account, then logs in, starts the client and your lobby.' $script:fSmall $script:C.Muted 40 }
  $bK = New-Btn 'Hotkey' 0 0 310 38 'setting'; $bK.Chip = $(if ($script:hkCapture) { 'press keys...' } elseif ($script:R.hotkey) { $script:R.hotkey } else { 'none' })
  $bK.Add_Click({ $script:hkCapture = $true; Update-Side })
  Add-Side $bK 44
  if ($script:hkMsg) { $null = Add-SideLabel $script:hkMsg $script:fSmall $script:C.Muted 40 }
  $bCard = New-Btn $(if ($script:R.card) { 'Mise pop-up: placed on the map' } else { 'Mise pop-up: place it on the map' }) 0 0 310 34
  $bCard.Add_Click({
    Save-UndoPoint
    if ($script:R.card) { $script:R.card = $null; if ($script:sel -eq 'card') { $script:sel = '' } }
    else { $v = $script:view | Where-Object { $_.Live.Primary } | Select-Object -First 1; if (-not $v) { $v = $script:view[0] }; if ($v) { $script:R.card = [pscustomobject]@{ monitor = $v.Live.id; rect = @{ x = 16.0 / $v.Area.W; y = 16.0 / $v.Area.H; w = 320.0 / $v.Area.W; h = 96.0 / $v.Area.H } }; $script:sel = 'card' } }
    Set-Dirty; Update-Side; $canvas.Invalidate()
  })
  $tip.SetToolTip($bCard, 'Where the small progress pop-up shows while this routine runs. Click again to remove it.')
  Add-Side $bCard 46

  # the selected tile
  $t = if ($script:sel -and $script:sel -ne 'card') { Get-Tile $script:sel } else { $null }
  if ($t) {
    $null = Add-SideLabel 'TILE' $script:fTiny $script:C.Muted 20
    $null = Add-SideLabel $t.name $script:fBig $script:C.Text 28
    $bRn = New-Btn 'Rename' 0 0 90 26 'ghost'; $bRn.Tag = $t.id; $bRn.Add_Click({ param($s, $e) $tt = Get-Tile $s.Tag; if ($tt) { Rename-Tile $tt } }); Add-Side $bRn 30
    $mon = ($script:cfg.monitors | Where-Object { $_.id -eq $t.monitor } | Select-Object -First 1).name
    $areaTxt = ''
    $v = Get-ViewFor $t.monitor
    if ($v) { $px = ConvertTo-PxRect $v.Area $t.rect; $areaTxt = "  -  $($px.W) x $($px.H) px" }
    $null = Add-SideLabel "$mon$areaTxt" $script:fSmall $script:C.Muted 24
    switch ($t.kind) {
      'web' {
        $null = Add-SideLabel 'Address' $script:fSmall $script:C.Muted 20
        $ub = New-MiseText 0 0 310 "$($t.url)"; $ub.Box.Tag = $t.id
        $ub.Box.Add_TextChanged({ param($s, $e) $tt = Get-Tile $s.Tag; if ($tt -and $tt.url -ne $s.Text) { $tt.url = $s.Text.Trim(); Set-Dirty } })
        Add-Side $ub.Panel 38
        $chips = New-Object Windows.Forms.FlowLayoutPanel; $chips.Height = 36; $chips.BackColor = $script:C.Bg
        foreach ($k in $script:WebPresets.Keys) { $cbtn = New-Btn $k 0 0 72 28; $cbtn.Tag = @{ Id = $t.id; Url = $script:WebPresets[$k]; Name = $k }; $cbtn.Add_Click({ param($s, $e) $tt = Get-Tile $s.Tag.Id; $tt.url = $s.Tag.Url; $tt.name = $s.Tag.Name; $tt.hint = $s.Tag.Name; if ($tt.url -like '*u.gg*') { $tt.kind = 'ugg'; $tt.name = 'u.gg (opens in champ select)' }; Set-Dirty; Update-Side; $canvas.Invalidate() }); $chips.Controls.Add($cbtn) }
        Add-Side $chips 40
        $bc = New-Btn 'Clean window' 0 0 310 38 'setting'; $bc.IsSwitch = $true; $bc.On = [bool]$t.clean -and $script:browser.Clean; $bc.Enabled = [bool]$script:browser.Clean; $bc.Tag = $t.id
        $bc.Add_Click({ param($s, $e) $tt = Get-Tile $s.Tag; $tt.clean = -not [bool]$tt.clean; $s.On = $tt.clean; $s.Invalidate(); Set-Dirty })
        Add-Side $bc 44
        $null = Add-SideLabel $(if ($script:browser.Kind -eq 'none') { "No supported browser found. Install Chrome, Brave, Vivaldi or Opera (Mise doesn't use Edge)." } elseif ($script:browser.Clean) { "Opens in $($script:browser.Name). Clean: no address bar, tabs or bookmarks." } else { "Opens in $($script:browser.Name) as a normal window ($($script:browser.Name) can't open clean windows)." }) $script:fSmall $script:C.Muted 40
      }
      'ugg' { $null = Add-SideLabel "Opens when you pick a champion, here. $(if (-not [bool](Get-MiseSetting $script:cfg 'champPage')) { 'Off right now: Open u.gg for my champion is off in Options.' })" $script:fSmall $script:C.Muted 44 }
      'spotify' {
        $bm = New-Btn 'Mini player' 0 0 310 38 'setting'; $bm.IsSwitch = $true; $bm.On = [bool]$t.mini; $bm.Tag = $t.id
        $bm.Add_Click({ param($s, $e)
          try {
            $tt = Get-Tile $s.Tag; $tt.mini = -not [bool]$tt.mini; $s.On = $tt.mini
            $vv = Get-ViewFor $tt.monitor; if (-not $vv) { $vv = $script:view | Select-Object -First 1 }
            if ($tt.mini) {
              $tt.minW = 300; $tt.minH = 90
              if ($vv) { $tt.rect.w = [Math]::Min(1.0, 360.0 / $vv.Area.W); $tt.rect.h = [Math]::Min(1.0, 100.0 / $vv.Area.H); if ($tt.rect.x + $tt.rect.w -gt 1) { $tt.rect.x = 1 - $tt.rect.w }; if ($tt.rect.y + $tt.rect.h -gt 1) { $tt.rect.y = 1 - $tt.rect.h } }
            } else { $tt.minW = 800; $tt.minH = 600 }
          } catch { Write-Log "mini toggle failed: $($_.Exception.Message)" }
          $s.Invalidate(); Set-Dirty; Update-Side; $canvas.Invalidate() })
        Add-Side $bm 44
        $null = Add-SideLabel 'Turning it on shrinks the tile to the mini player. Test run opens it; Preview only moves windows that are already open.' $script:fSmall $script:C.Muted 54
      }
      'league' { $null = Add-SideLabel 'The League client keeps the size set in League. Drag it to choose where it opens.' $script:fSmall $script:C.Muted 40 }
      default { $null = Add-SideLabel $(if ($t.exe) { $t.exe } elseif ($t.appid) { $t.appid } else { 'Learned on the first run' }) $script:fSmall $script:C.Muted 36 }
    }
    if ($t.minW -or $t.minH) { $null = Add-SideLabel "Smallest size the app allows: $($t.minW) x $($t.minH) px" $script:fSmall $script:C.Muted 24 }
    if ($t.kind -ne 'league' -and $t.kind -ne 'ugg') {
      $be = New-Btn 'On exit this app' 0 0 310 38 'setting'; $be.Seg = 'Stays open|Closes'; $be.On = ($t.exit -eq 'close'); $be.Tag = $t.id
      $be.Add_Click({ param($s, $e) Save-UndoPoint; $tt = Get-Tile $s.Tag; $tt.exit = $(if ($tt.exit -eq 'close') { 'leave' } else { 'close' }); $s.On = ($tt.exit -eq 'close'); $s.Invalidate(); Set-Dirty })
      Add-Side $be 44
    }
    $bRm = New-Btn 'Remove from routine' 0 0 310 32 'ghost'; $bRm.Tag = $t.id
    $bRm.Add_Click({ param($s, $e) Save-UndoPoint; $script:R.tiles = @(Get-Tiles | Where-Object { $_.id -ne $s.Tag }); $script:sel = ''; Set-Dirty; Update-Side; $canvas.Invalidate() })
    Add-Side $bRm 40
  } elseif ($script:sel -eq 'card') {
    $null = Add-SideLabel 'MISE POP-UP' $script:fTiny $script:C.Muted 20
    $null = Add-SideLabel 'The small progress pop-up shows here while the routine runs.' $script:fSmall $script:C.Muted 40
  } elseif (@(Get-Tiles).Count) {
    $null = Add-SideLabel 'Click a tile to see its settings, right-click it to rename. Drag the line between two tiles to resize both.' $script:fSmall $script:C.Muted 44
  }

  # test run and check results
  if ($script:checks.Count) {
    $null = Add-SideLabel 'CHECK' $script:fTiny $script:C.Muted 20
    foreach ($c2 in $script:checks) {
      $col = switch ($c2.Level) { 'error' { [Drawing.Color]::FromArgb(240, 140, 120) } 'warn' { [Drawing.Color]::FromArgb(240, 215, 154) } default { $script:C.Muted } }
      $pre = switch ($c2.Level) { 'error' { 'Fix: ' } 'warn' { 'Note: ' } default { 'OK: ' } }
      $null = Add-SideLabel "$pre$($c2.Text)" $script:fSmall $col 36
    }
  }
  $side.ResumeLayout()
}

# ======================= hotkey capture =======================
$script:hkMsg = ''
$form.Add_KeyDown({
  param($s, $e)
  if ($e.Control -and $e.KeyCode -eq 'Z' -and -not $script:hkCapture -and -not $nameBox.Box.Focused) { $e.SuppressKeyPress = $true; Restore-Undo; return }
  if ($e.KeyCode -eq 'Delete' -and -not $script:hkCapture -and -not $nameBox.Box.Focused -and $form.ActiveControl -isnot [Windows.Forms.TextBox] -and $form.ActiveControl -isnot [Windows.Forms.ComboBox] -and $script:sel -and $script:sel -ne 'card') {
    Save-UndoPoint; $script:R.tiles = @(Get-Tiles | Where-Object { $_.id -ne $script:sel }); $script:sel = ''; Set-Dirty; Update-Side; $canvas.Invalidate(); return }
  if (-not $script:hkCapture) { return }
  $e.SuppressKeyPress = $true; $e.Handled = $true
  $k = $e.KeyCode.ToString()
  if ($k -in 'ControlKey', 'ShiftKey', 'Menu', 'LWin', 'RWin', 'None') { return }
  if ($k -eq 'Escape') { $script:hkCapture = $false; $script:hkMsg = ''; Update-Side; return }
  if ($k -in 'Back', 'Delete') { $script:R.hotkey = ''; $script:hkCapture = $false; $script:hkMsg = 'No hotkey.'; Set-Dirty; Update-Side; return }
  if (-not ($e.Control -or $e.Alt)) { $script:hkMsg = 'Add Ctrl or Alt so it does not block normal typing.'; Update-Side; return }
  $key = if ($k -match '^D([0-9])$') { $Matches[1] } else { $k }
  $txt = ((@($(if ($e.Control) { 'Ctrl' }), $(if ($e.Alt) { 'Alt' }), $(if ($e.Shift) { 'Shift' })) | Where-Object { $_ }) -join '+') + "+$key"
  if (-not (ConvertTo-Hotkey $txt)) { $script:hkMsg = 'That key cannot be used. Try a letter, digit or F-key.'; Update-Side; return }
  $own = @(Get-HotkeyConflicts $script:cfg $txt $script:R.id)
  $taken = ($own.Count -eq 0 -and $txt -ne $script:R.hotkey -and -not (Test-HotkeyFree $txt))
  if ($own.Count -or $taken) {
    $why = if ($own.Count) { $own[0] } else { 'Windows or another program already uses it' }
    $script:hkMsg = "$txt is not available ($why)."; Update-Side; return
  }
  $script:R.hotkey = $txt; $script:hkCapture = $false; $script:hkMsg = 'Hotkey set. It works after you press Save.'; Set-Dirty; Update-Side
})

# ======================= Copy my screen =======================
function Show-CaptureDialog {
  $items = @(Get-CaptureList $script:cfg)
  if (-not $items.Count) { $null = Show-MiseAsk 'Copy my screen' 'No open windows were found on your named screens. Open your apps, then try again.' 'OK' 'Close'; return }
  $W = 660; $M = 18; $cw = $W - 2 * $M
  $f = New-MiseDialog 'Copy my screen' $W 600
  $f.Controls.Add((New-Label 'Tick the windows that belong to this routine. On the right: what each one does when you exit the routine (click to switch).' $script:fSmall $script:C.Muted $M 52 ($W - 2 * $M) 34))
  $box = New-Object Windows.Forms.Panel; $box.Location = New-Object Drawing.Point($M, 92); $box.Width = $cw; $box.BackColor = $script:C.Bg; $box.AutoScroll = $true
  $f.Controls.Add($box)
  $rows = @(); $y = 0
  foreach ($it in $items) {
    $isUgg = ($it.Url -like '*u.gg*')
    $on = ($it.Kind -ne 'league') -or [bool]$script:R.league
    $chk = New-MiseCheck $(if ($isUgg) { 'u.gg (opens in champ select)' } elseif ($it.Kind -eq 'league') { 'League client (position only)' } elseif ($it.Kind -eq 'spotify' -and $it.Mini) { 'Spotify mini player' } else { $it.Name }) 0 ($y + 6) 330 $on
    $mn = ($script:cfg.monitors | Where-Object { $_.id -eq $it.Monitor } | Select-Object -First 1).name
    $ml = New-Label $mn $script:fSmall $script:C.Muted 338 ($y + 8) 80 20
    $ex = New-Btn '' ($cw - 204) ($y + 1) 180 32 'seg'; $ex.Seg = 'Stays open|Closes'; $ex.On = ($it.Kind -eq 'web' -and -not $isUgg)
    $ex.Add_Click({ param($s, $e) $s.On = -not $s.On; $s.Invalidate() })
    if ($it.Kind -eq 'league' -or $isUgg) { $ex.Visible = $false }
    $box.Controls.AddRange(@($chk, $ml, $ex))
    $url = $null
    if ($it.Kind -eq 'web' -and -not $isUgg) {
      $y += 38
      $url = New-MiseText 26 $y 300 $it.Url; $box.Controls.Add($url.Panel)
      $px = 334
      foreach ($k in $script:WebPresets.Keys) { $pb = New-Btn $k $px ($y + 1) 66 30; $pb.Tag = @{ Box = $url.Box; Url = $script:WebPresets[$k] }; $pb.Add_Click({ param($s, $e) $s.Tag.Box.Text = $s.Tag.Url }); $box.Controls.Add($pb); $px += 70 }
    }
    $rows += @{ Item = $it; Check = $chk; Exit = $ex; Url = $url }
    $y += 42
  }
  $box.Height = [Math]::Min(420, $y + 4)
  $by = $box.Bottom + 16
  $script:capMode = $null
  $hasTiles = (@(Get-Tiles).Count -gt 0)
  $bCancel = New-Btn 'Cancel' $M $by 100 34 'ghost'; $bCancel.Add_Click({ $f.Close() }); $f.Controls.Add($bCancel)
  if ($hasTiles) {
    $bRep = New-Btn 'Replace the tiles' ($W - $M - 340) $by 170 34; $bRep.Add_Click({ $script:capMode = 'replace'; $f.Close() })
    $bAddT = New-Btn 'Add to the map' ($W - $M - 160) $by 160 34 'primary'; $bAddT.Add_Click({ $script:capMode = 'add'; $f.Close() })
    $f.Controls.AddRange(@($bRep, $bAddT))
  } else {
    $bGo = New-Btn 'Put them on the map' ($W - $M - 200) $by 200 34 'primary'; $bGo.Add_Click({ $script:capMode = 'replace'; $f.Close() }); $f.Controls.Add($bGo)
  }
  $f.ClientSize = New-Object Drawing.Size($W, ($by + 52))
  [void]$f.ShowDialog()
  if (-not $script:capMode) { return }
  Save-UndoPoint
  $new = @()
  foreach ($r in $rows) {
    if (-not $r.Check.Checked) { continue }
    $t = ConvertTo-Tile $r.Item $(if ($r.Exit.On) { 'close' } else { 'leave' })
    if ($r.Url) { $t.url = $r.Url.Box.Text.Trim(); if ($t.url -like '*u.gg*') { $t.kind = 'ugg'; $t.name = 'u.gg (opens in champ select)' } }
    if ($t.kind -eq 'league') { $script:R.league = $true }
    $new += $t
  }
  $script:R.tiles = $(if ($script:capMode -eq 'replace') { @($new) } else { @(Get-Tiles) + @($new) })
  # tidy each screen: close small gaps, remove small overlaps (the League client keeps its size)
  $gaps = 0; $ovs = 0
  foreach ($mid in @(Get-Tiles | ForEach-Object { $_.monitor } | Select-Object -Unique)) {
    $res = Invoke-Tidy @(Get-Tiles | Where-Object { $_.monitor -eq $mid -and $_.kind -ne 'league' }) 0.03
    $gaps += $res.Gaps; $ovs += $res.Overlaps
  }
  $script:helper = "Copied $($new.Count) windows. Tidied: $gaps gaps closed, $ovs overlaps removed."
  Set-Dirty; Update-Side; $canvas.Invalidate()
}

# ======================= + Add app =======================
function Add-TileFor($tile) {
  $v = $script:view | Where-Object { $_.Live.Primary } | Select-Object -First 1; if (-not $v) { $v = $script:view[0] }; if (-not $v) { return }
  $tile.monitor = $v.Live.id
  # the first free slot of a halves/stack split, else the middle
  $mine = @(Get-Tiles | Where-Object { $_.monitor -eq $v.Live.id })
  $slots = (Get-Presets ([bool]$v.Live.Vertical))['Thirds']
  $free = $slots | Where-Object { $sl = $_; -not ($mine | Where-Object { [Math]::Abs($_.rect.x - $sl.x) -lt 0.05 -and [Math]::Abs($_.rect.y - $sl.y) -lt 0.05 }) } | Select-Object -First 1
  $tile.rect = $(if ($free) { Copy-Rect $free } else { @{ x = 0.3; y = 0.3; w = 0.4; h = 0.4 } })
  Save-UndoPoint
  $script:R.tiles = @(Get-Tiles) + $tile; $script:sel = $tile.id
  Set-Dirty; Update-Side; $canvas.Invalidate()
}
function Show-AddDialog {
  $W = 460; $M = 18; $cw = $W - 2 * $M
  $f = New-MiseDialog 'Add app' $W 560
  $q = New-MiseText $M 54 $cw ''; $f.Controls.Add($q.Panel)
  $lst = New-Object Windows.Forms.ListBox; $lst.Location = New-Object Drawing.Point($M, 96); $lst.Size = New-Object Drawing.Size($cw, 380)
  $lst.BackColor = $script:C.Panel; $lst.ForeColor = $script:C.Text; $lst.BorderStyle = 'None'; $lst.Font = $script:fStatus; $lst.IntegralHeight = $false
  $f.Controls.Add($lst)
  $script:addApps = @(Get-InstalledApps)
  $fill = { $lst.Items.Clear(); [void]$lst.Items.Add('Web page'); foreach ($a in $script:addApps) { if (-not $q.Box.Text -or $a.Name -like "*$($q.Box.Text)*") { [void]$lst.Items.Add($a.Name) } } }
  & $fill
  $q.Box.Add_TextChanged({ & $fill })
  $script:addPick = $null
  $ok = New-Btn 'Add' ($W - $M - 110) 490 110 34 'primary'; $f.Controls.Add($ok)
  $go = { if ($lst.SelectedItem) { $script:addPick = "$($lst.SelectedItem)"; $f.Close() } }
  $ok.Add_Click($go); $lst.Add_DoubleClick($go)
  $f.ClientSize = New-Object Drawing.Size($W, 540)
  [void]$f.ShowDialog()
  if (-not $script:addPick) { return }
  $t = [pscustomobject]@{ id = (New-Id); kind = 'app'; name = $script:addPick; monitor = ''; rect = $null; exit = 'leave'; exe = ''; appid = ''; proc = ''; cls = ''; url = ''; hint = ''; clean = $false; mini = $false; minW = 0; minH = 0 }
  if ($script:addPick -eq 'Web page') { $t.kind = 'web'; $t.name = 'Web page'; $t.url = 'https://'; $t.clean = $true; $t.exit = 'close' }
  else {
    $a = $script:addApps | Where-Object { $_.Name -eq $script:addPick } | Select-Object -First 1
    $p = Resolve-AppIdPath $a.Id
    if ($p) { $t.exe = $p; $t.proc = [IO.Path]::GetFileNameWithoutExtension($p) } else { $t.appid = $a.Id }
    if ($a.Name -eq 'Spotify') { $t.kind = 'spotify'; $t.proc = 'Spotify' }
  }
  Add-TileFor $t
}

# ======================= save, preview, test run =======================
function Save-Routine {
  $h = @(Test-RoutineHealth $script:R @{ Exists = { param($t) Test-TileInstalled $t }; Monitors = @(Get-LiveMonitors $script:cfg | ForEach-Object { $_.id }); Browser = $script:browser; Conflicts = @(if ($script:R.hotkey) { Get-HotkeyConflicts $script:cfg $script:R.hotkey $script:R.id }) })
  $script:checks = $h
  $blocking = @($h | Where-Object { $_.Level -eq 'error' -and ($_.Text -like 'The routine is empty*' -or $_.Text -like 'Give the routine a name*') })
  if ($blocking.Count) { Update-Side; return $false }
  $cf = Get-MiseConfig
  $cf.routines = @(@($cf.routines | Where-Object { $_.id -ne $script:R.id }) + (Copy-Routine $script:R))
  Save-MiseConfig $cf; $script:cfg = $cf
  $script:dirty = $false
  Update-List; Update-Side
  return $true
}
function Start-Runner([string[]]$extra, [string]$headline) {
  $tmp = Join-Path $script:DataDir '_builder-routine.json'
  Set-Content -LiteralPath $tmp -Value (ConvertTo-Json $script:R -Depth 10) -Encoding UTF8
  $st = Join-Path $env:TEMP 'mise-status.txt'
  Set-Content -LiteralPath $st -Value $headline -Encoding UTF8
  $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$runner`"", '-RoutineFile', "`"$tmp`"", '-StatusFile', "`"$st`"") + $extra
  return (Start-Process powershell.exe -ArgumentList $a -WindowStyle Hidden -PassThru)
}
$bPrev.Add_Click({ if ($script:R) { $script:helper = 'Preview only moves windows that are already open. Use Test run to start the missing apps and pages.'; $canvas.Invalidate(); $null = Start-Runner @('-Arrange') "Arranging '$($script:R.name)'" } })
$script:testProc = $null
$testTimer = New-Object Windows.Forms.Timer; $testTimer.Interval = 700
$testTimer.Add_Tick({
  if (-not $script:testProc -or -not $script:testProc.HasExited) { return }
  $testTimer.Stop(); $script:testProc = $null
  $lines = @(); try { $lines = @(Get-Content -LiteralPath (Join-Path $env:TEMP 'mise-status.txt')) } catch {}
  $script:marks = @{}
  foreach ($t in Get-Tiles) {
    $n = [regex]::Escape($t.name)
    if ($lines -match "\[$n\] (placed|miniplayer placed)") { $script:marks[$t.id] = 'Passed' }
    elseif ($lines -match "\[$n\] app doesn't exist") { $script:marks[$t.id] = 'Not installed' }
    elseif ($lines -match "\[$n\] did not open") { $script:marks[$t.id] = 'Failed' }
    elseif ($lines -match "\[$n\] its screen is not connected") { $script:marks[$t.id] = 'No screen' }
    elseif ($t.kind -eq 'ugg') { $script:marks[$t.id] = 'Champ select' }
    if ($script:marks[$t.id] -eq 'Passed' -and ($lines -match "\[$n\] slow to open")) { $script:marks[$t.id] = 'Late' }
  }
  $bTest.Text = 'Test run'; $bTest.Enabled = $true; $bTest.Invalidate()
  $script:helper = 'Test run finished: each tile shows its result.'
  $canvas.Invalidate()
})
$bTest.Add_Click({
  if (-not $script:R -or $script:testProc) { return }
  # a League routine's test keeps the current login (no account picker); the League part runs like a real start
  $script:testProc = Start-Runner @() "Starting '$($script:R.name)'"
  $bTest.Text = 'Testing...'; $bTest.Enabled = $false; $bTest.Invalidate(); $testTimer.Start()
})
$bSave.Add_Click({ if ($script:R) { $null = Save-Routine } })
$bUndo.Add_Click({ Restore-Undo })
$bCopy.Add_Click({ if ($script:R) { Show-CaptureDialog } })
$bAdd.Add_Click({ if ($script:R) { Show-AddDialog } })
$bNewR.Add_Click({ if (Confirm-Leave) { Set-Routine (New-BlankRoutine) } })
$bDelR.Add_Click({
  if (-not $script:R) { return }
  if ((Show-MiseAsk 'Delete routine' "Delete '$($script:R.name)'? This can't be undone." 'Delete' 'Keep it') -ne 'yes') { return }
  $cf = Get-MiseConfig; $cf.routines = @($cf.routines | Where-Object { $_.id -ne $script:R.id }); Save-MiseConfig $cf; $script:cfg = $cf
  $script:dirty = $false
  if (@($cf.routines).Count) { Set-Routine (Copy-Routine @($cf.routines)[0]) } else { Set-Routine (New-BlankRoutine) }
})
$bHome.Add_Click({ $form.Close() })
$form.Add_FormClosing({ param($s, $e) if (-not (Confirm-Leave)) { $e.Cancel = $true } })

# ======================= start =======================
$start = $null
if (-not $New) {
  if ($Routine) { $start = @($script:cfg.routines) | Where-Object { $_.id -eq $Routine } | Select-Object -First 1 }
  if (-not $start) { $lf = Join-Path $script:DataDir '_last-routine.txt'; if (Test-Path $lf) { $lid = (Get-Content -LiteralPath $lf -Raw).Trim(); $start = @($script:cfg.routines) | Where-Object { $_.id -eq $lid } | Select-Object -First 1 } }
  if (-not $start) { $start = @($script:cfg.routines) | Select-Object -First 1 }
}
Do-Layout
Set-Routine $(if ($start) { Copy-Routine $start } else { New-BlankRoutine })
if (-not $start) { $script:dirty = $false }
$form.Add_Shown({ $form.Activate(); Start-OpenAnimation $form; Do-Layout })
[void]$form.ShowDialog()
try { $mutex.ReleaseMutex() } catch {}
# back to the Mise window
Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -STA -ExecutionPolicy Bypass -File `"$homeUi`""
