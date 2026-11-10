<#
  Mise home - the main window (desktop icon, tray > Open Mise).
  Routines and League accounts start with one click; tools, options and live progress in plain words.
  Esc closes it.
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
function Set-HomeTop { $form.TopMost = $false }   # on top only for a moment when it opens
$form.ClientSize = New-Object Drawing.Size($W, 300)
if (Test-Path $script:Icon) { try { $form.Icon = New-Object Drawing.Icon($script:Icon) } catch {} }
Set-MiseFrame $form

# ---------- header ----------
$logo = New-Logo $M 12 46
$title = New-Label 'Mise' $script:fTitle $script:C.Accent 74 11 200 30
$sub   = New-Label 'Everything in its place' $script:fSmall $script:C.Muted 76 39 240 18
$close = New-Btn ([string][char]0x00D7) ($W - $M - 30) 20 30 30 'ghost' (New-Object Drawing.Font('Segoe UI', 15))
$close.Add_Click({ $form.Close() })
$fIcon = New-Object Drawing.Font('Segoe MDL2 Assets', 11)
$btnGear = New-Btn ([string][char]0xE713) ($W - $M - 64) 22 30 30 'ghost' $fIcon
foreach ($ctl in $logo, $title, $sub) { Add-DragHandle $ctl $form }
$form.Controls.AddRange(@($logo, $title, $sub, $close, $btnGear))
$tip = New-Object Windows.Forms.ToolTip
$tip.SetToolTip($btnGear, 'Settings')

function New-Section($text) { $l = New-Label $text.ToUpper() $script:fTiny $script:C.Muted $M 0 200 14; $form.Controls.Add($l); return $l }
$secRt = New-Section 'Routines'; $secAcc = New-Section 'League accounts'; $secTools = New-Section 'Tools'; $secOpt = New-Section 'League options'
$script:optsOpen = [bool](Get-MiseSetting $script:cfg 'optsOpen')
$optCaret = New-Object MiseCaret; $optCaret.BackColor = $script:C.Bg; $optCaret.Ink = $script:C.Muted; $optCaret.Cursor = 'Hand'; $form.Controls.Add($optCaret)
$optCaret.Open = $script:optsOpen
function Show-OptsHeader { $secOpt.Text = 'LEAGUE OPTIONS'; $secOpt.AutoSize = $true; $optCaret.Open = $script:optsOpen }
$secOpt.Cursor = 'Hand'
$secOpt.Add_Click({ $script:optsOpen = -not $script:optsOpen; $script:cfg = Set-MiseSetting 'optsOpen' $script:optsOpen; Show-OptsHeader; Hide-QueueList; Do-Layout })
$optCaret.Add_Click({ $script:optsOpen = -not $script:optsOpen; $script:cfg = Set-MiseSetting 'optsOpen' $script:optsOpen; Show-OptsHeader; Hide-QueueList; Do-Layout })
Show-OptsHeader

# ---------- routines + accounts (rebuilt when the config changes) ----------
$rtPanel = New-Object Windows.Forms.Panel; $rtPanel.BackColor = $script:C.Bg; $form.Controls.Add($rtPanel)
$accPanel = New-Object Windows.Forms.Panel; $accPanel.BackColor = $script:C.Bg; $form.Controls.Add($accPanel)
$script:rtButtons = @(); $script:accButtons = @()

# right-click an account: save the current Riot session into it again, or remove it
$accMenu = New-Object Windows.Forms.ContextMenuStrip
$accMenu.BackColor = $script:C.Panel; $accMenu.ForeColor = $script:C.Text; $accMenu.ShowImageMargin = $false
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
    $b.Tag = $r.id; $b.Chip = "$($r.hotkey)"
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
      $b = New-Btn $nick 0 $y $cw 44 'row' $script:fBig; $b.Dots = $true
      $b.Tag = $n; $b.Chip = $region; $b.On = ($n -eq $active)
      $b.Sub = ('{0:N1} h this week' -f [double]$hours[$n])
      # the ... at the row's right end opens the account menu; the rest of the row logs in
      $b.Add_Click({ param($s, $e) if ($s.DotsHit($s.PointToClient([Windows.Forms.Cursor]::Position).X)) { $accMenu.Show($s, (New-Object Drawing.Point(($s.Width - 36), $s.Height))) } else { Start-Account $s.Tag } })
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
  $script:leagueOn = $lr
  Show-Tools
}

# ---------- tools ----------
$btnArr  = New-Btn 'Re-arrange'
$btnEdit = New-Btn 'Edit routines'; $btnAdd = New-Btn '+ Account'
$tools = @($btnArr, $btnEdit, $btnAdd)
$form.Controls.AddRange($tools)
$tip.SetToolTip($btnArr, 'Put the windows of your last routine back in place')
# Re-arrange names the routine it puts back; Exit shows only while a routine is running
function Show-Tools {
  $r = Get-LastRoutine
  $btnArr.Text = $(if ($r) { "Re-arrange '$($r.name)'" } else { 'Re-arrange' }); $btnArr.Enabled = [bool]$r; $btnArr.Invalidate()
  $aid = Get-ActiveRoutineId; $ar = $null
  if ($aid) { $ar = $script:cfg.routines | Where-Object { $_.id -eq $aid } | Select-Object -First 1 }
  $script:exitRoutine = $ar
  if ($ar) { $btnExitR.Text = "Exit '$($ar.name)'"; $btnExitR.Invalidate() }
}

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
  $form.TopMost = $false
  $before = Get-MiseConfig
  Show-MiseSettings
  Set-HomeTop
  $script:cfg = Get-MiseConfig
  switch ($script:settingsAction) {
    'fix'   { Start-Job2 $riot @('-Core', '-Fix') 'Fixing the League client' 'quick'; return }
    'screens' { $form.TopMost = $false; $c = Show-MonitorWizard (Get-MiseConfig); Save-MiseConfig $c; $script:cfg = $c; Set-HomeTop; return }
    'startover' { $form.TopMost = $false; if (Invoke-StartOver) { $form.Close() } else { Set-HomeTop }; return }
    'reset' { Reset-Mise; return }
    'about' { $form.TopMost = $false; Show-MiseAbout; Set-HomeTop }
    'feedback' { $form.TopMost = $false; Show-MiseFeedback; Set-HomeTop }
  }
  if ("$(Get-MiseSetting $before 'accent')" -ne "$(Get-MiseSetting $script:cfg 'accent')" -or [bool](Get-MiseSetting $before 'animations') -ne [bool](Get-MiseSetting $script:cfg 'animations')) { Update-MiseLook $script:cfg; Restart-Home }
})
$tip.SetToolTip($btnAcc, 'Accept the ready-check just before its timer ends')
$tip.SetToolTip($btnQueue, 'Click to pick a lobby')

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
# lobby after login: opens the list of lobbies
$btnQueue.Add_Click({ Show-QueueList })
$form.Add_MouseDown({ if ($qList.Visible) { Hide-QueueList } })

# ---------- footer ----------
$btnExitR = New-Btn 'Exit routine' 0 0 100 30 'ghost'
$form.Controls.Add($btnExitR)
$tip.SetToolTip($btnExitR, 'Closes or puts back the windows of the running routine and brings the taskbars back')
$script:hasAcc = $false; $script:leagueOn = $false; $script:exitRoutine = $null

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
  $cw = $W - 2 * $M; $y = 74
  $accOn = $script:hasAcc; $secAcc.Visible = $accOn; $accPanel.Visible = $accOn
  $optOn = [bool]$script:leagueOn; $secOpt.Visible = $optOn
  foreach ($b in $opts) { $b.Visible = $optOn -and $script:optsOpen }
  $exitOn = [bool]$script:exitRoutine; $btnExitR.Visible = $exitOn
  $secRt.Location = New-Object Drawing.Point($M, $y); $y += 20
  $rtPanel.Location = New-Object Drawing.Point($M, $y); $y = $rtPanel.Bottom + 16
  if ($accOn) { $secAcc.Location = New-Object Drawing.Point($M, $y); $y += 20; $accPanel.Location = New-Object Drawing.Point($M, $y); $y = $accPanel.Bottom + 16 }
  $secTools.Location = New-Object Drawing.Point($M, $y); $y += 20
  # Re-arrange '<routine>' gets a full row (the name can be long), Edit routines and + Account share the next
  $g = 8; $w2 = [int](($cw - $g) / 2)
  $btnArr.Size = New-Object Drawing.Size($cw, 34); $btnArr.Location = New-Object Drawing.Point($M, $y); $y += 34 + $g
  $btnEdit.Size = New-Object Drawing.Size($w2, 34); $btnEdit.Location = New-Object Drawing.Point($M, $y)
  $btnAdd.Size = New-Object Drawing.Size(($cw - $w2 - $g), 34); $btnAdd.Location = New-Object Drawing.Point(($M + $w2 + $g), $y)
  $y += 34 + 16
  if ($optOn) {
    $secOpt.Location = New-Object Drawing.Point($M, $y); $optCaret.Location = New-Object Drawing.Point(($M + $secOpt.PreferredWidth + 4), ($y + 1)); $y += 20
    if ($script:optsOpen) { foreach ($b in $opts) { $b.Size = New-Object Drawing.Size($cw, 38); $b.Location = New-Object Drawing.Point($M, $y); $y += 38 + 6 } } else { $y += 2 }
    $y += 4
  }
  $optCaret.Visible = $optOn
  if ($exitOn) { $btnExitR.Size = New-Object Drawing.Size($cw, 30); $btnExitR.Location = New-Object Drawing.Point($M, $y); $y += 30 + 8 }
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
function Start-Job2([string]$file, [string[]]$argList, [string]$headline, [string]$kind) {
  if ($script:proc -and -not $script:proc.HasExited) { return }
  Hide-QueueList
  Set-Content -LiteralPath $status -Value $headline -Encoding UTF8
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
$actAdd = { $form.TopMost = $false; Show-AccountWizard; Set-HomeTop; Build-Lists; Do-Layout }
$btnAdd.Add_Click($actAdd)
# Reset: stop everything Mise is running and start fresh (helper + this window)
function Reset-Mise {
  try { Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match 'mise-run\.ps1|riot-league\.ps1|mise-builder\.ps1' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } } catch {}
  foreach ($f in @($status, (Join-Path $script:DataDir '_ugg-now.txt'))) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
  Start-Sleep -Milliseconds 600
  Restart-Home
}
$btnExitR.Add_Click({ $r = $script:exitRoutine; if ($r) { Start-Job2 $run @('-Routine', "`"$($r.id)`"", '-Exit') "Exiting '$($r.name)'" 'quick' } })
$btnEdit.Add_Click({ Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -STA -ExecutionPolicy Bypass -File `"$editor`""; $form.Close() })
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
})

Show-Opts
Build-Lists
Do-Layout
Set-HomePosition
$form.Add_Shown({
  # tell the launcher's start card the window is here (it fades out as this window fades in)
  try { $ev = [Threading.EventWaitHandle]::OpenExisting('Local\MiseHomeShown'); [void]$ev.Set(); $ev.Dispose() } catch {}
  try { Write-Log ("home shown after {0} ms" -f [int]((Get-Date) - (Get-Process -Id $PID).StartTime).TotalMilliseconds) } catch {}
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
