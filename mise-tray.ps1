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
function Start-RoutineById([string]$id, [string]$account = '', [bool]$noAsk = $false) {
  $r = $script:cfg.routines | Where-Object { $_.id -eq $id } | Select-Object -First 1
  if (-not $r) { return }
  if (Test-RunBusy) { return }
  if (-not $account -and $r.league -and -not $noAsk) {
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
  # the account's own routine (if it has one): a League routine does the login itself; any other routine starts next to the switch
  $ar = Get-AccountRoutine $script:cfg $n
  if ($ar -and $ar.league) { Start-RoutineById $ar.id $n; return }
  if ($ar) { Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$run`"", '-Routine', "`"$($ar.id)`""); $script:lastRoutine = $ar.id }
  $mod = Join-Path $script:MiseDir 'modules\riot-league.ps1'
  Set-Content -LiteralPath $status -Value "Switching to $n" -Encoding UTF8
  $script:runProc = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$mod`"", '-Core', '-Account', "`"$n`"", '-Queue', "$(Get-AccountQueue $script:cfg $n)", '-StatusFile', "`"$status`"")
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
# the icon file's own small frame at the size the tray draws (16 px at 100 %, 20 at 125 % ...): a scaled-down 32 px icon looks pixelated
function Get-TrayIcon {
  $px = 16
  try { $d = [int](Get-ItemProperty -Path 'HKCU:\Control Panel\Desktop\WindowMetrics' -Name AppliedDPI -ErrorAction Stop).AppliedDPI; if ($d -gt 96) { $px = [int][Math]::Round(16 * $d / 96.0) } } catch {}
  try { return New-Object Drawing.Icon($script:Icon, $px, $px) } catch {}
  try { return New-Object Drawing.Icon($script:Icon) } catch {}
  return [Drawing.SystemIcons]::Application
}
$ni.Icon = Get-TrayIcon
$ni.Text = 'Mise'
# while a routine is on, the tray icon's tooltip names it (the icon itself stays the plain logo)
$script:trayRun = ''
function Update-TrayState {
  $act = Get-ActiveRoutineId; if ($act -eq $script:trayRun) { return }
  $script:trayRun = $act
  $ar = $null; if ($act) { $ar = $script:cfg.routines | Where-Object { $_.id -eq $act } | Select-Object -First 1 }
  if ($ar) { $t = "Mise - '$($ar.name)' is on"; if ($t.Length -gt 62) { $t = $t.Substring(0, 62) }; $ni.Text = $t } else { $ni.Text = 'Mise' }
}
$cm = New-Object Windows.Forms.ContextMenuStrip; $ni.ContextMenuStrip = $cm
$cm.ShowImageMargin = $false; $cm.ShowCheckMargin = $false; $cm.Padding = New-Object Windows.Forms.Padding(0, 4, 0, 4)
# the menu is drawn by Mise in the current look: compact rows, small icons, section titles, a status card on top
$script:menuRenderer = New-Object MiseMenuRenderer; $cm.Renderer = $script:menuRenderer
$cm.Add_HandleCreated({ param($s, $e) try { $v = 2; [MiseUi]::DwmSetWindowAttribute($s.Handle, 33, [ref]$v, 4) | Out-Null } catch {} })
# it fades in when it opens
$cm.Add_Opened({ if ($script:Animate) { $cm.Opacity = 0; $script:menuClock = [Diagnostics.Stopwatch]::StartNew(); $menuFade.Start() } })
$menuFade = New-Object Windows.Forms.Timer; $menuFade.Interval = 10
$menuFade.Add_Tick({ $k = [Math]::Min(1.0, $script:menuClock.ElapsedMilliseconds / 130.0); try { $cm.Opacity = 1 - [Math]::Pow(1 - $k, 3) } catch {}; if ($k -ge 1) { $menuFade.Stop() } })
function Update-MenuLook {
  $r = $script:menuRenderer; $r.Theme = $script:C.Theme
  $r.Bg = $(if ($script:C.Glass) { $script:C.Bg } else { [Drawing.Color]::FromArgb(27, 27, 31) })
  $r.Line = $script:C.Line; $r.Sep = $(if ($script:C.Glass) { [Drawing.Color]::FromArgb(26, 255, 255, 255) } else { [Drawing.Color]::FromArgb(44, 44, 49) })
  [MiseMenuItem]::TextC = $script:C.Text; [MiseMenuItem]::MutedC = $script:C.Muted; [MiseMenuItem]::AccentC = $script:C.Accent; [MiseMenuItem]::LineC = $script:C.Line
  [MiseMenuItem]::HoverC = $(if ($script:C.Glass) { [Drawing.Color]::FromArgb(30, 255, 255, 255) } else { [Drawing.Color]::FromArgb(42, 42, 48) })
  [MiseMenuItem]::CardC = $(if ($script:C.Glass) { [Drawing.Color]::FromArgb(36, $script:C.Accent) } else { [Drawing.Color]::FromArgb(37, 34, 32) })
  [MiseMenuItem]::CardLine = $(if ($script:C.Glass) { [Drawing.Color]::FromArgb(128, $script:C.Accent) } else { [Drawing.Color]::FromArgb(74, 56, 40) })
}
# the look changed in the Mise window: the menu and the pop-up follow
function Update-TrayLook {
  Update-MiseLook $script:cfg; Update-MenuLook
  try {
    $toast.BackColor = $script:C.Bg; [MiseGlass]::Attach($toast, $script:C.Theme, $script:C.Bg); Set-PopLook; $toast.Invalidate($true)
    $fixMenu.BackColor = $script:C.Panel; $fixMenu.ForeColor = $script:C.Text
  } catch {}
}
Update-MenuLook

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
  $script:runActive = $false
  try { Add-Content -LiteralPath $status -Value 'Stopped by you.' -Encoding UTF8 } catch {}
  $script:toastUntil = (Get-Date).AddSeconds(3)
}
$script:runActive = $false
$script:update = $null
function New-MenuItem([string]$text, [string]$glyph = '', [string]$right = '', $onClick = $null, [string]$kind = 'item') {
  $it = New-Object MiseMenuItem($text, $kind); $it.Glyph = $glyph; $it.Right = $right
  if ($onClick) { $it.Add_Click($onClick) }
  [void]$cm.Items.Add($it); return $it
}
function Add-MenuSep { $sp = New-Object Windows.Forms.ToolStripSeparator; $sp.AutoSize = $false; $sp.Height = 9; [void]$cm.Items.Add($sp) }
function Format-Since([datetime]$t) { $m = [int]((Get-Date) - $t).TotalMinutes; if ($m -lt 1) { return 'just now' }; if ($m -lt 60) { return "$m m" }; return ('{0} h {1} m' -f [int][Math]::Floor($m / 60), ($m % 60)) }
function Get-LastRoutineTray {
  $id = ''; try { $f = Join-Path $script:DataDir '_last-routine.txt'; if (Test-Path $f) { $id = (Get-Content -LiteralPath $f -Raw).Trim() } } catch {}
  $r = $script:cfg.routines | Where-Object { $_.id -eq $id } | Select-Object -First 1
  if (-not $r) { $r = $script:cfg.routines | Select-Object -First 1 }
  return $r
}
function Start-ArrangeRoutine([string]$id) {
  $r = $script:cfg.routines | Where-Object { $_.id -eq $id } | Select-Object -First 1; if (-not $r) { return }
  if (Test-RunBusy) { return }
  Set-Content -LiteralPath $status -Value "Arranging '$($r.name)'" -Encoding UTF8
  $script:runProc = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$run`"", '-Routine', "`"$($r.id)`"", '-Arrange', '-StatusFile', "`"$status`"")
}
function Build-TrayMenu {
  $cm.SuspendLayout(); $cm.Items.Clear()
  # on top: what is running, with its Exit (or Stop while a start or switch is in progress)
  $act = Get-ActiveRoutineId; $ar = if ($act) { $script:cfg.routines | Where-Object { $_.id -eq $act } | Select-Object -First 1 } else { $null }
  if ($script:runActive -or $ar) {
    $card = New-Object MiseMenuItem('', 'card')
    if ($script:runActive) {
      $st = ''; try { $st = (Get-Content -LiteralPath $status -TotalCount 1 -ErrorAction SilentlyContinue) } catch {}
      $card.Text = $(if ($st) { "$st" } else { 'Working...' }); $card.SubText = 'in progress'; $card.Action = 'Stop'
      $card.add_ActionClick({ Stop-MiseRun })
    } else {
      $card.Text = "$($ar.name) is on"; $since = ''
      try { $af = Join-Path $script:DataDir '_active-routine.txt'; $since = Format-Since ((Get-Item -LiteralPath $af).LastWriteTime) } catch {}
      $who = ''; if ($ar.league) { $who = Get-ActiveAccountName; if ($who) { $wp = @($who.Trim() -split '\s+'); if ($wp.Count -gt 1) { $who = $wp[0..($wp.Count - 2)] -join ' ' } } }
      $card.SubText = (@($who, $since) | Where-Object { $_ }) -join ' - '; $card.Action = 'Exit'; $card.Tag = $ar.id
      $card.add_ActionClick({ param($s, $e) Stop-RoutineById $s.Tag })
    }
    [void]$cm.Items.Add($card)
  }
  $o = New-MenuItem 'Open Mise' 'open' '' { Open-Home }; $o.Strong = $true
  # put the windows of the last routine back in place
  $lr = Get-LastRoutineTray
  if ($lr) { $ra = New-MenuItem "Re-arrange '$($lr.name)'" 'arrange' '' { param($s, $e) Start-ArrangeRoutine $s.Tag }; $ra.Tag = $lr.id }
  if ($script:update) { $u = New-MenuItem "Update to Mise $($script:update.Version)" 'update' '' { try { Install-MiseUpdate $script:update } catch { $ni.ShowBalloonTip(6000, 'Mise', "Update failed: $($_.Exception.Message)", 'Warning') } }; $u.Lit = $true }
  if (@($script:cfg.routines).Count) {
    Add-MenuSep; [void](New-MenuItem 'Routines' '' '' $null 'label')
    foreach ($r in $script:cfg.routines) { $it = New-MenuItem "$($r.name)" 'play' "$($r.hotkey)" { param($s, $e) Start-RoutineById $s.Tag }; $it.Tag = $r.id }
  }
  $accts = @(Get-RiotAccounts)
  if ($accts.Count) {
    Add-MenuSep; [void](New-MenuItem 'Switch account' '' '' $null 'label')
    # the account that is logged in now (League or Riot Client running) gets a check
    $on = ''; if (Get-Process -Name 'RiotClientServices', 'LeagueClient', 'Riot Client' -ErrorAction SilentlyContinue) { $on = Get-ActiveAccountName }
    foreach ($n in $accts) {
      $parts = $n.Trim() -split '\s+'; $region = $parts[-1].ToUpper(); $nick = if ($parts.Count -gt 1) { ($parts[0..($parts.Count - 2)] -join ' ') } else { $n }
      $isOn = ($on -and $n -eq $on)
      $it = New-MenuItem $nick $(if ($isOn) { 'check' } else { 'user' }) $(if ($isOn) { "$region - logged in" } else { $region }) { param($s, $e) Start-AccountSwitch $s.Tag }
      $it.Tag = $n; $it.Lit = $isOn
    }
  }
  Add-MenuSep
  [void](New-MenuItem 'Edit routines' 'edit' '' { Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', "`"$editor`"") })
  [void](New-MenuItem 'Restart Mise' 'restart' '' { Reset-Mise })
  if ($script:FeedbackForm) { [void](New-MenuItem 'Send feedback' 'feedback' '' { Show-MiseFeedback }) }
  [void](New-MenuItem 'Quit Mise' 'quit' '' { Stop-AllMise; try { $null = Show-AllTaskbars } catch {}; $timer.Stop(); $lcuTimer.Stop(); $toastTimer.Stop(); $ni.Visible = $false; [Windows.Forms.Application]::Exit() })
  $cm.ResumeLayout()
}
function Sync-TrayLook { if ((Get-MiseTheme $script:cfg) -ne $script:C.Theme -or "$(Get-MiseSetting $script:cfg 'accent')".ToUpper() -ne ('#{0:X2}{1:X2}{2:X2}' -f $script:C.Accent.R, $script:C.Accent.G, $script:C.Accent.B)) { Update-TrayLook } }
$cm.Add_Opening({ $script:cfg = Get-MiseConfig; Sync-TrayLook; Build-TrayMenu })
# single click shows the menu after the double-click window passes; a double click opens the Mise window
$dcTimer = New-Object Windows.Forms.Timer; $dcTimer.Interval = [Windows.Forms.SystemInformation]::DoubleClickTime + 40
$dcTimer.Add_Tick({ $dcTimer.Stop(); $script:cfg = Get-MiseConfig; Sync-TrayLook; Build-TrayMenu
  $mi = [Windows.Forms.NotifyIcon].GetMethod('ShowContextMenu', [Reflection.BindingFlags]'NonPublic,Instance'); $mi.Invoke($ni, $null) })
$ni.Add_MouseClick({ if ($_.Button -eq 'Left') { $dcTimer.Stop(); $dcTimer.Start() } })
$ni.Add_DoubleClick({ $dcTimer.Stop(); Open-Home })
$ni.Visible = $true

# ---------- the progress pop-up: a slim pill while all goes well; it unfolds into the step list ----------
# (spec 13 Nov 2026: pill + timeline. Unfolds by itself for a problem or a League update, and while the mouse is over it;
# shows for every start and exit, fades out 3 s after it is done)
$toast = New-Object Windows.Forms.Form
$toast.FormBorderStyle = 'None'; $toast.ShowInTaskbar = $false; $toast.TopMost = $true; $toast.StartPosition = 'Manual'
$toast.BackColor = $script:C.Bg; $toast.Size = New-Object Drawing.Size(320, [MisePop]::PillH); $toast.Opacity = 0
$toast.Add_HandleCreated({ param($s, $e) try { $v = 2; [MiseUi]::DwmSetWindowAttribute($s.Handle, 33, [ref]$v, 4) | Out-Null; $l = $script:C.Line; $bc = [int]$l.R + 256 * [int]$l.G + 65536 * [int]$l.B; [MiseUi]::DwmSetWindowAttribute($s.Handle, 34, [ref]$bc, 4) | Out-Null } catch {} })
Set-MiseBackdrop $toast
$pop = New-Object MisePop; $pop.Dock = 'Fill'
function Set-PopLook {
  $pop.BackColor = $(if ($script:C.Glass) { [Drawing.Color]::Transparent } else { $script:C.Bg })
  $pop.TextC = $script:C.Text; $pop.MutedC = $script:C.Muted; $pop.LineC = $script:C.Line; $pop.Accent = $script:C.Accent
  $pop.HeadFont = $script:fBtn; $pop.RowFont = $script:fSmall; $pop.SmallFont = New-Object Drawing.Font('Segoe UI', 8); $pop.BtnFont = $script:fTiny
  $pop.Logo.Accent = $script:LogoCopper; $pop.Invalidate()
}
Set-PopLook
$toast.Controls.Add($pop)
$pop.add_StopClick({ Stop-MiseRun })
$pop.add_HideClick({ Hide-Toast })
$pop.add_FixClick({ $i = $pop.FixIndex; $its = @($script:toastItems); if ($i -ge 0 -and $i -lt $its.Count) { Show-FixMenu $its[$i] ($pop.PointToClient([Windows.Forms.Cursor]::Position)) } })
$script:toastItems = @(); $script:toastKey = ''; $script:toastBottom = $false; $script:toastHead = ''
$script:runStart = $null; $script:stepSeen = @{}; $script:lastLines = 0; $script:lastHead = ''
# click a problem row: what went wrong in one line, and the one action that fixes it
$fixMenu = New-Object Windows.Forms.ContextMenuStrip
$fixMenu.BackColor = $script:C.Panel; $fixMenu.ForeColor = $script:C.Text; $fixMenu.ShowImageMargin = $false
function Get-ToastRoutine { $h = "$($script:toastHead)"; if ($h -match '^(Starting|Exiting|Arranging) (.+)$') { $n = $Matches[2]; return ($script:cfg.routines | Where-Object { $_.name -eq $n } | Select-Object -First 1) }; return $null }
function Start-ArrangeNow { $r = Get-ToastRoutine; if (-not $r) { return }; Set-Content -LiteralPath $status -Value "Arranging '$($r.name)'" -Encoding UTF8; Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$run`"", '-Routine', "`"$($r.id)`"", '-Arrange', '-StatusFile', "`"$status`"") }
function Show-FixMenu($it, $pt) {
  $fix = @{
    missing   = @("$($it.Name) is not installed on this PC.", 'Edit routines', { Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', "`"$editor`"") })
    nobrowser = @("No Chrome or Edge found for $($it.Name).", 'Edit routines', { Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', "`"$editor`"") })
    nowindow  = @("$($it.Name) did not open a window in time.", 'Re-arrange now', { Start-ArrangeNow })
    noscreen  = @("The screen for $($it.Name) is not connected.", 'Find screens and re-arrange', { try { $ua = Update-AutoMonitors (Get-MiseConfig); if ($ua.Added) { Save-MiseConfig $ua.Cfg; $script:cfg = $ua.Cfg } } catch {}; Start-ArrangeNow })
    mini      = @('The Spotify mini player is not open.', 'Re-arrange now (open the mini player first)', { Start-ArrangeNow })
    league    = @('The League client is stuck or did not open a lobby.', 'Fix League client', { $mod = Join-Path $script:MiseDir 'modules\riot-league.ps1'; Set-Content -LiteralPath $status -Value 'Fixing the League client' -Encoding UTF8; Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$mod`"", '-Core', '-Fix', '-StatusFile', "`"$status`"") })
    login     = @('Riot rejected the saved login.', 'Open Mise (account ... > Update saved login)', { Open-Home })
  }[$it.Why]
  if (-not $fix) { return }
  $fixMenu.Items.Clear()
  $h = $fixMenu.Items.Add($fix[0]); $h.Enabled = $false
  [void]$fixMenu.Items.Add('-')
  $a = $fixMenu.Items.Add($fix[1]); $a.ForeColor = $script:C.Accent; $a.Tag = $fix[2]
  $a.Add_Click({ param($s, $e) $script:toastUntil = (Get-Date).AddSeconds(1); & $s.Tag })
  $script:toastUntil = [datetime]::MinValue   # the pop-up stays while the menu is open
  $fixMenu.Show($pop, $pt)
}
Add-Type -Namespace MiseT -Name Native -MemberDefinition '[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int c);'
$script:toastUntil = [datetime]::MinValue
$toastTimer = New-Object Windows.Forms.Timer; $toastTimer.Interval = 500
# fading in and out
$script:fadeTo = 0.0; $script:fadeClock = $null; $script:fadeFrom = 0.0
$fadeTimer = New-Object Windows.Forms.Timer; $fadeTimer.Interval = 15
$fadeTimer.Add_Tick({
  $k = [Math]::Min(1.0, $script:fadeClock.ElapsedMilliseconds / $(if ($script:fadeTo -gt 0) { 160.0 } else { 260.0 }))
  $toast.Opacity = $script:fadeFrom + ($script:fadeTo - $script:fadeFrom) * (1 - [Math]::Pow(1 - $k, 3))
  if ($k -ge 1) { $fadeTimer.Stop(); if ($script:fadeTo -le 0) { $toast.Hide() } }
})
function Start-Fade([double]$to) {
  if (-not $script:Animate) { $toast.Opacity = [Math]::Max(0.01, $to); if ($to -le 0) { $toast.Hide() }; return }
  $script:fadeFrom = $toast.Opacity; $script:fadeTo = $to; $script:fadeClock = [Diagnostics.Stopwatch]::StartNew(); $fadeTimer.Start()
}
function Hide-Toast {
  $script:toastUntil = [datetime]::MinValue; $script:runActive = $false; $pop.Pinned = $false
  try { Set-Content -LiteralPath $status -Value '' } catch {}
  if ($toast.Visible) { Start-Fade 0.0 }
}
function Test-HomeOpen { try { $m = [Threading.Mutex]::OpenExisting('Local\MiseHome'); $m.Dispose(); return $true } catch { return $false } }
function Get-ToastSpot([string]$head = '') {
  $script:toastBottom = $false
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
    'bottom-right' { $script:toastBottom = $true; return New-Object Drawing.Point(($wa.Right - $toast.Width - $p), ($wa.Bottom - $toast.Height - $p)) }
    default        { $script:toastBottom = $true; return New-Object Drawing.Point(($wa.Left + $p), ($wa.Bottom - $toast.Height - $p)) }
  }
}
# the rows of the step list: in time order, with the second each one first showed up; apps placed one after
# another share a row; a problem gets the Fix of its app; the step running now pulses
function Get-PopRows($fr, $its) {
  $sec = [int]((Get-Date) - $script:runStart).TotalSeconds
  foreach ($st in @($fr.Steps)) { $k = $(if ($st.StartsWith('League is updating')) { 'League is updating' } else { $st }); if (-not $script:stepSeen.ContainsKey($k)) { $script:stepSeen[$k] = $sec } }
  $rows = New-Object Collections.ArrayList
  $placed = @($fr.Steps | Where-Object { $_ -match ' in place$' } | ForEach-Object { $_ -replace ' in place$', '' })
  foreach ($st in @($fr.Steps)) {
    if ($st -match '^Opening (.+)$' -and $placed -contains $Matches[1]) { continue }   # "Opening X" is folded into "X in place"
    $k = $(if ($st.StartsWith('League is updating')) { 'League is updating' } else { $st }); $t = "$($script:stepSeen[$k]) s"
    if ($st.StartsWith('!')) {
      $txt = $st.Substring(1); $fx = -1
      for ($i = 0; $i -lt $its.Count; $i++) { $it = $its[$i]; if ($it.State -eq 'bad' -and $it.Why -and ($txt -like "*$($it.Name)*" -or ($it.Name -eq 'League' -and $txt -match 'League|lobby|login|client'))) { $fx = $i; break } }
      [void]$rows.Add(@{ T = $t; X = $txt; K = 'warn'; P = -1.0; F = $fx })
    } elseif ($st.StartsWith('League is updating')) {
      $pc = -1.0; if ($st -match '(\d+)%') { $pc = [double]$Matches[1] }
      [void]$rows.Add(@{ T = $t; X = $(if ($pc -ge 0) { "League is updating $([int]$pc)%" } else { 'League is updating' }) + ' - Mise waits, no Play'; K = 'update'; P = $pc; F = -1 })
    } elseif ($st -match '^(.+) in place$' -and $rows.Count -and $rows[$rows.Count - 1].N) {
      [void]$rows[$rows.Count - 1].N.Add(($st -replace ' in place$', ''))
    } elseif ($st -match '^(.+) in place$') {
      $n = New-Object Collections.ArrayList; [void]$n.Add(($st -replace ' in place$', '')); [void]$rows.Add(@{ T = $t; X = $st; K = 'done'; P = -1.0; F = -1; N = $n })
    } else { [void]$rows.Add(@{ T = $t; X = $st; K = 'done'; P = -1.0; F = -1 }) }
  }
  # apps placed together: "A and B in place", "A, B + 3 more in place"
  foreach ($r in $rows) { if ($r.N) { $n = @($r.N); $r.X = $(if ($n.Count -le 3) { $(if ($n.Count -gt 1) { (($n[0..($n.Count - 2)]) -join ', ') + ' and ' + $n[-1] } else { $n[0] }) + ' in place' } else { "$($n[0]), $($n[1]) + $($n.Count - 2) more in place" }) } }
  # the last ordinary step is the one running now (unless everything is done)
  if (-not $fr.Done) { for ($i = $rows.Count - 1; $i -ge 0; $i--) { if ($rows[$i].K -eq 'done') { $rows[$i].K = 'now'; break } elseif ($rows[$i].K -eq 'update') { break } } }
  return @($rows | Select-Object -Last 9)
}
$toastTimer.Add_Tick({
  try {
    # done and shown long enough (and the mouse is not on it): fade out, and empty the status file so the finished run is not shown again
    if ($script:toastUntil -ne [datetime]::MinValue -and (Get-Date) -gt $script:toastUntil) {
      if ($pop.Open -and -not $pop.Needs) { $script:toastUntil = (Get-Date).AddSeconds(2) } else { Hide-Toast; return }
    }
    if (-not (Test-Path $status)) { return }
    $fi = Get-Item -LiteralPath $status
    $lines = @(); try { $fs = [IO.File]::Open($status, 'Open', 'Read', 'ReadWrite'); $sr = New-Object IO.StreamReader($fs); $lines = @($sr.ReadToEnd() -split "`r?`n" | Where-Object { $_.Trim() -ne '' }); $sr.Close() } catch { return }
    if ($lines.Count -eq 0) { return }
    $head = $lines[0].Trim(); if ($head -notmatch '^(Starting|Exiting|Arranging|Switching to|Checking the client|Fixing the League client)') { return }
    $age = ((Get-Date) - $fi.LastWriteTime).TotalSeconds
    if ($age -gt 120 -and -not $toast.Visible) { return }
    # a new run: the clock and the step times start again
    if ($head -ne $script:lastHead -or $lines.Count -lt $script:lastLines -or -not $script:runStart) { $script:runStart = Get-Date; $script:stepSeen = @{}; $pop.Pinned = $false; $script:toastUntil = [datetime]::MinValue }
    $script:lastHead = $head; $script:lastLines = $lines.Count
    $fr = Get-Friendly $lines
    $its = @(); foreach ($k in @($fr.Items.Keys)) { $its += @{ Name = "$k"; State = "$($fr.Items[$k])"; Why = "$($fr.Why[$k])" } }
    $script:toastItems = $its
    $rows = @(Get-PopRows $fr $its)
    $script:toastHead = $(if ($fr.Head) { $fr.Head } else { $head })
    $okN = @($its | Where-Object { $_.State -eq 'ok' }).Count
    $running = (-not $fr.Done) -and ($head -match '^(Starting|Switching to|Fixing the League client)')
    $problem = [bool](@($rows | Where-Object { $_.K -eq 'warn' }).Count)
    $updating = [bool](@($rows | Where-Object { $_.K -eq 'update' }).Count) -and -not $fr.Done
    $key = "$($script:toastHead)|$okN|$running|$($fr.Done)|" + (($rows | ForEach-Object { "$($_.T)~$($_.X)~$($_.K)~$($_.F)" }) -join '|')
    if ($key -ne $script:toastKey) {
      $script:toastKey = $key
      $pop.Head = ($script:toastHead -replace "'", ''); $pop.Count = $(if ($its.Count) { "$okN / $($its.Count)" } else { '' })
      $pop.Ring = $(if ($its.Count) { [single]($okN / $its.Count) } else { [single]-1 })
      $pop.Running = $running; $pop.Done = [bool]$fr.Done; $pop.Problem = $problem; $pop.Needs = ($problem -or $updating)
      $pop.Times = [string[]]@($rows | ForEach-Object { $_.T }); $pop.Texts = [string[]]@($rows | ForEach-Object { $_.X }); $pop.Kinds = [string[]]@($rows | ForEach-Object { $_.K })
      $pop.Pcts = [single[]]@($rows | ForEach-Object { [single]$_.P }); $pop.Fix = [int[]]@($rows | ForEach-Object { [int]$_.F })
      $pop.Kick(); $pop.Invalidate()
    }
    $script:runActive = $running
    if (-not $toast.Visible) {
      $toast.Height = [MisePop]::PillH
      $toast.Location = Get-ToastSpot $head; $pop.AnchorBottom = $script:toastBottom
      $toast.Opacity = 0.01; [MiseT.Native]::ShowWindow($toast.Handle, 4) | Out-Null; $toast.Visible = $true; Start-Fade 0.97; $pop.Kick()
    } elseif ($fadeTimer.Enabled -and $script:fadeTo -le 0 -and -not $fr.Done) { Start-Fade 0.97 }
    if ($fr.Done) { if ($script:toastUntil -eq [datetime]::MinValue -and -not $fixMenu.Visible) { $script:toastUntil = (Get-Date).AddSeconds($(if ($problem) { 20 } else { 3 })) } } else { $script:toastUntil = [datetime]::MinValue }
    if ($age -gt 900) { Hide-Toast }
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
# auto-exit: a League routine exits by itself once the League client has been gone for a minute
# (the client restarting during a routine start, account switch or fix does not count)
$script:axId = ''; $script:axSeen = $false; $script:axGone = $null
function Watch-AutoExit {
  if (-not [bool](Get-MiseSetting $script:cfg 'autoExit')) { $script:axId = ''; return }
  $act = Get-ActiveRoutineId
  if ($act -ne $script:axId) { $script:axId = $act; $script:axSeen = $false; $script:axGone = $null }
  if (-not $act) { return }
  $r = $script:cfg.routines | Where-Object { $_.id -eq $act } | Select-Object -First 1
  if (-not $r -or -not $r.league) { return }
  if (Get-Process -Name 'LeagueClient', 'LeagueClientUx', 'League of Legends' -ErrorAction SilentlyContinue) { $script:axSeen = $true; $script:axGone = $null; return }
  if (-not $script:axSeen) { return }
  if (-not $script:axGone) { $script:axGone = Get-Date; return }
  if (((Get-Date) - $script:axGone).TotalSeconds -lt 60) { return }
  $busy = ($script:runProc -and -not $script:runProc.HasExited)
  if (-not $busy) { try { $busy = [bool](Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'mise-run\.ps1|riot-league\.ps1' -and $_.CommandLine -notmatch '-StreamWatch' }) } catch {} }
  if ($busy) { $script:axGone = $null; return }
  $script:axSeen = $false; $script:axGone = $null
  Write-Log "auto-exit: League client closed, exiting '$($r.name)'"
  Stop-RoutineById $act
}
# auto-start: a routine with "Start with a program" starts when that program opens (only at the moment it opens:
# a program that was already running when Mise started, or whose routine was exited, does not start it again)
$script:autoSeen = $null
function Watch-AutoStart {
  $want = @($script:cfg.routines | Where-Object { "$($_.autoStart)".Trim() })
  if (-not $want.Count) { $script:autoSeen = @{}; return }
  $now = @{}
  foreach ($r in $want) { $n = ("$($r.autoStart)".Trim() -replace '(?i)\.exe$', ''); $now[$n.ToLower()] = [bool](Get-Process -Name $n -ErrorAction SilentlyContinue) }
  $old = $script:autoSeen; $script:autoSeen = $now
  if ($null -eq $old) { return }
  foreach ($r in $want) {
    $k = ("$($r.autoStart)".Trim() -replace '(?i)\.exe$', '').ToLower()
    if (-not $now[$k] -or -not $old.ContainsKey($k) -or $old[$k]) { continue }
    if ((Get-ActiveRoutineId) -eq $r.id) { continue }
    if ($script:runProc -and -not $script:runProc.HasExited) { continue }
    Write-Log "auto-start: $($r.autoStart) opened, starting '$($r.name)'"
    Start-RoutineById $r.id '' $true
    break
  }
}
$lcuTimer.Add_Tick({ try { Watch-League } catch {}; try { Watch-AutoExit } catch {}; try { Watch-AutoStart } catch {} })
$lcuTimer.Start()

# ---------- reload hotkeys when the editor saves ----------
$timer = New-Object Windows.Forms.Timer; $timer.Interval = 2000
$timer.Add_Tick({ try {
  $st = if (Test-Path $script:CfgPath) { (Get-Item $script:CfgPath).LastWriteTime } else { [datetime]::MinValue }
  if ($st -ne $script:cfgStamp) { $script:cfgStamp = $st; $script:cfg = Get-MiseConfig; Register-Hotkeys }
} catch {}
  try { Update-TrayState } catch {} })
$timer.Start()

# update check: 30 s after every start and then every 6 hours, only when a GitHub repository is set in Settings
$updTimer = New-Object Windows.Forms.Timer; $updTimer.Interval = 30000
$updTimer.Add_Tick({
  $updTimer.Interval = 3600000   # first check 30 s after start, then hourly
  # once per start: a screen plugged in since last time gets its automatic name (before the routine check)
  if (-not $script:screensDone) { $script:screensDone = $true; try { $ua = Update-AutoMonitors (Get-MiseConfig); if ($ua.Added) { Save-MiseConfig $ua.Cfg; $script:cfg = $ua.Cfg } } catch {} }
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
    # every start of the helper checks once; after that every 6 hours
    $due = (-not $script:updStartDone) -or (-not $last) -or (((Get-Date) - [datetime]$last).TotalHours -ge 6); $script:updStartDone = $true
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
