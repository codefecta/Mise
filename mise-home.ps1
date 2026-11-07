<#
  Mise home - the main window (desktop icon, tray > Open Mise).
  Routines and League accounts start with one click; tools, options and live progress in plain words.
  Keys: 1-9 start a routine, A arrange, F fix client, Esc close.
#>
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'mise-ui.ps1')
# every start writes a short log (errors included) to %APPDATA%\Mise\home.log
try { Start-Transcript -Path (Join-Path $script:DataDir 'home.log') -Force | Out-Null } catch {}
trap { try { Add-Content -LiteralPath (Join-Path $script:DataDir 'home-error.log') -Value ("{0}  {1}  line {2}: {3}" -f (Get-Date -Format s), $_.Exception.Message, $_.InvocationInfo.ScriptLineNumber, $_.InvocationInfo.Line.Trim()) } catch {}; continue }

$first = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\MiseHome', [ref]$first)
if (-not $first) { exit }

# the tray helper does hotkeys, auto-accept, the u.gg page and play time: start it if it is not running
$trayUp = $false
try { $m = [Threading.Mutex]::OpenExisting('Local\MiseTray'); $m.Dispose(); $trayUp = $true } catch {}
if (-not $trayUp) { Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -STA -ExecutionPolicy Bypass -File `"$(Join-Path $script:MiseDir 'mise-tray.ps1')`"" }

$selfPath = $PSCommandPath
$run    = Join-Path $script:MiseDir 'mise-run.ps1'
$riot   = Join-Path $script:MiseDir 'modules\riot-league.ps1'
$editor = Join-Path $script:MiseDir 'mise-builder.ps1'
$status = Join-Path $env:TEMP 'mise-status.txt'
$store  = Join-Path $env:USERPROFILE 'LeagueAccounts'
$script:cfg = Get-MiseConfig
if (-not $script:cfg.firstRunDone) { $script:cfg = Show-FirstRun $script:cfg }
$W = 380; $M = 18

$form = New-Object Windows.Forms.Form
$form.Text = 'Mise'; $form.StartPosition = 'Manual'; $form.TopMost = $true; $form.KeyPreview = $true
function Set-HomeTop { $form.TopMost = [bool]$script:card }   # on top only while it shows a run
$form.ClientSize = New-Object Drawing.Size($W, 300)
if (Test-Path $script:Icon) { try { $form.Icon = New-Object Drawing.Icon($script:Icon) } catch {} }
Set-MiseFrame $form

# ---------- header ----------
$logo = New-Logo $M 18
$title = New-Label 'Mise' $script:fTitle $script:C.Accent 58 12 200 30
$sub   = New-Label 'Everything in its place' $script:fSmall $script:C.Muted 60 38 240 18
$close = New-Btn ([string][char]0x00D7) ($W - $M - 30) 16 30 30 'ghost' (New-Object Drawing.Font('Segoe UI', 15))
$close.Add_Click({ $form.Close() })
$fIcon = New-Object Drawing.Font('Segoe MDL2 Assets', 11)
$btnGear = New-Btn ([string][char]0xE713) ($W - $M - 64) 16 30 30 'ghost' $fIcon
$btnMoreT = New-Btn ([string][char]0xE712) ($W - $M - 98) 16 30 30 'ghost' $fIcon
foreach ($ctl in $logo, $title, $sub) { Add-DragHandle $ctl $form }
$form.Controls.AddRange(@($logo, $title, $sub, $close, $btnGear, $btnMoreT))
$tip = New-Object Windows.Forms.ToolTip
$tip.SetToolTip($btnGear, 'Settings')
$tip.SetToolTip($btnMoreT, 'u.gg page')

function New-Section($text) { $l = New-Label $text.ToUpper() $script:fTiny $script:C.Muted $M 0 200 14; $form.Controls.Add($l); return $l }
$secRt = New-Section 'Routines'; $secAcc = New-Section 'League accounts'; $secTools = New-Section 'Tools'; $secOpt = New-Section 'Options'
$script:optsOpen = [bool](Get-MiseSetting $script:cfg 'optsOpen')
function Show-OptsHeader { $secOpt.Text = 'OPTIONS  ' + $(if ($script:optsOpen) { [string][char]0x25BE } else { [string][char]0x25B8 }) }
$secOpt.Cursor = 'Hand'
$secOpt.Add_Click({ $script:optsOpen = -not $script:optsOpen; $script:cfg = Set-MiseSetting 'optsOpen' $script:optsOpen; Show-OptsHeader; Hide-QueueList; Do-Layout })
Show-OptsHeader

# ---------- routines + accounts (rebuilt when the config changes) ----------
$rtPanel = New-Object Windows.Forms.Panel; $rtPanel.BackColor = $script:C.Bg; $form.Controls.Add($rtPanel)
$accPanel = New-Object Windows.Forms.Panel; $accPanel.BackColor = $script:C.Bg; $form.Controls.Add($accPanel)
$script:rtButtons = @(); $script:accButtons = @()

# right-click an account: save the current Riot session into it again, or remove it
$accMenu = New-Object Windows.Forms.ContextMenuStrip
$miUpd = $accMenu.Items.Add('Update saved login from the current session')
$miUpd.Add_Click({ $n = $accMenu.SourceControl.Tag; if ($n) { Start-Job2 $riot @('-Core', '-Save', "`"$n`"") "Saving the current login as $n" 'quick' } })
$miRem = $accMenu.Items.Add('Remove this account')
$miRem.Add_Click({
  $n = $accMenu.SourceControl.Tag
  if ($n -and [Windows.Forms.MessageBox]::Show("Remove '$n' from Mise?", 'Mise', 'YesNo', 'Question') -eq 'Yes') { Remove-Item -LiteralPath (Join-Path $store "$n.yaml") -ErrorAction SilentlyContinue; Build-Lists; Do-Layout }
})

# the builder opens on a new routine; the Mise window steps away while you build
function New-RoutineFromHome {
  Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -STA -ExecutionPolicy Bypass -File `"$editor`" -New"
  $form.Close()
}
function Get-WeekHours {
  $h = @{}; $f = Join-Path $store 'playtime.csv'
  if (-not (Test-Path $f)) { return $h }
  $from = (Get-Date).Date.AddDays(-7)
  try { foreach ($r in (Import-Csv -LiteralPath $f)) { try { if ([datetime]$r.start -ge $from) { $h[$r.account] = [double]$h[$r.account] + [double]$r.seconds / 3600 } } catch {} } } catch {}
  return $h
}
function Build-Lists {
  $cw = $W - 2 * $M
  $rtPanel.Controls.Clear(); $script:rtButtons = @(); $y = 0; $i = 0
  $lastId = ''; $lf = Join-Path $script:DataDir '_last-routine.txt'; if (Test-Path $lf) { $lastId = (Get-Content -LiteralPath $lf -Raw).Trim() }
  foreach ($r in $script:cfg.routines) {
    $i++
    $b = New-Btn $r.name 0 $y $cw 44 'row' $script:fBig
    $b.Num = "$i"; $b.Tag = $r.id; $b.Chip = "$($r.hotkey)"
    if ($r.id -eq $lastId) { $b.Sub = 'last' }
    $b.Add_Click({ param($s, $e) Start-Routine $s.Tag '' })
    $rtPanel.Controls.Add($b); $script:rtButtons += $b; $y += 44 + 6
  }
  if ($i -eq 0) {
    $card = New-EmptyCard 'No routines yet. A routine opens your apps and puts every window in its place.' 'Make a routine' { New-RoutineFromHome } $cw
    $rtPanel.Controls.Add($card); $y = $card.Height + 6
  }
  $rtPanel.Size = New-Object Drawing.Size($cw, [Math]::Max(0, $y - 6))

  $accPanel.Controls.Clear(); $script:accButtons = @(); $y = 0
  $names = @(Get-RiotAccounts)
  $lr = ($names.Count -gt 0) -or (Test-RiotInstalled)   # the accounts section shows when League is on this PC
  $active = ''; $af = Join-Path $store '_active.txt'; if (Test-Path $af) { $active = (Get-Content -LiteralPath $af -Raw).Trim() }
  $hours = Get-WeekHours
  if ($lr -and $names.Count) {
    $i = 0
    foreach ($n in $names) {
      $i++
      $parts = $n.Trim() -split '\s+'; $region = $parts[-1].ToUpper(); $nick = if ($parts.Count -gt 1) { ($parts[0..($parts.Count - 2)] -join ' ') } else { $n }
      $b = New-Btn $nick 0 $y $cw 44 'row' $script:fBig
      $b.Tag = $n; $b.Chip = $region; $b.On = ($n -eq $active)
      $b.Sub = ('{0:N1} h this week' -f [double]$hours[$n])
      $b.Add_Click({ param($s, $e) Start-Account $s.Tag })
      $b.ContextMenuStrip = $accMenu
      $accPanel.Controls.Add($b); $script:accButtons += $b; $y += 44 + 6
    }
  }
  if ($lr -and -not $names.Count) {
    $card = New-EmptyCard 'No League accounts yet. Save one and it logs in with one click.' 'Add your first account' { $form.TopMost = $false; Show-AccountWizard; Set-HomeTop; Build-Lists; Do-Layout } $cw
    $accPanel.Controls.Add($card); $y = $card.Height + 6
  }
  $accPanel.Size = New-Object Drawing.Size($cw, [Math]::Max(0, $y - 6))
  $script:hasAcc = ($y -gt 0)
}

# ---------- tools ----------
$btnArr  = New-Btn 'Arrange'; $btnFix = New-Btn 'Fix client'; $btnUgg = New-Btn 'u.gg page'
$btnEdit = New-Btn 'Routines'; $btnAdd = New-Btn '+ Account'
$tools = @($btnArr, $btnEdit, $btnAdd)
$form.Controls.AddRange($tools)
$tip.SetToolTip($btnArr, 'Put the windows of your last routine back in place')

# ---------- options ----------
$btnAcc   = New-Btn 'Auto-accept match' 0 0 100 38 'setting'; $btnAcc.IsSwitch = $true
$btnQueue = New-Btn 'Lobby after login' 0 0 100 38 'setting'
$btnUggA  = New-Btn 'Open u.gg for my champion' 0 0 100 38 'setting'; $btnUggA.IsSwitch = $true
$opts = @($btnAcc, $btnQueue, $btnUggA)
$form.Controls.AddRange($opts)
function Show-Opts {
  $btnAcc.On = [bool](Get-MiseSetting $script:cfg 'autoAccept'); $btnUggA.On = [bool](Get-MiseSetting $script:cfg 'champPage')
  $q = [int](Get-MiseSetting $script:cfg 'queue'); $qn = ($script:QueueList | Where-Object { $_.Id -eq $q } | Select-Object -First 1).Name
  $btnQueue.Chip = $(if ($qn) { $qn } else { "Queue $q" })
  foreach ($b in $opts) { $b.Invalidate() }
}
$btnAcc.Add_Click({ $script:cfg = Set-MiseSetting 'autoAccept' (-not [bool](Get-MiseSetting $script:cfg 'autoAccept')); Show-Opts })
$btnUggA.Add_Click({ $script:cfg = Set-MiseSetting 'champPage' (-not [bool](Get-MiseSetting $script:cfg 'champPage')); Show-Opts })
# gear: settings (look, quiet mode, pop-up, window spot, updates, troubleshooting, about)
$btnGear.Add_Click({
  Hide-Drop; $form.TopMost = $false
  $before = Get-MiseConfig
  Show-MiseSettings
  Set-HomeTop
  $script:cfg = Get-MiseConfig
  switch ($script:settingsAction) {
    'fix'   { Start-Job2 $riot @('-Core', '-Fix') 'Checking the client' 'quick'; return }
    'reset' { Reset-Mise; return }
    'about' { $form.TopMost = $false; Show-MiseAbout; Set-HomeTop }
  }
  if ("$(Get-MiseSetting $before 'accent')" -ne "$(Get-MiseSetting $script:cfg 'accent')" -or [bool](Get-MiseSetting $before 'animations') -ne [bool](Get-MiseSetting $script:cfg 'animations')) { Update-MiseLook $script:cfg; Restart-Home }
})
$tip.SetToolTip($btnAcc, 'Accept the ready-check just before its timer ends')
$tip.SetToolTip($btnQueue, 'Click to change')

# lobby picker: a short scroll list that drops down inside the window (mouse wheel scrolls), one choice
$qList = New-Object Windows.Forms.Panel; $qList.BackColor = $script:C.Panel; $qList.Visible = $false
$qInner = New-Object Windows.Forms.Panel; $qInner.BackColor = $script:C.Panel; $qList.Controls.Add($qInner)
$qBar = New-Object Windows.Forms.Panel; $qBar.BackColor = $script:C.Accent; $qBar.Width = 3; $qList.Controls.Add($qBar)
$qRow = 34; $qShow = 5; $script:qVis = 0
function Move-QueueList($dy) {
  $max = [Math]::Max(0, $qInner.Height - $qList.Height)
  $y = [Math]::Min(0, [Math]::Max(-$max, $qInner.Top + $dy)); $qInner.Top = $y
  if ($max -gt 0) { $qBar.Visible = $true; $bh = [Math]::Max(24, [int]($qList.Height * $qList.Height / $qInner.Height)); $qBar.Height = $bh; $qBar.Top = [int]((-$y / $max) * ($qList.Height - $bh)) } else { $qBar.Visible = $false }
}
$qGrow = New-Object Windows.Forms.Timer; $qGrow.Interval = 15
$qGrow.Add_Tick({ $d = $script:qVis - $qList.Height; if ($d -le 2) { $qList.Height = $script:qVis; $qGrow.Stop(); Move-QueueList 0 } else { $qList.Height = $qList.Height + [int][Math]::Ceiling($d * 0.3) } })
function Hide-QueueList { $qGrow.Stop(); $qList.Visible = $false }
function Show-QueueList {
  if ($qList.Visible) { Hide-QueueList; return }
  $cur = [int](Get-MiseSetting $script:cfg 'queue')
  $routesNo = @(); try { $rf = Join-Path $store '_routes.json'; if (Test-Path $rf) { $routesNo = @((Get-Content -LiteralPath $rf -Raw | ConvertFrom-Json).no | ForEach-Object { [int]$_ }) } } catch {}
  $cw = $btnQueue.Width; $qInner.Controls.Clear(); $y = 0
  foreach ($qq in $script:QueueList) {
    $r = New-Btn $qq.Name 0 $y ($cw - 6) $qRow 'row'; $r.BackColor = $script:C.Panel; $r.Surface = $script:C.Panel
    $r.Tag = $qq.Id; $r.On = ($qq.Id -eq $cur)
    if ($routesNo -contains $qq.Id) { $r.Sub = 'not available' }
    $r.Add_Click({ param($s, $e) $script:cfg = Set-MiseSetting 'queue' ([int]$s.Tag); Show-Opts; Hide-QueueList })
    $r.Add_MouseWheel({ param($s, $e) Move-QueueList ([int]($e.Delta / 120) * $qRow) })
    $qInner.Controls.Add($r); $y += $qRow
  }
  $qInner.Size = New-Object Drawing.Size($cw, $y); $qInner.Top = 0
  $script:qVis = [Math]::Min($script:QueueList.Count, $qShow) * $qRow
  $top = $btnQueue.Bottom + 4
  if ($top + $script:qVis -gt $form.ClientSize.Height - 6) { $top = $btnQueue.Top - $script:qVis - 4 }
  $qBar.Left = $cw - 4
  $qList.Bounds = New-Object Drawing.Rectangle($btnQueue.Left, $top, $cw, $(if ($script:Animate) { 4 } else { $script:qVis }))
  $qList.BringToFront(); $qList.Visible = $true
  for ($i = 0; $i -lt $script:QueueList.Count; $i++) { if ($script:QueueList[$i].Id -eq $cur) { Move-QueueList (-([Math]::Max(0, $i - 2) * $qRow)); break } }
  if ($script:Animate) { $qGrow.Start() } else { Move-QueueList 0 }
}
$qList.Add_MouseWheel({ param($s, $e) Move-QueueList ([int]($e.Delta / 120) * $qRow) })
$form.Controls.Add($qList)
# lobby after login: each click steps to the next lobby (lobbies the last test found closed are skipped)
$btnQueue.Add_Click({
  $cur = [int](Get-MiseSetting $script:cfg 'queue')
  $no = @(); try { $rf = Join-Path $store '_routes.json'; if (Test-Path $rf) { $no = @((Get-Content -LiteralPath $rf -Raw | ConvertFrom-Json).no | ForEach-Object { [int]$_ }) } } catch {}
  $ids = @($script:QueueList | ForEach-Object { $_.Id } | Where-Object { $no -notcontains $_ })
  $i = [Array]::IndexOf($ids, $cur)
  $script:cfg = Set-MiseSetting 'queue' $ids[($i + 1) % $ids.Count]; Show-Opts
})
$form.Add_MouseDown({ if ($qList.Visible) { Hide-QueueList } })

# ---------- footer + status ----------
$btnExitR = New-Btn 'Exit routine' 0 0 100 30 'ghost'
$btnStop  = New-Btn 'Stop' 0 0 100 34 'primary'; $btnStop.Visible = $false
$form.Controls.AddRange(@($btnExitR, $btnStop))
$tip.SetToolTip($btnExitR, 'Closes or puts back the windows of your last routine and brings the taskbars back')
$statusPanel = New-Object Windows.Forms.Panel; $statusPanel.BackColor = $script:C.Panel; $statusPanel.Visible = $false
$statusPanel.Padding = New-Object Windows.Forms.Padding(12, 10, 12, 10)
$statusBox = New-Object Windows.Forms.TextBox; $statusBox.Multiline = $true; $statusBox.ReadOnly = $true; $statusBox.BorderStyle = 'None'
$statusBox.BackColor = $script:C.Panel; $statusBox.ForeColor = $script:C.Text; $statusBox.Font = $script:fStatus; $statusBox.Dock = 'Fill'; $statusBox.TabStop = $false
$statusPanel.Controls.Add($statusBox); $form.Controls.Add($statusPanel)

# ---------- run card: progress bar ----------
$script:card = $false; $script:hasAcc = $false
$pTrack = New-Object Windows.Forms.Panel; $pTrack.BackColor = $script:C.Line; $pTrack.Visible = $false
$pFill = New-Object Windows.Forms.Panel; $pFill.BackColor = $script:C.Accent; $pFill.Width = 0; $pFill.Dock = 'Left'
$pTrack.Controls.Add($pFill); $form.Controls.Add($pTrack)
function Set-Progress($frac) { $pFill.Width = [int]([Math]::Max(0, [Math]::Min(1, $frac)) * $pTrack.Width) }

# ---------- small menu under the ... icon (less used tools) ----------
$drop = New-Object Windows.Forms.Panel; $drop.BackColor = $script:C.Panel; $drop.Visible = $false; $form.Controls.Add($drop)
function Hide-Drop { $drop.Visible = $false }
function Show-Drop($anchor, $items) {
  if ($drop.Visible) { Hide-Drop; return }
  Hide-QueueList
  $drop.Controls.Clear(); $dw = 210; $y = 4
  foreach ($it in $items) {
    $b = New-Btn $it.Text 4 $y ($dw - 8) 32; $b.Surface = $script:C.Panel; $b.Tag = $it.Act
    $b.Add_Click({ param($s, $e) $a = $s.Tag; Hide-Drop; & $a })
    $drop.Controls.Add($b); $y += 36
  }
  $drop.Bounds = New-Object Drawing.Rectangle(($anchor.Right - $dw), ($anchor.Bottom + 4), $dw, ($y + 2))
  $drop.BringToFront(); $drop.Visible = $true
}
$form.Add_MouseDown({ if ($drop.Visible) { Hide-Drop } })

# ---------- layout (window grows and shrinks smoothly) ----------
$script:hTarget = 0
$hTimer = New-Object Windows.Forms.Timer; $hTimer.Interval = 15
$hTimer.Add_Tick({
  $cur = $form.ClientSize.Height; $d = $script:hTarget - $cur
  if ([Math]::Abs($d) -le 2) { $form.ClientSize = New-Object Drawing.Size($W, $script:hTarget); $hTimer.Stop() }
  else { $form.ClientSize = New-Object Drawing.Size($W, ($cur + [int][Math]::Ceiling([Math]::Abs($d) * 0.28) * [Math]::Sign($d))) }
})
function Set-FormHeight($h) {
  if ($script:hTarget -eq $h) { return }
  $firstSet = ($script:hTarget -eq 0); $script:hTarget = $h
  $form.ClientSize = New-Object Drawing.Size($W, $h)   # instant: resizing a window frame by frame looks choppy
}
function Do-Layout {
  $cw = $W - 2 * $M; $y = 70
  $card = [bool]$script:card
  foreach ($c in @($secRt, $rtPanel, $secTools, $secOpt) + $tools) { $c.Visible = -not $card }
  $accOn = (-not $card) -and $script:hasAcc; $secAcc.Visible = $accOn; $accPanel.Visible = $accOn
  foreach ($b in $opts) { $b.Visible = (-not $card) -and $script:optsOpen }
  $btnExitR.Visible = -not $card
  if ($card) {
    $pTrack.Bounds = New-Object Drawing.Rectangle($M, $y, $cw, 4); $pTrack.Visible = $true; $y += 14
    $statusPanel.Size = New-Object Drawing.Size($cw, 150); $statusPanel.Location = New-Object Drawing.Point($M, $y); $y += 150 + 10
    $btnStop.Size = New-Object Drawing.Size($cw, 34); $btnStop.Location = New-Object Drawing.Point($M, $y); $y += 34 + 8
    Set-FormHeight ($y + 6); return
  }
  $pTrack.Visible = $false
  $secRt.Location = New-Object Drawing.Point($M, $y); $y += 20
  $rtPanel.Location = New-Object Drawing.Point($M, $y); $y = $rtPanel.Bottom + 16
  if ($accOn) { $secAcc.Location = New-Object Drawing.Point($M, $y); $y += 20; $accPanel.Location = New-Object Drawing.Point($M, $y); $y = $accPanel.Bottom + 16 }
  $secTools.Location = New-Object Drawing.Point($M, $y); $y += 20
  $g = 8; $w2 = [int](($cw - 2 * $g) / 3)
  $x = $M; foreach ($b in @($btnArr, $btnEdit, $btnAdd)) { $b.Size = New-Object Drawing.Size($w2, 34); $b.Location = New-Object Drawing.Point($x, $y); $x += $w2 + $g }
  $y += 34 + 16
  $secOpt.Location = New-Object Drawing.Point($M, $y); $y += 20
  if ($script:optsOpen) { foreach ($b in $opts) { $b.Size = New-Object Drawing.Size($cw, 38); $b.Location = New-Object Drawing.Point($M, $y); $y += 38 + 6 } } else { $y += 2 }
  $y += 4
  $btnExitR.Size = New-Object Drawing.Size($cw, 30); $btnExitR.Location = New-Object Drawing.Point($M, $y); $y += 30 + 8
  Set-FormHeight ($y + 6)
}

# ---------- where the window opens: a preset spot, or where it was last dragged ----------
function Get-HomeScreen {
  $mid = "$(Get-MiseSetting $script:cfg 'homeMonitor')"
  if ($mid) { $s = Resolve-Monitor $script:cfg $mid; if ($s) { return $s.WorkingArea } }
  return [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
}
function Set-HomePosition {
  $mode = "$(Get-MiseSetting $script:cfg 'homePos')"
  $fw = $form.Width; $fh = $form.Height
  if ($mode -eq 'remember') {
    $x = [int](Get-MiseSetting $script:cfg 'homeX'); $y = [int](Get-MiseSetting $script:cfg 'homeY')
    $onScreen = $false
    foreach ($s in [Windows.Forms.Screen]::AllScreens) { if ($s.WorkingArea.Contains((New-Object Drawing.Point(($x + 40), ($y + 20))))) { $onScreen = $true } }
    if ($x -ge -30000 -and $onScreen) { $form.Location = New-Object Drawing.Point($x, $y); return }
    $mode = 'center'
  }
  $a = Get-HomeScreen; $p = 16
  switch ($mode) {
    'top-left'     { $x = $a.X + $p; $y = $a.Y + $p }
    'top-center'   { $x = $a.X + [int](($a.Width - $fw) / 2); $y = $a.Y + $p }
    'top-right'    { $x = $a.Right - $fw - $p; $y = $a.Y + $p }
    'bottom-left'  { $x = $a.X + $p; $y = $a.Bottom - $fh - $p }
    'bottom-right' { $x = $a.Right - $fw - $p; $y = $a.Bottom - $fh - $p }
    default        { $x = $a.X + [int](($a.Width - $fw) / 2); $y = $a.Y + [int](($a.Height - $fh) / 3) }
  }
  $form.Location = New-Object Drawing.Point($x, $y)
}
$form.Add_FormClosing({
  if ("$(Get-MiseSetting $script:cfg 'homePos')" -eq 'remember') {
    try { $c = Get-MiseConfig; $c.settings.homeX = $form.Left; $c.settings.homeY = $form.Top; Save-MiseConfig $c } catch {}
  }
})

# ---------- running things in the background, progress in plain words ----------
$script:proc = $null; $script:kind = ''
$timer = New-Object Windows.Forms.Timer; $timer.Interval = 400
# a game starting closes the window: it must never sit over the game
$gameWatch = New-Object Windows.Forms.Timer; $gameWatch.Interval = 2000
# step away when a game starts (only a new one: opening Mise mid-game keeps it open)
$script:inGame = [bool](Get-Process -Name 'League of Legends' -ErrorAction SilentlyContinue)
$gameWatch.Add_Tick({
  $now = [bool](Get-Process -Name 'League of Legends' -ErrorAction SilentlyContinue)
  if ($now -and -not $script:inGame -and (-not $script:proc -or $script:proc.HasExited)) { $gameWatch.Stop(); $form.Close() }
  $script:inGame = $now
})
$gameWatch.Start()
$closer = New-Object Windows.Forms.Timer; $closer.Interval = 2500
$closer.Add_Tick({ $closer.Stop(); try { Set-Content -LiteralPath $status -Value '' } catch {}; $form.Close() })   # cleared: the tray pop-up must not repeat what the window just showed
function Set-Busy($busy) {
  foreach ($b in ($script:rtButtons + $script:accButtons + $tools + $opts + @($btnExitR, $btnGear, $btnMoreT))) { $b.Enabled = -not $busy }
  $script:logoSpeed = $(if ($busy) { 0.24 } else { 0.07 })
  $btnStop.Visible = $busy
  if ($busy) { $script:card = $true; $btnStop.Text = 'Stop'; $btnStop.Invalidate(); Set-Progress 0.04 }
  Do-Layout
}
$backer = New-Object Windows.Forms.Timer; $backer.Interval = 2500
$backer.Add_Tick({ $backer.Stop(); if ($script:card -and $btnStop.Text -eq 'Back') { Leave-Card } })
function Show-Finished { $btnStop.Text = 'Back'; $btnStop.Visible = $true; $btnStop.Enabled = $true; $btnStop.Invalidate(); Do-Layout }
function Leave-Card { $script:card = $false; $btnStop.Visible = $false; $statusPanel.Visible = $false; Set-HomeTop; Build-Lists; Do-Layout }
function Read-Status {
  if (-not (Test-Path $status)) { return '' }
  try { $fs = [IO.File]::Open($status, 'Open', 'Read', 'ReadWrite'); $sr = New-Object IO.StreamReader($fs); $t = $sr.ReadToEnd(); $sr.Close(); return $t } catch { return $null }
}
function Start-Job2([string]$file, [string[]]$argList, [string]$headline, [string]$kind) {
  if ($script:proc -and -not $script:proc.HasExited) { return }
  Hide-QueueList
  Set-Content -LiteralPath $status -Value $headline -Encoding UTF8
  $statusBox.Text = $headline; $statusPanel.Visible = $true
  $script:kind = $kind; Set-Busy $true
  $form.TopMost = $true   # the run card stays visible over the apps the routine opens
  $psi = New-Object Diagnostics.ProcessStartInfo('powershell.exe')
  $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$file`" $($argList -join ' ') -StatusFile `"$status`""
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $script:proc = [Diagnostics.Process]::Start($psi)
  # one progress display: the small pop-up (tray), placed where the routine's Mise tile is. The window steps away.
  $form.Close()
}
function Start-Account([string]$n) {
  Start-Job2 $riot @('-Core', '-Account', "`"$n`"", '-Queue', "$([int](Get-MiseSetting $script:cfg 'queue'))") "Switching to $n" 'run'
}
function Start-Routine([string]$id, [string]$account) {
  $r = $script:cfg.routines | Where-Object { $_.id -eq $id } | Select-Object -First 1; if (-not $r) { return }
  if (-not $account -and $r.league) {
    $account = Show-AccountChooser; if (-not $account) { return }
  }
  Set-Content -LiteralPath (Join-Path $script:DataDir '_last-routine.txt') -Value $r.id
  $a = @('-Routine', "`"$($r.id)`""); if ($account) { $a += @('-Account', "`"$account`"") }
  Start-Job2 $run $a "Starting '$($r.name)'" 'run'
}
function Get-LastRoutine {
  $f = Join-Path $script:DataDir '_last-routine.txt'; $id = ''
  if (Test-Path $f) { $id = (Get-Content -LiteralPath $f -Raw).Trim() }
  $r = $script:cfg.routines | Where-Object { $_.id -eq $id } | Select-Object -First 1
  if (-not $r) { $r = $script:cfg.routines | Select-Object -First 1 }
  return $r
}
$btnArr.Add_Click({ $r = Get-LastRoutine; if ($r) { Start-Job2 $run @('-Routine', "`"$($r.id)`"", '-Arrange') "Arranging '$($r.name)'" 'quick' } })
$actUgg = { Set-Content -LiteralPath (Join-Path $script:DataDir '_ugg-now.txt') -Value 'go' }
$actAdd = { $form.TopMost = $false; Show-AccountWizard; Set-HomeTop; Build-Lists; Do-Layout }
$btnMoreT.Add_Click({ Show-Drop $btnMoreT @(@{ Text = 'u.gg page'; Act = $actUgg }) })
$btnAdd.Add_Click($actAdd)
# Reset: stop everything Mise is running and start fresh (helper + this window)
function Reset-Mise {
  try { Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match 'mise-run\.ps1|riot-league\.ps1|mise-builder\.ps1' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } } catch {}
  foreach ($f in @($status, (Join-Path $script:DataDir '_ugg-now.txt'))) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
  Start-Sleep -Milliseconds 600
  Restart-Home
}
$btnExitR.Add_Click({ $r = Get-LastRoutine; if ($r) { Start-Job2 $run @('-Routine', "`"$($r.id)`"", '-Exit') "Exiting '$($r.name)'" 'quick' } })
$btnEdit.Add_Click({ Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -STA -ExecutionPolicy Bypass -File `"$editor`""; $form.Close() })
$btnStop.Add_Click({
  if ($btnStop.Text -eq 'Back') { $backer.Stop(); $closer.Stop(); Leave-Card; return }
  if ($script:proc -and -not $script:proc.HasExited) {
    try { Get-CimInstance Win32_Process -Filter "ParentProcessId=$($script:proc.Id)" | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } } catch {}
    try { $script:proc.Kill() } catch {}
  }
  Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*riot-league.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  $timer.Stop(); $statusBox.AppendText("`r`n`r`nStopped."); Set-Busy $false; Show-Finished; Set-HomeTop
})
$timer.Add_Tick({
  $t = Read-Status
  if ($t -ne $null) {
    $lines = @($t -split "`r?`n" | Where-Object { $_ -ne '' }); $fr = Get-Friendly $lines
    $statusBox.Text = Format-Friendly $fr; $statusBox.SelectionStart = $statusBox.Text.Length; $statusBox.ScrollToCaret()
    Set-Progress $(if ($fr.Done) { 1 } else { 1 - 1 / (1 + 0.3 * $fr.Steps.Count) })
  }
  if ($script:proc.HasExited) {
    $timer.Stop()
    if ($script:proc.ExitCode -eq 0) { Set-Progress 1 }
    # done: show the result for a moment, then step away to the tray (Back keeps the window open)
    if ($script:proc.ExitCode -eq 0) { Set-Busy $false; Show-Finished; $closer.Start() }
    else { $statusBox.AppendText("`r`n`r`nSomething needs a look. Try Fix League client (gear icon)."); Set-Busy $false; Show-Finished; Set-HomeTop; $form.Activate() }
  }
})

# reopen after the look changed (accent / animations)
function Restart-Home {
  $c = Get-MiseConfig; $c.settings.homeX = $form.Left; $c.settings.homeY = $form.Top; Save-MiseConfig $c
  $mutex.ReleaseMutex(); $script:restarting = $true
  Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -STA -ExecutionPolicy Bypass -File `"$selfPath`""
  $form.Close()
}

# ---------- keys ----------
$form.Add_KeyDown({
  $k = $_.KeyCode.ToString()
  if ($k -eq 'Escape') { if ($qList.Visible) { Hide-QueueList } else { $form.Close() }; return }
  if ($script:proc -and -not $script:proc.HasExited) { return }
  if ($k -match '^(D|NumPad)([1-9])$') { $i = [int]$Matches[2] - 1; if ($i -lt $script:rtButtons.Count) { $script:rtButtons[$i].PerformClick() } }
  elseif ($k -eq 'A') { $btnArr.PerformClick() }
})

Show-Opts
Build-Lists
Do-Layout
Set-HomePosition
$form.Add_Shown({
  $form.Activate(); Start-OpenAnimation $form
  Set-HomeTop   # on top only to come to the front when opened
  if (-not [bool](Get-MiseSetting $script:cfg 'introDone')) {
    $it = New-Object Windows.Forms.Timer; $it.Interval = 500
    $it.Add_Tick({ param($s, $e) $s.Stop(); $form.TopMost = $false; Show-Intro; Set-HomeTop; $script:cfg = Get-MiseConfig })
    $it.Start()
  }
})
[void]$form.ShowDialog()
if (-not $script:restarting) { try { $mutex.ReleaseMutex() } catch {} }
