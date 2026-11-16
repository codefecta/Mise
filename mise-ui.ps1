# Mise (shared edition) - UI helpers: monitor naming, first run, account chooser, dialogs, settings, setup, tips, tours.
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'mise-core.ps1')
. (Join-Path $script:MiseDir 'mise-layout.ps1'); . (Join-Path $script:MiseDir 'mise-engine.ps1')
Add-Type -AssemblyName System.Windows.Forms, System.Drawing, Microsoft.VisualBasic
[System.Windows.Forms.Application]::EnableVisualStyles()
$script:Icon = Join-Path $script:MiseDir 'mise.ico'
. (Join-Path $script:MiseDir 'mise-look.ps1')

function New-UiForm($title, $w, $h) {
  $f = New-Object Windows.Forms.Form
  $f.Text = $title; $f.ClientSize = New-Object Drawing.Size($w, $h); $f.StartPosition = 'CenterScreen'
  $f.BackColor = $script:C.Bg; $f.ForeColor = $script:C.Text; $f.Font = $script:fNorm; $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false
  if (Test-Path $script:Icon) { try { $f.Icon = New-Object Drawing.Icon($script:Icon) } catch {} }
  Set-MiseBackdrop $f; Set-MiseAppId $f
  return $f
}
function New-UiLabel($text, $x, $y, $w = 200, $h = 20, $muted = $false) {
  $l = New-Object Windows.Forms.Label; $l.Text = $text; $l.Location = New-Object Drawing.Point($x, $y); $l.Size = New-Object Drawing.Size($w, $h)
  $l.ForeColor = $(if ($muted) { $script:C.Muted } else { $script:C.Text }); $l.BackColor = [Drawing.Color]::Transparent; return $l
}
function New-UiButton($text, $x, $y, $w = 90, $h = 30, [bool]$accent = $false) {
  return (New-Btn $text $x $y $w $h $(if ($accent) { 'primary' } else { 'tool' }))
}
function New-UiBox($x, $y, $w, $h = 24) {
  $t = New-Object Windows.Forms.TextBox; $t.Location = New-Object Drawing.Point($x, $y); $t.Size = New-Object Drawing.Size($w, $h)
  $t.BackColor = $script:C.Panel; $t.ForeColor = $script:C.Text; $t.BorderStyle = 'FixedSingle'; return $t
}
function New-UiCombo($x, $y, $w) {
  $c = New-Object Windows.Forms.ComboBox; $c.Location = New-Object Drawing.Point($x, $y); $c.Size = New-Object Drawing.Size($w, 24)
  $c.DropDownStyle = 'DropDownList'; $c.FlatStyle = 'Flat'; $c.BackColor = $script:C.Panel; $c.ForeColor = $script:C.Text
  # drawn by Mise so the closed box matches the dark theme (Windows paints it white otherwise)
  $c.DrawMode = 'OwnerDrawFixed'; $c.ItemHeight = 20
  $c.Add_DrawItem({ param($s, $e)
    if ($e.Index -lt 0) { return }
    $sel = (($e.State -band [Windows.Forms.DrawItemState]::Selected) -ne 0) -and (($e.State -band [Windows.Forms.DrawItemState]::ComboBoxEdit) -eq 0)
    $bg = New-Object Drawing.SolidBrush($(if ($sel) { $script:C.Accent } else { $script:C.Panel })); $e.Graphics.FillRectangle($bg, $e.Bounds); $bg.Dispose()
    $fg = New-Object Drawing.SolidBrush($(if ($sel) { $script:C.Bg } else { $script:C.Text }))
    $e.Graphics.DrawString("$($s.Items[$e.Index])", $s.Font, $fg, ($e.Bounds.X + 4), ($e.Bounds.Y + 2)); $fg.Dispose() })
  return $c
}
function New-UiList($x, $y, $w, $h) {
  $l = New-Object Windows.Forms.ListBox; $l.Location = New-Object Drawing.Point($x, $y); $l.Size = New-Object Drawing.Size($w, $h)
  $l.BackColor = $script:C.Panel; $l.ForeColor = $script:C.Text; $l.BorderStyle = 'FixedSingle'; $l.IntegralHeight = $false; return $l
}

function Get-MonitorName($cfg, $id) { $m = $cfg.monitors | Where-Object { $_.id -eq $id } | Select-Object -First 1; if ($m) { $m.name } else { 'main screen' } }

# ---------- lobbies ----------
$script:QueueList = @(@{ Id = 2400; Name = 'ARAM Mayhem' }, @{ Id = 450; Name = 'ARAM' }, @{ Id = 400; Name = 'Draft' }, @{ Id = 420; Name = 'Ranked Solo/Duo' }, @{ Id = 440; Name = 'Ranked Flex' }, @{ Id = 480; Name = 'Swiftplay' }, @{ Id = 1740; Name = 'Arena' }, @{ Id = 4320; Name = 'Jade (event)' }, @{ Id = 0; Name = 'No lobby' })

function Get-RiotAccounts {
  $d = Join-Path $env:USERPROFILE 'LeagueAccounts'
  if (-not (Test-Path $d)) { return @() }
  $all = @(Get-ChildItem -LiteralPath $d -Filter *.yaml | Where-Object { $_.BaseName -notlike '_*' } | Sort-Object CreationTime, Name | ForEach-Object { $_.BaseName })
  # the order the user dragged them into comes first; accounts added later follow in the order they were saved
  $ord = @(); try { $ord = @((Get-MiseSetting (Get-MiseConfig) 'accountOrder') | Where-Object { $_ } | ForEach-Object { "$_" }) } catch {}
  if (-not $ord.Count) { return $all }
  return @(@($ord | Where-Object { $all -contains $_ }) + @($all | Where-Object { $ord -notcontains $_ }))
}

# ---------- monitor wizard: flash a number on every screen, the user names each one ----------
# ---------- screens get their names by themselves: where they sit and what model they are ----------
# e.g. "Main - MAG 274Q X24", "Left - LG ULTRAGEAR". The model comes from the screen itself (WMI); without it, the place only.
function Get-ScreenModels {
  $map = @{}
  try {
    foreach ($m in @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction Stop)) {
      $code = ("$($m.InstanceName)" -split '\\')[1]
      $n = (@($m.UserFriendlyName) | Where-Object { $_ -gt 0 } | ForEach-Object { [char]$_ }) -join ''
      if ($code -and $n.Trim()) { $map[$code.ToUpper()] = $n.Trim() }
    }
  } catch {}
  return $map
}
function Get-AutoScreenName($s, $screens, $models, $keys) {
  $prim = $screens | Where-Object Primary | Select-Object -First 1
  $place = 'Main'
  if (-not $s.Primary -and $prim) {
    $cx = $s.Bounds.X + $s.Bounds.Width / 2; $cy = $s.Bounds.Y + $s.Bounds.Height / 2
    $px = $prim.Bounds.X + $prim.Bounds.Width / 2; $py = $prim.Bounds.Y + $prim.Bounds.Height / 2
    if ([Math]::Abs($cx - $px) -ge [Math]::Abs($cy - $py)) { $place = $(if ($cx -lt $px) { 'Left' } else { 'Right' }) } else { $place = $(if ($cy -lt $py) { 'Top' } else { 'Bottom' }) }
    if ($s.Vertical) { $place += ' vertical' }
  }
  $model = ''; $hw = "$($keys[$s.DeviceName])"; if ($hw) { $model = "$($models[(($hw -split '#')[0]).ToUpper()])" }
  if ($model) { return "$place - $model" }
  return "$place screen"
}
# every connected screen the settings do not know yet is added with an automatic name; known screens keep their names
function Update-AutoMonitors($cfg) {
  $screens = @(Get-Screens); $keys = Get-MonitorKeys; $models = $null; $added = 0
  $list = New-Object Collections.ArrayList; foreach ($m in @($cfg.monitors)) { [void]$list.Add($m) }
  foreach ($s in $screens) {
    $hw = "$($keys[$s.DeviceName])"
    $known = $list | Where-Object { ($hw -and $_.hw -eq $hw) -or (-not $_.hw -and $_.deviceName -eq $s.DeviceName -and $_.size -eq $s.Size) } | Select-Object -First 1
    if ($known) { continue }
    if ($null -eq $models) { $models = Get-ScreenModels }
    $n = Get-AutoScreenName $s $screens $models $keys
    $base = $n; $k = 2; while (@($list | Where-Object { $_.name -eq $n }).Count) { $n = "$base $k"; $k++ }
    [void]$list.Add([pscustomobject]@{ id = New-Id; name = $n; deviceName = $s.DeviceName; hw = $hw; size = $s.Size; vertical = $s.Vertical; primary = $s.Primary })
    $added++
  }
  if ($added) { $cfg.monitors = @($list); Write-Log "screens: $added new screen(s) named automatically" }
  return @{ Cfg = $cfg; Added = $added }
}
function Show-MonitorWizard($cfg) {
  # each screen in turn: a light tint with a copper frame and its number, and a Mise card on it to type the name
  $screens = Get-Screens
  $keys = Get-MonitorKeys
  $found = @(); $script:wizModels = $null
  foreach ($s in $screens) {
    $o = New-Object Windows.Forms.Form
    $o.FormBorderStyle = 'None'; $o.StartPosition = 'Manual'; $o.Bounds = $s.Bounds; $o.TopMost = $true; $o.ShowInTaskbar = $false
    $o.BackColor = [Drawing.Color]::FromArgb(14, 14, 16); $o.Opacity = 0.32
    $o.Add_Paint({ param($sd, $e) $pen = New-Object Drawing.Pen($script:C.Accent, 14); $e.Graphics.DrawRectangle($pen, 7, 7, $sd.Width - 14, $sd.Height - 14); $pen.Dispose() })
    $o.Show(); $o.Refresh()
    if ($null -eq $script:wizModels) { $script:wizModels = Get-ScreenModels }
    $def = Get-AutoScreenName $s $screens $script:wizModels $keys
    $hw = "$($keys[$s.DeviceName])"
    $prev = $cfg.monitors | Where-Object { ($hw -and $_.hw -eq $hw) -or ($_.deviceName -eq $s.DeviceName -and $_.size -eq $s.Size) } | Select-Object -First 1
    if ($prev) { $def = $prev.name }
    $nm = Read-ScreenName $s $def
    $o.Close(); $o.Dispose()
    $found += [pscustomobject]@{ id = $(if ($prev) { $prev.id } else { New-Id }); name = $nm; deviceName = $s.DeviceName; hw = $hw; size = $s.Size; vertical = $s.Vertical; primary = $s.Primary }
  }
  $cfg.monitors = $found
  return $cfg
}
# the naming card, centred on the screen it names; Enter or OK keeps the name, an empty field keeps the suggestion
function Read-ScreenName($s, [string]$def) {
  $W = 380; $M = 18; $cw = $W - 2 * $M
  $f = New-MiseDialog 'Name this screen' $W 200
  $f.StartPosition = 'Manual'
  $f.Location = New-Object Drawing.Point(($s.Bounds.X + [int](($s.Bounds.Width - $W) / 2)), ($s.Bounds.Y + [int](($s.Bounds.Height - 200) / 2)))
  $info = "Screen $($s.Index)  -  $($s.Size)$(if ($s.Primary) { ', main' })$(if ($s.Vertical) { ', vertical' })"
  $f.Controls.Add((New-Label $info $script:fSmall $script:C.Muted $M 54 $cw 20))
  $tx = New-MiseText $M 82 $cw $def; $f.Controls.Add($tx.Panel)
  $ok = New-Btn 'OK' ($W - $M - 110) 130 110 34 'primary'; $f.Controls.Add($ok)
  $script:screenName = $def
  $ok.Add_Click({ param($sd, $e) $script:screenName = $tx.Box.Text; $sd.FindForm().Close() })
  $tx.Box.Add_KeyDown({ param($sd, $e) if ($e.KeyCode -eq 'Return') { $e.SuppressKeyPress = $true; $script:screenName = $tx.Box.Text; $sd.FindForm().Close() } })
  $f.Add_Shown({ param($sd, $e) $tx.Box.Focus(); $tx.Box.SelectAll() })
  $f.ClientSize = New-Object Drawing.Size($W, 180)
  [void]$f.ShowDialog()
  $n = "$($script:screenName)".Trim()
  if (-not $n) { $n = $def }
  return $n
}


# ---------- which account? (routines whose League step says "ask me") ----------
function Show-AccountChooser {
  $accts = Get-RiotAccounts
  if ($accts.Count -eq 0) { [Windows.Forms.MessageBox]::Show("No League accounts are saved yet.`nPress + Account under Tools to add one.", 'Mise') | Out-Null; return $null }
  # a Mise-styled picker that always sits on top (it used to open behind the Mise window); Esc or x cancels
  $W = 340; $M = 18
  $f = New-MiseDialog 'Which account?' $W 200
  $y = 56; $script:chosen = $null; $i = 0
  foreach ($a in $accts) {
    $i++
    $parts = $a.Trim() -split '\s+'; $nick = if ($parts.Count -gt 1) { ($parts[0..($parts.Count - 2)] -join ' ') } else { $a }
    $b = New-Btn $nick $M $y ($W - 2 * $M) 44 'row' $script:fBig; $b.Tag = $a; $b.Num = "$i"; $b.Chip = $parts[-1].ToUpper()
    $b.Add_Click({ param($s, $e) $script:chosen = $s.Tag; $s.FindForm().Close() }); $f.Controls.Add($b); $y += 50
  }
  $f.Add_KeyDown({ param($s, $e) $k = "$($e.KeyCode)"; if ($k -match '^(D|NumPad)([1-9])$') { $n = [int]$Matches[2] - 1; $bs = @($s.Controls | Where-Object { $_ -is [MiseBtn] -and $_.Kind -eq 'row' }); if ($n -lt $bs.Count) { $script:chosen = $bs[$n].Tag; $s.Close() } } })
  $f.ClientSize = New-Object Drawing.Size($W, ($y + 12))
  $owners = @([Windows.Forms.Application]::OpenForms | Where-Object { $_.Visible -and $_.TopMost -and $_ -ne $f })
  foreach ($o in $owners) { $o.TopMost = $false }
  [void]$f.ShowDialog()
  foreach ($o in $owners) { try { $o.TopMost = $true } catch {} }
  return $script:chosen
}

# ---------- Mise-styled dialog: borderless, title + close, drag anywhere ----------
function New-MiseDialog([string]$title, [int]$w, [int]$h) {
  $f = New-Object Windows.Forms.Form
  $f.Text = $title; $f.StartPosition = 'CenterScreen'; $f.ClientSize = New-Object Drawing.Size($w, $h); $f.TopMost = $true; $f.ShowInTaskbar = $true; $f.KeyPreview = $true
  if (Test-Path $script:Icon) { try { $f.Icon = New-Object Drawing.Icon($script:Icon) } catch {} }
  Set-MiseFrame $f
  # same header as the Mise window: the mark, then the title in the accent colour
  $lg = New-Logo 18 14; Add-DragHandle $lg $f; $f.Controls.Add($lg)
  $t = New-Label $title (New-Object Drawing.Font('Segoe UI Semibold', 14)) $script:C.Accent 58 15 ($w - 110) 28; Add-DragHandle $t $f; $f.Controls.Add($t)
  $x = New-Btn '' ($w - 50) 13 32 32 'ghost'; $x.Glyph = 'close'; $x.Add_Click({ param($s, $e) $s.FindForm().Close() }); $f.Controls.Add($x)
  $f.Add_KeyDown({ param($s, $e) if ($e.KeyCode -eq 'Escape') { $s.Close() } })
  $f.Add_Shown({ param($s, $e) $s.Activate(); Start-OpenAnimation $s })
  return $f
}
# a text field that matches the theme: panel colour, thin line, no Windows 3D border
function New-MiseText($x, $y, $w, [string]$text = '') {
  $p = New-Object Windows.Forms.Panel; $p.Location = New-Object Drawing.Point($x, $y); $p.Size = New-Object Drawing.Size($w, 32); $p.BackColor = $script:C.Panel
  $p.Padding = New-Object Windows.Forms.Padding(10, 7, 10, 4)
  $p.Add_Paint({ param($s, $e) $pen = New-Object Drawing.Pen($script:C.Line, 1); $e.Graphics.DrawRectangle($pen, 0, 0, $s.Width - 1, $s.Height - 1); $pen.Dispose() })
  $b = New-Object Windows.Forms.TextBox; $b.BorderStyle = 'None'; $b.BackColor = $script:C.Panel; $b.ForeColor = $script:C.Text; $b.Font = $script:fStatus; $b.Dock = 'Fill'; $b.Text = $text
  $p.Controls.Add($b)
  return @{ Panel = $p; Box = $b }
}
function New-MiseCheck($text, $x, $y, $w, [bool]$on) {
  $c = New-Object Windows.Forms.CheckBox; $c.Text = $text; $c.Checked = $on; $c.Location = New-Object Drawing.Point($x, $y); $c.Size = New-Object Drawing.Size($w, 24)
  $c.ForeColor = $script:C.Text; $c.BackColor = $script:C.Bg; $c.Font = $script:fSmall; $c.FlatStyle = 'Flat'; return $c
}

# ---------- settings: accent colour, animations, pop-up corner, where the Mise window opens, updates ----------
$script:CornerNames = [ordered]@{ 'bottom-left' = 'Bottom left'; 'bottom-right' = 'Bottom right'; 'top-left' = 'Top left'; 'top-right' = 'Top right' }
$script:HomePosNames = [ordered]@{ 'remember' = 'Where I last dragged it'; 'center' = 'Centre'; 'top-left' = 'Top left'; 'top-center' = 'Top centre'; 'top-right' = 'Top right'; 'bottom-left' = 'Bottom left'; 'bottom-right' = 'Bottom right' }
function Get-NextKey($dict, $cur) { $keys = @($dict.Keys); $i = [Array]::IndexOf($keys, "$cur"); return $keys[($i + 1) % $keys.Count] }
function Show-MiseSettings {
  $script:settingsAction = ''
  $cfg = Get-MiseConfig
  $W = 380; $M = 18
  $f = New-MiseDialog 'Settings' $W 520
  $y = 56
  # the look: six small previews of each backdrop, the chosen one ringed; the logo stays copper in all of them
  $f.Controls.Add((New-Label 'LOOK' $script:fTiny $script:C.Muted $M $y 200 14)); $y += 20
  $curT = Get-MiseTheme $cfg; $lk = @(); $x = $M; $tw = [int](($W - 2 * $M - 5 * 6) / 6)
  foreach ($k in $script:Themes.Keys) {
    $p = New-Object Windows.Forms.Panel; $p.Size = New-Object Drawing.Size($tw, 58); $p.Location = New-Object Drawing.Point($x, $y); $p.Cursor = 'Hand'; $p.BackColor = $script:C.Bg
    $prev = [MiseGlass]::Render($k, ($tw - 6), 34)
    if ($k -eq 'ember') { $gg = [Drawing.Graphics]::FromImage($prev); $gg.Clear([Drawing.Color]::FromArgb(23, 23, 26)); $gg.Dispose() }
    $p.Tag = @{ Key = $k; Sel = ($k -eq $curT); Img = $prev; Name = $script:Themes[$k].Name; Short = $(if ($k -eq 'midnight') { 'Midnight' } else { $script:Themes[$k].Name }); Line = (ConvertTo-Color $script:Themes[$k].Line) }
    [Windows.Forms.Control].GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic,Instance').SetValue($p, $true, $null)
    $p.Add_Paint({ param($s, $e)
      $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'ClearTypeGridFit'; $t = $s.Tag
      $r = New-Object Drawing.Rectangle(3, 3, ($s.Width - 6), 34)
      $g.DrawImage($t.Img, $r)
      # a tiny frosted row and the copper dot: how the look feels
      $rb = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb($(if ($t.Key -eq 'ember') { 255 } else { 30 }), $(if ($t.Key -eq 'ember') { 33 } else { 255 }), $(if ($t.Key -eq 'ember') { 33 } else { 255 }), $(if ($t.Key -eq 'ember') { 37 } else { 255 })))
      $g.FillRectangle($rb, 9, 21, ($s.Width - 18), 9); $rb.Dispose()
      $cb = New-Object Drawing.SolidBrush($script:LogoCopper); $g.FillEllipse($cb, 9, 9, 7, 7); $cb.Dispose()
      $pen = New-Object Drawing.Pen($(if ($t.Sel) { $script:C.Accent } else { $t.Line }), $(if ($t.Sel) { 2 } else { 1 })); $g.DrawRectangle($pen, 2, 2, ($s.Width - 5), 35); $pen.Dispose()
      $sf = New-Object Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.Trimming = 'EllipsisCharacter'; $sf.FormatFlags = 'NoWrap'
      $tb = New-Object Drawing.SolidBrush($(if ($t.Sel) { $script:C.Text } else { $script:C.Muted })); $fl = $script:fTiny; $mw = $g.MeasureString($t.Short, $fl).Width; if ($mw -gt $s.Width - 2) { $fl = New-Object Drawing.Font('Segoe UI Semibold', ([single][Math]::Max(5.5, 8 * ($s.Width - 2) / $mw))) }
      $g.DrawString($t.Short, $fl, $tb, (New-Object Drawing.RectangleF(0, 41, $s.Width, 16)), $sf); $tb.Dispose(); $sf.Dispose()
    })
    $p.Add_Click({ param($s, $e) foreach ($q in $script:lookTiles) { $q.Tag.Sel = $false; $q.Invalidate() }; $s.Tag.Sel = $true; $s.Invalidate(); $null = Set-MiseSetting 'theme' $s.Tag.Key })
    $tipL = New-Object Windows.Forms.ToolTip; $tipL.SetToolTip($p, "$($script:Themes[$k].Name) - applies when this window closes")
    $f.Controls.Add($p); $lk += $p; $x += $tw + 6
  }
  $script:lookTiles = $lk
  $y += 66
  $f.Controls.Add((New-Label 'ACCENT COLOUR' $script:fTiny $script:C.Muted $M $y 200 14)); $y += 20
  $sw = @(); $x = $M; $cur = "$(Get-MiseSetting $cfg 'accent')".ToUpper()
  foreach ($k in $script:AccentChoices.Keys) {
    $hex = $script:AccentChoices[$k]
    $p = New-Object Windows.Forms.Panel; $p.Size = New-Object Drawing.Size(32, 32); $p.Location = New-Object Drawing.Point($x, $y); $p.Cursor = 'Hand'
    $p.BackColor = $script:C.Bg; $p.Tag = @{ Hex = $hex; Sel = ($hex.ToUpper() -eq $cur); Col = (ConvertTo-Color $hex) }
    $tip = New-Object Windows.Forms.ToolTip; $tip.SetToolTip($p, $k)
    # round colour dots; the chosen one gets a thin ring
    $p.Add_Paint({ param($s, $e)
      $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'
      $br = New-Object Drawing.SolidBrush($s.Tag.Col); $g.FillEllipse($br, 6, 6, 20, 20); $br.Dispose()
      if ($s.Tag.Sel) { $pen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(238, 237, 234), 1.6); $g.DrawEllipse($pen, 2, 2, 27, 27); $pen.Dispose() }
    })
    $p.Add_Click({ param($s, $e) foreach ($q in $script:swatches) { $q.Tag.Sel = $false; $q.Invalidate() }; $s.Tag.Sel = $true; $s.Invalidate(); $null = Set-MiseSetting 'accent' $s.Tag.Hex })
    $f.Controls.Add($p); $sw += $p; $x += 40
  }
  $script:swatches = $sw
  $y += 50
  $f.Controls.Add((New-Label 'BEHAVIOUR' $script:fTiny $script:C.Muted $M $y 200 14)); $y += 20
  $cw = $W - 2 * $M
  $bAnim = New-Btn 'Animations' $M $y $cw 38 'setting'; $bAnim.IsSwitch = $true; $bAnim.On = [bool](Get-MiseSetting $cfg 'animations'); $y += 44
  $bAnim.Add_Click({ param($s, $e) $s.On = -not $s.On; $s.Invalidate(); $null = Set-MiseSetting 'animations' $s.On })
  $bLp = $null
  if (Test-RiotInstalled) {
    $bLp = New-Btn 'League parts' $M $y $cw 38 'setting'; $bLp.IsSwitch = $true; $bLp.On = [bool](Get-MiseSetting $cfg 'leagueParts'); $y += 44
    $bLp.Add_Click({ param($s, $e) $s.On = -not $s.On; $s.Invalidate(); $null = Set-MiseSetting 'leagueParts' $s.On })
    $tipLp = New-Object Windows.Forms.ToolTip; $tipLp.SetToolTip($bLp, 'Off: League accounts and League options are hidden, for using Mise only for your windows.')
  }
  $bCorner = New-Btn 'Progress pop-up' $M $y $cw 38 'setting'; $bCorner.Tag = "$(Get-MiseSetting $cfg 'toastCorner')"; $bCorner.Chip = $script:CornerNames[$bCorner.Tag]; $y += 40
  $bCorner.Add_Click({ param($s, $e) Show-PickMenu $s $script:CornerNames { param($k) $null = Set-MiseSetting 'toastCorner' $k } })
  $f.Controls.Add((New-Label 'Used when a routine has no pop-up spot of its own.' $script:fSmall $script:C.Muted ($M + 2) $y $cw 18)); $y += 24
  $f.Controls.Add((New-Label 'MISE WINDOW' $script:fTiny $script:C.Muted $M $y 200 14)); $y += 20
  $bPos = New-Btn 'Opens at' $M $y $cw 38 'setting'; $bPos.Tag = "$(Get-MiseSetting $cfg 'homePos')"; $bPos.Chip = $script:HomePosNames[$bPos.Tag]; $y += 44
  $bPos.Add_Click({ param($s, $e) Show-PickMenu $s $script:HomePosNames { param($k) $null = Set-MiseSetting 'homePos' $k; $script:bMonRef.Enabled = ($k -ne 'remember'); $script:bMonRef.Invalidate() } })
  $mons = @(@{ id = ''; name = 'Main screen' }) + @($cfg.monitors | ForEach-Object { @{ id = $_.id; name = $_.name } })
  $script:monChoices = $mons
  $bMon = New-Btn 'On screen' $M $y $cw 38 'setting'; $script:bMonRef = $bMon
  $mi = 0; for ($k = 0; $k -lt $mons.Count; $k++) { if ($mons[$k].id -eq "$(Get-MiseSetting $cfg 'homeMonitor')") { $mi = $k } }
  $bMon.Tag = $mi; $bMon.Chip = $mons[$mi].name; $bMon.Enabled = ($bPos.Tag -ne 'remember'); $y += 44
  $bMon.Add_Click({ param($s, $e)
    $names = [ordered]@{}; for ($k = 0; $k -lt $script:monChoices.Count; $k++) { $names[$k] = $script:monChoices[$k].name }
    Show-PickMenu $s $names { param($k) $null = Set-MiseSetting 'homeMonitor' $script:monChoices[[int]$k].id } })
  $y += 6
  $f.Controls.Add((New-Label 'UPDATES' $script:fTiny $script:C.Muted $M $y 200 14)); $y += 20
  $f.Controls.Add((New-Label "Installed: Mise $script:MiseVersion" $script:fSmall $script:C.Muted $M ($y + 7) ($cw - 168) 18))
  $bChk = New-Btn 'Check for updates' ($M + $cw - 160) $y 160 32
  $bChk.Add_Click({ $r = Test-MiseUpdate $true
    if ($r.Available) { if ([Windows.Forms.MessageBox]::Show("$($r.Message)`n`nInstall it now? Mise restarts for a few seconds.", 'Mise', 'YesNo') -eq 'Yes') { try { Install-MiseUpdate $r } catch { [Windows.Forms.MessageBox]::Show("Update failed: $($_.Exception.Message)", 'Mise') | Out-Null } } }
    else { [Windows.Forms.MessageBox]::Show($r.Message, 'Mise') | Out-Null } })
  $y += 44
  $f.Controls.Add((New-Label 'SCREENS' $script:fTiny $script:C.Muted $M $y 200 14)); $y += 20
  $bScr = New-Btn 'Rename screens' $M $y $cw 32; $bScr.Add_Click({ $script:settingsAction = 'screens'; $f.Close() }); $y += 40
  $tipS = New-Object Windows.Forms.ToolTip; $tipS.SetToolTip($bScr, 'Mise names screens by itself (place and model). Give them your own names here. Routines stay.')
  $f.Controls.Add((New-Label 'TROUBLESHOOTING' $script:fTiny $script:C.Muted $M $y 200 14)); $y += 20
  $hw = [int](($cw - 8) / 2)
  $bFix = New-Btn 'Fix League client' $M $y $hw 32; $bRes = New-Btn 'Restart Mise' ($M + $hw + 8) $y $hw 32; $y += 40
  $bFix.Add_Click({ $script:settingsAction = 'fix'; $f.Close() })
  $bRes.Add_Click({ $script:settingsAction = 'reset'; $f.Close() })
  $tipS.SetToolTip($bRes, 'Stops everything Mise is running and starts it fresh. Routines and settings stay.')
  $bOver = New-Btn 'Start over' $M $y $hw 30 'ghost'; $bOver.Add_Click({ $script:settingsAction = 'startover'; $f.Close() })
  $tipS.SetToolTip($bOver, 'Forget screens, routines and settings and show the first-time setup again. League accounts stay.')
  $bUn = New-Btn 'Uninstall Mise' ($M + $hw + 8) $y $hw 30 'ghost'; $bUn.Add_Click({ $script:settingsAction = 'uninstall'; $f.Close() }); $y += 36
  $tipS.SetToolTip($bUn, 'Remove Mise from this PC. Routines, settings and League accounts stay, so a new install picks them up.')
  $bAbout = New-Btn 'About Mise' $M $y $cw 30 'ghost'; $bAbout.Add_Click({ $script:settingsAction = 'about'; $f.Close() }); $y += 38
  $ctl = @(@($bAnim, $bLp) | Where-Object { $_ }) + @($bCorner, $bPos, $bMon, $bChk, $bScr, $bFix, $bRes, $bOver, $bUn, $bAbout)
  # Send feedback shows once the feedback form exists
  if ($script:FeedbackForm) { $bFb = New-Btn 'Send feedback' $M $y $cw 30 'ghost'; $bFb.Add_Click({ $script:settingsAction = 'feedback'; $f.Close() }); $ctl += $bFb; $y += 38 }
  $done = New-Btn 'Done' $M $y $cw 36 'primary'; $done.Add_Click({ $f.Close() }); $y += 36 + 18
  $f.Controls.AddRange([Windows.Forms.Control[]]@($ctl + $done))
  $f.ClientSize = New-Object Drawing.Size($W, $y)
  [void]$f.ShowDialog()
}

# a short list under a setting button; picking one sets the chip and calls $onPick with its key
function Show-PickMenu($btn, $names, [scriptblock]$onPick) {
  $m = New-Object Windows.Forms.ContextMenuStrip
  $m.BackColor = $script:C.Panel; $m.ForeColor = $script:C.Text; $m.ShowImageMargin = $false
  $m.Tag = @{ Btn = $btn; Names = $names; Pick = $onPick }
  foreach ($k in @($names.Keys)) {
    $it = New-Object Windows.Forms.ToolStripMenuItem("$($names[$k])"); $it.Tag = $k; $it.Checked = ("$k" -eq "$($btn.Tag)")
    $it.Add_Click({ param($s, $e) $t = $s.Owner.Tag; $t.Btn.Tag = $s.Tag; $t.Btn.Chip = "$($t.Names[$s.Tag])"; $t.Btn.Invalidate(); & $t.Pick $s.Tag })
    [void]$m.Items.Add($it)
  }
  $m.Show($btn, (New-Object Drawing.Point(($btn.Width - 180), $btn.Height)))
}
# Start over: settings backed up and emptied, helpers stopped, the tray starts again and opens the first-time setup
function Invoke-StartOver {
  $a = [Windows.Forms.MessageBox]::Show("Mise forgets your screens, routines and settings and shows the first-time setup again. Your League accounts stay. A copy of your settings is kept as config-before-first-time.json.`r`n`r`nStart over?", 'Mise', 'YesNo', 'Question')
  if ($a -ne 'Yes') { return $false }
  try {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match 'mise-run\.ps1|riot-league\.ps1|mise-home\.ps1|mise-builder\.ps1|mise-tray\.ps1' } |
      ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  } catch {}
  try { Copy-Item -LiteralPath $script:CfgPath -Destination (Join-Path $script:DataDir 'config-before-first-time.json') -Force } catch {}
  Save-MiseConfig (New-MiseConfig)
  foreach ($n in @('_ugg-now.txt', '_last-routine.txt', '_active-routine.txt', '_builder-routine.json', 'timings.json')) { Remove-Item -LiteralPath (Join-Path $script:DataDir $n) -Force -ErrorAction SilentlyContinue }
  Remove-Item -LiteralPath (Join-Path $env:TEMP 'mise-status.txt') -Force -ErrorAction SilentlyContinue
  $trayFile = Join-Path $script:MiseDir 'mise-tray.ps1'
  $cmd = "Start-Sleep -Seconds 2; Start-Process powershell.exe -WindowStyle Hidden -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File ' + [char]34 + '$trayFile' + [char]34)"
  $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
  Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $enc"
  return $true
}

# Uninstall: everything Mise is running stops, shortcuts and the app folder go; %APPDATA%\Mise and LeagueAccounts stay
function Invoke-MiseUninstall {
  $a = [Windows.Forms.MessageBox]::Show("Remove Mise from this PC?`r`n`r`nThe app, its desktop icon and its start with Windows are removed. Your routines, settings and League accounts stay, so installing Mise again picks them up.", 'Mise', 'YesNo', 'Question')
  if ($a -ne 'Yes') { return $false }
  try { $null = Show-AllTaskbars } catch {}   # a running routine may have hidden them
  $dir = $script:MiseDir
  $cmd = @(
    'Start-Sleep -Seconds 2'
    "Get-CimInstance Win32_Process | Where-Object { `$_.Name -eq 'powershell.exe' -and `$_.ProcessId -ne `$PID -and `$_.CommandLine -match 'mise-run\.ps1|riot-league\.ps1|mise-home\.ps1|mise-builder\.ps1|mise-tray\.ps1' } | ForEach-Object { Stop-Process -Id `$_.ProcessId -Force -ErrorAction SilentlyContinue }"
    "Get-Process -Name 'Mise' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue"
    "Remove-Item -LiteralPath (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Mise.lnk'), (Join-Path ([Environment]::GetFolderPath('Programs')) 'Mise.lnk'), (Join-Path ([Environment]::GetFolderPath('Startup')) 'Mise tray.lnk') -Force -ErrorAction SilentlyContinue"
    'Start-Sleep -Milliseconds 500'
    "Remove-Item -LiteralPath '$($dir -replace "'", "''")' -Recurse -Force -ErrorAction SilentlyContinue"
    "Add-Type -AssemblyName System.Windows.Forms; [void][Windows.Forms.MessageBox]::Show('Mise is removed. Your routines and League accounts are kept.', 'Mise')"
  ) -join '; '
  $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
  Start-Process powershell.exe -WindowStyle Hidden -WorkingDirectory $env:TEMP -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $enc"
  return $true
}

# ---------- small input box in the Mise look; returns the text, or $null when cancelled ----------
function Show-MiseInput([string]$title, [string]$label, [string]$value = '') {
  $W = 380; $M = 22; $cw = $W - 2 * $M
  $f = New-MiseDialog $title $W 200; $y = 58
  $f.Controls.Add((New-Label $label $script:fSmall $script:C.Muted $M $y $cw 20)); $y += 24
  $tb = New-MiseText $M $y $cw $value; $f.Controls.Add($tb.Panel); $y += 44
  $script:inputResult = $null
  $ok = New-Btn 'Save' $M $y $cw 36 'primary'; $ok.Add_Click({ $script:inputResult = $tb.Box.Text.Trim(); $f.Close() }); $f.Controls.Add($ok); $y += 36 + 18
  $tb.Box.Add_KeyDown({ param($s, $e) if ($e.KeyCode -eq 'Enter') { $e.SuppressKeyPress = $true; $script:inputResult = $tb.Box.Text.Trim(); $f.Close() } })
  $f.Add_Shown({ $tb.Box.Focus(); $tb.Box.SelectAll() })
  $f.ClientSize = New-Object Drawing.Size($W, $y)
  [void]$f.ShowDialog()
  return $script:inputResult
}

# ---------- what's new: shown once in the Mise window after an update ----------
function Show-WhatsNew {
  $W = 420; $M = 22; $cw = $W - 2 * $M
  $f = New-MiseDialog "New in Mise $($script:MiseVersion)" $W 200; $y = 60
  foreach ($l in @($script:WhatsNew)) {
    $f.Controls.Add((New-Label ([string][char]0x2022) $script:fSmall $script:C.Accent $M $y 14 18))
    $f.Controls.Add((New-Label "$l" $script:fSmall $script:C.Text ($M + 16) $y ($cw - 16) 36)); $y += 42
  }
  $ok = New-Btn 'OK' $M ($y + 2) $cw 36 'primary'; $ok.Add_Click({ $f.Close() }); $f.Controls.Add($ok); $y += 38 + 18
  $f.Add_KeyDown({ param($s, $e) if ($e.KeyCode -in 'Enter', 'Escape') { $f.Close() } })
  $f.ClientSize = New-Object Drawing.Size($W, $y)
  [void]$f.ShowDialog()
}

# ---------- feedback (bug or wish; sends only what the user typed plus version, Windows build and screen count) ----------
function Get-FeedbackQueuePath { Join-Path $script:DataDir '_feedback-queue.json' }
function Send-FeedbackOne($item) {
  if (-not $script:FeedbackForm) { return $false }
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $body = @{}
    foreach ($k in @('type', 'message', 'name', 'info')) { if ($script:FeedbackFields[$k]) { $body[$script:FeedbackFields[$k]] = "$($item.$k)" } }
    Invoke-WebRequest -Uri $script:FeedbackForm -Method Post -Body $body -UseBasicParsing -TimeoutSec 10 | Out-Null
    return $true
  } catch { return $false }
}
# try everything waiting in the queue; returns how many are still waiting
function Send-FeedbackQueue {
  $qp = Get-FeedbackQueuePath; if (-not (Test-Path $qp)) { return 0 }
  $left = @()
  try { foreach ($it in @(Get-Content -LiteralPath $qp -Raw | ConvertFrom-Json)) { if (-not (Send-FeedbackOne $it)) { $left += $it } } } catch { return 0 }
  if ($left.Count) { ConvertTo-Json @($left) -Depth 3 | Set-Content -LiteralPath $qp -Encoding UTF8 } else { Remove-Item -LiteralPath $qp -Force -ErrorAction SilentlyContinue }
  return $left.Count
}
function Show-MiseFeedback {
  $W = 460; $M = 22; $cw = $W - 2 * $M
  $f = New-MiseDialog 'Send feedback' $W 400; $y = 58
  $f.Controls.Add((New-Label 'Found a bug or want something? Tell me. Only what you type is sent, plus the Mise version, Windows version and how many screens you use. No account names, no passwords.' $script:fSmall $script:C.Muted $M $y $cw 52)); $y += 58
  $script:fbType = 'Bug'
  $bBug = New-Btn 'Bug' $M $y 120 32; $bWish = New-Btn 'Wish' ($M + 128) $y 120 32
  $bBug.On = $true
  $bBug.Add_Click({ $script:fbType = 'Bug'; $bBug.On = $true; $bWish.On = $false; $bBug.Invalidate(); $bWish.Invalidate() })
  $bWish.Add_Click({ $script:fbType = 'Wish'; $bWish.On = $true; $bBug.On = $false; $bBug.Invalidate(); $bWish.Invalidate() })
  $f.Controls.AddRange(@($bBug, $bWish)); $y += 42
  $msg = New-MiseText $M $y $cw; $msg.Panel.Height = 120; $msg.Box.Multiline = $true; $msg.Box.ScrollBars = 'Vertical'; $f.Controls.Add($msg.Panel); $y += 128
  $f.Controls.Add((New-Label 'YOUR NAME (optional)' $script:fTiny $script:C.Muted $M $y 200 14)); $y += 18
  $nm = New-MiseText $M $y $cw; $f.Controls.Add($nm.Panel); $y += 42
  $note = New-Label '' $script:fSmall $script:C.Muted $M $y $cw 20; $f.Controls.Add($note); $y += 26
  $send = New-Btn 'Send' $M $y $cw 36 'primary'; $f.Controls.Add($send); $y += 36 + 18
  $send.Add_Click({
    $t = $msg.Box.Text.Trim(); if ($t.Length -lt 3) { $note.Text = 'Write a few words first.'; return }
    $os = ''; try { $os = (Get-CimInstance Win32_OperatingSystem).Caption + ' ' + [Environment]::OSVersion.Version.Build } catch {}
    $info = "Mise $($script:MiseVersion) | $os | screens: $([Windows.Forms.Screen]::AllScreens.Count)"
    $item = [pscustomobject]@{ type = $script:fbType; message = $t; name = $nm.Box.Text.Trim(); info = $info; time = (Get-Date -Format s) }
    if (Send-FeedbackOne $item) { $null = Send-FeedbackQueue; [Windows.Forms.MessageBox]::Show('Sent. Thanks!', 'Mise') | Out-Null }
    else {
      $qp = Get-FeedbackQueuePath; $all = @(); try { if (Test-Path $qp) { $all = @(Get-Content -LiteralPath $qp -Raw | ConvertFrom-Json) } } catch {}
      $all += $item; ConvertTo-Json @($all) -Depth 3 | Set-Content -LiteralPath $qp -Encoding UTF8
      [Windows.Forms.MessageBox]::Show('Saved. Mise sends it as soon as it can.', 'Mise') | Out-Null
    }
    $f.Close() })
  $f.ClientSize = New-Object Drawing.Size($W, $y)
  [void]$f.ShowDialog()
}

# ---------- update check (GitHub releases; off until a repository is set) ----------
function Test-MiseUpdate([bool]$manual = $false) {
  $cfg = Get-MiseConfig; $repo = "$(Get-MiseSetting $cfg 'updateRepo')".Trim()
  if (-not $repo) { return @{ Available = $false; Message = 'No update repository is set.' } }
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers @{ 'User-Agent' = 'Mise-updater' } -TimeoutSec 8
    $null = Set-MiseSetting 'lastUpdateCheck' (Get-Date -Format s)
    $tag = "$($rel.tag_name)".TrimStart('v', 'V')
    $zip = @($rel.assets | Where-Object { $_.name -like '*.zip' }) | Select-Object -First 1
    $newer = $false; try { $newer = ([version]$tag -gt [version]$script:MiseVersion) } catch { $newer = ($tag -ne $script:MiseVersion) }
    if ($newer -and $zip) { return @{ Available = $true; Version = $tag; Url = $zip.browser_download_url; Message = "Mise $tag is available (you have $($script:MiseVersion))." } }
    return @{ Available = $false; Message = "Mise is up to date ($($script:MiseVersion))." }
  } catch { return @{ Available = $false; Message = "Could not check for updates: $($_.Exception.Message)" } }
}
function Install-MiseUpdate($u) {
  $tmp = Join-Path $env:TEMP "mise-update-$($u.Version)"
  Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  $zip = Join-Path $tmp 'mise.zip'
  Invoke-WebRequest -Uri $u.Url -OutFile $zip -UseBasicParsing -Headers @{ 'User-Agent' = 'Mise-updater' }
  Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
  $inst = Get-ChildItem -LiteralPath $tmp -Recurse -Filter 'install.ps1' | Select-Object -First 1
  if (-not $inst) { throw 'the download has no install.ps1' }
  Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$($inst.FullName)`" -Quiet"
}

# ---------- silent updates: download in the background, install when nothing is going on ----------
function Get-UpdateReadyPath { Join-Path $script:DataDir '_update-ready.json' }
function Save-MiseUpdate($u) {
  $dir = Join-Path $script:DataDir "_update\$($u.Version)"
  Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force -Path $dir | Out-Null
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $zip = Join-Path $dir 'mise.zip'
  Invoke-WebRequest -Uri $u.Url -OutFile $zip -UseBasicParsing -Headers @{ 'User-Agent' = 'Mise-updater' } -TimeoutSec 60
  Expand-Archive -LiteralPath $zip -DestinationPath $dir -Force
  $inst = Get-ChildItem -LiteralPath $dir -Recurse -Filter 'install.ps1' | Select-Object -First 1
  if (-not $inst) { throw 'the download has no install.ps1' }
  Set-Content -LiteralPath (Get-UpdateReadyPath) -Value (@{ version = $u.Version; installer = $inst.FullName } | ConvertTo-Json -Compress) -Encoding UTF8
}
# safe = no League game or client, no routine running, no Mise window open
function Test-UpdateSafe {
  if (Get-Process -Name 'League of Legends', 'LeagueClientUx' -ErrorAction SilentlyContinue) { return $false }
  try { if (Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'mise-run\.ps1|riot-league\.ps1|mise-home\.ps1|mise-builder\.ps1' }) { return $false } } catch { return $false }
  return $true
}
# installs a downloaded update if it is newer and the moment is safe; returns $true when the installer was started
function Start-PendingUpdate {
  $rp = Get-UpdateReadyPath; if (-not (Test-Path $rp)) { return $false }
  try { $r = Get-Content -LiteralPath $rp -Raw | ConvertFrom-Json } catch { Remove-Item -LiteralPath $rp -Force -ErrorAction SilentlyContinue; return $false }
  $newer = $false; try { $newer = ([version]$r.version -gt [version]$script:MiseVersion) } catch {}
  if (-not $newer -or -not (Test-Path -LiteralPath $r.installer)) { Remove-Item -LiteralPath $rp -Force -ErrorAction SilentlyContinue; return $false }
  if (-not (Test-UpdateSafe)) { return $false }
  Remove-Item -LiteralPath $rp -Force -ErrorAction SilentlyContinue
  Set-Content -LiteralPath (Join-Path $script:DataDir '_updated-from.txt') -Value $script:MiseVersion -Encoding UTF8
  Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$($r.installer)`" -Quiet"
  return $true
}

# ---------- League accounts, step by step ----------
$script:Regions = @('EUW', 'EUNE', 'TR', 'NA', 'KR', 'BR', 'LAN', 'LAS', 'OCE', 'RU', 'JP', 'ME', 'SEA', 'TW', 'VN')   # Riot's server list, Nov 2026
function Show-AccountWizard {
  # one step at a time: 1 open Riot Client, 2 log in, 3 name it and save. After saving, the next account starts at step 2.
  $W = 420; $M = 18; $cw = $W - 2 * $M
  $f = New-MiseDialog 'Add League accounts' $W 400
  $stepL = New-Label '' $script:fTiny $script:C.Accent $M 54 $cw 16; $f.Controls.Add($stepL)
  $head = New-Label '' $script:fBig $script:C.Text $M 72 $cw 26; $f.Controls.Add($head)
  $body = New-Label '' $script:fSmall $script:C.Muted $M 102 $cw 58; $f.Controls.Add($body)
  # step 1
  $bOpen = New-Btn 'Open Riot Client' $M 166 $cw 36 'primary'; $f.Controls.Add($bOpen)
  # step 2
  $bIn = New-Btn "I'm logged in" $M 166 $cw 36 'primary'; $f.Controls.Add($bIn)
  # step 3
  $lN = New-Label 'NICKNAME' $script:fTiny $script:C.Muted $M 166 200 14; $lR = New-Label 'REGION' $script:fTiny $script:C.Muted ($M + $cw - 110) 166 110 14
  $nick = New-UiBox $M 184 ($cw - 120); $nick.Font = $script:fStatus
  $reg = New-UiCombo ($M + $cw - 110) 184 110; foreach ($r in $script:Regions) { [void]$reg.Items.Add($r) }; $reg.SelectedIndex = 0
  $bSave = New-Btn 'Save this account' $M 222 $cw 36 'primary'
  $f.Controls.AddRange(@($lN, $lR, $nick, $reg, $bSave))
  # after saving
  $bNext = New-Btn 'Add another account' $M 166 $cw 36 'primary'; $f.Controls.Add($bNext)
  $bBack = New-Btn 'Back' $M 270 90 30 'ghost'; $f.Controls.Add($bBack)
  # always: what is saved, and Done
  $f.Controls.Add((New-Label 'SAVED' $script:fTiny $script:C.Muted $M 306 200 14))
  $list = New-Label '' $script:fSmall $script:C.Text $M 322 $cw 36; $f.Controls.Add($list)
  $bDone = New-Btn 'Done' $M 362 $cw 34; $bDone.Add_Click({ $f.Close() }); $f.Controls.Add($bDone)
  $f.ClientSize = New-Object Drawing.Size($W, 414)
  $fill = { $a = @(Get-RiotAccounts); $list.Text = $(if ($a.Count) { $a -join '   ' } else { 'none yet' }) }; & $fill
  $show = {
    param([int]$n)
    $script:accStep = $n
    $bOpen.Visible = ($n -eq 1); $bIn.Visible = ($n -eq 2); $bNext.Visible = ($n -eq 4)
    foreach ($c in @($lN, $lR, $nick, $reg, $bSave)) { $c.Visible = ($n -eq 3) }
    $bBack.Visible = ($n -eq 2 -or $n -eq 3)
    switch ($n) {
      1 { $stepL.Text = 'STEP 1 OF 3'; $head.Text = 'Open Riot Client'; $body.Text = 'Mise saves the login Riot Client keeps when you tick Stay signed in. Never your password.' }
      2 { $stepL.Text = 'STEP 2 OF 3'; $head.Text = 'Log in'; $body.Text = "Log in to the account and tick 'Stay signed in'. Don't sign out afterwards: that cancels the saved login." }
      3 { $stepL.Text = 'STEP 3 OF 3'; $head.Text = 'Name it'; $body.Text = 'A short nickname you will recognise, and the region. Mise then closes Riot Client and reopens it on a fresh login screen.'; $nick.Focus() | Out-Null }
    }
  }
  $bOpen.Add_Click({
    $rc = Get-RiotClientExe
    if (Test-Path -LiteralPath $rc) { Start-Process $rc; & $show 2 } else { $body.Text = "Riot Client doesn't exist on this PC. Install it from riotgames.com, then try again." }
  })
  $bIn.Add_Click({ & $show 3 })
  $bBack.Add_Click({ & $show ($script:accStep - 1) })
  $bNext.Add_Click({ & $show 2 })
  $bSave.Add_Click({
    $n = ($nick.Text.Trim() -replace '[\\/:*?"<>|]', '')
    if (-not $n) { $body.Text = 'Type a nickname first.'; return }
    $full = "$n $($reg.SelectedItem)"
    if (@(Get-RiotAccounts) -contains $full) { $body.Text = "$full is already saved. Pick another nickname, or right-click it in the Mise window to update its login."; return }
    $body.Text = "Saving $full ..."; $bSave.Enabled = $false; $f.Refresh()
    $mod = Join-Path $script:MiseDir 'modules\riot-league.ps1'
    $p = Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$mod`"", '-Core', '-Save', "`"$full`"", '-Next') -WindowStyle Hidden -PassThru
    $p.WaitForExit(); $bSave.Enabled = $true
    & $fill
    if ($p.ExitCode -eq 0) {
      $nick.Text = ''; & $show 4
      $stepL.Text = 'SAVED'; $head.Text = "$full is ready"; $body.Text = 'Riot Client is back on its login screen. Add the next account, or press Done.'
      if (@(Get-RiotAccounts).Count -eq 2) { $body.Text += ' Click an account in the Mise window to switch to it, even while another one is logged in.' }
    } else { $body.Text = "Could not save. Is Riot Client open and logged in, with 'Stay signed in' ticked?" }
  })
  # Riot Client already running: skip straight to logging in
  $f.Add_Shown({ if (Get-Process -Name 'RiotClientServices', 'Riot Client' -ErrorAction SilentlyContinue) { & $show 2 } else { & $show 1 } })
  [void]$f.ShowDialog()
}

# ---------- first run: screens, apps Mise found, a suggested layout, League accounts ----------
function Show-FirstRun($cfg) {
  # first launch: screens are named by themselves (Rename screens in Settings changes them); the intro takes it from there
  $cfg = (Update-AutoMonitors $cfg).Cfg
  $cfg.firstRunDone = $true
  Save-MiseConfig $cfg
  return $cfg
}


# ---------- empty state: a small card with one clear next step ----------
function New-EmptyCard([string]$text, [string]$btnText, [scriptblock]$onClick, [int]$w) {
  $p = New-Object Windows.Forms.Panel; $p.Size = New-Object Drawing.Size($w, 84); $p.BackColor = $script:C.Panel
  $p.Add_Paint({ param($s, $e) $pen = New-Object Drawing.Pen($script:C.Line, 1); $pen.DashStyle = 'Dash'; $e.Graphics.DrawRectangle($pen, 0, 0, $s.Width - 1, $s.Height - 1); $pen.Dispose() })
  $l = New-Label $text $script:fSmall $script:C.Muted 14 10 ($w - 28) 34; $p.Controls.Add($l)
  $b = New-Btn $btnText 14 46 ([Math]::Min(220, $w - 28)) 28 'primary'; $b.Surface = $script:C.Panel; $b.Add_Click($onClick); $p.Controls.Add($b)
  return $p
}

# ---------- first-time setup: each step is done for real and it ends with a working routine ----------
# welcome > League? > account > first routine (Copy my screen) > try it > where Mise lives. Every step can be skipped.
$script:SetupDemo = @(
  @{ N = 'League'; C = [Drawing.Color]::FromArgb(200, 170, 110); M = @(0.18, 0.08, 0.52, 0.60); P = @(0.00, 0.00, 0.66, 0.91) },
  @{ N = 'Discord'; C = [Drawing.Color]::FromArgb(140, 147, 232); M = @(0.04, 0.30, 0.40, 0.48); P = @(0.66, 0.00, 0.34, 0.55) },
  @{ N = 'Browser'; C = [Drawing.Color]::FromArgb(156, 184, 224); M = @(0.46, 0.22, 0.46, 0.52); P = @(0.66, 0.55, 0.34, 0.36) },
  @{ N = 'Spotify'; C = [Drawing.Color]::FromArgb(127, 199, 143); M = @(0.58, 0.04, 0.30, 0.13); P = @(0.02, 0.76, 0.24, 0.12) }
)
# a clickable choice: a bold line and a grey line, copper border when the mouse is on it
function New-SetupChoice([string]$title, [string]$sub, $x, $y, $w) {
  $p = New-Object Windows.Forms.Panel; $p.Location = New-Object Drawing.Point($x, $y); $p.Size = New-Object Drawing.Size($w, 58); $p.BackColor = $script:C.Panel; $p.Cursor = 'Hand'
  $p.Tag = @{ Hot = $false }
  $p.Add_Paint({ param($s, $e) $pen = New-Object Drawing.Pen($(if ($s.Tag.Hot) { $script:C.Accent } else { $script:C.Line }), 1); $e.Graphics.DrawRectangle($pen, 0, 0, $s.Width - 1, $s.Height - 1); $pen.Dispose() })
  $t = New-Label $title $script:fBig $script:C.Text 14 9 ($w - 28) 22; $t.BackColor = $script:C.Panel
  $d = New-Label $sub $script:fSmall $script:C.Muted 14 32 ($w - 28) 18; $d.BackColor = $script:C.Panel
  $p.Controls.AddRange(@($t, $d))
  foreach ($c in @($p, $t, $d)) {
    $c.Cursor = 'Hand'
    $c.Add_MouseEnter({ param($s, $e) $q = $(if ($s -is [Windows.Forms.Panel]) { $s } else { $s.Parent }); $q.Tag.Hot = $true; $q.Invalidate() })
    $c.Add_MouseLeave({ param($s, $e) $q = $(if ($s -is [Windows.Forms.Panel]) { $s } else { $s.Parent }); $q.Tag.Hot = $false; $q.Invalidate() })
  }
  return @{ Panel = $p; Parts = @($p, $t, $d) }
}
# a short explanation with a copper bar on its left
function New-SetupNote([string]$text, $x, $y, $w, $h) {
  $p = New-Object Windows.Forms.Panel; $p.Location = New-Object Drawing.Point($x, $y); $p.Size = New-Object Drawing.Size($w, $h); $p.BackColor = $script:C.Panel
  $p.Add_Paint({ param($s, $e) $b = New-Object Drawing.SolidBrush($script:C.Accent); $e.Graphics.FillRectangle($b, 0, 0, 3, $s.Height); $b.Dispose() })
  $l = New-Label $text $script:fSmall $script:C.Text 14 8 ($w - 24) ($h - 12); $l.BackColor = $script:C.Panel; $p.Controls.Add($l)
  return $p
}
function Show-Setup {
  $W = 460; $M = 18; $cw = $W - 2 * $M; $H = 560
  $f = New-MiseDialog 'Mise' $W $H
  $script:su = @{ Page = 'welcome'; League = [bool](Test-RiotInstalled); Tiles = @(); RoutineId = ''; Name = 'My setup'; Hotkey = ''; Ran = $false; T = 0.0; Target = 0.0; Clock = [Diagnostics.Stopwatch]::StartNew(); Last = 0L; Flip = 0L }
  if (-not $script:Animate) { $script:su.T = 1.0; $script:su.Target = 1.0 }
  # League accounts already saved: no need to ask whether they play
  $script:su.HadAccounts = (@(Get-RiotAccounts).Count -gt 0)
  if ($script:su.HadAccounts) { $script:su.League = $true; $null = Set-MiseSetting 'leagueParts' $true }
  # thin progress bar under the header: one segment per step
  $bar = New-Object Windows.Forms.Panel; $bar.Location = New-Object Drawing.Point($M, 54); $bar.Size = New-Object Drawing.Size($cw, 4); $bar.BackColor = $script:C.Bg
  $bar.Add_Paint({ param($s, $e)
    $steps = @(Get-SetupSteps); $i = [Array]::IndexOf($steps, $script:su.Page); if ($script:su.Page -eq 'routine2') { $i = [Array]::IndexOf($steps, 'routine') }
    $n = $steps.Count; $gw = ($s.Width - ($n - 1) * 4) / $n
    for ($k = 0; $k -lt $n; $k++) { $b = New-Object Drawing.SolidBrush($(if ($k -le $i) { $script:C.Accent } else { $script:C.Line })); $e.Graphics.FillRectangle($b, [single]($k * ($gw + 4)), 0, [single]$gw, 3); $b.Dispose() }
  })
  $f.Controls.Add($bar)
  $cp = New-Object Windows.Forms.Panel; $cp.Location = New-Object Drawing.Point(0, 66); $cp.Size = New-Object Drawing.Size($W, ($H - 66)); $cp.BackColor = $script:C.Bg
  $f.Controls.Add($cp)
  # the welcome picture: four windows, messy then in their place, again and again
  $demoTimer = New-Object Windows.Forms.Timer; $demoTimer.Interval = 15
  $demoTimer.Add_Tick({
    $now = $script:su.Clock.ElapsedMilliseconds
    if ($now - $script:su.Flip -gt 2600) { $script:su.Flip = $now; $script:su.Target = 1.0 - $script:su.Target }
    $dt = ($now - $script:su.Last) / 550.0; $script:su.Last = $now
    if ($script:su.T -lt $script:su.Target) { $script:su.T = [Math]::Min($script:su.Target, $script:su.T + $dt) } elseif ($script:su.T -gt $script:su.Target) { $script:su.T = [Math]::Max($script:su.Target, $script:su.T - $dt) }
    if ($script:su.Demo) { $script:su.Demo.Invalidate() }
  })
  # what is open right now (step: first routine), read every 2 seconds
  $openTimer = New-Object Windows.Forms.Timer; $openTimer.Interval = 2000
  $openTimer.Add_Tick({ Update-SetupOpen })
  $f.Add_FormClosed({ $demoTimer.Stop(); $openTimer.Stop(); $script:su.GoTimer.Stop(); $demoTimer.Dispose(); $openTimer.Dispose(); $null = Set-MiseSetting 'introDone' $true })
  $goTimer = New-Object Windows.Forms.Timer; $goTimer.Interval = 10
  $goTimer.Add_Tick({ param($s, $e) $s.Stop(); Render-SetupPage $script:su.Next })
  $script:su.Form = $f; $script:su.Cp = $cp; $script:su.Bar = $bar; $script:su.DemoTimer = $demoTimer; $script:su.OpenTimer = $openTimer; $script:su.GoTimer = $goTimer; $script:su.W = $W; $script:su.M = $M
  Render-SetupPage 'welcome'
  [void]$f.ShowDialog()
  return $script:su.RoutineId
}
function Get-SetupSteps {
  $s = @('welcome')
  if ((Test-RiotInstalled) -and -not $script:su.HadAccounts) { $s += 'league' }
  if ($script:su.League) { $s += 'account' }
  return @($s + @('routine', 'try', 'tray'))
}
function Move-SetupStep([int]$d) {
  $steps = @(Get-SetupSteps); $cur = $(if ($script:su.Page -eq 'routine2') { 'routine' } else { $script:su.Page })
  $i = [Array]::IndexOf($steps, $cur) + $d
  if ($i -ge $steps.Count) { $script:su.Form.Close(); return }
  Show-SetupPage $steps[[Math]::Max(0, $i)]
}
# the buttons at the bottom right: @(text, kind, action) from right to left
function Add-SetupButtons($defs) {
  $x = $script:su.W - $script:su.M; $y = $script:su.Cp.Height - 52
  foreach ($d in $defs) {
    $w = [Math]::Max(84, [int]([Windows.Forms.TextRenderer]::MeasureText($d[0], $script:fSmall).Width + 34))
    $x -= $w; $b = New-Btn $d[0] $x $y $w 34 $d[1]; $b.Tag = $d[2]; $b.Add_Click({ param($s, $e) & $s.Tag })
    $script:su.Cp.Controls.Add($b); $x -= 8
  }
}
function Add-SetupText([string]$text, $font, $color, [int]$y, [int]$h) {
  $l = New-Label $text $font $color $script:su.M $y ($script:su.W - 2 * $script:su.M) $h; $script:su.Cp.Controls.Add($l); return $l
}
# page changes wait for the click that asked for them to finish (its button is about to be removed)
function Show-SetupPage([string]$page) { $script:su.Next = $page; $script:su.GoTimer.Start() }
function Render-SetupPage([string]$page) {
  $su = $script:su; $cp = $su.Cp; $M = $su.M; $cw = $su.W - 2 * $M
  $su.Page = $page; $su.DemoTimer.Stop(); $su.OpenTimer.Stop(); $su.Demo = $null
  $cp.SuspendLayout(); foreach ($c in @($cp.Controls)) { $c.Dispose() }; $cp.Controls.Clear()
  $steps = @(Get-SetupSteps); $pos = [Array]::IndexOf($steps, $(if ($page -eq 'routine2') { 'routine' } else { $page }))
  $y = 8
  if ($page -ne 'welcome') { $null = Add-SetupText ("STEP {0} OF {1}" -f $pos, ($steps.Count - 1)) $script:fTiny $script:C.Muted $y 16; $y += 18 }
  switch ($page) {
    'welcome' {
      $null = Add-SetupText 'Welcome to Mise' $script:fTitle $script:C.Text $y 34; $y += 38
      $null = Add-SetupText 'Mise opens your apps and puts every window where you want it. One click, or one hotkey.' $script:fStatus $script:C.Text $y 42; $y += 50
      $demo = New-Object Windows.Forms.Panel; $demo.Location = New-Object Drawing.Point($M, $y); $demo.Size = New-Object Drawing.Size($cw, [int]($cw * 9 / 16)); $demo.BackColor = $script:C.Panel
      [Windows.Forms.Control].GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic,Instance').SetValue($demo, $true, $null)
      $demo.Add_Paint({ param($s, $e) Draw-SetupDemo $e.Graphics $s.ClientRectangle })
      $cp.Controls.Add($demo); $su.Demo = $demo; $y += $demo.Height + 12
      $null = Add-SetupText "Let's set yours up. It takes about 3 minutes, and you can skip any step." $script:fSmall $script:C.Muted $y 36
      Add-SetupButtons @(@('Start', 'primary', { Move-SetupStep 1 }), @('Skip setup', 'ghost', { $script:su.Form.Close() }))
      if ($script:Animate) { $su.Clock.Restart(); $su.Last = 0; $su.Flip = 0; $su.T = 0.0; $su.Target = 0.0; $su.DemoTimer.Start() }
    }
    'league' {
      $null = Add-SetupText 'Do you play League of Legends?' $script:fTitle $script:C.Text $y 34; $y += 40
      $null = Add-SetupText "Mise can log you in and switch accounts. If you don't play, it stays out of your way." $script:fStatus $script:C.Muted $y 44; $y += 54
      $yes = New-SetupChoice 'Yes, set up my account' 'Mise logs you in, switches accounts and starts your lobby' $M $y $cw; $y += 68
      $no = New-SetupChoice 'No, just my windows' 'Accounts and League options stay hidden' $M $y $cw
      foreach ($c in $yes.Parts) { $c.Add_Click({ $script:su.League = $true; $null = Set-MiseSetting 'leagueParts' $true; Show-SetupPage 'account' }) }
      foreach ($c in $no.Parts) { $c.Add_Click({ $script:su.League = $false; $null = Set-MiseSetting 'leagueParts' $false; Show-SetupPage 'routine' }) }
      $cp.Controls.AddRange(@($yes.Panel, $no.Panel))
      Add-SetupButtons @(, @('Back', 'ghost', { Move-SetupStep -1 }))
    }
    'account' {
      $null = Add-SetupText 'Add your League account' $script:fTitle $script:C.Text $y 34; $y += 42
      $accs = @(Get-RiotAccounts)
      $l1 = Add-SetupText "1   Mise opens Riot Client.`r`n2   Log in, with Stay signed in ticked.`r`n3   Give the account a short name you'll recognise." $script:fStatus $script:C.Text $y 74; $y += 82
      $cp.Controls.Add((New-SetupNote 'Mise never sees or stores your password. It keeps the sign-in Riot Client saves, so it can switch accounts for you.' $M $y $cw 48)); $y += 60
      if ($accs.Count) {
        $null = Add-SetupText 'SAVED' $script:fTiny $script:C.Muted $y 16; $y += 18
        $null = Add-SetupText ($accs -join '   ') $script:fBig $script:C.Accent $y 24; $y += 30
        $null = Add-SetupText 'More accounts? Add them any time with + Account in the Mise window.' $script:fSmall $script:C.Muted $y 36
        Add-SetupButtons @(@('Next', 'primary', { Move-SetupStep 1 }), @('Add another', 'tool', { $script:su.Form.TopMost = $false; Show-AccountWizard; $script:su.Form.TopMost = $true; Show-SetupPage 'account' }), @('Back', 'ghost', { Move-SetupStep -1 }))
      } else {
        Add-SetupButtons @(@('Add my account', 'primary', { $script:su.Form.TopMost = $false; Show-AccountWizard; $script:su.Form.TopMost = $true; Show-SetupPage 'account' }), @('Do this later', 'ghost', { Move-SetupStep 1 }), @('Back', 'ghost', { Move-SetupStep -1 }))
      }
    }
    'routine' {
      $su.Form.TopMost = $false   # out of the way while they place their windows
      $null = Add-SetupText 'Make your first routine' $script:fTitle $script:C.Text $y 34; $y += 42
      $cp.Controls.Add((New-SetupNote 'A routine is a set of apps and where each window goes. Run it, and Mise opens what is missing and puts everything in its place.' $M $y $cw 50)); $y += 62
      $null = Add-SetupText 'Open the apps you use while you play and put each window where you like it. Then come back here and press Copy my screen.' $script:fStatus $script:C.Text $y 62; $y += 70
      $null = Add-SetupText 'OPEN RIGHT NOW' $script:fTiny $script:C.Muted $y 16; $y += 18
      $su.OpenLbl = Add-SetupText 'Looking...' $script:fSmall $script:C.Text $y 60; $y += 64
      if ($su.League) { $null = Add-SetupText 'League is added to the routine by itself, even when the client is closed now.' $script:fSmall $script:C.Muted $y 36 }
      Add-SetupButtons @(@('Copy my screen', 'primary', { Invoke-SetupCopy }), @('Back', 'ghost', { Move-SetupStep -1 }))
      Update-SetupOpen; $su.OpenTimer.Start()
    }
    'routine2' {
      $null = Add-SetupText 'This is your routine' $script:fTitle $script:C.Text $y 34; $y += 40
      $null = Add-SetupText "Mise copied where every window sits. Each box is a window. Click one to leave it out." $script:fSmall $script:C.Muted $y 34; $y += 38
      $map = New-Object Windows.Forms.Panel; $map.Location = New-Object Drawing.Point($M, $y); $map.Size = New-Object Drawing.Size($cw, 190); $map.BackColor = $script:C.Panel
      [Windows.Forms.Control].GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic,Instance').SetValue($map, $true, $null)
      $map.Add_Paint({ param($s, $e) Draw-SetupMap $e.Graphics $s.ClientRectangle })
      $map.Cursor = 'Hand'
      $map.Add_MouseClick({ param($s, $e)
        foreach ($h in @($script:su.Hits)) { if ($h.R.Contains([single]$e.X, [single]$e.Y)) { $h.T.skip = -not [bool]$h.T.skip; $s.Invalidate(); break } } })
      $cp.Controls.Add($map); $y += 200
      $null = Add-SetupText 'NAME' $script:fTiny $script:C.Muted $y 16; $y += 18
      $nb = New-MiseText $M $y $cw $su.Name; $cp.Controls.Add($nb.Panel); $su.NameBox = $nb.Box; $y += 42
      $null = Add-SetupText 'You can fine-tune it any time in Edit routines.' $script:fSmall $script:C.Muted $y 20
      Add-SetupButtons @(@('Save routine', 'primary', { Save-SetupRoutine }), @('Copy again', 'tool', { Show-SetupPage 'routine' }))
    }
    'try' {
      $null = Add-SetupText 'Try it' $script:fTitle $script:C.Text $y 34; $y += 42
      $null = Add-SetupText "Move one of your windows out of place, then press Run. Mise puts it back.`r`n`r`nWhile it works, a small pop-up shows each step. This first time its list opens by itself; later, point at it to see the list. Stop is always there." $script:fStatus $script:C.Text $y 132; $y += 140
      $su.TryLbl = Add-SetupText $(if ($su.Ran) { 'Running. Watch the pop-up.' } else { '' }) $script:fSmall $script:C.Accent $y 40
      if ($su.Ran) { Add-SetupButtons @(@('Next', 'primary', { Move-SetupStep 1 }), @('Run again', 'tool', { Start-SetupRun })) }
      else { Add-SetupButtons @(@("Run $($su.Name)", 'primary', { Start-SetupRun }), @('Skip', 'ghost', { Move-SetupStep 1 })) }
    }
    'tray' {
      $null = Add-SetupText 'Mise lives near the clock' $script:fTitle $script:C.Text $y 34; $y += 42
      $null = Add-SetupText "Closing the Mise window doesn't quit Mise. Click its icon near the clock any time: your routines, accounts and Re-arrange are in its menu." $script:fStatus $script:C.Text $y 64; $y += 72
      $tb = New-Object Windows.Forms.Panel; $tb.Location = New-Object Drawing.Point($M, $y); $tb.Size = New-Object Drawing.Size($cw, 52); $tb.BackColor = [Drawing.Color]::FromArgb(20, 20, 22)
      $tb.Add_Paint({ param($s, $e)
        $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'
        $ib = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(58, 58, 64)); $g.FillRectangle($ib, ($s.Width - 196), 17, 18, 18); $g.FillRectangle($ib, ($s.Width - 166), 17, 18, 18); $ib.Dispose()
        $pen = New-Object Drawing.Pen($script:C.Accent, 2); $g.DrawEllipse($pen, ($s.Width - 145), 7, 38, 38); $pen.Dispose()
        $tb2 = New-Object Drawing.SolidBrush($script:C.Muted); $g.DrawString((Get-Date -Format 'HH:mm'), $script:fSmall, $tb2, ($s.Width - 70), 9); $g.DrawString((Get-Date -Format 'dd.MM.yyyy'), $script:fTiny, $tb2, ($s.Width - 78), 27); $tb2.Dispose()
      })
      $lg = New-Logo ($cw - 136) 10 30; $tb.Controls.Add($lg)
      $cp.Controls.Add($tb); $y += 64
      if ($su.Hotkey) { $null = Add-SetupText "Your hotkey: $($su.Hotkey) runs $($su.Name) from anywhere. Change it in Edit routines." $script:fStatus $script:C.Text $y 44; $y += 50 }
      $null = Add-SetupText 'Re-arrange puts your windows back in place without opening anything new.' $script:fStatus $script:C.Text $y 44
      Add-SetupButtons @(@('Finish', 'primary', { $script:su.Form.Close() }), @('Back', 'ghost', { Move-SetupStep -1 }))
    }
  }
  $cp.ResumeLayout(); $su.Bar.Invalidate()
}
# the welcome picture
function Draw-SetupDemo($g, $r) {
  $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'ClearTypeGridFit'
  $bg = New-Object Drawing.Drawing2D.LinearGradientBrush($r, [Drawing.Color]::FromArgb(38, 32, 28), [Drawing.Color]::FromArgb(18, 18, 20), 60.0); $g.FillRectangle($bg, $r); $bg.Dispose()
  $k = [double]$script:su.T; $k = $(if ($k -lt 0.5) { 4 * $k * $k * $k } else { 1 - [Math]::Pow(-2 * $k + 2, 3) / 2 })
  $wf = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(42, 42, 48)); $bf = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(52, 52, 59)); $tf = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(207, 205, 200))
  $pen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(68, 68, 76), 1)
  foreach ($w in $script:SetupDemo) {
    $q = @(0, 1, 2, 3 | ForEach-Object { $w.M[$_] + ($w.P[$_] - $w.M[$_]) * $k })
    $rc = New-Object Drawing.RectangleF([single]($r.X + $q[0] * $r.Width), [single]($r.Y + $q[1] * $r.Height), [single]($q[2] * $r.Width), [single]($q[3] * $r.Height))
    $g.FillRectangle($wf, $rc); $g.FillRectangle($bf, $rc.X, $rc.Y, $rc.Width, [Math]::Min(14, $rc.Height)); $g.DrawRectangle($pen, $rc.X, $rc.Y, $rc.Width, $rc.Height)
    $cb = New-Object Drawing.SolidBrush($w.C); $g.FillRectangle($cb, ($rc.X + 4), ($rc.Y + 3), 8, 8); $cb.Dispose()
    $g.DrawString($w.N, $script:fTiny, $tf, ($rc.X + 15), ($rc.Y))
  }
  $tbb = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(235, 20, 20, 22)); $g.FillRectangle($tbb, $r.X, ($r.Bottom - $r.Height * 0.09), $r.Width, ($r.Height * 0.09)); $tbb.Dispose()
  $wf.Dispose(); $bf.Dispose(); $tf.Dispose(); $pen.Dispose()
}
# the routine just copied: each screen as a box, each window inside it
function Draw-SetupMap($g, $r) {
  $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'ClearTypeGridFit'
  $lives = @(Get-LiveMonitors (Get-MiseConfig)); if (-not $lives.Count) { return }
  $minX = ($lives | ForEach-Object { $_.X } | Measure-Object -Minimum).Minimum; $minY = ($lives | ForEach-Object { $_.Y } | Measure-Object -Minimum).Minimum
  $maxX = ($lives | ForEach-Object { $_.X + $_.W } | Measure-Object -Maximum).Maximum; $maxY = ($lives | ForEach-Object { $_.Y + $_.H } | Measure-Object -Maximum).Maximum
  $pad = 14; $top = 18
  $sc = [Math]::Min(($r.Width - 2 * $pad) / [double]($maxX - $minX), ($r.Height - $pad - $top) / [double]($maxY - $minY))
  $ox = $r.X + ($r.Width - ($maxX - $minX) * $sc) / 2; $oy = $r.Y + $top
  $mf = New-Object Drawing.SolidBrush($script:C.Bg); $tf = New-Object Drawing.SolidBrush($script:C.Muted); $tl = New-Object Drawing.SolidBrush($script:C.Text)
  $tileB = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(190, 56, 56, 63)); $pen = New-Object Drawing.Pen($script:C.Line, 1); $tpen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(85, 85, 94), 1)
  $sf = New-Object Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'; $sf.Trimming = 'EllipsisCharacter'
  $offB = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(70, 40, 40, 44)); $offT = New-Object Drawing.SolidBrush($script:C.Muted); $offP = New-Object Drawing.Pen($script:C.Line, 1); $offP.DashStyle = 'Dash'
  $hits = @()
  foreach ($m in $lives) {
    $a = $m.Work
    $mr = New-Object Drawing.RectangleF([single]($ox + ($a.X - $minX) * $sc), [single]($oy + ($a.Y - $minY) * $sc), [single]($a.W * $sc), [single]($a.H * $sc))
    $g.FillRectangle($mf, $mr); $g.DrawRectangle($pen, $mr.X, $mr.Y, $mr.Width, $mr.Height)
    $g.DrawString("$($m.name)", $script:fTiny, $tf, $mr.X, ($mr.Y - 15))
    foreach ($t in @($script:su.Tiles | Where-Object { $_.monitor -eq $m.id })) {
      $tr = New-Object Drawing.RectangleF([single]($mr.X + [double]$t.rect.x * $mr.Width), [single]($mr.Y + [double]$t.rect.y * $mr.Height), [single]([double]$t.rect.w * $mr.Width), [single]([double]$t.rect.h * $mr.Height))
      if ($t.skip) { $g.FillRectangle($offB, $tr); $g.DrawRectangle($offP, $tr.X, $tr.Y, $tr.Width, $tr.Height); $g.DrawString("$($t.name) - left out", $script:fTiny, $offT, $tr, $sf) }
      else { $g.FillRectangle($tileB, $tr); $g.DrawRectangle($tpen, $tr.X, $tr.Y, $tr.Width, $tr.Height); $g.DrawString("$($t.name)", $script:fTiny, $tl, $tr, $sf) }
      $hits = @(@{ R = $tr; T = $t }) + $hits   # the one drawn last (on top) is found first
    }
  }
  $script:su.Hits = $hits
  foreach ($o in @($mf, $tf, $tl, $tileB, $pen, $tpen, $sf, $offB, $offT, $offP)) { $o.Dispose() }
}
function Update-SetupOpen {
  if (-not $script:su.OpenLbl -or $script:su.OpenLbl.IsDisposed) { return }
  try { $items = @(Get-CaptureList (Get-MiseConfig) | Where-Object { $_.Kind -ne 'league' -and $_.Proc -notin @('powershell', 'pwsh', 'conhost', 'WindowsTerminal') }) } catch { $items = @() }
  $script:su.OpenLbl.Text = $(if ($items.Count) { (@($items | ForEach-Object { $_.Name } | Select-Object -Unique) -join ',   ') } else { 'Nothing yet. Open your apps; this list updates by itself.' })
}
function Invoke-SetupCopy {
  $su = $script:su
  $items = @(Get-CaptureList (Get-MiseConfig) | Where-Object { ($su.League -or $_.Kind -ne 'league') -and $_.Proc -notin @('powershell', 'pwsh', 'conhost', 'WindowsTerminal') })
  if (-not @($items | Where-Object { $_.Kind -ne 'league' }).Count) { $su.OpenLbl.Text = 'No open windows yet. Open at least one app on your screens, then press Copy my screen again.'; $su.OpenLbl.ForeColor = $script:C.Accent; return }
  $tiles = @()
  foreach ($it in $items) {
    $t = ConvertTo-Tile $it $(if ($it.Kind -eq 'web') { 'close' } else { 'leave' }); $t | Add-Member -NotePropertyName skip -NotePropertyValue $false -Force
    if ($t.kind -eq 'web' -and $t.url -like '*u.gg*') { $t.kind = 'ugg'; $t.name = 'u.gg (opens in champ select)' }
    $tiles += $t
  }
  foreach ($mid in @($tiles | ForEach-Object { $_.monitor } | Select-Object -Unique)) { $null = Invoke-Tidy @($tiles | Where-Object { $_.monitor -eq $mid -and $_.kind -ne 'league' }) 0.03 }
  $su.Tiles = $tiles
  Show-SetupPage 'routine2'
}
function Save-SetupRoutine {
  $su = $script:su
  $n = "$($su.NameBox.Text)".Trim(); if (-not $n) { $n = 'My setup' }; $su.Name = $n
  $cfg = Get-MiseConfig
  $hk = Get-FreeHotkey $cfg ''
  $keep = @($su.Tiles | Where-Object { -not $_.skip } | Select-Object -Property * -ExcludeProperty skip)
  if (-not $keep.Count) { [void][Windows.Forms.MessageBox]::Show('Every window is left out. Click one on the map to keep it, or press Copy again.', 'Mise'); return }
  $r = [pscustomobject]@{ id = (New-Id); name = $n; hotkey = $(if ($hk) { $hk } else { '' }); league = [bool]$su.League; taskbar = @(); card = $null; tiles = @($keep) }
  $cfg.routines = @(@($cfg.routines) + $r)
  Save-MiseConfig $cfg
  $su.RoutineId = $r.id; $su.Hotkey = $r.hotkey
  Write-Log "setup: saved routine '$n' with $($keep.Count) tiles"
  Move-SetupStep 1
}
# a real run of the routine just saved; the tray shows the pop-up
function Start-SetupRun {
  $su = $script:su; if (-not $su.RoutineId) { Move-SetupStep 1; return }
  $status = Join-Path $env:TEMP 'mise-status.txt'
  Set-Content -LiteralPath $status -Value "Starting '$($su.Name)'" -Encoding UTF8
  Set-Content -LiteralPath (Join-Path $script:DataDir '_last-routine.txt') -Value $su.RoutineId
  $a = "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $script:MiseDir 'mise-run.ps1')`" -Routine `"$($su.RoutineId)`""
  $acc = @(Get-RiotAccounts) | Select-Object -First 1
  if ($su.League -and $acc) { $a += " -Account `"$acc`"" }
  $a += " -StatusFile `"$status`""
  Start-Process powershell.exe -WindowStyle Hidden -ArgumentList $a
  $su.Ran = $true; $su.Form.TopMost = $false
  Show-SetupPage 'try'
}

# ---------- one-time tips: a small note next to the thing it is about, shown once ----------
function Show-MiseHint($owner, [Drawing.Rectangle]$anchor, [string]$key, [string]$text, [bool]$modal = $false) {
  if (Test-HintSeen $key) { return }
  Set-HintSeen $key
  $W = 280
  $h = New-Object Windows.Forms.Form; $h.FormBorderStyle = 'None'; $h.ShowInTaskbar = $false; $h.StartPosition = 'Manual'; $h.TopMost = $true; $h.BackColor = $script:C.Panel
  $lb = New-Label $text $script:fSmall $script:C.Text 12 10 ($W - 24) 10; $lb.BackColor = $script:C.Panel
  $lb.Height = [int]([Windows.Forms.TextRenderer]::MeasureText($text, $script:fSmall, (New-Object Drawing.Size(($W - 24), 400)), 'WordBreak').Height + 4)
  $ok = New-Btn 'Got it' ($W - 92) ($lb.Bottom + 6) 80 28 'ghost'; $ok.Add_Click({ param($s, $e) $s.FindForm().Close() })
  $h.Controls.AddRange(@($lb, $ok))
  $h.ClientSize = New-Object Drawing.Size($W, ($ok.Bottom + 8))
  $h.Add_Paint({ param($s, $e) $pen = New-Object Drawing.Pen($script:C.Accent, 1); $e.Graphics.DrawRectangle($pen, 0, 0, $s.Width - 1, $s.Height - 1); $pen.Dispose() })
  # below the thing, else above it; always inside its screen
  $wa = [Windows.Forms.Screen]::FromRectangle($anchor).WorkingArea
  $x = [Math]::Max($wa.Left + 8, [Math]::Min($anchor.Left, $wa.Right - $h.Width - 8))
  $y = $anchor.Bottom + 8; if ($y + $h.Height -gt $wa.Bottom - 8) { $y = $anchor.Top - $h.Height - 8 }
  $h.Location = New-Object Drawing.Point($x, [Math]::Max($wa.Top + 8, $y))
  $t = New-Object Windows.Forms.Timer; $t.Interval = 15000; $t.Tag = $h; $t.Add_Tick({ param($s, $e) $s.Stop(); try { $s.Tag.Close() } catch {} }); $h.Tag = $t
  $h.Add_Shown({ param($s, $e) $s.Tag.Start() })
  $h.Add_FormClosed({ param($s, $e) try { $s.Tag.Stop(); $s.Tag.Dispose() } catch {} })
  if ($modal) { [void]$h.ShowDialog() } else { if ($owner) { $h.Owner = $owner }; $h.Show(); if ($owner) { $owner.Activate() } }
}

# ---------- a guided tour: the window dims, one part at a time stays bright, a note explains it ----------
# $stops: @{ T = title; B = text; Rect = { a scriptblock returning the part's screen rectangle, or $null to skip } }
function Show-MiseTour($form, $stops) {
  $stops = @($stops | Where-Object { $null -ne (& $_.Rect) })
  if (-not $stops.Count) { return }
  $ov = New-Object Windows.Forms.Form; $ov.FormBorderStyle = 'None'; $ov.ShowInTaskbar = $false; $ov.StartPosition = 'Manual'; $ov.BackColor = [Drawing.Color]::Black; $ov.Opacity = 0.6
  $ov.Bounds = $form.Bounds; $ov.Owner = $form
  $script:tour = @{ I = 0; Hole = [Drawing.Rectangle]::Empty }
  $ov.Add_Paint({ param($s, $e) if (-not $script:tour.Hole.IsEmpty) { $pen = New-Object Drawing.Pen($script:C.Accent, 3); $r = $script:tour.Hole; $r.Inflate(2, 2); $e.Graphics.DrawRectangle($pen, $r); $pen.Dispose() } })
  $W = 340; $M = 18
  $b = New-MiseDialog 'Edit routines' $W 220
  $cnt = New-Label '' $script:fTiny $script:C.Muted $M 54 200 16
  $hd = New-Label '' $script:fBig $script:C.Text $M 72 ($W - 2 * $M) 24
  $tx = New-Label '' $script:fSmall $script:C.Text $M 98 ($W - 2 * $M) 72
  $bN = New-Btn 'Next' ($W - $M - 90) 176 90 32 'primary'; $bB = New-Btn 'Back' ($W - $M - 188) 176 90 32; $bS = New-Btn 'Skip tour' $M 176 100 32 'ghost'
  $b.Controls.AddRange(@($cnt, $hd, $tx, $bN, $bB, $bS)); $b.ClientSize = New-Object Drawing.Size($W, 220)
  $apply = {
    $i = $script:tour.I; $st = $stops[$i]
    $r = & $st.Rect; $hole = New-Object Drawing.Rectangle(($r.X - $ov.Left - 6), ($r.Y - $ov.Top - 6), ($r.Width + 12), ($r.Height + 12))
    $script:tour.Hole = $hole
    $rg = New-Object Drawing.Region((New-Object Drawing.Rectangle(0, 0, $ov.Width, $ov.Height))); $rg.Exclude($hole)
    $ov.Region = $rg; $ov.Invalidate()
    $cnt.Text = "$($i + 1) OF $($stops.Count)"; $hd.Text = $st.T; $tx.Text = $st.B
    $bB.Visible = ($i -gt 0); $bN.Text = $(if ($i -eq $stops.Count - 1) { 'Got it' } else { 'Next' }); $bN.Invalidate()
    # the note sits below the bright part, else above it, else beside it
    $wa = [Windows.Forms.Screen]::FromRectangle($r).WorkingArea
    $x = [Math]::Max($wa.Left + 8, [Math]::Min($r.Left, $wa.Right - $b.Width - 8)); $y = $r.Bottom + 16
    if ($y + $b.Height -gt $wa.Bottom - 8) { $y = $r.Top - $b.Height - 16 }
    if ($y -lt $wa.Top + 8) { $y = [Math]::Max($wa.Top + 8, $r.Top); $x = $(if ($r.Right + 16 + $b.Width -lt $wa.Right) { $r.Right + 16 } else { [Math]::Max($wa.Left + 8, $r.Left - $b.Width - 16) }) }
    $b.Location = New-Object Drawing.Point($x, $y)
  }
  $bN.Add_Click({ if ($script:tour.I -ge $stops.Count - 1) { $b.Close() } else { $script:tour.I++; & $apply } })
  $bB.Add_Click({ if ($script:tour.I -gt 0) { $script:tour.I--; & $apply } })
  $bS.Add_Click({ $b.Close() })
  $b.StartPosition = 'Manual'
  $ov.Show()
  & $apply
  [void]$b.ShowDialog($ov)
  $ov.Close(); $ov.Dispose()
  $form.Activate()
}

# ---------- about: where the name and the icon come from ----------
# About > Replay setup: the setup again, and the tour and tips come back
function Invoke-ReplaySetup {
  foreach ($kv in @(@('tourDone', $false), @('hintsSeen', ''), @('popExplained', $false))) { $null = Set-MiseSetting $kv[0] $kv[1] }
  $null = Show-Setup
  $script:replayed = $true
}
function Show-MiseAbout {
  $W = 400; $M = 18
  $f = New-MiseDialog 'About Mise' $W 330
  $logo = New-Logo $M 56; $f.Controls.Add($logo)
  $f.Controls.Add((New-Label "Mise $($script:MiseVersion)" $script:fBig $script:C.Text 60 60 280 24))
  $txt = "The name comes from 'mise en place' - French for 'everything in its place'. Before service, cooks set out every ingredient and tool where their hands expect it, so cooking is calm and fast.`r`n`r`nThe icon is that station: three prep bowls in a row on the counter.`r`n`r`nMise does the same for your screens before you play."
  $f.Controls.Add((New-Label $txt $script:fSmall $script:C.Muted $M 100 ($W - 2 * $M) 150))
  $bIntro = New-Btn 'Replay setup' $M 262 ($W - 2 * $M) 32
  $tipA = New-Object Windows.Forms.ToolTip; $tipA.SetToolTip($bIntro, 'Runs the first-time setup again, and brings back the Edit routines tour and the one-time tips.')
  $bIntro.Add_Click({ $f.Close(); Invoke-ReplaySetup })
  $f.Controls.Add($bIntro)
  $f.ClientSize = New-Object Drawing.Size($W, 312)
  [void]$f.ShowDialog()
}
