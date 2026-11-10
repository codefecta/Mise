<# Mise tray: lives near the clock. Left- or right-click = menu (Open Mise, routines, quick account switch, Restart Mise ...).
   Registers each routine's hotkey, shows a small progress pop-up while a routine runs, runs the League helpers
   (auto-accept, u.gg page of your champion), logs League play time and checks for updates once a day. #>
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'mise-ui.ps1')
# every start writes a short log (errors included) to %APPDATA%\Mise\tray.log
try { Start-Transcript -Path (Join-Path $script:DataDir 'tray.log') -Force | Out-Null } catch {}
trap { try { Add-Content -LiteralPath (Join-Path $script:DataDir 'tray-error.log') -Value ("{0}  {1}  line {2}: {3}" -f (Get-Date -Format s), $_.Exception.Message, $_.InvocationInfo.ScriptLineNumber, $_.InvocationInfo.Line.Trim()) } catch {}; continue }
$first = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\MiseTray', [ref]$first)
if (-not $first) { exit }
# an update downloaded earlier installs now, before anything starts (the installer restarts the tray)
try { if (Start-PendingUpdate) { $mutex.ReleaseMutex(); exit } } catch {}

Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public class MiseHotkeyForm : Form {
  public event Action<int> Pressed;
  [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr h, int id, uint m, uint vk);
  [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr h, int id);
  protected override void WndProc(ref Message m) { if (m.Msg == 0x0312 && Pressed != null) Pressed(m.WParam.ToInt32()); base.WndProc(ref m); }
  protected override void SetVisibleCore(bool v) { base.SetVisibleCore(false); }
}
'@

$run    = Join-Path $script:MiseDir 'mise-run.ps1'
$editor = Join-Path $script:MiseDir 'mise-builder.ps1'
$homeUi = Join-Path $script:MiseDir 'mise-home.ps1'
$store  = Join-Path $env:USERPROFILE 'LeagueAccounts'
$status = Join-Path $env:TEMP 'mise-status.txt'
$script:cfg = Get-MiseConfig
$script:cfgStamp = if (Test-Path $script:CfgPath) { (Get-Item $script:CfgPath).LastWriteTime } else { [datetime]::MinValue }
$script:hkMap = @{}
$script:lastRoutine = $null

$hk = New-Object MiseHotkeyForm
[void]$hk.Handle

$script:runProc = $null
# one run at a time: a second hotkey press while a routine is starting does nothing
function Test-RunBusy {
  if ($script:runProc -and -not $script:runProc.HasExited) { $ni.ShowBalloonTip(3000, 'Mise', 'Mise is still working on the last run.', 'Info'); return $true }
  return $false
}
function Start-RoutineById([string]$id, [string]$account = '') {
  $r = $script:cfg.routines | Where-Object { $_.id -eq $id } | Select-Object -First 1
  if (-not $r) { return }
  if (Test-RunBusy) { return }
  if (-not $account -and $r.league) {
    $account = Show-AccountChooser; if (-not $account) { return }
  }
  Set-Content -LiteralPath $status -Value "Starting '$($r.name)'" -Encoding UTF8
  $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$run`"", '-Routine', "`"$id`"", '-StatusFile', "`"$status`"")
  if ($account) { $a += @('-Account', "`"$account`"") }
  $script:runProc = Start-Process powershell.exe -ArgumentList $a -WindowStyle Hidden -PassThru
  $script:lastRoutine = $id
}
# account switch from the tray: logs in, or switches if another account is open - nothing else
function Start-AccountSwitch([string]$n) {
  if (Test-RunBusy) { return }
  $mod = Join-Path $script:MiseDir 'modules\riot-league.ps1'
  Set-Content -LiteralPath $status -Value "Switching to $n" -Encoding UTF8
  $script:runProc = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$mod`"", '-Core', '-Account', "`"$n`"", '-Queue', "$([int](Get-MiseSetting $script:cfg 'queue'))", '-StatusFile', "`"$status`"")
}
function Stop-RoutineById([string]$id) {
  $r = $script:cfg.routines | Where-Object { $_.id -eq $id } | Select-Object -First 1; if (-not $r) { return }
  Set-Content -LiteralPath $status -Value "Exiting '$($r.name)'" -Encoding UTF8
  Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$run`"", '-Routine', "`"$id`"", '-Exit', '-StatusFile', "`"$status`"")
}

# ---------- hotkeys ----------
function Register-Hotkeys {
  foreach ($id in @($script:hkMap.Keys)) { [void][MiseHotkeyForm]::UnregisterHotKey($hk.Handle, $id) }
  $script:hkMap = @{}; $n = 100; $failed = @()
  foreach ($r in $script:cfg.routines) {
    $h = ConvertTo-Hotkey $r.hotkey; if (-not $h) { continue }
    $n++
    if ([MiseHotkeyForm]::RegisterHotKey($hk.Handle, $n, [uint32]($h.Mods -bor 0x4000), [uint32]$h.Vk)) { $script:hkMap[$n] = $r.id } else { $failed += "$($r.hotkey) ($($r.name))" }   # 0x4000 = no auto-repeat
  }
  if ($failed.Count) { $ni.ShowBalloonTip(6000, 'Mise', "Hotkey already in use: $($failed -join ', '). Change it in Edit routines.", 'Warning') }
}
$hk.Add_Pressed({ param($id) if ($script:hkMap.ContainsKey($id)) { Start-RoutineById $script:hkMap[$id] } })

# ---------- tray ----------
$ni = New-Object Windows.Forms.NotifyIcon
try { $ni.Icon = New-Object Drawing.Icon($script:Icon) } catch { $ni.Icon = [Drawing.SystemIcons]::Application }
$ni.Text = 'Mise'
$cm = New-Object Windows.Forms.ContextMenuStrip; $ni.ContextMenuStrip = $cm
$cm.BackColor = $script:C.Panel; $cm.ForeColor = $script:C.Text

function Stop-AllMise { try { Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match 'mise-run|riot-league|mise-home|mise-builder|mise-ui' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } } catch {} }
# Mise.exe plays the start animation; without it (no compiler at install) the window opens directly
function Open-Home {
  $exe = Join-Path $script:MiseDir 'Mise.exe'
  if (Test-Path -LiteralPath $exe) { Start-Process -FilePath $exe; return }
  Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', "`"$homeUi`"")
}
# Restart: stop everything Mise is running, clear stale progress, start a fresh helper and the Mise window
function Reset-Mise {
  $timer.Stop(); $lcuTimer.Stop(); $toastTimer.Stop()
  try {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match 'mise-run\.ps1|riot-league\.ps1|mise-home\.ps1|mise-builder\.ps1' } |
      ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  } catch {}
  foreach ($f in @($status, (Join-Path $script:DataDir '_ugg-now.txt'))) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
  $cmd = "Start-Sleep -Seconds 2; Start-Process powershell.exe -WindowStyle Hidden -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -File ' + [char]34 + '$homeUi' + [char]34)"
  $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
  Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $enc"
  $ni.Visible = $false; [Windows.Forms.Application]::Exit()
}
# Stop: ends the routine or account switch that is running now (the stream watcher keeps going)
function Stop-MiseRun {
  try {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match 'mise-run\.ps1|riot-league\.ps1' -and $_.CommandLine -notmatch '-StreamWatch' } |
      ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  } catch {}
  $script:runActive = $false; $bStopT.Visible = $false
  try { Set-Content -LiteralPath $status -Value '' } catch {}
  $tBody.Text = 'Stopped.'; $script:toastUntil = (Get-Date).AddSeconds(3)
}
$script:runActive = $false
$script:update = $null
function Build-TrayMenu {
  $cm.Items.Clear()
  $o = $cm.Items.Add('Open Mise'); $o.Font = New-Object Drawing.Font($o.Font, [Drawing.FontStyle]::Bold); $o.Add_Click({ Open-Home })
  if ($script:update) { $u = $cm.Items.Add("Update to Mise $($script:update.Version)"); $u.Add_Click({ try { Install-MiseUpdate $script:update } catch { $ni.ShowBalloonTip(6000, 'Mise', "Update failed: $($_.Exception.Message)", 'Warning') } }) }
  # the running routine (if any): exit it; a start or switch in progress: stop it
  $act = Get-ActiveRoutineId; $ar = if ($act) { $script:cfg.routines | Where-Object { $_.id -eq $act } | Select-Object -First 1 } else { $null }
  if ($ar -or $script:runActive) { [void]$cm.Items.Add('-') }
  if ($ar) { $x = $cm.Items.Add("Exit '$($ar.name)'"); $x.Font = New-Object Drawing.Font($x.Font, [Drawing.FontStyle]::Bold); $x.Tag = $ar.id; $x.Add_Click({ Stop-RoutineById $this.Tag }) }
  if ($script:runActive) { $st = $cm.Items.Add('Stop'); $st.Add_Click({ Stop-MiseRun }) }
  if (@($script:cfg.routines).Count) {
    [void]$cm.Items.Add('-')
    foreach ($r in $script:cfg.routines) {
      $it = $cm.Items.Add($(if ($r.hotkey) { "$($r.name)    $($r.hotkey)" } else { $r.name })); $it.Tag = $r.id
      $it.Add_Click({ Start-RoutineById $this.Tag })
    }
  }
  $accts = @(Get-RiotAccounts)
  if ($accts.Count) {
    [void]$cm.Items.Add('-')
    foreach ($n in $accts) { $it = $cm.Items.Add("Switch to $n"); $it.Tag = $n; $it.Add_Click({ Start-AccountSwitch $this.Tag }) }
  }
  if ($accts.Count -or (Test-RiotInstalled)) {
    [void]$cm.Items.Add('-')
    $mA = New-Object Windows.Forms.ToolStripMenuItem('League: auto-accept match'); $mA.Checked = (Get-Setting 'autoAccept'); $mA.Add_Click({ Set-Setting 'autoAccept' (-not (Get-Setting 'autoAccept')) }); [void]$cm.Items.Add($mA)
    $mU = New-Object Windows.Forms.ToolStripMenuItem('League: open u.gg for my champion'); $mU.Checked = (Get-Setting 'champPage'); $mU.Add_Click({ Set-Setting 'champPage' (-not (Get-Setting 'champPage')) }); [void]$cm.Items.Add($mU)
  }
  [void]$cm.Items.Add('-')
  $e = $cm.Items.Add('Edit routines'); $e.Add_Click({ Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', "`"$editor`"") })
  $rs = $cm.Items.Add('Restart Mise'); $rs.Add_Click({ Reset-Mise })
  if ($script:FeedbackForm) { $fb = $cm.Items.Add('Send feedback'); $fb.Add_Click({ Show-MiseFeedback }) }
  $q = $cm.Items.Add('Quit Mise'); $q.Add_Click({ Stop-AllMise; try { $null = Show-AllTaskbars } catch {}; $timer.Stop(); $lcuTimer.Stop(); $toastTimer.Stop(); $ni.Visible = $false; [Windows.Forms.Application]::Exit() })
}
$cm.Add_Opening({ $script:cfg = Get-MiseConfig; Build-TrayMenu })
# single click shows the menu after the double-click window passes; a double click opens the Mise window
$dcTimer = New-Object Windows.Forms.Timer; $dcTimer.Interval = [Windows.Forms.SystemInformation]::DoubleClickTime + 40
$dcTimer.Add_Tick({ $dcTimer.Stop(); $script:cfg = Get-MiseConfig; Build-TrayMenu
  $mi = [Windows.Forms.NotifyIcon].GetMethod('ShowContextMenu', [Reflection.BindingFlags]'NonPublic,Instance'); $mi.Invoke($ni, $null) })
$ni.Add_MouseClick({ if ($_.Button -eq 'Left') { $dcTimer.Stop(); $dcTimer.Start() } })
$ni.Add_DoubleClick({ $dcTimer.Stop(); Open-Home })
$ni.Visible = $true

# ---------- small info box (only while a routine starts or exits) ----------
$toast = New-Object Windows.Forms.Form
$toast.FormBorderStyle = 'None'; $toast.ShowInTaskbar = $false; $toast.TopMost = $true; $toast.StartPosition = 'Manual'
$toast.BackColor = $script:C.Bg; $toast.Size = New-Object Drawing.Size(320, 96); $toast.Opacity = 0.95
$toast.Add_Paint({ $p = New-Object Drawing.Pen($script:C.Line); $_.Graphics.DrawRectangle($p, 0, 0, $toast.Width - 1, $toast.Height - 1) })
$tHead = New-UiLabel '' 12 8 296 20; $tHead.ForeColor = $script:C.Accent; $tHead.Font = $script:fBig
$tBody = New-UiLabel '' 12 34 296 58
$tHead.Width = 236
$bStopT = New-Btn 'Stop' 256 8 54 24 'ghost'; $bStopT.Visible = $false; $bStopT.Add_Click({ Stop-MiseRun })
$toast.Controls.AddRange(@($tHead, $tBody, $bStopT))
Add-Type -Namespace MiseT -Name Native -MemberDefinition '[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int c);'
$script:toastUntil = [datetime]::MinValue
$toastTimer = New-Object Windows.Forms.Timer; $toastTimer.Interval = 700
function Test-HomeOpen { try { $m = [Threading.Mutex]::OpenExisting('Local\MiseHome'); $m.Dispose(); return $true } catch { return $false } }
function Get-ToastSpot([string]$head = '') {
  # the routine's Mise tile decides where the pop-up shows; without one, the corner from Settings
  if ($head -match "^(Starting|Exiting|Arranging) '(.+)'$") {
    $r = $script:cfg.routines | Where-Object { $_.name -eq $Matches[2] } | Select-Object -First 1
    if ($r -and $r.card -and $r.card.monitor) {
      $live = @(Get-LiveMonitors $script:cfg) | Where-Object { $_.id -eq $r.card.monitor } | Select-Object -First 1
      if ($live) { $px = ConvertTo-PxRect (Get-TileArea $live $r) $r.card.rect; return New-Object Drawing.Point([int]$px.X, [int]$px.Y) }
    }
  }
  $wa = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea; $p = 16
  switch ("$(Get-MiseSetting $script:cfg 'toastCorner')") {
    'top-left'     { return New-Object Drawing.Point(($wa.Left + $p), ($wa.Top + $p)) }
    'top-right'    { return New-Object Drawing.Point(($wa.Right - $toast.Width - $p), ($wa.Top + $p)) }
    'bottom-right' { return New-Object Drawing.Point(($wa.Right - $toast.Width - $p), ($wa.Bottom - $toast.Height - $p)) }
    default        { return New-Object Drawing.Point(($wa.Left + $p), ($wa.Bottom - $toast.Height - $p)) }
  }
}
$toastTimer.Add_Tick({
  try {
    if ($script:toastUntil -ne [datetime]::MinValue -and (Get-Date) -gt $script:toastUntil) { $toast.Hide(); $script:toastUntil = [datetime]::MinValue; $script:runActive = $false; $bStopT.Visible = $false }
    if (-not (Test-Path $status)) { return }
    $fi = Get-Item -LiteralPath $status
    $lines = @(); try { $fs = [IO.File]::Open($status, 'Open', 'Read', 'ReadWrite'); $sr = New-Object IO.StreamReader($fs); $lines = @($sr.ReadToEnd() -split "`r?`n" | Where-Object { $_.Trim() -ne '' }); $sr.Close() } catch { return }
    if ($lines.Count -eq 0) { return }
    $head = $lines[0].Trim(); if ($head -notmatch '^(Starting|Exiting|Arranging|Switching to|Checking the client|Fixing the League client)') { return }
    $age = ((Get-Date) - $fi.LastWriteTime).TotalSeconds
    if ($age -gt 120 -and -not $toast.Visible) { return }
    $fr = Get-Friendly $lines
    $probs = @($fr.Steps | Where-Object { $_.StartsWith('!') } | ForEach-Object { $_.Substring(1) } | Select-Object -Last 2)
    $cur = @($fr.Steps | Where-Object { -not $_.StartsWith('!') } | Select-Object -Last 1)
    $tHead.Text = $(if ($fr.Head) { $fr.Head } else { $head }); $tBody.Text = (@($probs + $cur) | Select-Object -Unique) -join "`n"
    if (-not $toast.Visible) {
      $toast.Location = Get-ToastSpot $head
      [MiseT.Native]::ShowWindow($toast.Handle, 4) | Out-Null; $toast.Visible = $true
    }
    $running = (-not $fr.Done) -and ($head -match '^(Starting|Switching to|Fixing the League client)')
    $script:runActive = $running; $bStopT.Visible = $running
    if ($fr.Done) { $script:runActive = $false; $bStopT.Visible = $false; if ($script:toastUntil -eq [datetime]::MinValue) { $script:toastUntil = (Get-Date).AddSeconds(5) } } else { $script:toastUntil = [datetime]::MinValue }
    if ($script:toastUntil -ne [datetime]::MinValue -and (Get-Date) -gt $script:toastUntil) { $toast.Hide(); $script:toastUntil = [datetime]::MinValue; Set-Content -LiteralPath $status -Value '' }
    if ($age -gt 900) { $toast.Hide() }
  } catch {}
})
$toastTimer.Start()

# ---------- optional League helpers (off by default; switched on in the tray menu) ----------
$leagueDir = Get-LeagueDir
$acceptAt  = 9      # seconds into the 12 s ready-check at which Accept is pressed
$uggUrls = @{ Mayhem = 'https://u.gg/lol/champions/aram-mayhem/{slug}-aram-mayhem'; Aram = 'https://u.gg/lol/champions/aram/{slug}-aram'; Rift = 'https://u.gg/lol/champions/{slug}/build/{role}' }
$slugFix = @{ 'nunuwillump' = 'nunu'; 'renataglasc' = 'renata' }
$script:accepted = $false; $script:lastChamp = 0; $script:aramChamp = 0; $script:aramSince = $null; $script:champCache = @{}
$script:gameStart = $null; $script:gameAccount = ''; $script:uggWin = 0
function Get-Setting([string]$k) { return [bool](Get-MiseSetting $script:cfg $k) }
function Set-Setting([string]$k, [bool]$v) { $script:cfg = Set-MiseSetting $k $v }
function Active-Account { $f = Join-Path $store '_active.txt'; if (Test-Path $f) { (Get-Content -LiteralPath $f -Raw).Trim() } else { 'unknown' } }
function Log-Game($account, $start, $end) {
  $secs = [int]($end - $start).TotalSeconds; if ($secs -lt 120) { return }
  $log = Join-Path $store 'playtime.csv'
  if (-not (Test-Path $log)) { Set-Content -LiteralPath $log -Value 'account,start,seconds' }
  Add-Content -LiteralPath $log -Value ('"{0}",{1},{2}' -f $account, $start.ToString('s'), $secs)
}
function Get-Lcu {
  $lf = Join-Path $leagueDir 'lockfile'; if (-not (Test-Path $lf)) { return $null }
  try { $fs = [IO.File]::Open($lf, 'Open', 'Read', 'ReadWrite'); $sr = New-Object IO.StreamReader($fs); $t = $sr.ReadToEnd(); $sr.Close() } catch { return $null }
  $p = $t.Trim().Split(':'); if ($p.Count -lt 5) { return $null }
  if (-not (Get-Process -Id $p[1] -ErrorAction SilentlyContinue)) { return $null }
  return @{ Port = $p[2]; Pass = $p[3] }
}
function Invoke-Lcu($lcu, $path, $method = 'GET') {
  $a = @('-sk', '-m', '4', '-u', "riot:$($lcu.Pass)", '-w', '\n%{http_code}')
  if ($method -ne 'GET') { $a += @('-X', $method, '-H', 'Content-Type: application/json', '-d', '{}') }
  $lines = @(& curl.exe @a "https://127.0.0.1:$($lcu.Port)$path" 2>$null)
  if ($lines.Count -eq 0) { return @{ Code = '000'; Body = '' } }
  $body = ''; if ($lines.Count -gt 1) { $body = ($lines | Select-Object -First ($lines.Count - 1)) -join "`n" }
  return @{ Code = "$($lines[-1])".Trim(); Body = $body }
}
function Get-LcuJson($lcu, $path) { $r = Invoke-Lcu $lcu $path; if ($r.Code -ne '200' -or -not $r.Body) { return $null }; try { $r.Body | ConvertFrom-Json } catch { $null } }

function Open-Ugg($lcu, $champId, $session) {
  if (-not $script:champCache.ContainsKey($champId)) { $c = Get-LcuJson $lcu "/lol-game-data/assets/v1/champions/$champId.json"; if ($c -and $c.name) { $script:champCache[$champId] = $c.name } }
  $name = $script:champCache[$champId]; if (-not $name) { return }
  $slug = ($name.ToLower() -replace '[^a-z0-9]', ''); if ($slugFix.ContainsKey($slug)) { $slug = $slugFix[$slug] }
  $role = ''
  if ($session) {
    $me = $session.myTeam | Where-Object { $_.cellId -eq $session.localPlayerCellId } | Select-Object -First 1
    switch ("$($me.assignedPosition)") { 'TOP' { $role = 'top' } 'JUNGLE' { $role = 'jungle' } 'MIDDLE' { $role = 'mid' } 'BOTTOM' { $role = 'adc' } 'UTILITY' { $role = 'supp' } }
  }
  $q = 0; try { $q = [int](Get-LcuJson $lcu '/lol-gameflow/v1/session').gameData.queue.id } catch {}
  $tpl = if ($q -eq 2400) { $uggUrls.Mayhem } elseif ($q -eq 450) { $uggUrls.Aram } else { $uggUrls.Rift }
  Open-UggUrl (($tpl -replace '\{slug\}', $slug -replace '\{role\}', $role).TrimEnd('/'))
}
# open a u.gg page where a routine's u.gg tile is (same screen and spot), as a clean window of the default browser
function Open-UggUrl([string]$url) {
  $tile = $null; $owner = $null
  # the u.gg spot of the routine that ran last, else of the first routine that has one
  $lid = ''; try { $lid = (Get-Content -LiteralPath (Join-Path $script:DataDir '_last-routine.txt') -Raw).Trim() } catch {}
  $rs = @(@($script:cfg.routines) | Where-Object { $_.id -eq $lid }) + @($script:cfg.routines)
  foreach ($r in $rs) { $tile = @($r.tiles | Where-Object { $_.kind -eq 'ugg' })[0]; if ($tile) { $owner = $r; break } }
  # close only the u.gg window Mise opened last time (never a browser window the user opened, it may hold other tabs)
  if ($script:uggWin -and [MiseWin]::IsWindow([IntPtr]$script:uggWin)) { [MiseWin]::Close([IntPtr]$script:uggWin); Start-Sleep -Milliseconds 600 }
  $script:uggWin = 0
  $browser = Get-DefaultBrowser
  $web = [pscustomobject]@{ kind = 'web'; url = $url; clean = $true; hint = '' }
  $before = @(Get-WinSnapshot | ForEach-Object { [int64]$_.H })
  if (-not (Start-Tile $web $browser)) { return }
  if (-not $tile) { Start-Sleep -Seconds 3; $nw = @(Get-WinSnapshot | Where-Object { $before -notcontains [int64]$_.H -and (Get-ProcName $_.Pid) -eq $browser.Proc }) | Select-Object -First 1; if ($nw) { $script:uggWin = [int64]$nw.H }; return }
  $lives = @(Get-LiveMonitors $script:cfg)
  $px = Get-TilePx $tile $lives $owner; if (-not $px) { return }
  $end = (Get-Date).AddSeconds(15)
  while ((Get-Date) -lt $end) {
    $snap = @(Get-WinSnapshot); $fresh = @($snap | Where-Object { $before -notcontains [int64]$_.H } | ForEach-Object { [int64]$_.H })
    $h = Find-TileWindow $web $snap $fresh $browser
    if ($h -ne [IntPtr]::Zero) { $script:uggWin = [int64]$h; if ($browser.Clean) { try { [MiseWin]::StripCaption($h) } catch {} }; Set-WindowPlace $h $px; return }
    Start-Sleep -Milliseconds 400
  }
}
# ARAM / Mayhem have no lock-in and champions can still be swapped or rerolled: take the champion from the team list
function Get-MyChamp($lcu) {
  $s = Get-LcuJson $lcu '/lol-champ-select/v1/session'
  if ($s) { $me = @($s.myTeam) | Where-Object { $_.cellId -eq $s.localPlayerCellId } | Select-Object -First 1; if ($me -and [int]$me.championId -gt 0) { return @{ Id = [int]$me.championId; Session = $s } } }
  $gf = Get-LcuJson $lcu '/lol-gameflow/v1/session'; $cur = Get-LcuJson $lcu '/lol-summoner/v1/current-summoner'
  if ($gf -and $cur) { foreach ($t in @($gf.gameData.teamOne) + @($gf.gameData.teamTwo)) { if ($t -and $t.summonerId -eq $cur.summonerId -and [int]$t.championId -gt 0) { return @{ Id = [int]$t.championId; Session = $null } } } }
  return $null
}
function Watch-League {
  # play time: any running game counts
  $inGame = [bool](Get-Process -Name 'League of Legends' -ErrorAction SilentlyContinue)
  if ($inGame -and -not $script:gameStart) { $script:gameStart = Get-Date; $script:gameAccount = Active-Account }
  if (-not $inGame -and $script:gameStart) { Log-Game $script:gameAccount $script:gameStart (Get-Date); $script:gameStart = $null }
  # u.gg button in the Mise window: open the page of the current champion now
  $uf = Join-Path $script:DataDir '_ugg-now.txt'
  if (Test-Path $uf) {
    Remove-Item -LiteralPath $uf -Force -ErrorAction SilentlyContinue
    $l2 = Get-Lcu; $mc = $null; if ($l2) { $mc = Get-MyChamp $l2 }
    if ($mc) { $script:lastChamp = $mc.Id; Open-Ugg $l2 $mc.Id $mc.Session } else { Open-UggUrl 'https://u.gg' }
    return
  }
  $acc = Get-Setting 'autoAccept'; $ugg = Get-Setting 'champPage'
  if (-not $acc -and -not $ugg) { return }
  $lcu = Get-Lcu; if (-not $lcu) { $script:accepted = $false; $script:lastChamp = 0; $script:aramChamp = 0; return }
  $g = Invoke-Lcu $lcu '/lol-gameflow/v1/gameflow-phase'; if ($g.Code -ne '200') { return }
  switch ($g.Body.Trim('"')) {
    'ReadyCheck' {
      if ($acc -and -not $script:accepted) {
        $rc = Get-LcuJson $lcu '/lol-matchmaking/v1/ready-check'
        if ($rc -and $rc.state -eq 'InProgress' -and $rc.playerResponse -eq 'None' -and [double]$rc.timer -ge $acceptAt) { Invoke-Lcu $lcu '/lol-matchmaking/v1/ready-check/accept' 'POST' | Out-Null; $script:accepted = $true }
      }
    }
    'ChampSelect' {
      if ($ugg) {
        $s = Get-LcuJson $lcu '/lol-champ-select/v1/session'
        if ($s) {
          $mine = $null
          foreach ($grp in @($s.actions)) { foreach ($a in @($grp)) { if ($a.actorCellId -eq $s.localPlayerCellId -and $a.type -eq 'pick' -and $a.completed -and $a.championId -gt 0) { $mine = $a } } }
          if ($mine -and $mine.championId -ne $script:lastChamp) { $script:lastChamp = $mine.championId; Open-Ugg $lcu $mine.championId $s }
          # ARAM style (bench, no lock-in): follow the assigned champion, open at the final countdown
          if (($s.benchEnabled -eq $true) -or (-not @($s.actions).Count)) {
            $me = @($s.myTeam) | Where-Object { $_.cellId -eq $s.localPlayerCellId } | Select-Object -First 1
            if ($me -and [int]$me.championId -gt 0) {
              # swaps and rerolls can still happen in the last seconds: open only once the champion has stayed the same for ~4 s
              if ([int]$me.championId -ne $script:aramChamp) { $script:aramChamp = [int]$me.championId; $script:aramSince = Get-Date }
              $stable = $script:aramSince -and ((Get-Date) - $script:aramSince).TotalSeconds -ge 4
              if ($s.timer.phase -eq 'FINALIZATION' -and $stable -and $script:aramChamp -ne $script:lastChamp) { $script:lastChamp = $script:aramChamp; Open-Ugg $lcu $script:aramChamp $s }
            }
          }
        }
      }
    }
    { $_ -eq 'GameStart' -or $_ -eq 'InProgress' } {
      # safety net: the countdown was missed - open the final champion once the game loads
      if ($ugg -and $script:aramChamp -gt 0 -and $script:aramChamp -ne $script:lastChamp) { $script:lastChamp = $script:aramChamp; Open-Ugg $lcu $script:aramChamp $null }
    }
    default { $script:accepted = $false; $script:lastChamp = 0; $script:aramChamp = 0 }
  }
}
$lcuTimer = New-Object Windows.Forms.Timer; $lcuTimer.Interval = 2000
$lcuTimer.Add_Tick({ try { Watch-League } catch {} })
$lcuTimer.Start()

# ---------- reload hotkeys when the editor saves ----------
$timer = New-Object Windows.Forms.Timer; $timer.Interval = 2000
$timer.Add_Tick({ try {
  $st = if (Test-Path $script:CfgPath) { (Get-Item $script:CfgPath).LastWriteTime } else { [datetime]::MinValue }
  if ($st -ne $script:cfgStamp) { $script:cfgStamp = $st; $script:cfg = Get-MiseConfig; Register-Hotkeys }
} catch {} })
$timer.Start()

# update check: once a day, 30 s after start, only when a GitHub repository is set in Settings
$updTimer = New-Object Windows.Forms.Timer; $updTimer.Interval = 30000
$updTimer.Add_Tick({
  $updTimer.Interval = 3600000   # first check 30 s after start, then hourly
  # once per start: routines whose apps or screens are gone
  if (-not $script:healthDone) {
    $script:healthDone = $true
    try {
      $lives = @(Get-LiveMonitors $script:cfg); $msgs = @()
      foreach ($r in @($script:cfg.routines)) {
        $miss = @(@($r.tiles) | Where-Object { ($_.kind -eq 'app' -or $_.kind -eq 'spotify') -and ($_.exe -or $_.appid) -and -not (Test-TileInstalled $_) } | ForEach-Object { $_.name })
        $offs = @(@($r.tiles) | Where-Object { $t = $_; -not ($lives | Where-Object { $_.id -eq $t.monitor }) })
        $parts = @(); if ($miss.Count) { $parts += "$($miss -join ', ') not installed" }; if ($offs.Count) { $parts += "$($offs.Count) tile(s) on a screen that isn't connected" }
        if ($parts.Count) { $msgs += "'$($r.name)': $($parts -join '; ')" }
      }
      if ($msgs.Count) { $ni.ShowBalloonTip(10000, 'Mise: check your routines', ((@($msgs | Select-Object -First 3) -join "`n") + "`nOpen Edit routines to fix it."), 'Warning') }
    } catch {}
  }
  try { $null = Send-FeedbackQueue } catch {}
  try {
    # just updated: say so once
    $uf = Join-Path $script:DataDir '_updated-from.txt'
    if (Test-Path $uf) { $from = (Get-Content -LiteralPath $uf -Raw).Trim(); Remove-Item -LiteralPath $uf -Force -ErrorAction SilentlyContinue; Remove-Item -LiteralPath (Join-Path $script:DataDir '_update') -Recurse -Force -ErrorAction SilentlyContinue; $ni.ShowBalloonTip(6000, 'Mise', "Updated to Mise $($script:MiseVersion) (was $from).", 'Info') }
    # a downloaded update waits for a quiet moment: no League, no routine, no Mise window
    if (Test-Path (Get-UpdateReadyPath)) { if (Test-UpdateSafe) { if (Start-PendingUpdate) { $ni.Visible = $false; [Windows.Forms.Application]::Exit() } }; return }
    $last = "$(Get-MiseSetting $script:cfg 'lastUpdateCheck')"
    $due = (-not $last) -or (((Get-Date) - [datetime]$last).TotalHours -ge 6)
    if ("$(Get-MiseSetting $script:cfg 'updateRepo')" -and $due) {
      $u = Test-MiseUpdate
      if ($u.Available) { $script:update = $u; try { Save-MiseUpdate $u; Remove-Item -LiteralPath (Join-Path $script:DataDir '_update-error.txt') -Force -ErrorAction SilentlyContinue } catch { try { Set-Content -LiteralPath (Join-Path $script:DataDir '_update-error.txt') -Value "$(Get-Date -Format s) $($_.Exception.Message)" -Encoding UTF8 } catch {} } }
    }
  } catch {}
})
$updTimer.Start()

Register-Hotkeys
if (-not $script:cfg.firstRunDone) { Open-Home }
[Windows.Forms.Application]::Run()
$ni.Dispose()
