<# Mise builder: one window for new and existing routines.
   Copy my screen (or + Add app or page) puts tiles on a map of your screens; fine-tune them there; Save.
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
try { $ua = Update-AutoMonitors $script:cfg; if ($ua.Added) { Save-MiseConfig $ua.Cfg; $script:cfg = $ua.Cfg } } catch {}
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
function Save-UndoPoint { Push-Undo $script:undo @{ tiles = @($script:R.tiles); card = $script:R.card; taskbar = @($script:R.taskbar) }; Update-UndoButton }
function Restore-Undo {
  $s = Pop-Undo $script:undo
  # say what happened on the map, so Ctrl+Z is never a silent key
  if (-not $s) { $script:helper = 'Nothing more to undo.'; Update-UndoButton; $canvas.Invalidate(); return }
  $script:R.tiles = @($s.tiles | Where-Object { $_ }); $script:R.card = $s.card; $script:R.taskbar = @($s.taskbar | Where-Object { $_ })
  $n = @($script:undo.Items).Count
  $script:dirty = $true; $script:helper = $(if ($n) { "Undone. Ctrl+Z again goes $n more step$(if ($n -ne 1) { 's' }) back." } else { 'Undone. That was the last change.' })
  Update-UndoButton; Update-Side; $canvas.Invalidate()
}
# the Undo button shows its shortcut and how many steps there are; greyed out with nothing to undo
function Update-UndoButton { try { $n = @($script:undo.Items).Count; $bUndo.Text = $(if ($n) { "Undo ($n)  Ctrl+Z" } else { 'Undo  Ctrl+Z' }); $bUndo.Enabled = ($n -gt 0); $bUndo.Invalidate() } catch {} }
function Set-Dirty { $script:dirty = $true; $script:marks = @{}; $script:checks = @() }
# a Mise-styled yes/no (no grey Windows boxes)
function Show-MiseAsk([string]$title, [string]$text, [string]$yes, [string]$no) {
  $W = 380; $M = 18
  $f = New-MiseDialog $title $W 190
  $f.Controls.Add((New-Label $text $script:fSmall $script:C.Text $M 54 ($W - 2 * $M) 60))
  $by = New-Btn $yes ($W - $M - 130) 126 130 34 'primary'
  $script:askAnswer = $null
  $by.Add_Click({ param($s, $e) $script:askAnswer = 'yes'; $s.FindForm().Close() }); $f.Controls.Add($by)
  if ($no) { $bn = New-Btn $no ($W - $M - 270) 126 130 34; $bn.Add_Click({ param($s, $e) $script:askAnswer = 'no'; $s.FindForm().Close() }); $f.Controls.Add($bn) }
  $f.ClientSize = New-Object Drawing.Size($W, 176)
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
Set-MiseBackdrop $form; Set-MiseAppId $form
$form.Add_HandleCreated({ param($s, $e) try { $v = 2; [MiseUi]::DwmSetWindowAttribute($s.Handle, 33, [ref]$v, 4) | Out-Null; $v = 1; [MiseUi]::DwmSetWindowAttribute($s.Handle, 20, [ref]$v, 4) | Out-Null } catch {} })
$tip = New-Object Windows.Forms.ToolTip

# header
$logo = New-Logo 18 16; $form.Controls.Add($logo)
$hdr = New-Label 'Routines' $script:fTitle $script:C.Accent 58 12 150 34; $form.Controls.Add($hdr)
$lblName = New-Label 'Name' $script:fSmall $script:C.Muted 220 26 44 18; $form.Controls.Add($lblName)
$nameBox = New-MiseText 266 18 240; $form.Controls.Add($nameBox.Panel)
$nameBox.Box.Add_TextChanged({ if ($script:R -and $nameBox.Box.Text -ne $script:R.name) { $script:R.name = $nameBox.Box.Text; $script:dirty = $true; Update-List } })
$bCopy = New-Btn 'Copy my screen' 0 16 150 34 'primary'
$bAdd = New-Btn '+ Add app or page' 0 16 150 34
$bUndo = New-Btn 'Undo  Ctrl+Z' 0 16 138 34
$bTest = New-Btn 'Test run' 0 16 100 34
$bSave = New-Btn 'Save' 0 16 80 34 'primary'
$bSaveC = New-Btn 'Save and close' 0 16 130 34
$form.Controls.AddRange(@($bCopy, $bAdd, $bUndo, $bTest, $bSave, $bSaveC))
$tip.SetToolTip($bCopy, 'Put your apps roughly in place first. Mise lists the open windows; tick the ones for this routine.')
$tip.SetToolTip($bUndo, 'Undo the last change on the map (Ctrl+Z)')
$tip.SetToolTip($bTest, 'Run the routine now (League with the current login) and mark each tile passed or failed')

# left: routines
$lblR = New-Label 'ROUTINES' $script:fTiny $script:C.Muted 18 76 200 14; $form.Controls.Add($lblR)
$listPanel = New-Object Windows.Forms.Panel; $listPanel.BackColor = $script:C.Bg; $listPanel.Location = New-Object Drawing.Point(18, 96); $listPanel.AutoScroll = $true
$form.Controls.Add($listPanel)
$bNewR = New-Btn '+ New routine' 18 0 200 34
$bHome = New-Btn 'Back to Mise' 18 0 200 30 'ghost'
$form.Controls.AddRange(@($bNewR, $bHome))

# centre: the map
$canvas = New-Object Windows.Forms.Panel; $canvas.BackColor = $(if ($script:C.Glass) { $b0 = $script:C.Bg; [Drawing.Color]::FromArgb([Math]::Max(0, $b0.R - 3), [Math]::Max(0, $b0.G - 3), [Math]::Max(0, $b0.B - 3)) } else { [Drawing.Color]::FromArgb(18, 18, 21) })
[Windows.Forms.Control].GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic,Instance').SetValue($canvas, $true, $null)
$form.Controls.Add($canvas)

# right: settings
$side = New-Object Windows.Forms.Panel; $side.BackColor = $script:C.Bg; $side.AutoScroll = $true
$form.Controls.Add($side)

function Do-Layout {
  $script:lives = @(Get-LiveMonitors $script:cfg)   # screens are read once per layout, not on every repaint
  $W = $form.ClientSize.Width; $H = $form.ClientSize.Height
  $x = $W - 18
  foreach ($b in @($bSaveC, $bSave, $bTest, $bUndo, $bAdd, $bCopy)) { $x -= $b.Width; $b.Left = $x; $x -= 8 }
  $listPanel.Size = New-Object Drawing.Size(212, ($H - 96 - 94))
  $bNewR.Top = $H - 88; $bHome.Top = $H - 50
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
    $b = New-Btn $nm 0 $y 196 40 'row'; $b.Dots = $true; $b.Tag = $r.id; $b.Chip = $(if ($r.league) { 'LoL' } else { '' })
    $b.On = ($script:R -and $r.id -eq $script:R.id)
    $b.Add_Click({ param($s, $e) if ($s.DotsHit($s.PointToClient([Windows.Forms.Cursor]::Position).X)) { Show-RoutineMenu $s.Tag $s } else { Open-Routine $s.Tag } })
    $b.Add_MouseUp({ param($s, $e) if ($e.Button -eq 'Right') { Show-RoutineMenu $s.Tag $s } })
    $listPanel.Controls.Add($b); $y += 46
  }
}
# right-click a routine in the list (or its ...): duplicate or delete it
function Show-RoutineMenu([string]$id, $ctl) {
  $m = New-Object Windows.Forms.ContextMenuStrip
  $m.BackColor = $script:C.Panel; $m.ForeColor = $script:C.Text; $m.ShowImageMargin = $false
  $miDup = $m.Items.Add('Duplicate'); $miDup.Tag = $id; $miDup.Add_Click({ param($s, $e) Copy-RoutineEntry $s.Tag })
  $miDel = $m.Items.Add('Delete'); $miDel.Tag = $id; $miDel.Add_Click({ param($s, $e) Remove-RoutineEntry $s.Tag })
  $m.Show($ctl, (New-Object Drawing.Point(($ctl.Width - 36), $ctl.Height)))
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
# the Spotify mini player's real smallest and largest size, read once from it when it is open (it is always on top)
$script:miniLimits = $null
function Get-MiniLimits {
  if ($null -ne $script:miniLimits) { return $script:miniLimits }
  $script:miniLimits = $false
  try {
    $mw = Get-WinSnapshot | Where-Object { (Get-ProcName $_.Pid) -eq 'Spotify' -and [MiseWin]::IsTopmost($_.H) } | Select-Object -First 1
    if ($mw) { $mn = [MiseWin2]::ProbeMinSize($mw.H); $mx = [MiseWin2]::ProbeMaxSize($mw.H); if ($mn -and $mx) { $script:miniLimits = @{ MinW = $mn[0]; MinH = $mn[1]; MaxW = $mx[0]; MaxH = $mx[1] } } }
  } catch {}
  return $script:miniLimits
}
function Set-Routine($r) {
  $script:R = $r
  foreach ($k in @('tiles', 'taskbar')) { $script:R.$k = @($script:R.$k | Where-Object { $_ }) }
  # mini player tiles saved before Mise knew its limits get them now (and are shrunk or grown to fit)
  foreach ($t in @($script:R.tiles)) {
    if ($t.kind -eq 'spotify' -and $t.mini -and -not $t.maxW) {
      $ml = Get-MiniLimits
      if ($ml) {
        foreach ($kv in @(@('minW', $ml.MinW), @('minH', $ml.MinH), @('maxW', $ml.MaxW), @('maxH', $ml.MaxH))) { $t | Add-Member -NotePropertyName $kv[0] -NotePropertyValue $kv[1] -Force }
        $mon = @(Get-LiveMonitors $script:cfg) | Where-Object { $_.id -eq $t.monitor } | Select-Object -First 1
        if ($mon) { $t.rect = Set-MinSize $t.rect (Get-MinFrac $t (Get-TileArea $mon $script:R)); $script:dirty = $true }
      }
    }
  }
  $script:dirty = $false; $script:sel = ''; $script:undo = New-UndoStack; $script:marks = @{}; $script:checks = @(); $script:helper = ''
  Update-UndoButton
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
  # corners first (drag a corner to resize width and height at once); the top-most tile wins
  $rev = @($mine); [array]::Reverse($rev)
  foreach ($t in $rev) {
    $b = Get-TileBox $v $t.rect
    $c = [Math]::Min(10.0, [Math]::Min($b.Width, $b.Height) / 3.0)
    $nl = [Math]::Abs($pt.X - $b.Left) -le $c; $nr = [Math]::Abs($pt.X - $b.Right) -le $c
    $nt = [Math]::Abs($pt.Y - $b.Top) -le $c; $nb = [Math]::Abs($pt.Y - $b.Bottom) -le $c
    if (($nl -or $nr) -and ($nt -or $nb)) { return @{ Kind = 'edge'; Edge = "$(if ($nt) { 't' } else { 'b' })$(if ($nl) { 'l' } else { 'r' })"; Tile = $t; V = $v } }
  }
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
function New-RoundPath($r, [double]$rad) {
  $p = New-Object Drawing.Drawing2D.GraphicsPath
  $d = [single]([Math]::Max(0.5, $rad * 2))
  if ($rad -lt 0.5) { $p.AddRectangle($r); return $p }
  $p.AddArc($r.X, $r.Y, $d, $d, 180, 90); $p.AddArc(($r.Right - $d), $r.Y, $d, $d, 270, 90)
  $p.AddArc(($r.Right - $d), ($r.Bottom - $d), $d, $d, 0, 90); $p.AddArc($r.X, ($r.Bottom - $d), $d, $d, 90, 90); $p.CloseFigure()
  return $p
}
function Get-Lighter($c, [int]$n) { return [Drawing.Color]::FromArgb([Math]::Min(255, $c.R + $n), [Math]::Min(255, $c.G + $n), [Math]::Min(255, $c.B + $n)) }
function Get-Darker($c, [int]$n) { return [Drawing.Color]::FromArgb([Math]::Max(0, $c.R - $n), [Math]::Max(0, $c.G - $n), [Math]::Max(0, $c.B - $n)) }
# a stream tile's body: a play symbol and a LIVE badge (a shape and a word, not colour alone)
function Draw-StreamBody($g, $body, $cols) {
  if ($body.Width -lt 30 -or $body.Height -lt 24) { return }
  $r = [single][Math]::Min(18, [Math]::Min($body.Width, $body.Height) * 0.28)
  $cx = $body.X + $body.Width / 2; $cy = $body.Y + $body.Height / 2
  $cb = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(70, $cols[1])); $g.FillEllipse($cb, ($cx - $r), ($cy - $r), (2 * $r), (2 * $r)); $cb.Dispose()
  $tri = [Drawing.PointF[]]@((New-Object Drawing.PointF(($cx - $r * 0.35), ($cy - $r * 0.5))), (New-Object Drawing.PointF(($cx - $r * 0.35), ($cy + $r * 0.5))), (New-Object Drawing.PointF(($cx + $r * 0.55), $cy)))
  $tb = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(235, 236, 255)); $g.FillPolygon($tb, $tri); $tb.Dispose()
  if ($body.Width -ge 70 -and $body.Height -ge 40) {
    $lr = New-Object Drawing.RectangleF(($body.Right - 38), ($body.Y + 5), 32, 15)
    $lp = New-RoundPath $lr 4; $lb = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(214, 54, 56)); $g.FillPath($lb, $lp); $lb.Dispose(); $lp.Dispose()
    $sf = New-Object Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
    $wb = New-Object Drawing.SolidBrush([Drawing.Color]::White); $g.DrawString('LIVE', $script:fTiny, $wb, $lr, $sf); $wb.Dispose(); $sf.Dispose()
  }
}
$script:KindColors = @{
  app = @([Drawing.Color]::FromArgb(51, 48, 74), [Drawing.Color]::FromArgb(140, 134, 200)); web = @([Drawing.Color]::FromArgb(43, 58, 74), [Drawing.Color]::FromArgb(110, 143, 176))
  ugg = @([Drawing.Color]::FromArgb(43, 58, 74), [Drawing.Color]::FromArgb(110, 143, 176)); spotify = @([Drawing.Color]::FromArgb(36, 64, 47), [Drawing.Color]::FromArgb(111, 174, 134))
  league = @([Drawing.Color]::FromArgb(58, 44, 34), [Drawing.Color]::FromArgb(200, 134, 90))
  stream = @([Drawing.Color]::FromArgb(46, 49, 92), [Drawing.Color]::FromArgb(116, 127, 236))
}
$canvas.Add_Paint({
  param($s, $e)
  $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'ClearTypeGridFit'
  $script:view = @(Get-View)
  $muted = New-Object Drawing.SolidBrush($script:C.Muted); $text = New-Object Drawing.SolidBrush($script:C.Text); $acc = New-Object Drawing.SolidBrush($script:C.Accent)
  if (-not $script:view.Count) { $g.DrawString('No named screens are connected. Mise names them by itself; reopen this window after plugging one in.', $script:fSmall, $muted, 24, 24); return }
  foreach ($v in $script:view) {
    # screen, its header (name, taskbar, layout) and the work area
    $hy = $v.Mon.Y - $script:hdrH + 2
    $rowH = $script:hdrH / 3.0
    $g.DrawString($v.Live.name, $script:fBtn, $text, $v.Mon.X, $hy)
    $tbHidden = @($script:R.taskbar) -contains $v.Live.id
    $tbText = $(if ($tbHidden) { 'Taskbar: hidden' } else { 'Taskbar: shown' }); $tbBrush = $(if ($tbHidden) { $acc } else { $muted })
    $pill = New-Object Drawing.Pen([Drawing.Color]::FromArgb(110, 108, 100), 1)
    if ($v.Mon.Width -ge 200) {
      $g.DrawRectangle($pill, ($v.Mon.Right - 190), ($hy + $rowH), 120, 18); $g.DrawString($tbText, $script:fSmall, $(if ($tbHidden) { $acc } else { $text }), ($v.Mon.Right - 187), ($hy + $rowH + 1))
      $g.DrawRectangle($pill, ($v.Mon.Right - 66), ($hy + $rowH), 64, 18); $g.DrawString('Layout ' + [char]0x25BE, $script:fSmall, $text, ($v.Mon.Right - 63), ($hy + $rowH + 1))
    } else {
      $g.DrawRectangle($pill, $v.Mon.X, ($hy + $rowH), ($v.Mon.Width - 1), 17); $g.DrawString($tbText, $script:fSmall, $(if ($tbHidden) { $acc } else { $text }), ($v.Mon.X + 3), ($hy + $rowH))
      $g.DrawRectangle($pill, $v.Mon.X, ($hy + 2 * $rowH), ($v.Mon.Width - 1), 17); $g.DrawString('Layout ' + [char]0x25BE, $script:fSmall, $text, ($v.Mon.X + 3), ($hy + 2 * $rowH))
    }
    $pill.Dispose()
    $fill = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(29, 29, 33)); $g.FillRectangle($fill, $v.Mon); $fill.Dispose()
    $pen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(74, 74, 82), 1); $g.DrawRectangle($pen, $v.Mon.X, $v.Mon.Y, $v.Mon.Width, $v.Mon.Height); $pen.Dispose()
    if (-not $tbHidden) { $tb = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(38, 38, 43)); $g.FillRectangle($tb, $v.Mon.X, $v.A.Bottom, $v.Mon.Width, [Math]::Max(0, $v.Mon.Bottom - $v.A.Bottom)); $tb.Dispose() }
    # tiles: each one drawn like a small window - a title bar with the app's icon and name, a body in the kind's colour
    # dragging a tile: a faint ghost stays where it came from
    $dg = $script:drag
    if ($dg -and $dg.Mode -eq 'move' -and $dg.Orig -and $dg.OrigMon -eq $v.Live.id -and $script:Animate) {
      $gp = New-RoundPath $dg.Orig 6; $gpen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(130, $script:C.Accent), 1.4); $gpen.DashStyle = 'Dash'; $g.DrawPath($gpen, $gp); $gpen.Dispose(); $gp.Dispose()
    }
    foreach ($t in @(Get-Tiles | Where-Object { $_.monitor -eq $v.Live.id })) {
      $b = Get-TileBox $v $t.rect
      if ($b.Width -lt 4 -or $b.Height -lt 4) { continue }
      $cols = $script:KindColors[$t.kind]; if (-not $cols) { $cols = $script:KindColors.app }
      # held: it lifts (a little bigger, a shadow under it); let go: it settles with a small bounce
      $infl = 0.0; $held = ($dg -and $dg.Mode -eq 'move' -and $dg.Hit.Tile.id -eq $t.id -and $script:Animate)
      if ($held) { $infl = 2.0 } elseif ($script:bounce -and $script:bounce.Id -eq $t.id -and -not $script:bounce.NoMove) { $bk = [Math]::Min(1.0, $script:bounce.Clock.ElapsedMilliseconds / 300.0); $infl = 2.0 * (1 - $bk) * [Math]::Cos($bk * [Math]::PI * 1.5) }
      if ($held) { $sp = New-RoundPath (New-Object Drawing.RectangleF(($b.X + 2), ($b.Y + 7), $b.Width, $b.Height)) 7; $sb = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(110, 0, 0, 0)); $g.FillPath($sb, $sp); $sb.Dispose(); $sp.Dispose() }
      if ($infl -ne 0) { $b = New-Object Drawing.RectangleF(([single]($b.X - $infl)), ([single]($b.Y - $infl)), ([single]($b.Width + 2 * $infl)), ([single]($b.Height + 2 * $infl))) }
      $isSel = ($script:sel -eq $t.id); $isHot = ($script:hover -and $script:hover.Tile -and $script:hover.Tile.id -eq $t.id)
      $rad = [Math]::Min(6.0, [Math]::Min($b.Width, $b.Height) / 4.0)
      $path = New-RoundPath $b $rad
      $fb = New-Object Drawing.SolidBrush($(if ($isHot -or $isSel) { Get-Lighter $cols[0] 10 } else { $cols[0] })); $g.FillPath($fb, $path); $fb.Dispose()
      # title bar (only when the tile is tall enough to keep room for the body)
      $barH = $(if ($b.Height -ge 46) { 20.0 } else { 0.0 })
      $old = $g.Clip; $g.SetClip($path)
      if ($barH) {
        $bar = New-Object Drawing.SolidBrush((Get-Darker $cols[0] 14)); $g.FillRectangle($bar, $b.X, $b.Y, $b.Width, [single]$barH); $bar.Dispose()
        $ln = New-Object Drawing.Pen([Drawing.Color]::FromArgb(70, $cols[1]), 1); $g.DrawLine($ln, $b.X, ($b.Y + $barH), $b.Right, ($b.Y + $barH)); $ln.Dispose()
      }
      $g.Clip = $old
      $label = $t.name; if ($t.kind -eq 'spotify' -and $t.mini) { $label = 'Spotify mini' }
      if ($t.kind -eq 'stream') { $label = "$($t.streamer)".Trim(); if (-not $label) { $label = 'Discord stream' } }
      $icon = $null; try { $icon = Get-TileIcon $t $script:browser } catch {}
      $sf = New-Object Drawing.StringFormat; $sf.Trimming = 'EllipsisCharacter'; $sf.FormatFlags = 'NoWrap'; $sf.LineAlignment = 'Center'
      if ($barH) {
        $tx = $b.X + 6
        if ($icon -and $b.Width -ge 60) { $g.InterpolationMode = 'HighQualityBicubic'; $g.DrawImage($icon, (New-Object Drawing.RectangleF(($b.X + 5), ($b.Y + 3), 14, 14))); $tx = $b.X + 23 }
        $g.DrawString($label, $script:fTiny, $text, (New-Object Drawing.RectangleF($tx, $b.Y, [Math]::Max(1, $b.Right - $tx - 4), $barH)), $sf)
        $body = New-Object Drawing.RectangleF($b.X, ($b.Y + $barH), $b.Width, ($b.Height - $barH))
        if ($t.kind -eq 'stream') { Draw-StreamBody $g $body $cols }
        elseif ($icon -and $body.Width -ge 60 -and $body.Height -ge 52) {
          # the app's icon, big and faint, in the middle of the body
          $sz = [single][Math]::Min(40, [Math]::Min($body.Width, $body.Height) * 0.45)
          $ia = New-Object Drawing.Imaging.ImageAttributes; $cm = New-Object Drawing.Imaging.ColorMatrix; $cm.Matrix33 = 0.35; $ia.SetColorMatrix($cm)
          $dst = New-Object Drawing.Rectangle([int]($body.X + ($body.Width - $sz) / 2), [int]($body.Y + ($body.Height - $sz) / 2), [int]$sz, [int]$sz)
          $g.DrawImage($icon, $dst, 0, 0, $icon.Width, $icon.Height, [Drawing.GraphicsUnit]::Pixel, $ia); $ia.Dispose()
        }
      } else {
        $sf.Alignment = 'Center'
        $g.DrawString($label, $script:fTiny, $text, $b, $sf)
      }
      $bw = $(if ($isSel) { 2.4 } elseif ($isHot) { 1.6 } else { 1.1 })
      $tp = New-Object Drawing.Pen($(if ($isSel) { $script:C.Accent } elseif ($isHot) { Get-Lighter $cols[1] 30 } else { $cols[1] }), $bw); $g.DrawPath($tp, $path); $tp.Dispose(); $path.Dispose()
      $mk = $script:marks[$t.id]
      $my = $b.Y + $barH + 3
      if ($mk) { $mb = New-Object Drawing.SolidBrush($(if ($mk -eq 'Passed') { $script:C.Accent } else { [Drawing.Color]::FromArgb(240, 192, 96) })); $g.DrawString($mk, $script:fTiny, $mb, ($b.X + 5), $my); $mb.Dispose() }
      if ($script:bounce -and $script:bounce.Id -eq $t.id -and $script:bounce.Snapped -and $b.Width -ge 60 -and $b.Height -ge 34) {
        $sa = [int](255 * [Math]::Max(0.0, 1 - $script:bounce.Clock.ElapsedMilliseconds / 700.0))
        if ($sa -gt 0) { $snb = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb($sa, $script:C.Accent)); $g.DrawString('snapped', $script:fTiny, $snb, ($b.X + 5), ($b.Bottom - 17)); $snb.Dispose() }
      }
      if ($t.kind -eq 'league') { $g.DrawString('size set by League', $script:fTiny, $muted, ($b.X + 5), ($b.Bottom - 17)) }
      elseif (($isSel -or $isHot) -and $b.Width -ge 70 -and $b.Height -ge 34) {
        # the size the window will get, in pixels
        $pw = [int]([double]$t.rect.w * $v.Area.W); $ph = [int]([double]$t.rect.h * $v.Area.H)
        $rf = New-Object Drawing.StringFormat; $rf.Alignment = 'Far'
        $g.DrawString("$pw x $ph", $script:fTiny, $muted, (New-Object Drawing.RectangleF($b.X, ($b.Bottom - 17), ($b.Width - 6), 16)), $rf); $rf.Dispose()
      }
      $sf.Dispose()
    }
    # the Mise tile (where the progress pop-up shows)
    if ($script:R.card -and $script:R.card.monitor -eq $v.Live.id) {
      $cb = Get-TileBox $v (Get-CardRect $v)
      $cp = New-Object Drawing.Pen($script:C.Accent, 1.5); $cp.DashStyle = 'Dash'; $g.DrawRectangle($cp, $cb.X, $cb.Y, $cb.Width, $cb.Height); $cp.Dispose()
      $g.DrawString('Mise', $script:fTiny, $acc, ($cb.X + 3), ($cb.Y + 2))
    }
  }
  # while a tile is dragged or resized: copper guide lines where its edges line up with another tile
  if ($script:drag -and $script:drag.Mode -in 'move', 'edge' -and $script:drag.Hit.Tile) {
    $dt = $script:drag.Hit.Tile; $v = Get-ViewFor $dt.monitor
    if ($v) {
      $gl = Get-AlignedGuides $dt
      $gpn = New-Object Drawing.Pen([Drawing.Color]::FromArgb(220, $script:C.Accent), 1.6)
      foreach ($x in $gl.X) { $lx = [single]($v.A.X + $x * $v.A.Width); $g.DrawLine($gpn, $lx, $v.A.Y, $lx, $v.A.Bottom) }
      foreach ($yv in $gl.Y) { $ly = [single]($v.A.Y + $yv * $v.A.Height); $g.DrawLine($gpn, $v.A.X, $ly, $v.A.Right, $ly) }
      $gpn.Dispose()
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
  } elseif ($script:helper) { $g.DrawString($script:helper, $script:fSmall, $acc, 12, ($canvas.ClientSize.Height - 26)) } else { $g.DrawString('Drag an edge or a corner to resize. Right-click a tile for quick sizes, rename and more. Delete removes the selected tile. Ctrl+Z undoes the last change.', $script:fSmall, $muted, 12, ($canvas.ClientSize.Height - 26)) }
  $muted.Dispose(); $text.Dispose(); $acc.Dispose()
})

# ======================= mouse =======================
function Set-CursorFor($hit) {
  $cur = switch ($hit.Kind) {
    'grip' { if ($hit.Edge.axis -eq 'x') { 'SizeWE' } else { 'SizeNS' } }
    'edge' { switch ($hit.Edge) { 'l' { 'SizeWE' } 'r' { 'SizeWE' } 't' { 'SizeNS' } 'b' { 'SizeNS' } 'tl' { 'SizeNWSE' } 'br' { 'SizeNWSE' } default { 'SizeNESW' } } }
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
    'tile' { Save-UndoPoint; $script:sel = $hit.Tile.id; $b = Get-TileBox $hit.V $hit.Tile.rect; $script:drag = @{ Mode = 'move'; Hit = $hit; Dx = $e.X - $b.X; Dy = $e.Y - $b.Y; Orig = $b; OrigMon = $hit.Tile.monitor; Moved = $false }; Update-Side; $canvas.Invalidate(); return }
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
      # one edge (l, r, t, b) or a corner (tl, tr, bl, br = both edges at once); each edge snaps to the others' edges
      $v = $d.Hit.V; $t = $d.Hit.Tile
      $others = @(Get-Tiles | Where-Object { $_.monitor -eq $v.Live.id })
      $mf = Get-MinFrac $t $v.Area
      foreach ($ch in @(([string]$d.Hit.Edge).ToCharArray())) {
        $edg = [string]$ch; $axis = if ($edg -in 'l', 'r') { 'x' } else { 'y' }
        $val = if ($axis -eq 'x') { ($e.X - $v.A.X) / $v.A.Width } else { ($e.Y - $v.A.Y) / $v.A.Height }
        $tol = if ($axis -eq 'x') { 10 / $v.A.Width } else { 10 / $v.A.Height }
        $t.rect = Get-ResizedRect $t.rect $edg $val (Get-Guides $others $axis $t.id) $tol $mf.w $mf.h $mf.xw $mf.xh
      }
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
      $d.Moved = $true
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
$canvas.Add_MouseUp({ param($s, $e)
  if ($script:drag) {
    $d = $script:drag; $script:drag = $null
    # a moved tile settles with a bounce; "snapped" when an edge landed on another tile or the screen edge
    if ($d.Mode -in 'move', 'edge' -and $d.Hit.Tile -and ($d.Mode -eq 'edge' -or $d.Moved) -and $script:Animate) {
      $gl = Get-AlignedGuides $d.Hit.Tile $true
      $script:bounce = @{ Id = $d.Hit.Tile.id; Clock = [Diagnostics.Stopwatch]::StartNew(); Snapped = (@($gl.X).Count + @($gl.Y).Count -gt 0) }
      if ($d.Mode -eq 'edge') { $script:bounce.Id = '' }   # resizing: no bounce, only the tick
      if ($d.Mode -eq 'edge' -and $script:bounce.Snapped) { $script:bounce.Id = $d.Hit.Tile.id; $script:bounce.NoMove = $true }
      $bounceTimer.Start()
    }
    Update-Side; $canvas.Invalidate()
  } })
$script:bounce = $null
$bounceTimer = New-Object Windows.Forms.Timer; $bounceTimer.Interval = 15
$bounceTimer.Add_Tick({ if (-not $script:bounce -or $script:bounce.Clock.ElapsedMilliseconds -gt 720) { $bounceTimer.Stop(); $script:bounce = $null }; $canvas.Invalidate() })
# the edges of a tile that line up with another tile's edges (with $edges: the screen's edges count too)
function Get-AlignedGuides($t, [bool]$edges = $false) {
  $xs = @(); $ys = @(); $eps = 0.0005
  $others = @(Get-Tiles | Where-Object { $_.monitor -eq $t.monitor -and $_.id -ne $t.id })
  $gx = @(); $gy = @(); foreach ($o in $others) { $gx += [double]$o.rect.x; $gx += (Get-Right $o.rect); $gy += [double]$o.rect.y; $gy += (Get-Bottom $o.rect) }
  if ($edges) { $gx += 0.0; $gx += 1.0; $gy += 0.0; $gy += 1.0 }
  foreach ($v in @([double]$t.rect.x, (Get-Right $t.rect))) { foreach ($q in $gx) { if ([Math]::Abs($v - $q) -lt $eps -and ($edges -or ($v -gt $eps -and $v -lt 1 - $eps))) { $xs += $q; break } } }
  foreach ($v in @([double]$t.rect.y, (Get-Bottom $t.rect))) { foreach ($q in $gy) { if ([Math]::Abs($v - $q) -lt $eps -and ($edges -or ($v -gt $eps -and $v -lt 1 - $eps))) { $ys += $q; break } } }
  return @{ X = $xs; Y = $ys }
}
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
    $iE = $m.Items.Add($(if ($t.exit -eq 'close') { 'When the routine exits: Closes (click for Stays open)' } else { 'When the routine exits: Stays open (click for Closes)' })); $iE.Tag = $t.id
    $iE.Add_Click({ param($s, $e) Save-UndoPoint; $tt = Get-Tile $s.Tag; $tt.exit = $(if ($tt.exit -eq 'close') { 'leave' } else { 'close' }); Set-Dirty; Update-Side; $canvas.Invalidate() })
  }
  # quick sizes: one click puts the tile on a common part of its screen (never smaller than the app allows)
  if ($t.kind -ne 'league' -and -not ($t.kind -eq 'spotify' -and $t.mini)) {
    $qs = New-Object Windows.Forms.ToolStripMenuItem('Quick size')
    $qs.DropDown.BackColor = $script:C.Panel; $qs.DropDown.ForeColor = $script:C.Text; try { $qs.DropDown.ShowImageMargin = $false } catch {}
    $third = 1.0 / 3
    $sizes = [ordered]@{
      'Full screen' = @(0, 0, 1, 1); '-1' = $null
      'Left half' = @(0, 0, 0.5, 1); 'Right half' = @(0.5, 0, 0.5, 1); 'Top half' = @(0, 0, 1, 0.5); 'Bottom half' = @(0, 0.5, 1, 0.5); '-2' = $null
      'Left third' = @(0, 0, $third, 1); 'Middle third' = @($third, 0, $third, 1); 'Right third' = @((2 * $third), 0, $third, 1)
      'Top third' = @(0, 0, 1, $third); 'Middle third (across)' = @(0, $third, 1, $third); 'Bottom third' = @(0, (2 * $third), 1, $third); '-3' = $null
      'Top-left quarter' = @(0, 0, 0.5, 0.5); 'Top-right quarter' = @(0.5, 0, 0.5, 0.5); 'Bottom-left quarter' = @(0, 0.5, 0.5, 0.5); 'Bottom-right quarter' = @(0.5, 0.5, 0.5, 0.5)
    }
    foreach ($k in $sizes.Keys) {
      if ($k -like '-*') { [void]$qs.DropDownItems.Add('-'); continue }
      $it = New-Object Windows.Forms.ToolStripMenuItem($k); $it.Tag = @{ Id = $t.id; R = $sizes[$k] }
      $it.Add_Click({ param($s, $e)
        $tt = Get-Tile $s.Tag.Id; if (-not $tt) { return }
        Save-UndoPoint
        $q = $s.Tag.R; $r = @{ x = [double]$q[0]; y = [double]$q[1]; w = [double]$q[2]; h = [double]$q[3] }
        $v = Get-ViewFor $tt.monitor; if ($v) { $r = Set-MinSize $r (Get-MinFrac $tt $v.Area) }
        $tt.rect = $r; Set-Dirty; Update-Side; $canvas.Invalidate() })
      [void]$qs.DropDownItems.Add($it)
    }
    [void]$m.Items.Add($qs)
  }
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
function Set-AutoStart([string]$v) {
  $script:R | Add-Member -NotePropertyName autoStart -NotePropertyValue ("$v".Trim() -replace '(?i)\.exe$', '') -Force
  Set-Dirty; Update-Side
}
# pick the program that starts this routine: off, one of the programs that are open now, or a typed name
function Show-AutoStartMenu($btn) {
  $m = New-Object Windows.Forms.ContextMenuStrip
  $m.BackColor = $script:C.Panel; $m.ForeColor = $script:C.Text; $m.ShowImageMargin = $false
  $cur = "$($script:R.autoStart)".Trim()
  $off = $m.Items.Add($(if (-not $cur) { [string][char]0x2713 + '  Off' } else { '     Off' })); $off.Add_Click({ Set-AutoStart '' })
  [void]$m.Items.Add('-')
  $skip = @('powershell', 'pwsh', 'explorer', 'Mise', 'TextInputHost', 'ShellExperienceHost', 'SearchHost', 'StartMenuExperienceHost', 'LockApp', 'ApplicationFrameHost', 'SystemSettings')
  $names = @(); try { $names = @(Get-WinSnapshot | ForEach-Object { Get-ProcName $_.Pid } | Where-Object { $_ -and $skip -notcontains $_ } | Sort-Object -Unique) } catch {}
  if ($cur -and $names -notcontains $cur) { $names = @($cur) + $names }
  foreach ($n in @($names | Select-Object -First 24)) {
    $it = $m.Items.Add($(if ($n -eq $cur) { [string][char]0x2713 + '  ' + $n } else { '     ' + $n })); $it.Tag = $n
    $it.Add_Click({ param($s, $e) Set-AutoStart "$($s.Tag)" })
  }
  [void]$m.Items.Add('-')
  $ty = $m.Items.Add('     Type a name...')
  $ty.Add_Click({ $v = Show-MiseInput 'Start with a program' 'Program name as Task Manager shows it, without .exe (for example Wow)' "$($script:R.autoStart)"; if ($null -ne $v) { Set-AutoStart $v } })
  $m.Show($btn, (New-Object Drawing.Point(($btn.Width - 200), $btn.Height)))
}
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
  if ($script:hkCapture) { $null = Add-SideLabel 'Press the keys now. Backspace clears, Esc cancels.' $script:fSmall $script:C.Muted 40 }
  elseif ($script:hkMsg) { $null = Add-SideLabel $script:hkMsg $script:fSmall $script:C.Muted 40 }
  $bAuto = New-Btn 'Start with a program' 0 0 310 38 'setting'; $bAuto.Chip = $(if ("$($script:R.autoStart)".Trim()) { "$($script:R.autoStart)".Trim() } else { 'off' })
  $bAuto.Add_Click({ param($s, $e) Show-AutoStartMenu $s })
  $tip.SetToolTip($bAuto, 'The routine starts by itself when this program opens (for example your game). Open the program first to pick it from the list.')
  Add-Side $bAuto 44
  $bCard = New-Btn 'Pop-up spot on the map' 0 0 310 38 'setting'; $bCard.IsSwitch = $true; $bCard.On = [bool]$script:R.card
  $bCard.Add_Click({
    Save-UndoPoint
    if ($script:R.card) { $script:R.card = $null; if ($script:sel -eq 'card') { $script:sel = '' } }
    else { $v = $script:view | Where-Object { $_.Live.Primary } | Select-Object -First 1; if (-not $v) { $v = $script:view[0] }; if ($v) { $script:R.card = [pscustomobject]@{ monitor = $v.Live.id; rect = @{ x = 16.0 / $v.Area.W; y = 16.0 / $v.Area.H; w = 320.0 / $v.Area.W; h = 96.0 / $v.Area.H } }; $script:sel = 'card' } }
    Set-Dirty; Update-Side; $canvas.Invalidate()
  })
  $tip.SetToolTip($bCard, 'On: a small tile on the map marks where the progress pop-up shows while this routine runs. Off: the corner from Settings.')
  Add-Side $bCard 44

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
              # the mini player's real limits: read from it when it is open, else the sizes Spotify allowed before
              $tt | Add-Member -NotePropertyName maxW -NotePropertyValue 0 -Force; $tt | Add-Member -NotePropertyName maxH -NotePropertyValue 0 -Force
              $tt.minW = 242; $tt.minH = 53
              try {
                $mw = Get-WinSnapshot | Where-Object { (Get-ProcName $_.Pid) -eq 'Spotify' -and [MiseWin]::IsTopmost($_.H) } | Select-Object -First 1
                if ($mw) { $mn = [MiseWin2]::ProbeMinSize($mw.H); $mx = [MiseWin2]::ProbeMaxSize($mw.H); if ($mn) { $tt.minW = $mn[0]; $tt.minH = $mn[1] }; if ($mx) { $tt.maxW = $mx[0]; $tt.maxH = $mx[1] } }
              } catch {}
              if ($vv) { $tt.rect.w = [Math]::Min(1.0, 360.0 / $vv.Area.W); $tt.rect.h = [Math]::Min(1.0, 100.0 / $vv.Area.H); if ($tt.rect.x + $tt.rect.w -gt 1) { $tt.rect.x = 1 - $tt.rect.w }; if ($tt.rect.y + $tt.rect.h -gt 1) { $tt.rect.y = 1 - $tt.rect.h } }
            } else { $tt.minW = 800; $tt.minH = 600; $tt | Add-Member -NotePropertyName maxW -NotePropertyValue 0 -Force; $tt | Add-Member -NotePropertyName maxH -NotePropertyValue 0 -Force }
          } catch { Write-Log "mini toggle failed: $($_.Exception.Message)" }
          $s.Invalidate(); Set-Dirty; Update-Side; $canvas.Invalidate() })
        Add-Side $bm 44
        $null = Add-SideLabel 'Turning it on shrinks the tile to the mini player. Test run opens it.' $script:fSmall $script:C.Muted 40
      }
      'stream' {
        $null = Add-SideLabel "Friend's Discord display name" $script:fSmall $script:C.Muted 20
        $sb = New-MiseText 0 0 310 "$($t.streamer)"; $sb.Box.Tag = $t.id
        $sb.Box.Add_TextChanged({ param($s, $e) $tt = Get-Tile $s.Tag; if ($tt -and "$($tt.streamer)" -ne $s.Text.Trim()) { $tt | Add-Member -NotePropertyName streamer -NotePropertyValue $s.Text.Trim() -Force; Set-Dirty } })
        Add-Side $sb.Panel 38
        $bMu = New-Btn 'Open with sound off' 0 0 310 38 'setting'; $bMu.IsSwitch = $true; $bMu.On = [bool]$t.mute; $bMu.Tag = $t.id
        $bMu.Add_Click({ param($s, $e) $tt = Get-Tile $s.Tag; if ($tt) { $tt | Add-Member -NotePropertyName mute -NotePropertyValue (-not [bool]$tt.mute) -Force; $s.On = [bool]$tt.mute; $s.Invalidate(); Set-Dirty } })
        Add-Side $bMu 44
        $null = Add-SideLabel 'Drag the tile to choose where the stream popout goes; drag an edge or corner to size it. While the routine runs (a League routine: once League is open) and you are in a voice call, Mise opens this friend''s stream when they go live, pops it out and puts it here. It never joins a channel for you. Saved changes move an open popout right away.' $script:fSmall $script:C.Muted 112
      }
      'league' { $null = Add-SideLabel 'The League client keeps the size set in League. Drag it to choose where it opens.' $script:fSmall $script:C.Muted 40 }
      default { $null = Add-SideLabel $(if ($t.exe) { $t.exe } elseif ($t.appid) { $t.appid } else { 'Learned on the first run' }) $script:fSmall $script:C.Muted 36 }
    }
    if ($t.minW -or $t.minH) { $null = Add-SideLabel "Smallest size the app allows: $($t.minW) x $($t.minH) px" $script:fSmall $script:C.Muted 24 }
    if ($t.maxW -or $t.maxH) { $null = Add-SideLabel "Largest size it allows: $($t.maxW) x $($t.maxH) px" $script:fSmall $script:C.Muted 24 }
    if ($t.kind -ne 'league' -and $t.kind -ne 'ugg') {
      $be = New-Btn 'When the routine exits' 0 0 310 38 'setting'; $be.Seg = 'Stays open|Closes'; $be.On = ($t.exit -eq 'close'); $be.Tag = $t.id
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
  if (-not $items.Count) { $null = Show-MiseAsk 'Copy my screen' 'No open windows were found on your named screens. Open your apps, then try again.' 'OK' ''; return }
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

# ======================= + Add app or page =======================
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
  $f = New-MiseDialog '+ Add app or page' $W 560
  $q = New-MiseText $M 54 $cw ''; $f.Controls.Add($q.Panel)
  $lst = New-Object Windows.Forms.ListBox; $lst.Location = New-Object Drawing.Point($M, 96); $lst.Size = New-Object Drawing.Size($cw, 380)
  $lst.BackColor = $script:C.Panel; $lst.ForeColor = $script:C.Text; $lst.BorderStyle = 'None'; $lst.Font = $script:fStatus; $lst.IntegralHeight = $false
  $f.Controls.Add($lst)
  $script:addApps = @(Get-InstalledApps)
  $fill = { $lst.Items.Clear(); [void]$lst.Items.Add('Web page'); [void]$lst.Items.Add("A friend's Discord stream"); foreach ($a in $script:addApps) { if (-not $q.Box.Text -or $a.Name -like "*$($q.Box.Text)*") { [void]$lst.Items.Add($a.Name) } } }
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
  elseif ($script:addPick -eq "A friend's Discord stream") {
    $form.TopMost = $false
    $who = Show-MiseInput 'Discord stream' "Your friend's Discord display name (as it shows in your voice channel)" ''
    if (-not $who) { return }
    $t.kind = 'stream'; $t.name = "$who's stream"; $t.exit = 'close'; $t.minW = 320; $t.minH = 180
    $t | Add-Member -NotePropertyName streamer -NotePropertyValue $who -Force
  }
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
    elseif ($t.kind -eq 'stream') { $script:marks[$t.id] = 'When live' }
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
$bSave.Add_Click({ if ($script:R -and (Save-Routine)) { $script:helper = 'Saved'; $canvas.Invalidate() } })
$bSaveC.Add_Click({ if ($script:R -and (Save-Routine)) { $form.Close() } })
$bUndo.Add_Click({ Restore-Undo })
$bCopy.Add_Click({ if ($script:R) { Show-CaptureDialog } })
$bAdd.Add_Click({ if ($script:R) { Show-AddDialog } })
$bNewR.Add_Click({ if (Confirm-Leave) { Set-Routine (New-BlankRoutine) } })
function Remove-RoutineEntry([string]$id) {
  $nm = "$((@($script:cfg.routines) + @($script:R) | Where-Object { $_ -and $_.id -eq $id } | Select-Object -First 1).name)"
  if ((Show-MiseAsk 'Delete routine' "Delete '$nm'? This can't be undone." 'Delete' 'Keep it') -ne 'yes') { return }
  $cf = Get-MiseConfig; $cf.routines = @($cf.routines | Where-Object { $_.id -ne $id }); Save-MiseConfig $cf; $script:cfg = $cf
  if ($script:R -and $script:R.id -eq $id) {
    $script:dirty = $false
    if (@($cf.routines).Count) { Set-Routine (Copy-Routine @($cf.routines)[0]) } else { Set-Routine (New-BlankRoutine) }
  } else { Update-List }
}
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
