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
try { $ua = Update-AutoMonitors $script:cfg; if ($ua.Added) { Save-MiseConfig $ua.Cfg; $script:cfg = $ua.Cfg } } catch {}
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
$sub   = New-Label 'Everything in its place' $script:fSmall $script:C.Muted 76 39 200 18   # stops before the header buttons (it used to cover the gear)
# close and settings: two drawn icons of the same size, side by side on one line
$close = New-Btn '' ($W - $M - 32) 20 32 32 'ghost'; $close.Glyph = 'close'
$close.Add_Click({ $form.Close() })
$btnGear = New-Btn '' ($W - $M - 32 - 36) 20 32 32 'ghost'; $btnGear.Glyph = 'gear'
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
# League options fold open and shut: the window grows or shrinks smoothly, the rows slide in one by one
function Switch-Opts {
  $script:optsOpen = -not $script:optsOpen; $script:cfg = Set-MiseSetting 'optsOpen' $script:optsOpen; Show-OptsHeader
  if ($script:qOpen) { $script:qOpen = $false; $script:av.q = 0.0; $qList.Visible = $false }
  if ($script:optsOpen) {
    $d = 40; foreach ($b in $opts) { $b.Visible = $true; $b.SlideIn($d); $d += 45 }
    Start-Anim 'o' 1.0 240 { if ($btnExitR.Visible) { $btnExitR.SlideIn(0) } }
  } else { Start-Anim 'o' 0.0 200 { foreach ($b in $opts) { $b.Visible = $false } } }
}
$secOpt.Add_Click({ Switch-Opts })
$optCaret.Add_Click({ Switch-Opts })
Show-OptsHeader

# ---------- routines + accounts (rebuilt when the config changes) ----------
$rtPanel = New-Object Windows.Forms.Panel; $rtPanel.BackColor = $script:C.Bg; $form.Controls.Add($rtPanel)
$accPanel = New-Object Windows.Forms.Panel; $accPanel.BackColor = $script:C.Bg; $form.Controls.Add($accPanel)
$script:rtButtons = @(); $script:accButtons = @()
$script:browser = $null; try { $script:browser = Get-DefaultBrowser } catch {}

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

# drag a routine or account row up or down to reorder it; the order is kept (tray menu and builder follow it)
$script:drag = $null; $script:dragAt = [datetime]::MinValue
# a row's Click can come before or after its MouseUp: both orders are covered
function Test-JustDragged { return (($script:drag -and $script:drag.On) -or (((Get-Date) - $script:dragAt).TotalMilliseconds -lt 400)) }
function Get-DragSlot($d) { $n = $d.List.Count; return [Math]::Max(0, [Math]::Min($n - 1, [int][Math]::Round($d.Btn.Top / 50.0))) }
function Add-RowDrag($b, [string]$kind) {
  $b.Group = $kind
  $b.Add_MouseDown({ param($s, $e)
    if ($e.Button -ne 'Left') { return }
    $list = $(if ($s.Group -eq 'rt') { @($script:rtButtons) } else { @($script:accButtons) })
    if ($list.Count -lt 2) { return }
    $script:drag = @{ Btn = $s; List = $list; Y0 = [Windows.Forms.Cursor]::Position.Y; Top0 = $s.Top; On = $false } })
  $b.Add_MouseMove({ param($s, $e)
    $d = $script:drag; if (-not $d -or -not [object]::ReferenceEquals($d.Btn, $s)) { return }
    if ($e.Button -ne 'Left') { $script:drag = $null; return }
    $dy = [Windows.Forms.Cursor]::Position.Y - $d.Y0
    if (-not $d.On) { if ([Math]::Abs($dy) -lt 8) { return }; $d.On = $true; $s.BringToFront(); $s.Cursor = [Windows.Forms.Cursors]::SizeNS }
    $s.Top = [Math]::Max(0, [Math]::Min(($d.List.Count - 1) * 50, $d.Top0 + $dy))
    $t = Get-DragSlot $d; $k = 0
    foreach ($o in $d.List) { if ([object]::ReferenceEquals($o, $s)) { continue }; if ($k -eq $t) { $k++ }; $o.Top = $k * 50; $k++ } })
  $b.Add_MouseUp({ param($s, $e)
    $d = $script:drag; $script:drag = $null
    if (-not $d -or -not $d.On) { return }
    $script:dragAt = Get-Date; $s.Cursor = [Windows.Forms.Cursors]::Default
    $t = Get-DragSlot $d
    $ids = New-Object Collections.ArrayList; foreach ($o in $d.List) { if (-not [object]::ReferenceEquals($o, $s)) { [void]$ids.Add("$($o.Tag)") } }
    $ids.Insert($t, "$($s.Tag)")
    try {
      if ($s.Group -eq 'rt') {
        $c = Get-MiseConfig; $byId = @{}; foreach ($r in $c.routines) { $byId["$($r.id)"] = $r }
        $c.routines = @($ids | ForEach-Object { $byId[$_] } | Where-Object { $_ }); Save-MiseConfig $c; $script:cfg = $c
      } else { $script:cfg = Set-MiseSetting 'accountOrder' @($ids) }
    } catch {}
    Build-Lists; Do-Layout })
}

# per account: its own lobby and a routine that starts with it (submenus of the ... menu, rebuilt each time it opens)
$miLobby = New-Object Windows.Forms.ToolStripMenuItem('Lobby for this account')
$miRout = New-Object Windows.Forms.ToolStripMenuItem('Routine for this account')
[void]$accMenu.Items.Add('-'); [void]$accMenu.Items.Add($miLobby); [void]$accMenu.Items.Add($miRout)
foreach ($dd in @($miLobby.DropDown, $miRout.DropDown)) { $dd.BackColor = $script:C.Panel; $dd.ForeColor = $script:C.Text; try { $dd.ShowImageMargin = $false } catch {} }
$script:accMenuFor = ''
function Add-PrefItem($parent, [string]$text, [bool]$on, [string]$key, $value) {
  $it = New-Object Windows.Forms.ToolStripMenuItem($(if ($on) { [string][char]0x2713 + '  ' + $text } else { '     ' + $text }))
  $it.ForeColor = $(if ($on) { $script:C.Accent } else { $script:C.Text }); $it.Tag = @{ Key = $key; Value = $value }
  $it.Add_Click({ param($s, $e) if ($script:accMenuFor) { $script:cfg = Set-AccountPref $script:accMenuFor $s.Tag.Key $s.Tag.Value; Build-Lists; Do-Layout } })
  [void]$parent.DropDownItems.Add($it)
}
$accMenu.Add_Opening({
  $n = ''; try { $n = "$($accMenu.SourceControl.Tag)" } catch {}
  $script:accMenuFor = $n; $miLobby.DropDownItems.Clear(); $miRout.DropDownItems.Clear()
  if (-not $n) { return }
  $p = Get-AccountPref $script:cfg $n
  $own = ($p -and $null -ne $p.queue -and "$($p.queue)" -ne '')
  Add-PrefItem $miLobby 'Same as Lobby after login' (-not $own) 'queue' $null
  foreach ($qq in $script:QueueList) { Add-PrefItem $miLobby "$($qq.Name)" ($own -and [int]$p.queue -eq [int]$qq.Id) 'queue' ([int]$qq.Id) }
  $rid = $(if ($p) { "$($p.routine)" } else { '' }); if ($rid -and -not ($script:cfg.routines | Where-Object { $_.id -eq $rid })) { $rid = '' }
  Add-PrefItem $miRout 'None' (-not $rid) 'routine' ''
  foreach ($r in $script:cfg.routines) { Add-PrefItem $miRout "$($r.name)" ($rid -eq "$($r.id)") 'routine' "$($r.id)" }
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
    # small icons of the apps this routine opens (one per app, in tile order)
    try {
      $ics = New-Object Collections.ArrayList; $seen = @{}
      foreach ($t in @($r.tiles)) { if (-not $t -or "$($t.kind)" -eq 'mise') { continue }; $ic = Get-TileIcon $t $script:browser; if ($ic -and -not $seen.ContainsKey($ic.GetHashCode())) { $seen[$ic.GetHashCode()] = 1; [void]$ics.Add($ic) } }
      if ($ics.Count) { $b.Icons = [Drawing.Image[]]@($ics) }
    } catch {}
    $b.Add_Click({ param($s, $e) if (Test-JustDragged) { return }; $script:closeDelay = 240; Start-Routine $s.Tag '' })
    Add-RowDrag $b 'rt'
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
      # an account with its own lobby or routine says so on its row
      $pf = Get-AccountPref $script:cfg $n; $own = @()
      if ($pf -and $null -ne $pf.queue -and "$($pf.queue)" -ne '') { $qn2 = ($script:QueueList | Where-Object { $_.Id -eq [int]$pf.queue } | Select-Object -First 1).Name; if ([int]$pf.queue -eq 0 -and -not $qn2) { $qn2 = 'No lobby' }; if ($qn2) { $own += $qn2 } }
      $ar2 = Get-AccountRoutine $script:cfg $n; if ($ar2) { $own += "$($ar2.name)" }
      if ($own.Count) { $b.Sub = ($own -join ' + ') }
      # the ... at the row's right end opens the account menu; the rest of the row logs in
      $b.Add_Click({ param($s, $e) if (Test-JustDragged) { return }; if ($s.DotsHit($s.PointToClient([Windows.Forms.Cursor]::Position).X)) { $accMenu.Show($s, (New-Object Drawing.Point(($s.Width - 36), $s.Height))) } else { Show-AccountGlide $s; Start-Account $s.Tag } })
      $b.ContextMenuStrip = $accMenu
      Add-RowDrag $b 'acc'
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
$btnAutoX = New-Btn 'Exit routine when League closes' 0 0 100 38 'setting'; $btnAutoX.IsSwitch = $true
$opts = @($btnAcc, $btnQueue, $btnUggA, $btnAutoX)
$form.Controls.AddRange($opts)
function Show-Opts {
  $btnAcc.On = [bool](Get-MiseSetting $script:cfg 'autoAccept'); $btnUggA.On = [bool](Get-MiseSetting $script:cfg 'champPage'); $btnAutoX.On = [bool](Get-MiseSetting $script:cfg 'autoExit')
  $q = [int](Get-MiseSetting $script:cfg 'queue'); $qn = ($script:QueueList | Where-Object { $_.Id -eq $q } | Select-Object -First 1).Name
  $btnQueue.Chip = $(if ($qn) { $qn } else { "Queue $q" })
  foreach ($b in $opts) { $b.Invalidate() }
}
$btnAcc.Add_Click({ $script:cfg = Set-MiseSetting 'autoAccept' (-not [bool](Get-MiseSetting $script:cfg 'autoAccept')); Show-Opts })
$btnAutoX.Add_Click({ $script:cfg = Set-MiseSetting 'autoExit' (-not [bool](Get-MiseSetting $script:cfg 'autoExit')); Show-Opts })
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
    'uninstall' { $form.TopMost = $false; if (Invoke-MiseUninstall) { $form.Close() } else { Set-HomeTop }; return }
    'about' { $form.TopMost = $false; Show-MiseAbout; Set-HomeTop }
    'feedback' { $form.TopMost = $false; Show-MiseFeedback; Set-HomeTop }
  }
  if ("$(Get-MiseSetting $before 'accent')" -ne "$(Get-MiseSetting $script:cfg 'accent')" -or "$(Get-MiseSetting $before 'theme')" -ne "$(Get-MiseSetting $script:cfg 'theme')" -or [bool](Get-MiseSetting $before 'animations') -ne [bool](Get-MiseSetting $script:cfg 'animations')) { Update-MiseLook $script:cfg; Restart-Home }
})
$tip.SetToolTip($btnAcc, 'Accept the ready-check just before its timer ends')
$tip.SetToolTip($btnQueue, 'Click to pick a lobby')
$tip.SetToolTip($btnAutoX, 'When the League client has been closed for about a minute, the running routine exits by itself')

# lobby picker: a short list that slides down inside the window under its row (mouse wheel scrolls), one choice
$qList = New-Object MiseList; $qList.Visible = $false; $qList.BackColor = $(if ($script:C.Glass) { [Drawing.Color]::Transparent } else { $script:C.Bg })
$qList.Fill = $(if ($script:C.Glass) { [Drawing.Color]::FromArgb(22, 255, 255, 255) } else { $script:C.Panel }); $qList.LineC = $script:C.GLine; $qList.HoverC = $script:C.GHover
if (-not $script:C.Glass) { $qList.LineC = $script:C.Line; $qList.HoverC = $script:C.Hover }
$qList.TextC = $script:C.Text; $qList.MutedC = $script:C.Muted; $qList.Accent = $script:C.Accent; $qList.RowFont = $script:fBtn; $qList.NoteFont = $script:fSmall
$qRow = 32; $qShow = 5; $script:qVis = [Math]::Min($script:QueueList.Count, $qShow) * $qRow + 8
$script:qOpen = $false
function Hide-QueueList { if (-not $script:qOpen) { return }; $script:qOpen = $false; Start-Anim 'q' 0.0 170 { $qList.Visible = $false } }
function Show-QueueList {
  if ($script:qOpen) { Hide-QueueList; return }
  $cur = [int](Get-MiseSetting $script:cfg 'queue')
  $routesNo = @(); try { $rf = Join-Path $store '_routes.json'; if (Test-Path $rf) { $routesNo = @((Get-Content -LiteralPath $rf -Raw | ConvertFrom-Json).no | ForEach-Object { [int]$_ }) } } catch {}
  $qList.Names = [string[]]@($script:QueueList | ForEach-Object { "$($_.Name)" })
  $qList.Notes = [string[]]@($script:QueueList | ForEach-Object { if ($routesNo -contains $_.Id) { 'not available' } else { '' } })
  $qList.Chosen = -1; for ($i = 0; $i -lt $script:QueueList.Count; $i++) { if ($script:QueueList[$i].Id -eq $cur) { $qList.Chosen = $i } }
  $qList.Width = $btnQueue.Width; $qList.Height = $script:qVis; $qList.ScrollTo([Math]::Max(0, $qList.Chosen))
  $script:qOpen = $true; $qList.Visible = $true; $qList.BringToFront()
  Start-Anim 'q' 1.0 220
}
$qList.Add_Click({ $i = $qList.Picked; if ($i -ge 0 -and $i -lt $script:QueueList.Count) { $script:cfg = Set-MiseSetting 'queue' ([int]$script:QueueList[$i].Id); $qList.Chosen = $i; $qList.Invalidate(); Show-Opts; Hide-QueueList } })
$form.Controls.Add($qList)
# lobby after login: opens the list of lobbies
$btnQueue.Add_Click({ Show-QueueList })
$form.Add_MouseDown({ Hide-QueueList })

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
  # grown past the bottom of its screen (lobby list opened low on the screen): slide up so everything stays visible
  if ($form.Visible) { try { $wa = [Windows.Forms.Screen]::FromControl($form).WorkingArea; if ($form.Bottom -gt $wa.Bottom - 4) { $form.Top = [Math]::Max($wa.Top + 4, $wa.Bottom - 4 - $form.Height) } } catch {} }
}
# a value eased over a few frames (dropdowns sliding open and shut); the layout is redone each frame
$script:av = @{ q = 0.0; o = $(if ($script:optsOpen) { 1.0 } else { 0.0 }) }; $script:anims = @{}
$animTimer = New-Object Windows.Forms.Timer; $animTimer.Interval = 15
$animTimer.Add_Tick({
  $done = @()
  foreach ($k in @($script:anims.Keys)) {
    $a = $script:anims[$k]; $t = [Math]::Min(1.0, $a.Clock.ElapsedMilliseconds / [double]$a.Dur); $e = 1 - [Math]::Pow(1 - $t, 3)
    $script:av[$k] = $a.From + ($a.To - $a.From) * $e
    if ($t -ge 1.0) { $done += $k }
  }
  Do-Layout
  foreach ($k in $done) { $a = $script:anims[$k]; $script:anims.Remove($k); if ($a.Done) { & $a.Done } }
  if (-not $script:anims.Count) { $animTimer.Stop(); Do-Layout }
})
function Start-Anim([string]$name, [double]$to, [int]$dur, [scriptblock]$done = $null) {
  if (-not $script:Animate) { $script:av[$name] = $to; $script:anims.Remove($name); Do-Layout; if ($done) { & $done }; return }
  $script:anims[$name] = @{ From = [double]$script:av[$name]; To = $to; Dur = $dur; Clock = [Diagnostics.Stopwatch]::StartNew(); Done = $done }
  if (-not $animTimer.Enabled) { $animTimer.Start() }
}
function Do-Layout {
  $cw = $W - 2 * $M; $y = 74
  $accOn = $script:hasAcc; $secAcc.Visible = $accOn; $accPanel.Visible = $accOn
  $optOn = [bool]$script:leagueOn; $secOpt.Visible = $optOn
  $ok = [double]$script:av.o; $optAnim = $script:anims.ContainsKey('o')
  foreach ($b in $opts) { $b.Visible = $optOn -and ($script:optsOpen -or $optAnim) }
  $exitOn = [bool]$script:exitRoutine; $btnExitR.Visible = $exitOn -and -not $optAnim
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
    # the rows sit at their places; the window's bottom edge (and what follows) moves with the fold
    $y0 = $y; $qk = [double]$script:av.q
    foreach ($b in $opts) {
      $b.Size = New-Object Drawing.Size($cw, 38); $b.Location = New-Object Drawing.Point($M, $y); $y += 38 + 6
      if ($qk -gt 0.001 -and [object]::ReferenceEquals($b, $btnQueue)) {
        $qh = [int][Math]::Round($script:qVis * $qk); $qList.Bounds = New-Object Drawing.Rectangle($M, ($y - 2), $cw, [Math]::Max(1, $qh)); $y += $qh + [int](4 * $qk)
      }
    }
    $y = $y0 + [int][Math]::Round(($y - $y0) * $ok) + [int](2 * (1 - $ok))
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
  if ($script:proc -and -not $script:proc.HasExited) { $script:closeDelay = 0; return }
  Hide-QueueList
  Set-Content -LiteralPath $status -Value $headline -Encoding UTF8
  $psi = New-Object Diagnostics.ProcessStartInfo('powershell.exe')
  $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$file`" $($argList -join ' ') -StatusFile `"$status`""
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $script:proc = [Diagnostics.Process]::Start($psi)
  # one progress display: the small pop-up (tray), placed where the routine's Mise tile is. The window steps away
  # (a moment later when a row's motion is still playing: the ripple, or the account frame gliding over)
  $dl = [int]$script:closeDelay; $script:closeDelay = 0
  if ($dl -gt 0 -and $script:Animate) { $ct = New-Object Windows.Forms.Timer; $ct.Interval = $dl; $ct.Add_Tick({ param($s, $e) $s.Stop(); $form.Close() }); $ct.Start() } else { $form.Close() }
}
$script:closeDelay = 0
# an account click: a light sweep over it, the copper frame glides from the old account to this one, "switching..." on its row
function Show-AccountGlide($b) {
  try {
    $rows = [MiseBtn[]]@($script:accButtons); $to = [Array]::IndexOf($rows, $b); $from = -1
    for ($i = 0; $i -lt $rows.Count; $i++) { if ($rows[$i].On) { $from = $i } }
    if ($from -eq $to) { return }
    $b.Sweep(); $b.Sub = 'switching...'; $b.Invalidate()
    [MiseGlide]::Run($accPanel, $rows, $from, $to)
    $script:closeDelay = 700
  } catch {}
}
function Start-Account([string]$n) {
  # the account's own routine (if it has one): a League routine does the login itself; any other routine starts next to the switch
  $ar = Get-AccountRoutine $script:cfg $n
  if ($ar -and $ar.league) { Start-Routine $ar.id $n; return }
  if ($ar) {
    Set-Content -LiteralPath (Join-Path $script:DataDir '_last-routine.txt') -Value $ar.id
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$run`"", '-Routine', "`"$($ar.id)`"")
  }
  Start-Job2 $riot @('-Core', '-Account', "`"$n`"", '-Queue', "$(Get-AccountQueue $script:cfg $n)") "Switching to $n" 'run'
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
  if ($k -eq 'Escape') { if ($script:qOpen) { Hide-QueueList } else { $form.Close() }; return }
})

Show-Opts
Build-Lists
Do-Layout
Set-HomePosition
# opening: the bowls drop onto the counter (unless the start card just did that), then the rows slide in top to bottom
$form.Add_Load({ $card = $false; try { $ev = [Threading.EventWaitHandle]::OpenExisting('Local\MiseHomeShown'); $ev.Dispose(); $card = $true } catch {}
  Start-RowsIn $(if ($card) { $null } else { $logo }) (@($script:rtButtons) + @($script:accButtons) + @($btnArr, $btnEdit, $btnAdd) + @($opts) + @($btnExitR)) })
$form.Add_Shown({
  # tell the launcher's start card the window is here (it fades out as this window fades in)
  try { $ev = [Threading.EventWaitHandle]::OpenExisting('Local\MiseHomeShown'); [void]$ev.Set(); $ev.Dispose() } catch {}
  try { Write-Log ("home shown after {0} ms" -f [int]((Get-Date) - (Get-Process -Id $PID).StartTime).TotalMilliseconds) } catch {}
  $form.Activate(); Start-OpenAnimation $form
  Set-HomeTop   # on top only to come to the front when opened
  # after an update: what is new, once (a first install gets the intro instead)
  if ("$(Get-MiseSetting $script:cfg 'lastSeenVersion')" -ne $script:MiseVersion) {
    $wasIntro = [bool](Get-MiseSetting $script:cfg 'introDone')
    $script:cfg = Set-MiseSetting 'lastSeenVersion' $script:MiseVersion
    if ($wasIntro -and @($script:WhatsNew).Count) {
      $wt = New-Object Windows.Forms.Timer; $wt.Interval = 500
      $wt.Add_Tick({ param($s, $e) $s.Stop(); $form.TopMost = $false; Show-WhatsNew; Set-HomeTop })
      $wt.Start()
    }
  }
  if (-not [bool](Get-MiseSetting $script:cfg 'introDone')) {
    $it = New-Object Windows.Forms.Timer; $it.Interval = 500
    $it.Add_Tick({ param($s, $e) $s.Stop(); $form.TopMost = $false; Show-Intro; Set-HomeTop; $script:cfg = Get-MiseConfig })
    $it.Start()
  }
})
[void]$form.ShowDialog()
if (-not $script:restarting) { try { $mutex.ReleaseMutex() } catch {} }
