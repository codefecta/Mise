<#
  Mise riot module (shared edition) - Windows PowerShell 5.1 or 7. Generated from Personal Mise's engine.
  Started by Mise's League step (mise-core.ps1 passes -Core), never needed by hand.
  It logs in to a saved account, starts and repairs the client, presses Play and opens the lobby.
  The routine itself places every other window.

  Saved logins live in %USERPROFILE%\LeagueAccounts and never contain passwords: keep that folder private.
  Log of every run: %USERPROFILE%\LeagueAccounts\league-mode.log
#>
param([string]$Account = '', [string]$Save = '', [switch]$Next, [switch]$Fix, [switch]$Layout, [switch]$Keep, [switch]$Exit, [switch]$TestQueues, [string]$Ugg = '', [switch]$Core, [string]$Queue = '', [string]$LeagueAt = '',
      [string]$StatusFile = '', [switch]$DryRun)

# Every status line gets an elapsed-seconds stamp in the log; with a StatusFile the menu also shows it live.
$script:miseClock = [Diagnostics.Stopwatch]::StartNew()
function Write-Host {
  param([Parameter(ValueFromRemainingArguments = $true)]$Object)
  $m = "$Object"
  Microsoft.PowerShell.Utility\Write-Host ("[{0,4}s] {1}" -f [int]$script:miseClock.Elapsed.TotalSeconds, $m)
  if ($StatusFile) { try { Add-Content -LiteralPath $StatusFile -Value $m -Encoding UTF8 } catch {} }
}

# Riot Client and League can be installed on any drive: Riot's own install records first, then the usual folder on every drive
function Get-RiotClientExe {
  try {
    $j = Join-Path $env:ProgramData 'Riot Games\RiotClientInstalls.json'
    if (Test-Path -LiteralPath $j) {
      $o = Get-Content -LiteralPath $j -Raw | ConvertFrom-Json
      foreach ($k in @('rc_default', 'rc_live', 'rc_beta')) { $p = "$($o.$k)"; if ($p -and (Test-Path -LiteralPath $p)) { return (Resolve-Path -LiteralPath $p).Path } }
    }
  } catch {}
  try { $pr = Get-Process -Name 'RiotClientServices' -ErrorAction SilentlyContinue | Select-Object -First 1; if ($pr -and $pr.Path) { return $pr.Path } } catch {}
  foreach ($d in @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady })) {
    $p = Join-Path $d.RootDirectory.FullName 'Riot Games\Riot Client\RiotClientServices.exe'; if (Test-Path -LiteralPath $p) { return $p }
  }
  return "$env:SystemDrive\Riot Games\Riot Client\RiotClientServices.exe"
}
function Get-LeagueDir {
  try {
    $y = Join-Path $env:ProgramData 'Riot Games\Metadata\league_of_legends.live\league_of_legends.live.product_settings.yaml'
    if (Test-Path -LiteralPath $y) {
      $m = [regex]::Match((Get-Content -LiteralPath $y -Raw), '(?m)^\s*product_install_full_path:\s*"?([^"\r\n]+)"?')
      if ($m.Success) { $p = $m.Groups[1].Value.Trim() -replace '/', '\'; if (Test-Path -LiteralPath $p) { return $p } }
    }
  } catch {}
  $rc = Get-RiotClientExe
  if ($rc) { $p = Join-Path (Split-Path (Split-Path $rc -Parent) -Parent) 'League of Legends'; if (Test-Path -LiteralPath $p) { return $p } }
  foreach ($d in @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady })) {
    $p = Join-Path $d.RootDirectory.FullName 'Riot Games\League of Legends'; if (Test-Path -LiteralPath $p) { return $p }
  }
  return "$env:SystemDrive\Riot Games\League of Legends"
}

# ======================= SETTINGS =======================
$riotClient = Get-RiotClientExe
$leagueDir  = Get-LeagueDir
$riotData   = "$env:LOCALAPPDATA\Riot Games\Riot Client\Data\RiotGamesPrivateSettings.yaml"
$store      = "$env:USERPROFILE\LeagueAccounts"
$leagueArgs = @('--launch-product=league_of_legends', '--launch-patchline=live')

$setRegion     = $true   # write the account's region into League's settings before launch
$startTimeout  = 600     # seconds to wait for the client to appear (covers patching)
$readyTimeout  = 90      # seconds the client gets to become usable once it is open
$windowTimeout = 25      # seconds to wait for each side app window
$playQueue     = 2400 # lobby opened by the automatic Play press: a queue id (2400 = ARAM: Mayhem, 450 = ARAM, 400 = Draft) or a queue name, 0 = off
$playList      = @()  # several lobbies picked in the menu, best first (the first one that opens wins)
$playFallback  = 450     # used when that queue is not available right now (450 = ARAM)
# choices made in the menu (queue, u.gg) are kept in this small file and win over the values above
try { $sf = Join-Path $store '_settings.json'; if (Test-Path $sf) { $st = Get-Content -LiteralPath $sf -Raw | ConvertFrom-Json; if ($null -ne $st.queue) { $playQueue = [int]$st.queue }; if ($null -ne $st.queues) { $ql = @($st.queues | ForEach-Object { [int]$_ } | Where-Object { $_ -gt 0 }); if ($ql.Count -gt 0) { $playList = $ql; $playQueue = $ql[0] } elseif (@($st.queues).Count -eq 0) { $playQueue = 0 } } } } catch {}
$hideSideTaskbar = $true # hide the taskbar on the vertical monitor while Mise is arranged; the Exit button brings it back
# Spotify miniplayer: found through Windows accessibility. If that ever fails, put the button's distance
# from the Spotify window's bottom-right corner here (pixels at 100% scaling), e.g. @{ Right = 60; Bottom = 45 }
$spotifyMiniBtn = $null

# Spotify: 'mini' = miniplayer strip at the bottom (Premium only; open it once with the
#          miniplayer button, the script places it and hides the big window)
#          'hidden' = minimize Spotify completely, control with media keys
$spotifyMode = 'mini'

# Vertical monitor (left), top to bottom. Y/H are fractions of the screen height.
# Windows are tiled edge to edge (Windows' invisible borders are compensated).
#   u.gg      0-45%   eye level, room for runes/builds; title bar removed (experimental)
#   Discord   45-73%
#   WhatsApp  73-94%
#   Spotify   miniplayer strip at the bottom, centred left-right (about 0.5 cm shorter than before)
$sideApps = @(
  @{ Name = 'u.gg';     Exe = 'chrome'; Args = @('--new-window', '--app=https://u.gg')
     Process = @('chrome'); Title = 'U.GG'; Exclude = ''; StripCaption = $true; Remember = $true; CloseOnExit = $true; LaunchOnStart = $false
     Monitor = 'vertical'; X = 0; Y = 0;    W = 1; H = 0.45 },
  @{ Name = 'Discord';  Exe = "$env:LOCALAPPDATA\Discord\Update.exe"; Args = @('--processStart', 'Discord.exe')
     Process = @('Discord'); Title = ''; Exclude = 'Updater'
     Monitor = 'vertical'; X = 0; Y = 0.45; W = 1; H = 0.28 },
  @{ Name = 'WhatsApp'; Exe = 'whatsapp:'; Args = @()
     Process = @('WhatsApp.Root', 'WhatsApp', 'ApplicationFrameHost'); Title = 'WhatsApp'; Exclude = ''
     Monitor = 'vertical'; X = 0; Y = 0.73; W = 1; H = 0.21 },
  @{ Name = 'Spotify';  Exe = "$env:APPDATA\Spotify\Spotify.exe"; Args = @()
     Process = @('Spotify'); Title = ''; Exclude = ''; Spotify = $true
     Monitor = 'vertical'; X = 0; Y = 0.94; W = 1; H = 0.06 }
)
# If Spotify is set to 'hidden', WhatsApp takes the bottom strip too
if ($spotifyMode -ne 'mini') { $sideApps[2].H = 0.27 }

# League client: centered on the main monitor (its size is fixed by League's own settings)
$leagueWin = @{ Name = 'League'; Process = @('LeagueClientUx'); Title = 'League of Legends'; Exclude = ''
                Monitor = 'main'; Center = $true }
$regions = @('EUW', 'EUNE', 'TR', 'NA', 'KR', 'BR', 'RU', 'JP')
# shared edition: only log in / start / repair / press Play - the routine places everything else
if ($Core) { $sideApps = @(); $hideSideTaskbar = $false }
if ("$Queue" -ne '') { $playList = @(); if ("$Queue" -match '^\d+$') { $playQueue = [int]$Queue } else { $playQueue = $Queue } }
# shared edition: the routine's League tile says where the client goes (top-left of its visible edge; its size is League's own)
if ("$LeagueAt" -match '^(-?\d+),(-?\d+)$') { $leagueWin.Center = $false; $leagueWin.At = @([int]$Matches[1], [int]$Matches[2]) }
# ========================================================

New-Item -ItemType Directory -Force -Path $store | Out-Null

# ---------- save current Riot login ----------
if ($Save) {
  if (Get-Process -Name 'League of Legends' -ErrorAction SilentlyContinue) { Write-Host "A game is running - finish it first."; exit 1 }
  if (-not (Test-Path $riotData)) { Write-Host "Riot settings file not found: $riotData"; exit 1 }
  # Riot only writes the login to disk reliably once the client is closed - and NEVER sign out
  # first, because signing out cancels the saved login.
  Write-Host "Closing Riot Client so the login is written to disk..."
  foreach ($n in 'LeagueClientUx', 'Riot Client') {
    Get-Process -Name $n -ErrorAction SilentlyContinue | ForEach-Object { try { $_.CloseMainWindow() | Out-Null } catch {} }
  }
  Start-Sleep -Seconds 4
  foreach ($n in 'LeagueClientUxRender', 'LeagueClientUx', 'LeagueClient', 'RiotClientUxRender', 'RiotClientUx', 'RiotClientServices', 'Riot Client') {
    Stop-Process -Name $n -Force -ErrorAction SilentlyContinue
  }
  Start-Sleep -Seconds 2
  Copy-Item $riotData (Join-Path $store "$Save.yaml") -Force
  Write-Host "Saved the current login as '$Save'."
  if ($Next) {
    # set the live login aside (kept as a backup) so Riot Client shows a fresh login screen
    Move-Item $riotData (Join-Path $store '_last-live-login.bak') -Force
    Remove-Item (Join-Path $store '_active.txt') -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $riotClient) { Start-Process $riotClient }
    Write-Host "Riot Client reopened on the login screen: log in to the NEXT account (tick Stay signed in), then press + Account again."
  }
  exit 0
}

try { Start-Transcript -Path (Join-Path $store 'league-mode.log') -Append | Out-Null } catch {}

Add-Type @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class Win {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
  [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  public static void Close(IntPtr h) { PostMessage(h, 0x0010, IntPtr.Zero, IntPtr.Zero); }
  // taskbars (primary and secondary, visible or hidden) whose centre lies inside the rectangle
  public static IntPtr[] Taskbars(int L, int T, int R, int B) {
    List<IntPtr> res = new List<IntPtr>();
    EnumWindows(delegate (IntPtr h, IntPtr x) {
      StringBuilder sb = new StringBuilder(64); GetClassName(h, sb, 64);
      string c = sb.ToString();
      if (c != "Shell_SecondaryTrayWnd" && c != "Shell_TrayWnd") return true;
      RECT rc; if (!GetWindowRect(h, out rc)) return true;
      int cx = (rc.Left + rc.Right) / 2, cy = (rc.Top + rc.Bottom) / 2;
      if (cx >= L && cx < R && cy >= T && cy < B) res.Add(h);
      return true;
    }, IntPtr.Zero);
    return res.ToArray();
  }
  public static void ClickXY(int x, int y) {
    SetCursorPos(x, y); System.Threading.Thread.Sleep(150);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero); System.Threading.Thread.Sleep(60);
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
  }
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
  // left click at a fraction of the window (fx, fy in 0..1)
  public static void ClickAt(IntPtr h, double fx, double fy) {
    RECT r; if (!GetWindowRect(h, out r)) return;
    ShowWindow(h, 9); SetForegroundWindow(h); System.Threading.Thread.Sleep(400);
    int x = r.Left + (int)((r.Right - r.Left) * fx), y = r.Top + (int)((r.Bottom - r.Top) * fy);
    SetCursorPos(x, y); System.Threading.Thread.Sleep(150);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero); System.Threading.Thread.Sleep(60);
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
  }
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int w, int hgt, uint f);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool IsHungAppWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int i, int v);
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
  [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int a, out RECT r, int size);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }

  // all visible, titled top-level windows of the given processes
  public static IntPtr[] FindAll(int[] pids, string contains, string excludes) {
    List<IntPtr> list = new List<IntPtr>();
    EnumWindows(delegate (IntPtr h, IntPtr l) {
      if (!IsWindowVisible(h)) return true;
      uint pid; GetWindowThreadProcessId(h, out pid);
      if (Array.IndexOf(pids, (int)pid) < 0) return true;
      StringBuilder sb = new StringBuilder(512); GetWindowText(h, sb, 512);
      string t = sb.ToString();
      if (t.Length == 0) return true;
      if (!String.IsNullOrEmpty(contains) && t.IndexOf(contains, StringComparison.OrdinalIgnoreCase) < 0) return true;
      if (!String.IsNullOrEmpty(excludes) && t.IndexOf(excludes, StringComparison.OrdinalIgnoreCase) >= 0) return true;
      list.Add(h); return true;
    }, IntPtr.Zero);
    return list.ToArray();
  }

  public static bool IsTopmost(IntPtr h) { return (GetWindowLong(h, -20) & 0x8) != 0; }

  // remove title bar and resize frame
  public static void StripCaption(IntPtr h) {
    int s = GetWindowLong(h, -16);
    SetWindowLong(h, -16, (s & ~0x00C00000) | 0x00040000);
    SetWindowPos(h, IntPtr.Zero, 0, 0, 0, 0, 0x0027);   // FRAMECHANGED | NOMOVE | NOSIZE | NOZORDER
  }

  // place so the VISIBLE edges match the rectangle (Windows 10/11 add invisible borders)
  public static void PlaceExact(IntPtr h, int x, int y, int w, int hh) {
    SetWindowPos(h, IntPtr.Zero, x, y, w, hh, 0x0044);
    RECT wr, fr;
    if (!GetWindowRect(h, out wr)) return;
    if (DwmGetWindowAttribute(h, 9, out fr, Marshal.SizeOf(typeof(RECT))) != 0) return;
    int l = fr.Left - wr.Left, t = fr.Top - wr.Top, r = wr.Right - fr.Right, b = wr.Bottom - fr.Bottom;
    if (l == 0 && t == 0 && r == 0 && b == 0) return;
    SetWindowPos(h, IntPtr.Zero, x - l, y - t, w + l + r, hh + t + b, 0x0044);
  }
}
"@
# use real pixels so placement is right with Windows scaling (125%, 150%...)
try { [Win]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null } catch {}
Add-Type -AssemblyName System.Windows.Forms

# ---------- windows ----------
function Get-Area($which) {
  $main = [System.Windows.Forms.Screen]::PrimaryScreen
  $vert = [System.Windows.Forms.Screen]::AllScreens |
          Where-Object { -not $_.Primary -and $_.Bounds.Height -gt $_.Bounds.Width } | Select-Object -First 1
  if ($which -eq 'vertical' -and $vert) { if ($script:sideBarHidden) { return $vert.Bounds } else { return $vert.WorkingArea } }
  return $main.WorkingArea
}

function Get-AppWindows($app) {
  $ids = @(Get-Process -Name $app.Process -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
  if ($ids.Count -eq 0) { return @() }
  return @([Win]::FindAll([int[]]$ids, $app.Title, $app.Exclude))
}

function Find-AppWindow($app) {
  if ($app.Remember) {   # window we opened ourselves earlier (its title changes with the page)
    $f = Join-Path $store "_$($app.Name).hwnd"
    if (Test-Path $f) {
      try { $hv = [IntPtr][long](Get-Content -LiteralPath $f -Raw).Trim()
            if ([Win]::IsWindow($hv) -and [Win]::IsWindowVisible($hv)) { return $hv } } catch {}
    }
  }
  $all = Get-AppWindows $app
  if ($all.Count -eq 0) { return [IntPtr]::Zero }
  return $all[0]
}

function Wait-AppWindow($app, $seconds) {
  $deadline = (Get-Date).AddSeconds($seconds)
  do {
    $h = Find-AppWindow $app
    if ($h -ne [IntPtr]::Zero) { return $h }
    Start-Sleep -Milliseconds 500
  } while ((Get-Date) -lt $deadline)
  return [IntPtr]::Zero
}

function Get-Zone($app) {
  $a = Get-Area $app.Monitor
  return @{ X = [int]($a.X + $app.X * $a.Width); Y = [int]($a.Y + $app.Y * $a.Height)
            W = [int]($app.W * $a.Width);        H = [int]($app.H * $a.Height) }
}

# ---------- taskbar on the vertical monitor ----------
$taskbarFlag = Join-Path $store '_taskbar-hidden.txt'
$script:sideBarHidden = (Test-Path $taskbarFlag)
function Get-VertScreen {
  [System.Windows.Forms.Screen]::AllScreens | Where-Object { -not $_.Primary -and $_.Bounds.Height -gt $_.Bounds.Width } | Select-Object -First 1
}
function Hide-SideTaskbar {
  if (-not $hideSideTaskbar) { return }
  $v = Get-VertScreen; if (-not $v) { return }
  $b = $v.Bounds
  $bars = @([Win]::Taskbars($b.Left, $b.Top, $b.Right, $b.Bottom))
  if ($bars.Count -eq 0) { return }
  foreach ($h in $bars) { [Win]::ShowWindow($h, 0) | Out-Null }
  $script:sideBarHidden = $true
  Set-Content -LiteralPath $taskbarFlag -Value (Get-Date -Format s)
  Write-Host "  [Taskbar] left monitor taskbar hidden (Exit brings it back)"
}
function Show-AllTaskbars {
  $bars = @([Win]::Taskbars(-100000, -100000, 100000, 100000))
  foreach ($h in $bars) { [Win]::ShowWindow($h, 5) | Out-Null }
  $script:sideBarHidden = $false
  Remove-Item -LiteralPath $taskbarFlag -ErrorAction SilentlyContinue
  Write-Host "  [Taskbar] restored ($($bars.Count) bar(s))"
}

# ---------- Spotify miniplayer ----------
function Open-Miniplayer($main) {
  try {
    Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes -ErrorAction Stop
    [Win]::ShowWindow($main, 9) | Out-Null; [Win]::SetForegroundWindow($main) | Out-Null
    Start-Sleep -Milliseconds 900
    $root = [System.Windows.Automation.AutomationElement]::FromHandle($main)
    $btnType = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
    $found = $null
    for ($i = 0; $i -lt 5 -and -not $found; $i++) {       # the page's accessibility tree builds up lazily
      $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnType)
      foreach ($e in $all) { if ($e.Current.Name -match 'mini\s*-?player') { $found = $e; break } }
      if (-not $found) { Start-Sleep -Milliseconds 500 }
    }
    if ($found) {
      try { ($found.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)).Invoke() }
      catch { $r = $found.Current.BoundingRectangle; [Win]::ClickXY([int]($r.X + $r.Width / 2), [int]($r.Y + $r.Height / 2)) }
      Write-Host "  [Spotify] miniplayer button pressed"
      return $true
    }
  } catch { Write-Host "  [Spotify] accessibility lookup failed: $($_.Exception.Message)" }
  if ($spotifyMiniBtn) {
    $r = New-Object Win+RECT; [Win]::GetWindowRect($main, [ref]$r) | Out-Null
    $sc = [Win]::GetDpiForWindow($main) / 96.0
    [Win]::ClickXY([int]($r.Right - $spotifyMiniBtn.Right * $sc), [int]($r.Bottom - $spotifyMiniBtn.Bottom * $sc))
    Write-Host "  [Spotify] clicked the saved miniplayer position"
    return $true
  }
  Write-Host "  [Spotify] could not find the miniplayer button"
  return $false
}

# ---------- which lobby to open ----------
function Resolve-Queue($lcu) {
  $ids = @(Resolve-QueueRaw $lcu)
  $rt = Get-Routes
  if ($rt.fresh -and $rt.ok.Count) { $keep = @($ids | Where-Object { $rt.ok -contains [int]$_ }); if ($keep.Count) { return $keep } }
  return $ids
}
function Resolve-QueueRaw($lcu) {
  # returns the queue ids to try, best first (the last one is always the fallback)
  $q = $playQueue
  if ($playList.Count -gt 1) { return @($playList | Select-Object -Unique) }
  if ($q -is [int] -or "$q" -match '^\d+$') { return @([int]$q, [int]$playFallback | Select-Object -Unique) }
  $ids = @()
  $r = Invoke-Lcu $lcu '/lol-game-queues/v1/queues'
  if ($r.Code -eq '200') {
    try {
      $all = @($r.Body | ConvertFrom-Json)
      $pat = [regex]::Escape("$q")
      # any field may carry the name, and a queue that is not 'Available' by the flag can still be joinable
      $hits = @($all | Where-Object { ($_.queueAvailability -eq 'Available') -and ((@($_.name, $_.shortName, $_.description) -join ' ') -match $pat) })
      foreach ($h in ($hits | Sort-Object { if ($_.queueAvailability -eq 'Available') { 0 } else { 1 } })) {
        Write-Host "  [Play] found queue $($h.id) '$($h.name)' ($($h.queueAvailability))"
        $ids += [int]$h.id
      }
      if (-not $hits.Count) {
        $aram = @($all | Where-Object { ($_.name, $_.shortName -join ' ') -match 'ARAM' } | ForEach-Object { "$($_.id)=$($_.name)/$($_.queueAvailability)" })
        Write-Host "  [Play] no queue named '$q'; ARAM-type queues: $($aram -join ', ')"
      }
    } catch { Write-Host "  [Play] queue lookup failed: $($_.Exception.Message)" }
  }
  if ("$q" -match 'Mayhem' -and ($ids -notcontains 2400)) { $ids += 2400 }
  $ids += [int]$playFallback
  return @($ids | Select-Object -Unique)
}

function Place-Spotify($app, $seconds) {
  $null = Wait-AppWindow $app $seconds
  $wins = Get-AppWindows $app
  if ($wins.Count -eq 0) { Write-Host "  [Spotify] no window found - skipped"; return }
  foreach ($w in $wins) {
    $rr = New-Object Win+RECT; [Win]::GetWindowRect($w, [ref]$rr) | Out-Null
    Write-Host ("  [Spotify] window {0}: {1}x{2} at {3},{4} topmost={5} minimized={6}" -f $w, ($rr.Right - $rr.Left), ($rr.Bottom - $rr.Top), $rr.Left, $rr.Top, [Win]::IsTopmost($w), [Win]::IsIconic($w))
  }
  # the miniplayer is the Spotify window that is always on top
  $mini = $wins | Where-Object { [Win]::IsTopmost($_) -and -not [Win]::IsIconic($_) } | Select-Object -First 1
  if (-not $mini -and $spotifyMode -eq 'mini') {
    # a miniplayer that got minimized earlier is still the miniplayer (always on top): bring it back
    $hid = $wins | Where-Object { [Win]::IsTopmost($_) -and [Win]::IsIconic($_) } | Select-Object -First 1
    if ($hid) { [Win]::ShowWindow($hid, 9) | Out-Null; Start-Sleep -Milliseconds 800; $mini = $hid; Write-Host "  [Spotify] miniplayer was minimized - restored" }
  }
  if (-not $mini -and $spotifyMode -eq 'mini') {
    $main = $wins | Select-Object -First 1
    if (Open-Miniplayer $main) {
      Start-Sleep -Seconds 2
      $wins = Get-AppWindows $app
      $mini = $wins | Where-Object { [Win]::IsTopmost($_) -and -not [Win]::IsIconic($_) } | Select-Object -First 1
    }
  }
  foreach ($w in $wins) { if ($w -ne $mini) { [Win]::ShowWindow($w, 6) | Out-Null } }   # minimize main window
  if ($spotifyMode -ne 'mini') { Write-Host "  [Spotify] minimized"; return }
  if ($mini) {
    # bottom strip, centred left-right; if Spotify refuses to get that short, WhatsApp gives up the difference
    $z = Get-Zone $app
    $a = Get-Area $app.Monitor
    [Win]::PlaceExact($mini, $z.X, $z.Y, $z.W, $z.H)
    $r = New-Object Win+RECT; [Win]::GetWindowRect($mini, [ref]$r) | Out-Null
    $w = $r.Right - $r.Left; $hh = $r.Bottom - $r.Top
    $x = [int]($a.X + ($a.Width - $w) / 2); $y = [int]($a.Y + $a.Height - $hh)
    [Win]::SetWindowPos($mini, [IntPtr]::Zero, $x, $y, 0, 0, 0x0045) | Out-Null   # move only
    # Spotify likes to snap back to its own size a moment later: watch it for a few seconds and put it back
    $fixes = 0
    $watchN = $(if ($script:quickPlace) { 0 } else { 6 })   # first pass: no watch (the final pass watches), saves ~4 s
    for ($k = 0; $k -lt $watchN; $k++) {
      Start-Sleep -Milliseconds 700
      $r2 = New-Object Win+RECT; [Win]::GetWindowRect($mini, [ref]$r2) | Out-Null
      $w2 = $r2.Right - $r2.Left; $h2 = $r2.Bottom - $r2.Top
      if ([Math]::Abs($w2 - $w) -gt 3 -or [Math]::Abs($h2 - $hh) -gt 3 -or [Math]::Abs($r2.Left - $x) -gt 3 -or [Math]::Abs($r2.Top - $y) -gt 3) {
        $fixes++
        [Win]::PlaceExact($mini, $z.X, $z.Y, $z.W, $z.H)
        [Win]::GetWindowRect($mini, [ref]$r) | Out-Null
        $w = $r.Right - $r.Left; $hh = $r.Bottom - $r.Top
        $x = [int]($a.X + ($a.Width - $w) / 2); $y = [int]($a.Y + $a.Height - $hh)
        [Win]::SetWindowPos($mini, [IntPtr]::Zero, $x, $y, 0, 0, 0x0045) | Out-Null
      }
    }
    if ($fixes) { Write-Host "  [Spotify] snapped back $fixes time(s) - put it back" }
    # WhatsApp must never lie under the miniplayer
    $wa = $sideApps | Where-Object { $_.Name -eq 'WhatsApp' } | Select-Object -First 1
    $wh = Find-AppWindow $wa
    if ($wh -ne [IntPtr]::Zero) {
      $rw = New-Object Win+RECT; [Win]::GetWindowRect($wh, [ref]$rw) | Out-Null
      if ($rw.Bottom -gt $y + 4) {
        $zw = Get-Zone $wa; $newH = $y - $zw.Y
        if ($newH -gt 100) { [Win]::PlaceExact($wh, $zw.X, $zw.Y, $zw.W, $newH) }
      }
    }
    Write-Host "  [Spotify] miniplayer at the bottom, centred (${w}x${hh}, wanted height $($z.H))"
  } else {
    Write-Host "  [Spotify] no miniplayer yet - open it once (button next to volume), then press Arrange"
  }
}

function Place-App($app, $seconds) {
  if ($app.Missing) { return }
  if ($app.Spotify) { Place-Spotify $app $seconds; return }
  # u.gg is opened by the tray after you lock a champion: nothing to place before that
  if ($app.ContainsKey('LaunchOnStart') -and -not $app.LaunchOnStart -and (Find-AppWindow $app) -eq [IntPtr]::Zero) { return }
  $h = Wait-AppWindow $app $seconds
  if ($h -eq [IntPtr]::Zero) { Write-Host "  [$($app.Name)] no window found - skipped"; return }
  [Win]::ShowWindow($h, 9) | Out-Null                       # restore if minimized/maximized
  if ($app.StripCaption) { try { [Win]::StripCaption($h) } catch {} }
  if ($app.At) {
    [Win]::SetWindowPos($h, [IntPtr]::Zero, $app.At[0], $app.At[1], 0, 0, 0x0045) | Out-Null   # move only: the League client has no invisible border
  } elseif ($app.Center) {
    $a = Get-Area $app.Monitor
    $r = New-Object Win+RECT; [Win]::GetWindowRect($h, [ref]$r) | Out-Null
    $w = $r.Right - $r.Left; $hh = $r.Bottom - $r.Top
    $x = [int]($a.X + ($a.Width - $w) / 2); $y = [int]($a.Y + ($a.Height - $hh) / 2)
    [Win]::SetWindowPos($h, [IntPtr]::Zero, $x, $y, 0, 0, 0x0045) | Out-Null   # move only
  } else {
    $z = Get-Zone $app
    [Win]::PlaceExact($h, $z.X, $z.Y, $z.W, $z.H)
  }
  Write-Host "  [$($app.Name)] placed"
}

function Test-AppExists($app) {
  $e = "$($app.Exe)"
  if ($e -like '*\*') { return (Test-Path -LiteralPath $e) }
  if ($e.EndsWith(':')) {   # store apps register a protocol; also look for the package by name
    $pn = $e.TrimEnd(':')
    if (Test-Path -LiteralPath "Registry::HKEY_CLASSES_ROOT\$pn") { return $true }
    return [bool](Get-AppxPackage -Name "*$pn*" -ErrorAction SilentlyContinue)
  }
  if (Get-Command $e -ErrorAction SilentlyContinue) { return $true }
  foreach ($root in 'HKLM', 'HKCU') {
    if (Test-Path "${root}:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$e.exe") { return $true }
  }
  return $false
}

function Start-SideApp($app) {
  if (-not (Test-AppExists $app)) { $app.Missing = $true; Write-Host "  [$($app.Name)] app doesn't exist on this PC - skipped"; return }
  if ((Find-AppWindow $app) -ne [IntPtr]::Zero) { Write-Host "  [$($app.Name)] already open"; return }
  try {
    $before = @()
    if ($app.Remember) { $before = @(Get-AppWindows @{ Process = $app.Process; Title = ''; Exclude = '' }) }
    if ($app.Args.Count -gt 0) { Start-Process $app.Exe -ArgumentList $app.Args } else { Start-Process $app.Exe }
    Write-Host "  [$($app.Name)] starting"
    if ($app.Remember) {
      $end = (Get-Date).AddSeconds(15); $new = $null
      while (-not $new -and (Get-Date) -lt $end) {
        Start-Sleep -Milliseconds 500
        $now = @(Get-AppWindows @{ Process = $app.Process; Title = ''; Exclude = '' })
        $fresh = @($now | Where-Object { $before -notcontains $_ })
        if ($fresh.Count -gt 0) { $new = $fresh[0] }
      }
      if ($new) { Set-Content -LiteralPath (Join-Path $store "_$($app.Name).hwnd") -Value ([long]$new) }
    }
  } catch { Write-Host "  [$($app.Name)] could not start: $($_.Exception.Message)" }
}

# ---------- League client API (LCU) ----------
function Get-Lcu {
  $lf = Join-Path $leagueDir 'lockfile'
  if (-not (Test-Path $lf)) { return $null }
  try {
    $fs = [System.IO.File]::Open($lf, 'Open', 'Read', 'ReadWrite')
    $sr = New-Object System.IO.StreamReader($fs); $t = $sr.ReadToEnd(); $sr.Close()
  } catch { return $null }
  $p = $t.Trim().Split(':')
  if ($p.Count -lt 5) { return $null }
  if (-not (Get-Process -Id $p[1] -ErrorAction SilentlyContinue)) { return $null }   # stale lockfile
  return @{ Port = $p[2]; Pass = $p[3] }
}

function Invoke-Lcu($lcu, $path, $method = 'GET', $json = '{}') {
  $a = @('-sk', '-m', '5', '-u', "riot:$($lcu.Pass)", '-w', '\n%{http_code}')
  if ($method -ne 'GET') { $a += @('-X', $method, '-H', 'Content-Type: application/json', '-d', ($json -replace '"', '\"')) }
  $lines = @(& curl.exe @a "https://127.0.0.1:$($lcu.Port)$path" 2>$null)
  if ($lines.Count -eq 0) { return @{ Code = '000'; Body = '' } }
  $body = ''
  if ($lines.Count -gt 1) { $body = ($lines | Select-Object -First ($lines.Count - 1)) -join "`n" }
  return @{ Code = "$($lines[-1])".Trim(); Body = $body }
}

function Test-Client {   # '' = usable, otherwise the reason
  $lcu = Get-Lcu
  if (-not $lcu) { return 'client API not up' }
  $s = Invoke-Lcu $lcu '/lol-login/v1/session'
  if ($s.Code -eq '200' -and $s.Body -match '"state"\s*:\s*"ERROR"') { return 'login session error' }
  $r = Invoke-Lcu $lcu '/lol-summoner/v1/current-summoner'
  if ($r.Code -ne '200') { return "no summoner loaded (HTTP $($r.Code))" }
  $g = Invoke-Lcu $lcu '/lol-gameflow/v1/gameflow-phase'
  if ($g.Code -ne '200') { return "gameflow not ready (HTTP $($g.Code))" }
  if (-not (Get-Process -Name 'LeagueClientUxRender' -ErrorAction SilentlyContinue)) { return 'client UI not running' }
  $h = Find-AppWindow $leagueWin
  if ($h -eq [IntPtr]::Zero) { return 'no client window' }
  if ([Win]::IsHungAppWindow($h)) { return 'client window not responding' }
  return ''
}

function Test-InGame { [bool](Get-Process -Name 'League of Legends' -ErrorAction SilentlyContinue) }

# The Riot Client window sometimes sits on the League page with the Play button not pressed
# (launch requests are ignored). Click League in the side bar, then Play.
# ask Riot Client itself to launch League (the same thing the Play button does) - no clicking needed
function Riot-Launch {
  $lf = "$env:LOCALAPPDATA\Riot Games\Riot Client\Config\lockfile"
  if (-not (Test-Path $lf)) { return '000' }
  try { $fs = [IO.File]::Open($lf, 'Open', 'Read', 'ReadWrite'); $sr = New-Object IO.StreamReader($fs); $t = $sr.ReadToEnd(); $sr.Close() } catch { return '000' }
  $p = $t.Trim().Split(':')
  if ($p.Count -lt 5) { return '000' }
  $out = @(& curl.exe -sk -m 2 -u "riot:$($p[3])" -X POST -H 'Content-Type: application/json' -d '{}' -o NUL -w '%{http_code}' "https://127.0.0.1:$($p[2])/product-launcher/v1/products/league_of_legends/patchlines/live" 2>$null)
  if ($out.Count -eq 0) { return '000' }
  return "$($out[-1])".Trim()
}

# colour of the spot where the Play button sits in the Riot Client window ($null while the window is not up)
function Get-RiotPlayColor {
  $ids = @(Get-Process -Name 'Riot Client' -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
  if ($ids.Count -eq 0) { return $null }
  $w = @([Win]::FindAll([int[]]$ids, 'Riot Client', ''))
  if ($w.Count -eq 0) { return $null }
  # the client often starts minimized or behind other windows: bring it up once so its pixels can be read
  if ($script:riotShownHwnd -ne $w[0]) {
    $script:riotShownHwnd = $w[0]
    [Win]::ShowWindow($w[0], 9) | Out-Null; [Win]::SetForegroundWindow($w[0]) | Out-Null
    Start-Sleep -Milliseconds 300
  }
  if ([Win]::IsIconic($w[0])) { return $null }
  $rc = New-Object Win+RECT; [Win]::GetWindowRect($w[0], [ref]$rc) | Out-Null
  $x = $rc.Left + [int](($rc.Right - $rc.Left) * 0.14); $y = $rc.Top + [int](($rc.Bottom - $rc.Top) * 0.87)
  try {
    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
    $bmp = New-Object Drawing.Bitmap(1, 1)
    $g = [Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($x, $y, 0, 0, (New-Object Drawing.Size(1, 1)))
    $c = $bmp.GetPixel(0, 0); $g.Dispose(); $bmp.Dispose()
    return $c
  } catch { return $null }
}
# ready = a warm button (the red or the gold Play); the dark blue/grey while Riot Client is still loading or updating is not
function Test-PlayReady($c) { return ($c -and $c.R -gt 150 -and ($c.R - $c.B) -gt 70) }

# once League is up, Riot Client has done its job: tuck its window away (it was brought forward to read the Play button)
function Hide-RiotWindow {
  $ids = @(Get-Process -Name 'Riot Client' -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
  if ($ids.Count -eq 0) { return }
  foreach ($h in @([Win]::FindAll([int[]]$ids, 'Riot Client', ''))) { [Win]::ShowWindow($h, 6) | Out-Null }
}
function Click-RiotPlay {
  $ids = @(Get-Process -Name 'Riot Client' -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
  if ($ids.Count -eq 0) { return $false }
  $w = @([Win]::FindAll([int[]]$ids, 'Riot Client', ''))
  if ($w.Count -eq 0) { return $false }
  [Win]::ClickAt($w[0], 0.025, 0.496)   # League of Legends in the left bar
  Start-Sleep -Milliseconds 350
  [Win]::ClickAt($w[0], 0.14, 0.87)     # Play
  return $true
}

function Wait-Healthy {
  $t = (Get-Date).AddSeconds($startTimeout)
  $t0 = Get-Date; $whiteSince = -1; $nudge = 0; $nudgeAt = 0; $lastSeen = -99; $seenLogs = 0; $apiAt = -1; $lastTry = -99; $apiFails = 0; $retried = $false
  while (-not (Get-Process -Name 'LeagueClientUx' -ErrorAction SilentlyContinue)) {
    if ((Get-Date) -gt $t) { Write-Host "  client did not open within $startTimeout s"; return $false }
    $el = ((Get-Date) - $t0).TotalSeconds
    # a Riot Client that was already running ignores the launch arguments: ask it directly (fast), click Play as a backup
    if ($apiAt -lt 0 -and $el -gt 1 -and ($el - $lastTry) -ge 2) {
      $lastTry = $el; $c = Riot-Launch
      if ($c -match '^2') { $apiAt = $el; Write-Host "  launch requested from Riot Client (HTTP $c)" }
      else { $apiFails++; if ($apiFails -eq 1) { Write-Host "  Riot Client not ready for a launch request yet (HTTP $c)" } }
    }
    if ($apiAt -ge 0 -and -not $retried -and ($el - $apiAt) -gt 40) { $retried = $true; $apiAt = -1; $lastTry = -99; $apiFails = 0; Write-Host "  not opening - asking again" }
    # watch the Play button: the moment it turns red the client is ready, so press it right then
    # Riot Client stuck on its white login screen = the saved login was rejected: stop instead of looping for minutes
    $pcw = Get-RiotPlayColor
    if ($pcw -and $pcw.R -gt 235 -and $pcw.G -gt 235 -and $pcw.B -gt 235) {
      if ($whiteSince -lt 0) { $whiteSince = $el }
      elseif (($el - $whiteSince) -gt 25) {
        $script:loginRejected = $true
        Write-Host "  login rejected - Riot Client is on its login screen. Log in by hand, then right-click the account > 'Update saved login'."
        return $false
      }
    } else { $whiteSince = -1 }
    if ($apiAt -lt 0 -and $nudge -eq 0) {
      $pc = $pcw
      if ($pc -and ($el - $lastSeen) -ge 3 -and $seenLogs -lt 12) { $lastSeen = $el; $seenLogs++; Write-Host ("  Play button colour {0},{1},{2}" -f $pc.R, $pc.G, $pc.B) }
      if (Test-PlayReady $pc) { $nudge = 1; $nudgeAt = $el; Write-Host "  Play button is ready - pressing it"; Click-RiotPlay | Out-Null }
      elseif ($el -gt 22) { $nudge = 1; $nudgeAt = $el; Write-Host "  pressing Play in Riot Client (timed)"; Click-RiotPlay | Out-Null }
    }
    if ($nudge -eq 1 -and ($el - $nudgeAt) -gt 18) { $nudge = 2; $nudgeAt = $el; Write-Host "  pressing Play again"; Click-RiotPlay | Out-Null }
    if ($nudge -le 2 -and $el -gt 120 -and -not ($script:riotRestarted)) { $nudge = 3; $script:riotRestarted = $true; Write-Host "  still not opening - restarting Riot Client (login is kept)"; Stop-Riot; Start-Sleep -Seconds 2; Start-League; $t0 = Get-Date; $apiAt = -1; $lastTry = -99; $retried = $false; $nudge = 0 }
    Start-Sleep -Milliseconds 400
  }
  $t = (Get-Date).AddSeconds($readyTimeout); $ok = 0; $why = ''
  while ((Get-Date) -lt $t) {
    if (Test-InGame) { return $true }
    $why = Test-Client
    if ($why -eq '') { $ok++; if ($ok -ge 2) { return $true } } else { $ok = 0 }
    Start-Sleep -Seconds 2
  }
  Write-Host "  client not usable: $why"
  return $false
}

function Stop-League {
  $p = @(Get-Process -Name 'LeagueClientUxRender', 'LeagueClientUx', 'LeagueClient' -ErrorAction SilentlyContinue)
  if (-not $p.Count) { return }
  $p | Stop-Process -Force -ErrorAction SilentlyContinue
  for ($k = 0; $k -lt 12 -and (Get-Process -Name 'LeagueClientUx', 'LeagueClient' -ErrorAction SilentlyContinue); $k++) { Start-Sleep -Milliseconds 250 }
  Start-Sleep -Milliseconds 500
}

function Stop-Riot {
  $p = @(Get-Process -Name 'RiotClientUxRender', 'RiotClientUx', 'RiotClientServices', 'Riot Client' -ErrorAction SilentlyContinue)
  if (-not $p.Count) { return }
  $p | Stop-Process -Force -ErrorAction SilentlyContinue
  for ($k = 0; $k -lt 12 -and (Get-Process -Name 'RiotClientServices', 'Riot Client' -ErrorAction SilentlyContinue); $k++) { Start-Sleep -Milliseconds 250 }
  Start-Sleep -Milliseconds 500
}

function Start-League { Start-Process $riotClient -ArgumentList $leagueArgs }

# fix ladder: 1 reload UI, 2 restart League client, 3 restart Riot + League (login is kept)
function Ensure-League {
  Write-Host "[Health check]"
  for ($i = 0; $i -le 3; $i++) {
    if (Wait-Healthy) { Write-Host "  client OK"; Hide-RiotWindow; return $true }
    if ($script:loginRejected) { return $false }
    if (Test-InGame) { Write-Host "  in game - not touching it"; return $true }
    switch ($i) {
      0 { Write-Host "  fix 1/3: reloading client UI"
          $lcu = Get-Lcu
          if ($lcu) { Invoke-Lcu $lcu '/riotclient/kill-and-restart-ux' 'POST' | Out-Null }
          else { Stop-League; Start-League } }
      1 { Write-Host "  fix 2/3: restarting League client"; Stop-League; Start-League }
      2 { Write-Host "  fix 3/3: restarting Riot Client and League"; Stop-League; Stop-Riot; Start-League }
      3 { Write-Host "  still not usable after 3 fixes - check it by hand"; return $false }
    }
    Start-Sleep -Seconds 5
  }
}

# ---------- lobby routes: which queue ids really open a lobby today (refreshed by the probe below) ----------
$routesFile = Join-Path $store '_routes.json'
function Get-Routes {
  $r = @{ ok = @(); no = @(); fresh = $false }
  try {
    if (Test-Path $routesFile) {
      $j = Get-Content -LiteralPath $routesFile -Raw | ConvertFrom-Json
      $r.ok = @($j.ok | ForEach-Object { [int]$_ }); $r.no = @($j.no | ForEach-Object { [int]$_ })
      $r.fresh = ((Get-Date) - (Get-Item -LiteralPath $routesFile).LastWriteTime).TotalHours -lt 6
    }
  } catch {}
  return $r
}
function Get-LobbyQueue($lcu) {
  $lb = Invoke-Lcu $lcu '/lol-lobby/v2/lobby'
  try { return [int](($lb.Body | ConvertFrom-Json).gameConfig.queueId) } catch { return 0 }
}
# open and close a lobby for every known queue id (no matchmaking is started); saves the result as the new routes
function Test-Queues($lcu, [switch]$Quiet) {
  $g = Invoke-Lcu $lcu '/lol-gameflow/v1/gameflow-phase'
  if ($g.Body -match 'Lobby') { Invoke-Lcu $lcu '/lol-lobby/v2/lobby' 'DELETE' | Out-Null; Start-Sleep -Seconds 2 }
  elseif ($g.Body -notmatch 'None') { return $null }
  $ids = @(400, 420, 440, 450, 480, 1740, 1750, 2400, 3140, 3260, 3270, 4320)
  $ok = @(); $no = @()
  foreach ($id in $ids) {
    $r = Invoke-Lcu $lcu '/lol-lobby/v2/lobby' 'POST' "{`"queueId`":$id}"
    $mode = ''; $good = $false
    if ($r.Code -eq '200') {
      for ($k = 0; $k -lt 5 -and -not $good; $k++) {
        Start-Sleep -Milliseconds 800
        $ph = Invoke-Lcu $lcu '/lol-gameflow/v1/gameflow-phase'
        if ($ph.Body -match 'Lobby') {
          $actual = Get-LobbyQueue $lcu
          if ($actual -eq $id) { $good = $true; $mode = "queue $actual" } else { $mode = "opened queue $actual instead" }
        }
      }
    }
    if ($good) { $ok += $id } else { $no += $id }
    if (-not $Quiet) { Write-Host ("  {0} {1,-5} HTTP {2}  {3}" -f $(if ($good) { 'OK ' } else { 'NO ' }), $id, $r.Code, $mode) }
    if ($good -or $mode) { Invoke-Lcu $lcu '/lol-lobby/v2/lobby' 'DELETE' | Out-Null; Start-Sleep -Milliseconds 1500 }
  }
  # no lobby opened at all = the client wasn't ready, not that every mode is gone: keep the old routes
  if (-not $ok.Count) { Write-Host '  [Routes] no lobby opened - client not ready, routes kept'; return @{ ok = $ok; no = $no } }
  try { Set-Content -LiteralPath $routesFile -Value (@{ time = (Get-Date -Format 's'); ok = @($ok); no = @($no) } | ConvertTo-Json -Compress) -Encoding UTF8 } catch {}
  Write-Host "  [Routes] updated - working lobbies: $($ok -join ', ')"
  return @{ ok = $ok; no = $no }
}
# a lobby failed or was the wrong one: test every route once, then enter the best working one
$script:recovered = $false
function Recover-Lobby($lcu, $why) {
  if ($script:recovered) { return $false }
  $script:recovered = $true
  Write-Host "  [Play] $why - checking which lobbies work"
  $res = Test-Queues $lcu -Quiet
  if (-not $res -or -not $res.ok.Count) { Write-Host "  [Play] could not open a lobby"; return $false }
  $want = @(if ($playList.Count -gt 0) { $playList } else { @([int]$playQueue, [int]$playFallback) }) + @($playFallback, 2400, 450, 400)
  $pick = $want | Where-Object { $res.ok -contains [int]$_ } | Select-Object -First 1
  if (-not $pick) { $pick = $res.ok[0] }
  $r = Invoke-Lcu $lcu '/lol-lobby/v2/lobby' 'POST' "{`"queueId`":$pick}"
  for ($k = 0; $k -lt 8; $k++) {
    Start-Sleep -Milliseconds 1000
    $g = Invoke-Lcu $lcu '/lol-gameflow/v1/gameflow-phase'
    if ($g.Body -match 'Lobby') { Write-Host "  [Play] lobby open (queue $pick)"; return $true }
  }
  Write-Host "  [Play] could not open a lobby"
  return $false
}

# press Play: open a lobby, the same as Play > Confirm in the client
function Press-Play {
  if ("$playQueue" -eq '0') { return $true }
  $cands = @(); $ci = 0
  for ($i = 1; $i -le 6; $i++) {
    if (Test-InGame) { return $true }
    $lcu = Get-Lcu
    if ($lcu) {
      $g = Invoke-Lcu $lcu '/lol-gameflow/v1/gameflow-phase'
      if ($g.Body -match 'Lobby|Matchmaking|ChampSelect|ReadyCheck|InProgress') { Write-Host "  [Play] already in $($g.Body.Trim('"'))"; return $true }
      if ($cands.Count -eq 0) { $cands = @(Resolve-Queue $lcu) }
      $queueId = $cands[[Math]::Min($ci, $cands.Count - 1)]
      $r = Invoke-Lcu $lcu '/lol-lobby/v2/lobby' 'POST' "{`"queueId`":$queueId}"
      Write-Host "  [Play] lobby request for queue $queueId - HTTP $($r.Code)"
      for ($k = 0; $k -lt 8; $k++) {
        Start-Sleep -Milliseconds 500
        $g = Invoke-Lcu $lcu '/lol-gameflow/v1/gameflow-phase'
        if ($g.Body -match 'Lobby') {
          $actual = Get-LobbyQueue $lcu
          if ($actual -gt 0 -and $actual -ne $queueId) { Write-Host "  [Play] wrong lobby (asked $queueId, got $actual)"; return (Recover-Lobby $lcu 'wrong lobby') }
          Write-Host "  [Play] lobby open (queue $queueId)"; return $true
        }
        if ($r.Code -match '^4' -and $r.Code -ne '423') { break }   # refused: no point waiting
      }
      # refused for this queue (not available / not allowed): try the next candidate
      if ($r.Code -match '^4' -and $r.Code -ne '423' -and $ci -lt $cands.Count - 1) { $ci++ }
      Write-Host "  [Play] try $i - HTTP $($r.Code), phase $($g.Body)"
    }
    Start-Sleep -Milliseconds 800
  }
  $lcu = Get-Lcu
  if ($lcu) { return (Recover-Lobby $lcu 'lobby did not open') }
  Write-Host "  [Play] could not open a lobby"
  return $false
}
function Set-LeagueRegion($region) {
  $f = Join-Path $leagueDir 'Config\LeagueClientSettings.yaml'
  if (-not (Test-Path $f)) { Write-Host "  region file not found - skipped"; return }
  try {
    $txt = [System.IO.File]::ReadAllText($f)
    $rx  = [regex]'(?m)^(\s*region:\s*)"?[^"\r\n]*"?'
    $new = $rx.Replace($txt, ('${1}"' + $region + '"'), 1)
    if ($new -ne $txt) {
      Copy-Item $f "$f.bak" -Force
      [System.IO.File]::WriteAllText($f, $new)          # UTF-8 without BOM
      Write-Host "  region set to $region"
    } else { Write-Host "  region already $region" }
  } catch { Write-Host "  could not set region: $($_.Exception.Message)" }
}

function Stop-Log { try { Stop-Transcript | Out-Null } catch {} }

# ======================= RUN =======================
if ($Ugg) {   # open a u.gg page in the u.gg window slot (used by the tray when you lock a champion)
  $app = $sideApps | Where-Object { $_.Name -eq 'u.gg' } | Select-Object -First 1
  if ($DryRun) { Write-Host "would open $Ugg in the u.gg window" } else {
    $old = Find-AppWindow $app
    if ($old -ne [IntPtr]::Zero) { [Win]::Close($old); Start-Sleep -Milliseconds 1200 }
    Remove-Item -LiteralPath (Join-Path $store "_u.gg.hwnd") -ErrorAction SilentlyContinue
    $app.Args = @('--new-window', "--app=$Ugg")
    Start-SideApp $app
    Place-App $app 10
  }
  Stop-Log; exit 0
}

if ($TestQueues) {   # kept for manual use: probe every lobby and save the routes
  $lcu = Get-Lcu
  if (-not $lcu) { Write-Host "Client is not open - start League first."; Stop-Log; exit 1 }
  Write-Host "[Lobby test]"
  $res = Test-Queues $lcu
  if (-not $res) { Write-Host "Client is busy - finish that first."; Stop-Log; exit 1 }
  Write-Host "Lobby test done."
  Stop-Log; exit 0
}

if ($Exit) {
  if ($DryRun) { Write-Host "would bring the taskbar back and close u.gg" }
  else {
    Show-AllTaskbars
    foreach ($app in $sideApps) {
      if ($app.CloseOnExit) {
        $h = Find-AppWindow $app
        if ($h -ne [IntPtr]::Zero) { [Win]::Close($h); Write-Host "  [$($app.Name)] closed" }
      }
    }
    Remove-Item -LiteralPath (Join-Path $store "_u.gg.hwnd") -ErrorAction SilentlyContinue
  }
  Stop-Log; exit 0
}

if ($Layout) {
  if ($DryRun) { Write-Host "would re-arrange: $(($sideApps | ForEach-Object { $_.Name }) -join ', '), League" }
  else { Hide-SideTaskbar; foreach ($app in $sideApps) { Place-App $app 3 }; Place-App $leagueWin 3 }
  Stop-Log; exit 0
}

if ($Fix) {
  if ($DryRun) { Write-Host "would check the running client and repair it if needed" }
  else {
    $ok = Ensure-League
    if ($ok) { Place-App $leagueWin 5 }
    Stop-Log
    if ($ok) { exit 0 } else { exit 2 }
  }
  Stop-Log; exit 0
}

# text menu (only when run by hand in a console)
if (-not $Account -and -not $Keep -and -not $StatusFile) {
  $names = @(Get-ChildItem $store -Filter *.yaml | ForEach-Object { $_.BaseName })
  if ($names.Count -gt 0) {
    Write-Host "Mise"
    for ($i = 0; $i -lt $names.Count; $i++) { Write-Host "  $($i + 1)) $($names[$i])" }
    $pick = Read-Host "Account number (Enter = keep current login)"
    if ($pick -match '^\d+$' -and [int]$pick -ge 1 -and [int]$pick -le $names.Count) { $Account = $names[[int]$pick - 1] }
  }
}

# account switch
if ($Account) {
  $saved = Join-Path $store "$Account.yaml"
  if (-not (Test-Path $saved)) { Write-Host "No saved login called '$Account'. Run -Save `"$Account`" first."; Stop-Log; exit 1 }
  $region = ($Account.Trim() -split '\s+')[-1].ToUpper()
  Write-Host "[Account] $Account"
  if ($DryRun) {
    Write-Host "  would close Riot/League, load the saved login, set region $region"
  } else {
    if (Test-InGame) { Write-Host "  a game is running - finish it first."; Stop-Log; exit 1 }
    # clicking the account that is already logged in with the client open changes nothing
    $alreadyOn = $false
    try { $alreadyOn = ((Get-Content -LiteralPath (Join-Path $store '_active.txt') -Raw).Trim() -eq $Account) -and [bool](Get-Process -Name 'LeagueClientUx' -ErrorAction SilentlyContinue) } catch {}
    if ($alreadyOn) { Write-Host "  already logged in as $Account - nothing to change" } else {
    # Riot rotates the saved login while you use it: keep the copy of the account we are leaving fresh,
    # otherwise its old copy can be rejected next time ("login failed"). Close Riot gently so it writes the file.
    $leaving = ''; $okFile = Join-Path $store '_login-ok.txt'; $actFile = Join-Path $store '_active.txt'
    if ((Test-Path $okFile) -and (Test-Path $actFile)) {
      $leaving = (Get-Content -LiteralPath $actFile -Raw).Trim()
      if ($leaving -ne (Get-Content -LiteralPath $okFile -Raw).Trim()) { $leaving = '' }
    }
    if ($leaving -and $leaving -ne $Account -and (Test-Path $riotData) -and (Test-Path (Join-Path $store "$leaving.yaml"))) {
      $before = (Get-Item $riotData).LastWriteTimeUtc
      foreach ($n in 'LeagueClientUx', 'Riot Client') { Get-Process -Name $n -ErrorAction SilentlyContinue | ForEach-Object { try { $_.CloseMainWindow() | Out-Null } catch {} } }
      for ($k = 0; $k -lt 28; $k++) {
        if (-not (Get-Process -Name 'RiotClientServices', 'Riot Client' -ErrorAction SilentlyContinue)) { break }
        if ((Get-Item $riotData).LastWriteTimeUtc -ne $before) { Start-Sleep -Milliseconds 400; break }   # written: no need to wait for the rest
        Start-Sleep -Milliseconds 250
      }
      if ((Get-Item $riotData).Length -gt 1000) {
        $dst = Join-Path $store "$leaving.yaml"
        Copy-Item $dst "$dst.prev" -Force
        Copy-Item $riotData $dst -Force
        Write-Host "  kept the login of $leaving fresh"
      }
    }
    Remove-Item -LiteralPath $okFile -Force -ErrorAction SilentlyContinue
    Stop-League; Stop-Riot
    Copy-Item $saved $riotData -Force
    Set-Content -LiteralPath (Join-Path $store '_active.txt') -Value $Account -Encoding UTF8
    if ($setRegion -and ($regions -contains $region)) { Set-LeagueRegion $region }
    }
  }
}

if ($DryRun) {
  Write-Host "[League] would start the client, then health-check it (fix ladder: UI reload, client restart, Riot restart)"
  foreach ($app in $sideApps) { Write-Host "[$($app.Name)] would start: $($app.Exe) $($app.Args -join ' ')" }
  Write-Host "[Spotify] mode: $spotifyMode"
  exit 0
}

Write-Host "[Starting]"
if (-not (Get-Process -Name 'LeagueClientUx' -ErrorAction SilentlyContinue)) { Start-League; Write-Host "  [League] starting" }
foreach ($app in $sideApps) { if ($app.ContainsKey('LaunchOnStart') -and -not $app.LaunchOnStart) { continue }; Start-SideApp $app }

Write-Host "[Layout]"
Hide-SideTaskbar
$script:quickPlace = $true
foreach ($app in $sideApps) { Place-App $app $windowTimeout }
$script:quickPlace = $false

$ok = Ensure-League
if ($ok) {
  Place-App $leagueWin 10
  try { $cur = (Get-Content -LiteralPath (Join-Path $store '_active.txt') -Raw).Trim(); if ($cur) { Set-Content -LiteralPath (Join-Path $store '_login-ok.txt') -Value $cur -Encoding UTF8 } } catch {}
}

# press Play, then re-check: the client often breaks right after the lobby opens
if ($ok -and "$playQueue" -ne '0') {
  Write-Host "[Play]"
  $played = Press-Play
  Start-Sleep -Seconds 3
  if (-not (Test-InGame) -and (Test-Client) -ne '') {
    Write-Host "  client broke after Play - repairing"
    $ok = Ensure-League
    if ($ok) { Place-App $leagueWin 10; Press-Play | Out-Null }
  }
}

# some apps move themselves after loading - put them back once (the wait after Play already covers it)
if (-not ($ok -and "$playQueue" -ne '0')) { Start-Sleep -Seconds 2 }
foreach ($app in $sideApps) { Place-App $app 3 }

if ($ok) { Write-Host "Mise ready." } elseif ($script:loginRejected) { Write-Host "Mise stopped: the saved login was rejected." } else { Write-Host "Mise finished, but the client needs a manual look." }
Stop-Log
if ($ok) { exit 0 } else { exit 2 }
