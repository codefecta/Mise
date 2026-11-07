# Mise (shared edition) - core library. Dot-sourced by the runner, the tray and the builder.
# Everything the routines can do lives here, driven by a JSON config:  %APPDATA%\Mise\config.json
$script:MiseVersion = '0.6.1'
$script:IsWin = ($PSVersionTable.PSEdition -ne 'Core') -or [bool]$IsWindows
$script:MiseDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:DataDir  = if ($env:MISE_DATA) { $env:MISE_DATA } elseif ($env:APPDATA) { Join-Path $env:APPDATA 'Mise' } else { Join-Path $HOME '.mise' }
$script:CfgPath  = Join-Path $script:DataDir 'config.json'
$script:LogPath  = Join-Path $script:DataDir 'mise.log'
New-Item -ItemType Directory -Force -Path $script:DataDir | Out-Null

# ======================= config =======================
$script:DefaultSettings = [ordered]@{
  autoAccept = $false; champPage = $true         # League helpers (tray): u.gg page of your champion is on by default
  queue = 2400                                    # one global lobby after login (queue id, 0 = none)
  accent = '#D8895A'                              # copper; users can pick another accent
  animations = $true
  toastCorner = 'bottom-left'                     # bottom-left | bottom-right | top-left | top-right
  homePos = 'remember'                            # remember | top-left | top-center | top-right | center | bottom-left | bottom-right
  homeMonitor = ''                                # monitor id for the preset spot ('' = main screen)
  homeX = -1; homeY = -1                          # last dragged spot (remember)
  updateRepo = 'codefecta/Mise'                                 # GitHub owner/repo for the update check ('' = off)
  lastUpdateCheck = ''
  introDone = $false                              # the short intro was shown once
  optsOpen = $true                                # Options section unfolded in the Mise window
}
function New-MiseConfig { [pscustomobject]@{ version = 4; firstRunDone = $false; monitors = @(); routines = @(); settings = [pscustomobject]$script:DefaultSettings } }
function Get-MiseSetting($cfg, [string]$k) {
  try { if ($cfg.settings.PSObject.Properties.Name -contains $k) { $v = $cfg.settings.$k; if (-not ($k -eq 'updateRepo' -and -not "$v".Trim())) { return $v } } } catch {}
  return $script:DefaultSettings[$k]
}
function Set-MiseSetting([string]$k, $v) {
  $cfg = Get-MiseConfig
  if ($cfg.settings.PSObject.Properties.Name -contains $k) { $cfg.settings.$k = $v } else { $cfg.settings | Add-Member $k $v }
  Save-MiseConfig $cfg
  return $cfg
}

function Get-MiseConfig {
  if (-not (Test-Path $script:CfgPath)) { return (New-MiseConfig) }
  try {
    $c = Get-Content -LiteralPath $script:CfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $c.monitors)  { $c | Add-Member -Force monitors @() }
    if (-not $c.routines)  { $c | Add-Member -Force routines @() }
    if (-not $c.settings)  { $c | Add-Member -Force settings ([pscustomobject]@{}) }
    foreach ($k in $script:DefaultSettings.Keys) { if (-not ($c.settings.PSObject.Properties.Name -contains $k)) { $c.settings | Add-Member $k $script:DefaultSettings[$k] } }
    # 0.5: the u.gg page of your champion is on by default (u.gg no longer opens at the start of a routine)
    if ([int]$c.version -lt 3) { $c.settings.champPage = $true; $c.version = 3 }
    # 0.6: routines are made of tiles on a map. Old step routines are not carried over (fresh start, decided 6 Nov);
    # screens, accounts and settings stay. A copy of the old file is kept as config-v3.json.
    if ([int]$c.version -lt 4) {
      try { Copy-Item -LiteralPath $script:CfgPath -Destination (Join-Path $script:DataDir 'config-v3.json') -Force } catch {}
      $c.routines = @(); $c.version = 4
      foreach ($k in @('leagueOnLogin', 'quietRun')) { $c.settings.PSObject.Properties.Remove($k) }
      Save-MiseConfig $c
    }
    $c.monitors = @($c.monitors); $c.routines = @($c.routines)
    foreach ($r in $c.routines) {
      foreach ($k in @('tiles', 'taskbar')) { if (-not ($r.PSObject.Properties.Name -contains $k)) { $r | Add-Member $k @() } else { $r.$k = @($r.$k) } }
      if (-not ($r.PSObject.Properties.Name -contains 'league')) { $r | Add-Member league $false }
      if (-not ($r.PSObject.Properties.Name -contains 'card')) { $r | Add-Member card $null }
    }
    return $c
  } catch { Write-Log "config unreadable: $($_.Exception.Message)"; return (New-MiseConfig) }
}

function Save-MiseConfig($cfg) {
  $tmp = "$($script:CfgPath).tmp"
  $json = $cfg | ConvertTo-Json -Depth 12
  [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
  Move-Item -LiteralPath $tmp -Destination $script:CfgPath -Force
}

function Write-Log($m) { try { Add-Content -LiteralPath $script:LogPath -Value ("{0} {1}" -f (Get-Date -Format s), $m) } catch {} }

function New-Id { ([guid]::NewGuid().ToString('N')).Substring(0, 8) }

# ======================= zones =======================
$script:ZonePresets = [ordered]@{
  'Full screen'   = @{ x = 0;   y = 0;    w = 1;    h = 1 }
  'Left half'     = @{ x = 0;   y = 0;    w = 0.5;  h = 1 }
  'Right half'    = @{ x = 0.5; y = 0;    w = 0.5;  h = 1 }
  'Top half'      = @{ x = 0;   y = 0;    w = 1;    h = 0.5 }
  'Bottom half'   = @{ x = 0;   y = 0.5;  w = 1;    h = 0.5 }
  'Top third'     = @{ x = 0;   y = 0;    w = 1;    h = 0.3333 }
  'Middle third'  = @{ x = 0;   y = 0.3333; w = 1;  h = 0.3334 }
  'Bottom third'  = @{ x = 0;   y = 0.6667; w = 1;  h = 0.3333 }
  'Top-left'      = @{ x = 0;   y = 0;    w = 0.5;  h = 0.5 }
  'Top-right'     = @{ x = 0.5; y = 0;    w = 0.5;  h = 0.5 }
  'Bottom-left'   = @{ x = 0;   y = 0.5;  w = 0.5;  h = 0.5 }
  'Bottom-right'  = @{ x = 0.5; y = 0.5;  w = 0.5;  h = 0.5 }
  'Centre (keep size)' = @{ x = 0; y = 0; w = 0; h = 0 }     # w = h = 0 means: keep the window's size, centre it
}
function Get-ZonePixels($screen, $zone, [bool]$fullBounds) {
  $a = if ($fullBounds) { $screen.Bounds } else { $screen.WorkingArea }
  return @{ X = [int]($a.X + $zone.x * $a.Width); Y = [int]($a.Y + $zone.y * $a.Height)
            W = [int]($zone.w * $a.Width);        H = [int]($zone.h * $a.Height) }
}

# ======================= hotkeys (parse only; registering happens in the tray) =======================
function ConvertTo-Hotkey([string]$text) {
  # "Ctrl+Alt+L" -> @{ Mods = 3; Vk = 76 }   (MOD_ALT=1, CTRL=2, SHIFT=4, WIN=8). $null when invalid.
  if (-not $text) { return $null }
  $mods = 0; $key = $null
  foreach ($p in ($text -split '\+')) {
    switch -Regex ($p.Trim()) {
      '^(ctrl|control)$' { $mods = $mods -bor 2; continue }
      '^alt$'            { $mods = $mods -bor 1; continue }
      '^shift$'          { $mods = $mods -bor 4; continue }
      '^(win|windows)$'  { $mods = $mods -bor 8; continue }
      default            { $key = $p.Trim().ToUpper() }
    }
  }
  if (-not $key -or $mods -eq 0) { return $null }                # a bare key would block normal typing
  if ($key -match '^[A-Z]$') { return @{ Mods = $mods; Vk = [int][char]$key } }
  if ($key -match '^[0-9]$') { return @{ Mods = $mods; Vk = [int][char]$key } }
  if ($key -match '^F([1-9]|1[0-9]|2[0-4])$') { return @{ Mods = $mods; Vk = 0x6F + [int]$Matches[1] } }
  return $null
}
function Get-HotkeyConflicts($cfg, [string]$text, [string]$exceptRoutineId) {
  $mine = ConvertTo-Hotkey $text
  if (-not $mine) { return @('not a valid hotkey (use e.g. Ctrl+Alt+1)') }
  $out = @()
  foreach ($r in $cfg.routines) {
    if ($r.id -eq $exceptRoutineId -or -not $r.hotkey) { continue }
    $o = ConvertTo-Hotkey $r.hotkey
    if ($o -and $o.Mods -eq $mine.Mods -and $o.Vk -eq $mine.Vk) { $out += "already used by routine '$($r.name)'" }
  }
  return $out
}
function Get-FreeHotkey($cfg, [string]$exceptRoutineId) {
  $cands = @(1..9 | ForEach-Object { "Ctrl+Alt+$_" }) + @(1..12 | ForEach-Object { "Ctrl+Shift+F$_" })
  foreach ($c in $cands) { if ((Get-HotkeyConflicts $cfg $c $exceptRoutineId).Count -eq 0) { return $c } }
  return $null
}

# ======================= Windows-only parts =======================
if ($script:IsWin) {
Add-Type @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class MiseWin {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int w, int hgt, uint f);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int i, int v);
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
  [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int a, out RECT r, int size);
  [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int size);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public class Info { public IntPtr H; public uint Pid; public string Title; public string Cls; }

  public static List<Info> All() {
    List<Info> list = new List<Info>();
    EnumWindows(delegate (IntPtr h, IntPtr l) {
      if (!IsWindowVisible(h)) return true;
      if ((GetWindowLong(h, -20) & 0x80) != 0) return true;                       // tool windows
      int cloaked; if (DwmGetWindowAttribute(h, 14, out cloaked, 4) == 0 && cloaked != 0) return true;
      StringBuilder t = new StringBuilder(512); GetWindowText(h, t, 512);
      if (t.Length == 0) return true;
      StringBuilder c = new StringBuilder(128); GetClassName(h, c, 128);
      string cls = c.ToString();
      if (cls == "Progman" || cls == "WorkerW" || cls == "Shell_TrayWnd" || cls == "Shell_SecondaryTrayWnd") return true;
      uint pid; GetWindowThreadProcessId(h, out pid);
      Info i = new Info(); i.H = h; i.Pid = pid; i.Title = t.ToString(); i.Cls = cls; list.Add(i);
      return true;
    }, IntPtr.Zero);
    return list;
  }
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
  public static void Close(IntPtr h) { PostMessage(h, 0x0010, IntPtr.Zero, IntPtr.Zero); }
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  public static bool IsTopmost(IntPtr h) { return (GetWindowLong(h, -20) & 0x8) != 0; }
  // the visible rectangle of a window (without Windows' invisible borders): x, y, w, h
  public static int[] VisibleRect(IntPtr h) {
    RECT r;
    if (DwmGetWindowAttribute(h, 9, out r, Marshal.SizeOf(typeof(RECT))) != 0) { if (!GetWindowRect(h, out r)) return null; }
    return new int[] { r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top };
  }
  public static void StripCaption(IntPtr h) {
    int s = GetWindowLong(h, -16);
    SetWindowLong(h, -16, (s & ~0x00C00000) | 0x00040000);
    SetWindowPos(h, IntPtr.Zero, 0, 0, 0, 0, 0x0027);
  }
  [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
  public static void ClickXY(int x, int y) {
    SetCursorPos(x, y); System.Threading.Thread.Sleep(150);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero); System.Threading.Thread.Sleep(60);
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
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
  public static void Centre(IntPtr h, int ax, int ay, int aw, int ah) {
    RECT r; if (!GetWindowRect(h, out r)) return;
    int w = r.Right - r.Left, hh = r.Bottom - r.Top;
    SetWindowPos(h, IntPtr.Zero, ax + (aw - w) / 2, ay + (ah - hh) / 2, 0, 0, 0x0045);
  }
}
"@
try { [MiseWin]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null } catch {}
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
}

# ======================= monitors =======================
function Get-Screens {
  $i = 0
  return @([System.Windows.Forms.Screen]::AllScreens | ForEach-Object {
    $i++
    [pscustomobject]@{ Index = $i; DeviceName = $_.DeviceName; Primary = $_.Primary; Bounds = $_.Bounds; WorkingArea = $_.WorkingArea
                       Vertical = ($_.Bounds.Height -gt $_.Bounds.Width); Size = "$($_.Bounds.Width)x$($_.Bounds.Height)" }
  })
}
# a saved monitor is found by its device name first, then by resolution + orientation, finally the primary screen
function Resolve-Monitor($cfg, [string]$id) {
  $screens = Get-Screens
  $m = $cfg.monitors | Where-Object { $_.id -eq $id } | Select-Object -First 1
  if (-not $m) { return ($screens | Where-Object Primary | Select-Object -First 1) }
  $hit = $screens | Where-Object { $_.DeviceName -eq $m.deviceName -and $_.Size -eq $m.size } | Select-Object -First 1
  if (-not $hit) { $hit = $screens | Where-Object { $_.Size -eq $m.size } | Select-Object -First 1 }
  if (-not $hit) { $hit = $screens | Where-Object { $_.Vertical -eq [bool]$m.vertical } | Select-Object -First 1 }
  if (-not $hit) { $hit = $screens | Where-Object Primary | Select-Object -First 1 }
  return $hit
}

# ======================= windows =======================
function Get-WinSnapshot { if (-not $script:IsWin) { return @() }; return @([MiseWin]::All()) }

function Get-ProcName([uint32]$procId) { try { (Get-Process -Id $procId -ErrorAction Stop).ProcessName } catch { '' } }


function Get-HiddenBarMonitors { $f = Join-Path $script:DataDir '_taskbar-hidden.txt'; if (Test-Path $f) { @((Get-Content -LiteralPath $f) | Select-Object -Skip 1) } else { @() } }

# ---------- what happens to a window when the routine exits (per step: leave | close | restore) ----------
function Track-ForExit($step, [IntPtr]$h, $ctx) {
  $mode = "$($step.onExit)"
  if ($mode -ne 'close' -and $mode -ne 'restore') { return }
  if (@($ctx.Track | Where-Object { $_.h -eq [int64]$h }).Count) { return }
  $r = $null; try { $r = [MiseWin]::VisibleRect($h) } catch {}
  $ctx.Track += [pscustomobject]@{ h = [int64]$h; mode = $mode; name = "$($step.name)"; rect = $(if ($r) { @($r) } else { @() }) }
}
function Save-ExitTrack($routine, $ctx) {
  $f = Join-Path $script:DataDir "_exit-$($routine.id).json"
  $old = @(); if (Test-Path $f) { try { $old = @(Get-Content -LiteralPath $f -Raw | ConvertFrom-Json) } catch {} }
  $all = @($old) + @($ctx.Track) | Where-Object { $_ }
  if (@($all).Count) { Set-Content -LiteralPath $f -Value (ConvertTo-Json @($all) -Depth 5) -Encoding UTF8 }
}
function Invoke-ExitTrack($routine) {
  $f = Join-Path $script:DataDir "_exit-$($routine.id).json"
  if (-not (Test-Path $f)) { return }
  $items = @(); try { $items = @(Get-Content -LiteralPath $f -Raw | ConvertFrom-Json) } catch {}
  foreach ($t in $items) {
    $h = [IntPtr][int64]$t.h
    if (-not [MiseWin]::IsWindow($h)) { continue }
    if ($t.mode -eq 'close') { [MiseWin]::Close($h); Say "[$($t.name)] closed" }
    elseif ($t.mode -eq 'restore' -and @($t.rect).Count -eq 4) { [MiseWin]::PlaceExact($h, [int]$t.rect[0], [int]$t.rect[1], [int]$t.rect[2], [int]$t.rect[3]); Say "[$($t.name)] put back" }
  }
  Remove-Item -LiteralPath $f -ErrorAction SilentlyContinue
}

# ---------- Spotify miniplayer: the always-on-top Spotify window; opened through accessibility if needed ----------
function Open-SpotifyMini([IntPtr]$main) {
  try {
    Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes -ErrorAction Stop
    # a minimized Spotify has no usable UI: bring it back, big enough to show its top bar
    [MiseWin]::ShowWindow($main, 9) | Out-Null; Start-Sleep -Milliseconds 400
    [MiseWin]::ShowWindow($main, 3) | Out-Null; [MiseWin]::SetForegroundWindow($main) | Out-Null
    Start-Sleep -Milliseconds 1200
    $root = [System.Windows.Automation.AutomationElement]::FromHandle($main)
    $all = [System.Windows.Automation.Condition]::TrueCondition
    # Chromium builds its accessibility tree only after the first query: ask repeatedly
    for ($i = 0; $i -lt 12; $i++) {
      foreach ($e in $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $all)) {
        $n = ''; try { $n = $e.Current.Name } catch {}
        if ($n -match 'mini\s*-?\s*player') {
          try { ($e.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)).Invoke(); return $true } catch {}
          try { $r = $e.Current.BoundingRectangle; if ($r.Width -gt 0) { [MiseWin]::ClickXY([int]($r.X + $r.Width / 2), [int]($r.Y + $r.Height / 2)); return $true } } catch {}
        }
      }
      Start-Sleep -Milliseconds 700
    }
    $names = @(); foreach ($e in $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $all)) { try { $n = $e.Current.Name; if ($n -and $n.Length -lt 40) { $names += $n } } catch {} }
    Write-Log ("[Spotify-diag] no Mini Player control found; " + $names.Count + " named controls: " + ((@($names | Select-Object -Unique | Select-Object -First 40)) -join ' | '))
  } catch { Write-Log "Open-SpotifyMini: $($_.Exception.Message)" }
  return $false
}
function Get-SpotifyWindows { @(Get-WinSnapshot | Where-Object { (Get-ProcName $_.Pid) -eq 'Spotify' }) }

# ======================= taskbars =======================
function Hide-MonitorTaskbar($screen, $ctx) {
  $b = $screen.Bounds
  $bars = @([MiseWin]::Taskbars($b.Left, $b.Top, $b.Right, $b.Bottom))
  foreach ($h in $bars) { [MiseWin]::ShowWindow($h, 0) | Out-Null }
  if ($bars.Count) { $ctx.HiddenBars += $screen.DeviceName; $f = Join-Path $script:DataDir '_taskbar-hidden.txt'; $names = @(Get-HiddenBarMonitors) + $screen.DeviceName | Select-Object -Unique; Set-Content -LiteralPath $f -Value (@(Get-Date -Format s) + $names) }
  return $bars.Count
}
function Show-AllTaskbars {
  $bars = @([MiseWin]::Taskbars(-100000, -100000, 100000, 100000))
  foreach ($h in $bars) { [MiseWin]::ShowWindow($h, 5) | Out-Null }
  Remove-Item -LiteralPath (Join-Path $script:DataDir '_taskbar-hidden.txt') -ErrorAction SilentlyContinue
  return $bars.Count
}

# ======================= apps =======================
function Get-InstalledApps {
  # Start-menu apps incl. Store apps: @{ Name; Id }  (launched with shell:AppsFolder\<Id>)
  try { return @(Get-StartApps | Sort-Object Name | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Id = $_.AppID } }) } catch { return @() }
}

# ======================= run context and messages =======================
function Say($m) { Write-Host "  $m"; Write-Log $m }
function New-Ctx { @{ HiddenBars = @(); Account = ''; StatusFile = ''; Pending = @(); Track = @() } }
function Test-RiotInstalled { Test-Path "$env:SystemDrive\Riot Games\Riot Client\RiotClientServices.exe" }
