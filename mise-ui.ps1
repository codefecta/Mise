# Mise (shared edition) - UI helpers: monitor naming, first run, account chooser, dialogs, settings, intro.
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
  $c.DropDownStyle = 'DropDownList'; $c.FlatStyle = 'Flat'; $c.BackColor = $script:C.Panel; $c.ForeColor = $script:C.Text; return $c
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
  return @(Get-ChildItem -LiteralPath $d -Filter *.yaml | Where-Object { $_.BaseName -notlike '_*' } | Sort-Object CreationTime, Name | ForEach-Object { $_.BaseName })
}

# ---------- monitor wizard: flash a number on every screen, the user names each one ----------
function Show-MonitorWizard($cfg) {
  # each screen in turn: a light tint with a copper frame and its number, and a Mise card on it to type the name
  $screens = Get-Screens
  $keys = Get-MonitorKeys
  $found = @()
  foreach ($s in $screens) {
    $o = New-Object Windows.Forms.Form
    $o.FormBorderStyle = 'None'; $o.StartPosition = 'Manual'; $o.Bounds = $s.Bounds; $o.TopMost = $true; $o.ShowInTaskbar = $false
    $o.BackColor = [Drawing.Color]::FromArgb(14, 14, 16); $o.Opacity = 0.32
    $o.Add_Paint({ param($sd, $e) $pen = New-Object Drawing.Pen($script:C.Accent, 14); $e.Graphics.DrawRectangle($pen, 7, 7, $sd.Width - 14, $sd.Height - 14); $pen.Dispose() })
    $o.Show(); $o.Refresh()
    $def = if ($s.Primary) { 'Main screen' } elseif ($s.Vertical) { 'Vertical screen' } else { "Screen $($s.Index)" }
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
  if ($accts.Count -eq 0) { [Windows.Forms.MessageBox]::Show("No League accounts are saved yet.`nOpen the editor > Riot accounts to add one.", 'Mise') | Out-Null; return $null }
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
  $x = New-Btn ([string][char]0x00D7) ($w - 48) 12 30 30 'ghost' (New-Object Drawing.Font('Segoe UI', 15)); $x.Add_Click({ param($s, $e) $s.FindForm().Close() }); $f.Controls.Add($x)
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
  $bCorner = New-Btn 'Progress pop-up' $M $y $cw 38 'setting'; $bCorner.Tag = "$(Get-MiseSetting $cfg 'toastCorner')"; $bCorner.Chip = $script:CornerNames[$bCorner.Tag]; $y += 44
  $bCorner.Add_Click({ param($s, $e) $s.Tag = Get-NextKey $script:CornerNames $s.Tag; $s.Chip = $script:CornerNames[$s.Tag]; $s.Invalidate(); $null = Set-MiseSetting 'toastCorner' $s.Tag })
  $y += 6
  $f.Controls.Add((New-Label 'MISE WINDOW' $script:fTiny $script:C.Muted $M $y 200 14)); $y += 20
  $bPos = New-Btn 'Opens at' $M $y $cw 38 'setting'; $bPos.Tag = "$(Get-MiseSetting $cfg 'homePos')"; $bPos.Chip = $script:HomePosNames[$bPos.Tag]; $y += 44
  $bPos.Add_Click({ param($s, $e) $s.Tag = Get-NextKey $script:HomePosNames $s.Tag; $s.Chip = $script:HomePosNames[$s.Tag]; $s.Invalidate(); $null = Set-MiseSetting 'homePos' $s.Tag; $script:bMonRef.Enabled = ($s.Tag -ne 'remember') })
  $mons = @(@{ id = ''; name = 'Main screen' }) + @($cfg.monitors | ForEach-Object { @{ id = $_.id; name = $_.name } })
  $script:monChoices = $mons
  $bMon = New-Btn 'On screen' $M $y $cw 38 'setting'; $script:bMonRef = $bMon
  $mi = 0; for ($k = 0; $k -lt $mons.Count; $k++) { if ($mons[$k].id -eq "$(Get-MiseSetting $cfg 'homeMonitor')") { $mi = $k } }
  $bMon.Tag = $mi; $bMon.Chip = $mons[$mi].name; $bMon.Enabled = ($bPos.Tag -ne 'remember'); $y += 44
  $bMon.Add_Click({ param($s, $e) $s.Tag = ([int]$s.Tag + 1) % $script:monChoices.Count; $s.Chip = $script:monChoices[$s.Tag].name; $s.Invalidate(); $null = Set-MiseSetting 'homeMonitor' $script:monChoices[$s.Tag].id })
  $y += 6
  $f.Controls.Add((New-Label 'UPDATES' $script:fTiny $script:C.Muted $M $y 200 14)); $y += 20
  $f.Controls.Add((New-Label 'GitHub repository (owner/name), empty = no update check' $script:fSmall $script:C.Muted $M $y $cw 18)); $y += 20
  $rt = New-MiseText $M $y ($cw - 108) "$(Get-MiseSetting $cfg 'updateRepo')"; $repo = $rt.Box
  $bChk = New-Btn 'Check now' ($M + $cw - 100) $y 100 32
  $bChk.Add_Click({ $null = Set-MiseSetting 'updateRepo' $repo.Text.Trim(); $r = Test-MiseUpdate $true; [Windows.Forms.MessageBox]::Show($r.Message, 'Mise') | Out-Null })
  $y += 44
  $f.Controls.Add((New-Label 'TROUBLESHOOTING' $script:fTiny $script:C.Muted $M $y 200 14)); $y += 20
  $hw = [int](($cw - 8) / 2)
  $bFix = New-Btn 'Fix League client' $M $y $hw 32; $bRes = New-Btn 'Reset Mise' ($M + $hw + 8) $y $hw 32; $y += 40
  $bFix.Add_Click({ $script:settingsAction = 'fix'; $f.Close() })
  $bRes.Add_Click({ $script:settingsAction = 'reset'; $f.Close() })
  $tipS = New-Object Windows.Forms.ToolTip; $tipS.SetToolTip($bRes, 'Stops everything Mise is running and starts it fresh. Routines and settings stay.')
  $bAbout = New-Btn 'About Mise' $M $y $cw 30 'ghost'; $bAbout.Add_Click({ $script:settingsAction = 'about'; $f.Close() }); $y += 38
  $done = New-Btn 'Done' $M $y $cw 36 'primary'; $done.Add_Click({ $f.Close() }); $y += 36 + 18
  $f.Controls.AddRange(@($bAnim, $bCorner, $bPos, $bMon, $rt.Panel, $bChk, $bFix, $bRes, $bAbout, $done))
  $f.ClientSize = New-Object Drawing.Size($W, $y)
  $f.Add_FormClosing({ $null = Set-MiseSetting 'updateRepo' $repo.Text.Trim() })
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

# ---------- League accounts, step by step ----------
$script:Regions = @('EUW', 'EUNE', 'TR', 'NA', 'KR', 'BR', 'LAN', 'LAS', 'OCE', 'RU', 'JP')
function Show-AccountWizard {
  $W = 420; $M = 18; $cw = $W - 2 * $M
  $f = New-MiseDialog 'Add League accounts' $W 470
  $y = 54
  $steps = "1.  Open Riot Client and log in. Tick 'Stay signed in'.`r`n2.  Do NOT sign out afterwards.`r`n3.  Type a nickname, pick the region, press Save.`r`n`r`nMise closes Riot Client, keeps the login (never the password) and reopens it on a fresh login screen, so you can add the next account the same way."
  $l = New-Label $steps $script:fSmall $script:C.Text $M $y $cw 118; $f.Controls.Add($l); $y += 124
  $bOpen = New-Btn 'Open Riot Client' $M $y $cw 34; $f.Controls.Add($bOpen); $y += 46
  $bOpen.Add_Click({ $rc = "$env:SystemDrive\Riot Games\Riot Client\RiotClientServices.exe"; if (Test-Path $rc) { Start-Process $rc } else { [Windows.Forms.MessageBox]::Show("Riot Client doesn't exist on this PC.", 'Mise') | Out-Null } })
  $f.Controls.Add((New-Label 'NICKNAME' $script:fTiny $script:C.Muted $M $y 200 14)); $f.Controls.Add((New-Label 'REGION' $script:fTiny $script:C.Muted ($M + $cw - 110) $y 110 14)); $y += 18
  $nick = New-UiBox $M $y ($cw - 120); $nick.Font = $script:fStatus
  $reg = New-UiCombo ($M + $cw - 110) $y 110; foreach ($r in $script:Regions) { [void]$reg.Items.Add($r) }; $reg.SelectedIndex = 0
  $f.Controls.AddRange(@($nick, $reg)); $y += 38
  $bSave = New-Btn 'Save this account' $M $y $cw 36 'primary'; $f.Controls.Add($bSave); $y += 46
  $msg = New-Label '' $script:fSmall $script:C.Muted $M $y $cw 40; $f.Controls.Add($msg); $y += 44
  $f.Controls.Add((New-Label 'SAVED' $script:fTiny $script:C.Muted $M $y 200 14)); $y += 18
  $list = New-Label '' $script:fSmall $script:C.Text $M $y $cw 60; $f.Controls.Add($list); $y += 66
  $fill = { $a = @(Get-RiotAccounts); $list.Text = $(if ($a.Count) { $a -join '   ' } else { 'none yet' }) }; & $fill
  $bDone = New-Btn 'Done' $M $y $cw 34; $bDone.Add_Click({ $f.Close() }); $f.Controls.Add($bDone); $y += 34 + 18
  $f.ClientSize = New-Object Drawing.Size($W, $y)
  $bSave.Add_Click({
    $n = ($nick.Text.Trim() -replace '[\\/:*?"<>|]', '').ToUpper()
    if (-not $n) { $msg.Text = 'Type a nickname first.'; return }
    $full = "$n $($reg.SelectedItem)"
    $msg.Text = "Saving $full ..."; $f.Refresh()
    $mod = Join-Path $script:MiseDir 'modules\riot-league.ps1'
    $p = Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$mod`"", '-Core', '-Save', "`"$full`"", '-Next') -WindowStyle Hidden -PassThru
    $p.WaitForExit()
    if ($p.ExitCode -eq 0) { $msg.Text = "Saved $full. Riot Client is on a fresh login screen: log in to the next account, or press Done."; $nick.Text = '' }
    else { $msg.Text = "Could not save - is Riot Client logged in?" }
    & $fill
  })
  [void]$f.ShowDialog()
}

# ---------- first run: screens, apps Mise found, a suggested layout, League accounts ----------
function Show-FirstRun($cfg) {
  # first launch: name the screens; the intro and the empty home view take it from there
  $cfg = Show-MonitorWizard $cfg
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

# ---------- intro: four short pages, once, from the Mise window ----------
$script:IntroPages = @(
  @{ T = 'Welcome to Mise'; B = "Mise opens your apps and puts every window in its place - with one click or one hotkey." },
  @{ T = 'Routines'; B = "A routine is your setup: which apps and web pages open, and where each window goes.`r`n`r`nMake one by placing your windows roughly, then Copy my screen. Fine-tune it on the map." },
  @{ T = 'League'; B = "Click an account to log in, or to switch if another account is open.`r`n`r`nA routine with League in it asks which account, then starts the client and your lobby while it arranges the rest." },
  @{ T = 'Make it yours'; B = "Settings: accent colour, animations and where this window opens.`r`n`r`nThe tray icon near the clock has your routines and accounts too." }
)
function Show-Intro {
  $W = 400; $M = 18
  $f = New-MiseDialog 'Mise' $W 250
  $script:introI = 0
  $head = New-Label '' $script:fBig $script:C.Text $M 54 ($W - 2 * $M) 26
  $body = New-Label '' $script:fSmall $script:C.Muted $M 86 ($W - 2 * $M) 100
  $dots = New-Label '' $script:fSmall $script:C.Accent $M 196 120 20
  $bSkip = New-Btn 'Skip' ($W - $M - 220) 192 100 32 'ghost'
  $bNext = New-Btn 'Next' ($W - $M - 110) 192 110 32 'primary'
  $f.Controls.AddRange(@($head, $body, $dots, $bSkip, $bNext))
  $show = {
    $p = $script:IntroPages[$script:introI]; $head.Text = $p.T; $body.Text = $p.B
    $dots.Text = (@(for ($k = 0; $k -lt $script:IntroPages.Count; $k++) { if ($k -eq $script:introI) { [string][char]0x25CF } else { [string][char]0x25CB } }) -join ' ')
    $bNext.Text = $(if ($script:introI -eq $script:IntroPages.Count - 1) { 'Start' } else { 'Next' }); $bNext.Invalidate()
  }
  & $show
  $bNext.Add_Click({ if ($script:introI -ge $script:IntroPages.Count - 1) { $f.Close() } else { $script:introI++; & $show } })
  $bSkip.Add_Click({ $f.Close() })
  [void]$f.ShowDialog()
  $null = Set-MiseSetting 'introDone' $true
}

# ---------- about: where the name and the icon come from ----------
function Show-MiseAbout {
  $W = 400; $M = 18
  $f = New-MiseDialog 'About Mise' $W 330
  $logo = New-Logo $M 56; $f.Controls.Add($logo)
  $f.Controls.Add((New-Label "Mise $($script:MiseVersion)" $script:fBig $script:C.Text 60 60 280 24))
  $txt = "The name comes from 'mise en place' - French for 'everything in its place'. Before service, cooks set out every ingredient and tool where their hands expect it, so cooking is calm and fast.`r`n`r`nThe icon is that station: three prep bowls in a row on the counter.`r`n`r`nMise does the same for your screens before you play."
  $f.Controls.Add((New-Label $txt $script:fSmall $script:C.Muted $M 100 ($W - 2 * $M) 150))
  $bIntro = New-Btn 'Show the intro again' $M 262 ($W - 2 * $M) 32
  $bIntro.Add_Click({ $f.Close(); Show-Intro })
  $f.Controls.Add($bIntro)
  $f.ClientSize = New-Object Drawing.Size($W, 312)
  [void]$f.ShowDialog()
}
