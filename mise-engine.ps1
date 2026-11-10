# Mise (shared edition) - routine engine (routines made of tiles, config v4).
# Needs mise-core.ps1 and mise-layout.ps1 loaded first. Windows calls live here; the maths is in mise-layout.ps1.

if ($script:IsWin) {
Add-Type @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class MiseWin2 {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct DISPLAY_DEVICE {
    public int cb;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
    public int StateFlags;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
  }
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool EnumDisplayDevices(string dev, uint i, ref DISPLAY_DEVICE dd, uint flags);
  [DllImport("user32.dll")] static extern bool IsZoomed(IntPtr h);
  [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int w, int hh, uint f);
  [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int a, out RECT r, int size);
  [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool QueryFullProcessImageName(IntPtr h, int flags, StringBuilder sb, ref int size);

  // "\\.\DISPLAY1|\\?\DISPLAY#MSI3CB0#5&1a2b&0&UID4353#{...}" for every active monitor
  public static string[] MonitorIds() {
    List<string> res = new List<string>();
    DISPLAY_DEVICE ad = new DISPLAY_DEVICE(); ad.cb = Marshal.SizeOf(ad);
    for (uint i = 0; EnumDisplayDevices(null, i, ref ad, 0); i++) {
      if ((ad.StateFlags & 1) != 0) {
        DISPLAY_DEVICE md = new DISPLAY_DEVICE(); md.cb = Marshal.SizeOf(md);
        if (EnumDisplayDevices(ad.DeviceName, 0, ref md, 1)) res.Add(ad.DeviceName + "|" + md.DeviceID);
        else res.Add(ad.DeviceName + "|");
      }
      ad = new DISPLAY_DEVICE(); ad.cb = Marshal.SizeOf(ad);
    }
    return res.ToArray();
  }
  public static string ExePath(uint pid) {
    IntPtr h = OpenProcess(0x1000, false, pid);
    if (h == IntPtr.Zero) return "";
    StringBuilder sb = new StringBuilder(1024); int n = sb.Capacity;
    string r = QueryFullProcessImageName(h, 0, sb, ref n) ? sb.ToString() : "";
    CloseHandle(h);
    return r;
  }
  // out of maximized / minimized state, so a move sticks
  [DllImport("kernel32.dll")] static extern void Sleep(uint ms);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [StructLayout(LayoutKind.Sequential)] public struct WINDOWPLACEMENT { public int length, flags, showCmd; public int ptMinX, ptMinY, ptMaxX, ptMaxY; public RECT rcNormal; }
  [DllImport("user32.dll")] static extern bool GetWindowPlacement(IntPtr h, ref WINDOWPLACEMENT p);
  // out of maximized / minimized state, so a move sticks (a window minimized while maximized needs two restores)
  public static void Unsnap(IntPtr h) {
    for (int i = 0; i < 3 && (IsZoomed(h) || IsIconic(h)); i++) { ShowWindow(h, 9); Sleep(60); }
  }
  // size of the window in its normal (restored) state, also while minimized
  public static long NormalArea(IntPtr h) {
    WINDOWPLACEMENT p = new WINDOWPLACEMENT(); p.length = Marshal.SizeOf(p);
    if (!GetWindowPlacement(h, ref p)) return 0;
    return (long)(p.rcNormal.Right - p.rcNormal.Left) * (p.rcNormal.Bottom - p.rcNormal.Top);
  }
  public static uint Pid(IntPtr h) { uint pid; GetWindowThreadProcessId(h, out pid); return pid; }
  public static int[] Visible(IntPtr h) {
    RECT r;
    if (DwmGetWindowAttribute(h, 9, out r, Marshal.SizeOf(typeof(RECT))) != 0) { if (!GetWindowRect(h, out r)) return null; }
    return new int[] { r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top };
  }
  // the smallest size the app accepts: shrink it for a moment, read what it allowed, put it back
  public static int[] ProbeMinSize(IntPtr h) {
    RECT wr; if (!GetWindowRect(h, out wr)) return null;
    SetWindowPos(h, IntPtr.Zero, 0, 0, 1, 1, 0x0016);
    int[] v = Visible(h);
    SetWindowPos(h, IntPtr.Zero, wr.Left, wr.Top, wr.Right - wr.Left, wr.Bottom - wr.Top, 0x0014);
    if (v == null) return null;
    return new int[] { v[2], v[3] };
  }
}
"@
}

# ======================= monitors (by hardware, not by Windows' number) =======================
# hardware key: model code + connection id, e.g. "MSI3CB0#UID4353". The model code alone helps when the cable moved.
function ConvertTo-MonitorKey([string]$deviceId) {
  if ($deviceId -match 'DISPLAY#([^#]+)#([^#]+)') { $model = $Matches[1]; $inst = $Matches[2]; $uid = if ($inst -match '(UID\d+)') { $Matches[1] } else { $inst }; return "$model#$uid" }
  return ''
}
function Get-MonitorKeys {
  $map = @{}
  if (-not $script:IsWin) { return $map }
  try { foreach ($s in [MiseWin2]::MonitorIds()) { $p = $s -split '\|', 2; $map[$p[0]] = ConvertTo-MonitorKey $p[1] } } catch {}
  return $map
}
# connected monitors that the config knows: @{ id; name; DeviceName; X; Y; W; H; Work; Vertical; Primary }
function Get-LiveMonitors($cfg) {
  $keys = Get-MonitorKeys
  $screens = @(Get-Screens)
  $out = @(); $used = @()
  foreach ($m in @($cfg.monitors)) {
    $hit = $null
    if ($m.hw) { $hit = $screens | Where-Object { $keys[$_.DeviceName] -and $keys[$_.DeviceName] -eq $m.hw -and $used -notcontains $_.DeviceName } | Select-Object -First 1 }
    if (-not $hit -and $m.hw) { $model = ($m.hw -split '#')[0]; $hit = $screens | Where-Object { $keys[$_.DeviceName] -like "$model#*" -and $_.Size -eq $m.size -and $used -notcontains $_.DeviceName } | Select-Object -First 1 }
    if (-not $hit) { $hit = $screens | Where-Object { $_.DeviceName -eq $m.deviceName -and $_.Size -eq $m.size -and $used -notcontains $_.DeviceName } | Select-Object -First 1 }
    if (-not $hit) { $hit = $screens | Where-Object { $_.Size -eq $m.size -and $used -notcontains $_.DeviceName } | Select-Object -First 1 }
    if (-not $hit) { continue }
    $used += $hit.DeviceName
    $out += @{ id = $m.id; name = $m.name; DeviceName = $hit.DeviceName; X = $hit.Bounds.X; Y = $hit.Bounds.Y; W = $hit.Bounds.Width; H = $hit.Bounds.Height
               Work = @{ id = $m.id; X = $hit.WorkingArea.X; Y = $hit.WorkingArea.Y; W = $hit.WorkingArea.Width; H = $hit.WorkingArea.Height }
               Vertical = $hit.Vertical; Primary = $hit.Primary }
  }
  return $out
}
# the area a routine's tiles fill on a monitor: the whole screen where the routine hides its taskbar, else the work area
function Get-TileArea($live, $routine) {
  if (@($routine.taskbar) -contains $live.id) { return @{ id = $live.id; X = $live.X; Y = $live.Y; W = $live.W; H = $live.H } }
  return $live.Work
}

# ======================= apps: who is this window, how to start it =======================
function Get-WindowExe([uint32]$procId) { try { return [MiseWin2]::ExePath($procId) } catch { return '' } }
# Store apps live under WindowsApps and start through their app id (PackageFamilyName!AppId)
function Get-StoreAppId([string]$exe) {
  if ($exe -notlike '*\WindowsApps\*') { return '' }
  try {
    $pkg = Get-AppxPackage | Where-Object { $_.InstallLocation -and $exe.StartsWith($_.InstallLocation + '\', [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
    if (-not $pkg) { return '' }
    $man = Get-AppxPackageManifest $pkg
    $app = @($man.Package.Applications.Application)[0]
    if ($app) { return "$($pkg.PackageFamilyName)!$($app.Id)" }
  } catch {}
  return ''
}
# the browser web tiles open in: the default one; Mise never uses Edge (decided 6 Nov), so with Edge as the default
# it takes the first installed Chrome, Brave, Vivaldi or Opera instead, and with none of those web tiles are skipped
function Get-DefaultBrowser {
  $progId = ''
  try { $progId = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice' -ErrorAction Stop).ProgId } catch {}
  $b = Get-BrowserKind $progId
  $exe = ''
  if ($b.Kind -ne 'edge') {
    try { $cmd = (Get-ItemProperty "Registry::HKEY_CLASSES_ROOT\$progId\shell\open\command" -ErrorAction Stop).'(default)'; if ($cmd -match '^"([^"]+)"') { $exe = $Matches[1] } elseif ($cmd -match '^(\S+)') { $exe = $Matches[1] } } catch {}
  }
  if ($b.Kind -eq 'edge' -or -not $exe) {
    $alts = @(
      @{ Id = 'ChromeHTML'; Paths = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe", "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe") },
      @{ Id = 'BraveHTML'; Paths = @("$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe", "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\Application\brave.exe") },
      @{ Id = 'VivaldiHTM'; Paths = @("$env:LOCALAPPDATA\Vivaldi\Application\vivaldi.exe", "$env:ProgramFiles\Vivaldi\Application\vivaldi.exe") },
      @{ Id = 'OperaStable'; Paths = @("$env:LOCALAPPDATA\Programs\Opera\opera.exe", "$env:LOCALAPPDATA\Programs\Opera GX\opera.exe") })
    $exe = ''
    foreach ($a in $alts) { $p = $a.Paths | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1; if ($p) { $b = Get-BrowserKind $a.Id; $exe = $p; break } }
    if (-not $exe) { $b = @{ Kind = 'none'; Name = 'no supported browser'; Clean = $false } }
  }
  $b.Exe = $exe; $b.Proc = if ($exe) { [IO.Path]::GetFileNameWithoutExtension($exe) } else { '' }
  return $b
}
# Discord-style apps (Squirrel) install each version in its own app-x.y.z folder; after an update the saved path is gone:
# use the newest app-* folder next to it
function Resolve-TileExe([string]$exe) {
  if (-not $exe -or (Test-Path -LiteralPath $exe)) { return $exe }
  if ($exe -match '^(.*)\\app-[\d\.]+\\(.+)$') {
    $root = $Matches[1]; $rest = $Matches[2]
    if (Test-Path -LiteralPath $root) {
      $new = Get-ChildItem -LiteralPath $root -Directory -Filter 'app-*' | Sort-Object { try { [version]($_.Name.Substring(4)) } catch { [version]'0.0' } } -Descending |
        ForEach-Object { Join-Path $_.FullName $rest } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
      if ($new) { return $new }
    }
  }
  return $exe
}
function Test-TileInstalled($tile) {
  if ($tile.appid) { return [bool](Get-StartApps | Where-Object { $_.AppID -eq $tile.appid }) -or [bool](Get-AppxPackage -Name (($tile.appid -split '_')[0]) -ErrorAction SilentlyContinue) }
  if ($tile.exe) { return (Test-Path -LiteralPath (Resolve-TileExe $tile.exe)) }
  return $false
}
function Start-Tile($tile, $browser) {
  switch ($tile.kind) {
    'web' {
      if (-not $browser.Exe) { return $false }
      if ($tile.clean -and $browser.Clean) { Start-Process $browser.Exe -ArgumentList @('--new-window', "--app=$($tile.url)") }
      elseif ($browser.Kind -eq 'firefox') { Start-Process $browser.Exe -ArgumentList @('-new-window', $tile.url) }
      else { Start-Process $browser.Exe -ArgumentList @('--new-window', $tile.url) }
      return $true
    }
    default {
      if ($tile.appid) { Start-Process 'explorer.exe' "shell:AppsFolder\$($tile.appid)"; return $true }
      $exe = Resolve-TileExe "$($tile.exe)"
      if ($exe -and (Test-Path -LiteralPath $exe)) {
        # Discord/Squirrel apps start through Update.exe next to the app folder; starting the versioned exe directly works too
        Start-Process $exe; return $true
      }
      return $false
    }
  }
}
# the window that belongs to a tile: same program (by path, else by process name), biggest visible window first.
# A web tile only takes a window that is new since the run started, or one whose title holds its hint.
# a desktop app id often names its program: Microsoft.Office.EXCEL.EXE.15 -> EXCEL, ElectronicArts.EADesktop -> EADesktop
function Get-AppIdProcGuess([string]$id) {
  if ($id -match '(?i)([A-Za-z0-9]+)\.exe') { return $Matches[1] }
  if ($id -match '^[A-Za-z0-9]+(\.[A-Za-z0-9]+)+$') { return ($id -split '\.')[-1] }
  return ''
}
function Find-TileWindow($tile, $snap, $freshIds, $browser) {
  $cands = @()
  $popH = Get-StreamWin
  foreach ($w in $snap) {
    if ($popH -and [int64]$w.H -eq $popH) { continue }
    if ($tile.kind -eq 'web') {
      $pn = Get-ProcName $w.Pid
      if (-not $browser -or $pn -ne $browser.Proc) { continue }
      $isNew = $freshIds -contains [int64]$w.H
      $hinted = "$($tile.hint)".Length -ge 4 -and $w.Title -like "*$($tile.hint)*"
      if ($isNew -or $hinted) { $cands += $w }
      continue
    }
    if ($tile.kind -eq 'spotify') { if ((Get-ProcName $w.Pid) -eq 'Spotify') { $cands += $w }; continue }
    # an app added from the list whose program is not known yet: the first new window after it started (learned, see Invoke-TileRoutine)
    # a Store app already open: its window is hosted by ApplicationFrameHost, so it is matched by title
    # Store apps: the window belongs to the package (its program lives in WindowsApps\<package>...), or it is an
    # ApplicationFrameHost window with the app's name in the title. A learned process name is never trusted for them.
    # app ids without '!' (Excel, EA app...) are ordinary programs: matched like an app whose program is not known yet
    if ($tile.appid -and -not $tile.exe -and "$($tile.appid)" -match '!') {
      $pkg = (("$($tile.appid)" -split '!')[0] -split '_')[0]
      $tn = if ($tile.hint) { "$($tile.hint)" } else { "$($tile.name)" }
      $p = Get-WindowExe ([uint32]$w.Pid)
      if ($pkg -and $p -like "*\WindowsApps\$pkg*") { $cands += $w; continue }
      if ($w.Cls -eq 'ApplicationFrameWindow' -and $tn -and $w.Title -like "*$tn*") { $cands += $w }
      continue
    }
    if (-not $tile.exe -and -not $tile.proc -and $tile.appid) { $gp = Get-AppIdProcGuess "$($tile.appid)"; if ($gp -and (Get-ProcName $w.Pid) -ieq $gp) { $cands += $w; continue } }
    if (-not $tile.exe -and -not $tile.proc) { if ($freshIds -contains [int64]$w.H -and (-not $browser -or (Get-ProcName $w.Pid) -ne $browser.Proc)) { $cands += $w }; continue }
    $ok = $false
    if ($tile.exe) { $p = Get-WindowExe ([uint32]$w.Pid); if ($p -and $p -ieq $tile.exe) { $ok = $true } }
    if (-not $ok -and $tile.proc) { if ((Get-ProcName $w.Pid) -ieq $tile.proc) { $ok = $true } }
    if ($ok -and $tile.cls -and $w.Cls -ne $tile.cls) { $ok = $false }
    if ($ok) { $cands += $w }
  }
  if (-not $cands.Count) { return [IntPtr]::Zero }
  $best = $cands | Sort-Object @{ Expression = { [MiseWin]::IsIconic($_.H) } }, @{ Expression = { [MiseWin2]::NormalArea($_.H) }; Descending = $true } | Select-Object -First 1
  return $best.H
}

# ======================= placing =======================
# out of maximized/minimized state, then place so the VISIBLE edges land on the rectangle; check once and correct
function Set-WindowPlace([IntPtr]$h, $px) {
  [MiseWin2]::Unsnap($h)
  [MiseWin]::PlaceExact($h, $px.X, $px.Y, $px.W, $px.H)
  $v = [MiseWin2]::Visible($h)
  if ($v -and ([Math]::Abs($v[0] - $px.X) -gt 2 -or [Math]::Abs($v[1] - $px.Y) -gt 2)) { Start-Sleep -Milliseconds 150; [MiseWin]::PlaceExact($h, $px.X, $px.Y, $px.W, $px.H) }
}
function Get-TilePx($tile, $lives, $routine) {
  $live = $lives | Where-Object { $_.id -eq $tile.monitor } | Select-Object -First 1
  if (-not $live) { return $null }
  return (ConvertTo-PxRect (Get-TileArea $live $routine) $tile.rect)
}
function Set-SpotifyMiniPlace($tile, $px) {
  $wins = @(Get-WinSnapshot | Where-Object { (Get-ProcName $_.Pid) -eq 'Spotify' })
  if (-not $wins.Count) { return $false }
  $mini = $wins | Where-Object { [MiseWin]::IsTopmost($_.H) } | Select-Object -First 1
  if (-not $mini) {
    # the real Spotify window is the biggest one that is not always-on-top (Spotify also has small helper windows)
    $main = $wins | Sort-Object { $r = [MiseWin2]::Visible($_.H); if ($r) { - $r[2] * $r[3] } else { 0 } } | Select-Object -First 1
    for ($try = 0; $try -lt 3 -and -not $mini; $try++) {
      $ok = Open-SpotifyMini $main.H; if (-not $ok) { Say "[Spotify] mini player button not found (try $($try + 1))" }
      if ($ok) { Start-Sleep -Seconds 2; $mini = Get-WinSnapshot | Where-Object { (Get-ProcName $_.Pid) -eq 'Spotify' -and [MiseWin]::IsTopmost($_.H) } | Select-Object -First 1 }
      if (-not $mini) { Start-Sleep -Seconds 3 }
    }
  }
  if (-not $mini) { return $false }
  foreach ($w in @(Get-WinSnapshot | Where-Object { (Get-ProcName $_.Pid) -eq 'Spotify' })) { if ($w.H -ne $mini.H) { [MiseWin]::ShowWindow($w.H, 9) | Out-Null; [MiseWin]::ShowWindow($w.H, 6) | Out-Null } }
  Set-WindowPlace $mini.H $px
  # Spotify resizes the mini player itself right after a move: watch it briefly and put it back
  for ($i = 0; $i -lt 6; $i++) {
    Start-Sleep -Milliseconds 600
    $v = [MiseWin2]::Visible($mini.H)
    if ($v -and ([Math]::Abs($v[0] - $px.X) -gt 3 -or [Math]::Abs($v[1] - $px.Y) -gt 3 -or [Math]::Abs($v[2] - $px.W) -gt 3 -or [Math]::Abs($v[3] - $px.H) -gt 3)) { [MiseWin]::PlaceExact($mini.H, $px.X, $px.Y, $px.W, $px.H) }
  }
  return $mini.H
}

# ======================= stream tile: a friend's Discord stream, popped out and placed =======================
# A routine can hold one 'stream' tile with a Discord display name. While that routine runs and League is open,
# the tray watches Discord: when that person streams in your voice channel, Mise presses Watch Stream, then
# Pop Out, and puts the popout window on the tile. Buttons are found by their names (screen-reader names),
# never by screen position. Words in the common Discord languages.
$script:StreamLive  = '(?i)^(live|canl[\u0131i]|en direct|en vivo|ao vivo|in diretta|na [\u017cz]ywo|\u0432 \u044d\u0444\u0438\u0440\u0435)$'
$script:StreamWatch = '(?i)(watch stream|join stream|yay[\u0131i]n[\u0131i] [\u0130Ii]zle|yay[\u0131i]na kat[\u0131i]l|regarder le stream|ver transmisi[o\u00f3]n|stream ansehen|guarda (lo )?stream|assistir|ogl[a\u0105]daj)'
$script:StreamPop   = '(?i)(pop ?out|a[\u00e7c][\u0131i]l[\u0131i]r pencere|ayr[\u0131i] pencere|fen[e\u00ea]tre (flottante|s[e\u00e9]par[e\u00e9]e)|ventana emergente|externes fenster|finestra separata|janela separada)'
function Get-StreamWinPath { Join-Path $script:DataDir '_stream-win.txt' }
function Get-StreamWin { try { $f = Get-StreamWinPath; if (Test-Path $f) { $h = [int64](Get-Content -LiteralPath $f -Raw).Trim(); if ($h -and [MiseWin]::IsWindow([IntPtr]$h)) { return $h } } } catch {}; return 0 }
function Set-StreamWin([int64]$h) { $f = Get-StreamWinPath; if ($h) { Set-Content -LiteralPath $f -Value $h -Encoding UTF8 } else { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue } }
# Discord's main window: the biggest Discord window that is not the stream popout
function Get-DiscordMain {
  $pop = Get-StreamWin
  @(Get-WinSnapshot | Where-Object { (Get-ProcName $_.Pid) -eq 'Discord' -and [int64]$_.H -ne $pop }) |
    Sort-Object @{ Expression = { [MiseWin2]::NormalArea($_.H) }; Descending = $true } | Select-Object -First 1
}
function Get-UiaAll($root) {
  # Chromium builds its accessibility tree on the first question: ask, wait, ask again
  $all = [System.Windows.Automation.Condition]::TrueCondition
  $null = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $all); Start-Sleep -Milliseconds 700
  return @($root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $all))
}
function Get-UiaName($e) { try { return "$($e.Current.Name)" } catch { return '' } }
# press an element: Invoke, else Select/Toggle, else (only when allowed) a real click on its middle
function Press-UiaElement($e, [bool]$allowClick) {
  try { ($e.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)).Invoke(); return $true } catch {}
  try { ($e.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)).Select(); return $true } catch {}
  try { ($e.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)).Toggle(); return $true } catch {}
  if ($allowClick) { try { $r = $e.Current.BoundingRectangle; if ($r.Width -gt 0) { [MiseWin]::ClickXY([int]($r.X + $r.Width / 2), [int]($r.Y + $r.Height / 2)); return $true } } catch {} }
  return $false
}
# the person's LIVE entry in the voice channel list: an element with their name whose row also says LIVE
function Find-LiveEntry($els, [string]$who) {
  $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
  foreach ($e in $els) {
    $n = Get-UiaName $e
    if (-not $n -or $n -notlike "*$who*") { continue }
    if ($n -match '(?i)\b(live|canl[\u0131i]|streaming|yay[\u0131i]nda)\b') { return $e }
    $p = $null; try { $p = $walker.GetParent($e) } catch {}
    for ($up = 0; $up -lt 3 -and $p; $up++) {
      try { foreach ($k in @($p.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition))) { if ((Get-UiaName $k) -match $script:StreamLive) { return $k } } } catch {}
      try { $p = $walker.GetParent($p) } catch { $p = $null }
    }
  }
  return $null
}
# opens <who>'s stream in a popout; returns @{ H = popout handle or 0; Why = what is missing }
function Open-DiscordStream([string]$who, [bool]$allowClick) {
  try { Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes -ErrorAction Stop } catch { return @{ H = 0; Why = 'accessibility not available' } }
  $main = Get-DiscordMain
  if (-not $main) { return @{ H = 0; Why = 'Discord is not open' } }
  if ([MiseWin]::IsIconic($main.H)) { [MiseWin]::ShowWindow($main.H, 4) | Out-Null; Start-Sleep -Milliseconds 600 }   # restore without taking focus
  $before = @(Get-WinSnapshot | Where-Object { (Get-ProcName $_.Pid) -eq 'Discord' } | ForEach-Object { [int64]$_.H })
  $root = [System.Windows.Automation.AutomationElement]::FromHandle($main.H)
  $els = Get-UiaAll $root
  # already watching (stream open inside Discord)? then only Pop Out is needed
  $pop = $els | Where-Object { (Get-UiaName $_) -match $script:StreamPop } | Select-Object -First 1
  if (-not $pop) {
    $watch = $els | Where-Object { (Get-UiaName $_) -match $script:StreamWatch -and (Get-UiaName $_) -like "*$who*" } | Select-Object -First 1
    if (-not $watch) {
      $live = Find-LiveEntry $els $who
      if (-not $live) { return @{ H = 0; Why = "$who is not streaming in your voice channel" } }
      if (-not (Press-UiaElement $live $allowClick)) { return @{ H = 0; Why = "could not press $who's LIVE entry" } }
      Start-Sleep -Milliseconds 1500
      $els = Get-UiaAll $root
      $watch = $els | Where-Object { (Get-UiaName $_) -match $script:StreamWatch } | Select-Object -First 1
    }
    if ($watch) { if (-not (Press-UiaElement $watch $allowClick)) { return @{ H = 0; Why = 'could not press Watch Stream' } }; Start-Sleep -Milliseconds 2000; $els = Get-UiaAll $root }
    $pop = $els | Where-Object { (Get-UiaName $_) -match $script:StreamPop } | Select-Object -First 1
  }
  if (-not $pop) { return @{ H = 0; Why = 'no Pop Out button (is the stream open in Discord?)' } }
  if (-not (Press-UiaElement $pop $allowClick)) { return @{ H = 0; Why = 'could not press Pop Out' } }
  for ($i = 0; $i -lt 16; $i++) {
    Start-Sleep -Milliseconds 500
    $new = @(Get-WinSnapshot | Where-Object { (Get-ProcName $_.Pid) -eq 'Discord' -and $before -notcontains [int64]$_.H }) | Select-Object -First 1
    if ($new) { return @{ H = [int64]$new.H; Why = '' } }
  }
  return @{ H = 0; Why = 'pressed Pop Out but no popout window appeared' }
}
# the stream watcher: its own hidden process (so the tray never freezes while Discord is searched).
# Runs while this routine is the active one; acts only while League is open; checks every 10 s.
function Invoke-StreamWatch($cfg, $routine) {
  $first = $false; $mx = New-Object System.Threading.Mutex($true, 'Local\MiseStream', [ref]$first)
  if (-not $first) { return }
  $tile = @(@($routine.tiles) | Where-Object { $_.kind -eq 'stream' -and "$($_.streamer)".Trim() })[0]
  if (-not $tile) { return }
  $who = "$($tile.streamer)".Trim(); $lastWhy = ''; $diagDone = $false; $next = [datetime]::MinValue
  Write-Log "[stream] watching for $who's stream"
  while ((Get-ActiveRoutineId) -eq $routine.id) {
    Start-Sleep -Seconds 2
    $inGame = [bool](Get-Process -Name 'League of Legends' -ErrorAction SilentlyContinue)
    if (-not $inGame -and -not (Get-Process -Name 'LeagueClientUx' -ErrorAction SilentlyContinue)) { continue }
    $px = Get-TilePx $tile @(Get-LiveMonitors $cfg) $routine; if (-not $px) { continue }
    $h = Get-StreamWin
    if ($h) {
      # keep the popout on its tile; placing never takes focus
      $v = [MiseWin2]::Visible([IntPtr]$h)
      if ([MiseWin]::IsIconic([IntPtr]$h) -or ($v -and ([Math]::Abs($v[0] - $px.X) -gt 3 -or [Math]::Abs($v[1] - $px.Y) -gt 3 -or [Math]::Abs($v[2] - $px.W) -gt 3 -or [Math]::Abs($v[3] - $px.H) -gt 3))) { Set-WindowPlace ([IntPtr]$h) $px }
      continue
    }
    if ((Get-Date) -lt $next) { continue }
    $next = (Get-Date).AddSeconds(10)
    # a real mouse click only outside a game; in game only buttons that can be pressed without the mouse
    $res = Open-DiscordStream $who (-not $inGame)
    if ($res.H) {
      Set-StreamWin $res.H; Set-WindowPlace ([IntPtr]$res.H) $px
      $c = @{ Track = @() }; Track-ForExit ([pscustomobject]@{ onExit = $(if ($tile.exit -eq 'leave') { 'leave' } else { 'close' }); name = "$($tile.name)" }) ([IntPtr]$res.H) $c; Save-ExitTrack $routine $c
      Write-Log "[stream] $who's stream popped out and placed"; $lastWhy = ''
      continue
    }
    if ($res.Why -ne $lastWhy) { Write-Log "[stream] $($res.Why)"; $lastWhy = $res.Why }
    # once: Discord shows something Mise can't use - write what it sees, so the button names can be fixed
    if (-not $diagDone -and $res.Why -notlike '*not streaming*' -and $res.Why -ne 'Discord is not open') { $diagDone = $true; Write-Log "[stream-diag] $(Get-StreamDiag $who)" }
  }
  Set-StreamWin 0
  Write-Log '[stream] watcher stopped'
}
function Start-StreamWatcher($routine, [string]$routineFile = '') {
  if (-not @(@($routine.tiles) | Where-Object { $_.kind -eq 'stream' -and "$($_.streamer)".Trim() }).Count) { return }
  $run = Join-Path $script:MiseDir 'mise-run.ps1'
  $a = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', "`"$run`"", '-StreamWatch')
  if ($routineFile) { $a += @('-RoutineFile', "`"$routineFile`"") } else { $a += @('-Routine', "`"$($routine.id)`"") }
  Start-Process powershell.exe -ArgumentList $a -WindowStyle Hidden | Out-Null
}
# what Discord shows near the person, for the log when something is missing (only names with them or stream words)
function Get-StreamDiag([string]$who) {
  try {
    Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes -ErrorAction Stop
    $main = Get-DiscordMain; if (-not $main) { return 'Discord window not found' }
    $els = Get-UiaAll ([System.Windows.Automation.AutomationElement]::FromHandle($main.H))
    $hits = @($els | ForEach-Object { $n = Get-UiaName $_; if ($n -and $n.Length -lt 60 -and ($n -like "*$who*" -or $n -match '(?i)live|stream|pop|watch|canl|yay')) { "$($_.Current.ControlType.ProgrammaticName -replace 'ControlType\.', ''):$n" } } | Select-Object -Unique -First 30)
    return "$($els.Count) elements; " + ($hits -join ' | ')
  } catch { return "diag failed: $($_.Exception.Message)" }
}

# ======================= Copy my screen =======================
# every normal window on a known monitor, with what Mise needs to find and start it again
function Get-CaptureList($cfg) {
  $lives = @(Get-LiveMonitors $cfg)
  $browser = Get-DefaultBrowser
  $out = @()
  foreach ($w in (Get-WinSnapshot)) {
    if ([MiseWin]::IsIconic($w.H)) { continue }
    $pn = Get-ProcName $w.Pid
    if ($pn -eq 'powershell' -and $w.Title -like 'Mise*') { continue }        # Mise's own windows
    # system windows, and old-style Store apps hosted by ApplicationFrameHost (Mise can't tell which app they are)
    if ($pn -in @('ApplicationFrameHost', 'TextInputHost', 'SystemSettings', 'ShellExperienceHost', 'SearchHost', 'StartMenuExperienceHost', 'LockApp', 'explorer')) { continue }
    $v = [MiseWin2]::Visible($w.H); if (-not $v -or $v[2] -lt 120 -or $v[3] -lt 60) { continue }
    $px = @{ X = $v[0]; Y = $v[1]; W = $v[2]; H = $v[3] }
    # the same program twice on exactly the same spot is one window (helper windows stacked on it)
    $dup = $false; foreach ($o in $out) { if ($o.Proc -eq $pn -and $o.Px.X -eq $px.X -and $o.Px.Y -eq $px.Y -and $o.Px.W -eq $px.W -and $o.Px.H -eq $px.H) { $dup = $true; break } }
    if ($dup) { continue }
    $mon = Find-MonitorFor (@($lives | ForEach-Object { $_.Work })) $px
    if (-not $mon) { continue }
    $exe = Get-WindowExe ([uint32]$w.Pid)
    $kind = 'app'
    if ($pn -eq 'Spotify') { $kind = 'spotify' }
    elseif ($browser.Proc -and $pn -eq $browser.Proc) { $kind = 'web' }
    elseif ($pn -eq 'LeagueClientUx') { $kind = 'league' }
    elseif ($pn -in @('chrome', 'msedge', 'brave', 'opera', 'vivaldi', 'firefox')) { $kind = 'web' }
    $out += [pscustomobject]@{
      H = $w.H; Title = $w.Title; Proc = $pn; Exe = $exe; Cls = $w.Cls; Kind = $kind; Monitor = $mon.id
      Rect = (Limit-ToMonitor (ConvertTo-FracRect $mon $px)); Px = $px
      Mini = ($pn -eq 'Spotify' -and [MiseWin]::IsTopmost($w.H))
      Url = $(if ($kind -eq 'web') { Get-UrlGuess $w.Title } else { '' })
      Name = $(if ($kind -eq 'web') { Get-ShortWebName $w.Title (Get-UrlGuess $w.Title) } elseif ($kind -eq 'league') { 'League client' } else { Get-FriendlyAppName $pn $exe $w.Title })
    }
  }
  return $out
}
# a short tile name for a browser window: the site's address, else the first words of the title
function Get-ShortWebName([string]$title, [string]$url) {
  if ($url) { try { return ([uri]$url).Host -replace '^www\.', '' } catch {} }
  $t = ($title -replace '\s+-\s+[^-]+$', '').Trim()
  if ($t.Length -gt 22) { $t = $t.Substring(0, 21).Trim() + '...' }
  if ($t) { return $t }
  return 'Web page'
}
function Get-FriendlyAppName([string]$proc, [string]$exe, [string]$title) {
  $n = Get-FriendlyAppName0 $proc $exe $title
  # Store apps often report names like 'WhatsApp.Root': keep the readable part
  if ($n -match '^([A-Za-z][\w ]+)\.(Root|App|Desktop|Main|Client|Shell)$') { $n = $Matches[1] }
  return $n
}
function Get-FriendlyAppName0([string]$proc, [string]$exe, [string]$title) {
  try { if ($exe) { $d = (Get-Item -LiteralPath $exe).VersionInfo.FileDescription; if ($d -and $d.Length -lt 40) { return $d.Trim() } } } catch {}
  if (-not $exe -and $title) { $t2 = ($title -replace '\s+-\s+[^-]+$', '').Trim(); if ($t2.Length -gt 26) { $t2 = $t2.Substring(0, 25).Trim() + '...' }; if ($t2) { return $t2 } }
  if ($proc) { return $proc }
  return $title
}
# a ticked capture row becomes a tile (min size probed once here, so the map can respect it)
function ConvertTo-Tile($item, [string]$exitMode) {
  $min = $null; try { if ($item.Kind -ne 'league') { $min = [MiseWin2]::ProbeMinSize($item.H) } } catch {}
  $t = [pscustomobject]@{
    id = New-Id; kind = $item.Kind; name = $item.Name; monitor = $item.Monitor; rect = $item.Rect; exit = $exitMode
    exe = ''; appid = ''; proc = ''; cls = ''; url = ''; hint = ''; clean = $false; mini = $false
    minW = $(if ($min) { $min[0] } else { 0 }); minH = $(if ($min) { $min[1] } else { 0 })
  }
  switch ($item.Kind) {
    'web' { $t.url = $item.Url; $t.clean = $true; $t.hint = ($item.Name -split '\s+')[0] }
    'spotify' { $t.exe = $item.Exe; $t.proc = 'Spotify'; $t.mini = [bool]$item.Mini }
    'league' { $t.proc = 'LeagueClientUx' }
    default { $t.proc = $item.Proc; $t.cls = $item.Cls; $id = Get-StoreAppId $item.Exe; if ($id) { $t.appid = $id } else { $t.exe = $item.Exe } }
  }
  if ($t.url -like '*u.gg*') { $t.kind = 'ugg'; $t.name = 'u.gg (opens in champ select)' }
  return $t
}

# ======================= timings learned on this PC =======================
function Get-Timings {
  $f = Join-Path $script:DataDir 'timings.json'; $h = @{}
  if (Test-Path $f) { try { $j = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json; foreach ($p in $j.PSObject.Properties) { $h[$p.Name] = @($p.Value) } } catch {} }
  return $h
}
function Save-Timings($t) { try { Set-Content -LiteralPath (Join-Path $script:DataDir 'timings.json') -Value (ConvertTo-Json $t -Depth 3) -Encoding UTF8 } catch {} }

# ======================= running a routine =======================
function Start-LeaguePart($cfg, $routine, $ctx, $lives) {
  $mod = Join-Path $script:MiseDir 'modules\riot-league.ps1'
  if (-not (Test-Path $mod)) { Say "[riot] module missing - skipped"; return }
  $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$mod`"", '-Core', '-Queue', "$([int](Get-MiseSetting $cfg 'queue'))")
  if ($ctx.Account) { $a += @('-Account', "`"$($ctx.Account)`"") } else { $a += '-Keep' }
  $lt = @($routine.tiles) | Where-Object { $_.kind -eq 'league' } | Select-Object -First 1
  if ($lt) { $px = Get-TilePx $lt $lives $routine; if ($px) { $a += @('-LeagueAt', "$($px.X),$($px.Y)") } }
  if ($ctx.StatusFile) { $a += @('-StatusFile', "`"$($ctx.StatusFile)`"") }
  Say "[riot] $(if ($ctx.Account) { "switching to $($ctx.Account)" } else { 'starting with the current login' })"
  $ctx.Pending += Start-Process 'powershell.exe' -ArgumentList $a -WindowStyle Hidden -PassThru
}

# a routine starts from a clear desk: every open window is minimized first (Mise's own windows, the desktop and League stay)
function Hide-OpenWindows {
  $n = 0
  foreach ($w in (Get-WinSnapshot)) {
    if ([MiseWin]::IsIconic($w.H)) { continue }
    $pn = Get-ProcName $w.Pid
    if ($pn -in @('powershell', 'pwsh') -and (-not $w.Title -or $w.Title -like 'Mise*')) { continue }
    if ($pn -in @('Mise', 'TextInputHost', 'ShellExperienceHost', 'SearchHost', 'StartMenuExperienceHost', 'LockApp', 'LeagueClientUx', 'LeagueClient', 'Riot Client', 'RiotClientServices')) { continue }
    if ($pn -eq 'explorer' -and $w.Cls -ne 'CabinetWClass') { continue }
    if ($pn -eq 'Spotify' -and [MiseWin]::IsTopmost($w.H)) { continue }
    $v = [MiseWin2]::Visible($w.H); if (-not $v -or $v[2] -lt 120 -or $v[3] -lt 60) { continue }
    [MiseWin]::ShowWindow($w.H, 6) | Out-Null; $n++
  }
  return $n
}
# $mode: run | arrange (place what is open, start nothing) | exit
function Invoke-TileRoutine($cfg, $routine, $ctx, [string]$mode = 'run') {
  $lives = @(Get-LiveMonitors $cfg)
  $tiles = @($routine.tiles)
  if ($mode -eq 'exit') {
    Say "Exiting '$($routine.name)'"
    Invoke-ExitTrack $routine
    $n = Show-AllTaskbars; if ($n) { Say "[taskbar] restored" }
    if ((Get-ActiveRoutineId) -eq $routine.id) { Set-ActiveRoutineId '' }
    return
  }
  Say "$(if ($mode -eq 'arrange') { 'Arranging' } else { 'Starting' }) '$($routine.name)'"
  if ($mode -eq 'run') { $nh = Hide-OpenWindows; if ($nh) { Say "[desktop] $nh open windows minimized" } }
  if ($routine.id -and (@($routine.tiles).Count -or @($routine.taskbar).Count)) { Set-ActiveRoutineId $routine.id }
  if ($routine.id) { try { Start-StreamWatcher $routine $script:RoutineFileArg } catch {} }
  # 1. League takes longest: it starts first, everything else is arranged while it loads
  if ($mode -eq 'run' -and $routine.league) { Start-LeaguePart $cfg $routine $ctx $lives }
  # 2. taskbars this routine hides
  foreach ($mid in @($routine.taskbar)) {
    $live = $lives | Where-Object { $_.id -eq $mid } | Select-Object -First 1
    if ($live) { $scr = Get-Screens | Where-Object { $_.DeviceName -eq $live.DeviceName } | Select-Object -First 1; if ($scr) { $n = Hide-MonitorTaskbar $scr $ctx; if ($n) { Say "[taskbar] hidden on $($live.name)" } } }
  }
  foreach ($t in $tiles) { if (-not ($lives | Where-Object { $_.id -eq $t.monitor })) { Say "[$($t.name)] its screen is not connected - not placed" } }
  # 3. start what is not open yet (slowest first), move what is
  $browser = Get-DefaultBrowser
  $timings = Get-Timings
  $startSnap = @(Get-WinSnapshot); $startIds = @($startSnap | ForEach-Object { [int64]$_.H })
  $running = @(); foreach ($t in $tiles) { if ($t.kind -ne 'web' -and (Find-TileWindow $t $startSnap @() $browser) -ne [IntPtr]::Zero) { $running += $t.id } }
  $order = @(Get-LaunchOrder $tiles $running $timings)
  $todo = @{}
  $t0 = Get-Date
  foreach ($t in $order) {
    if ($running -contains $t.id) { $todo[$t.id] = @{ Tile = $t; Started = $null; Retried = $true; Deadline = $t0.AddSeconds(5) }; continue }
    if ($mode -eq 'arrange') { continue }
    if ($t.kind -eq 'web' -and "$($t.hint)".Length -ge 4 -and (Find-TileWindow $t $startSnap @() $browser) -ne [IntPtr]::Zero) { $todo[$t.id] = @{ Tile = $t; Started = $null; Retried = $true; Deadline = $t0.AddSeconds(5) }; continue }
    if ($t.kind -ne 'web' -and -not (Test-TileInstalled $t)) { Say "[$($t.name)] app doesn't exist on this PC - skipped"; continue }
    if ($t.kind -eq 'web' -and -not $browser.Exe) { Say "[$($t.name)] no browser found - skipped"; continue }
    if (Start-Tile $t $browser) { Say "[$($t.name)] starting"; $todo[$t.id] = @{ Tile = $t; Started = Get-Date; Retried = $false; Deadline = (Get-Date).AddSeconds((Get-WaitSeconds $timings (Get-TimingKey $t))) } }
  }
  # 4. place each window as soon as it shows up; one retry for an installed app that does not open; late windows still placed (2 min)
  $placed = @{}; $learned = @{}
  $lateEnd = $t0.AddSeconds(120)
  while ($todo.Count) {
    $snap = @(Get-WinSnapshot); $fresh = @($snap | Where-Object { $startIds -notcontains [int64]$_.H } | ForEach-Object { [int64]$_.H })
    foreach ($id in @($todo.Keys)) {
      $job = $todo[$id]; $t = $job.Tile
      $h = Find-TileWindow $t $snap $fresh $browser
      if ($h -ne [IntPtr]::Zero -and $placed.Values -notcontains [int64]$h) {
        $px = Get-TilePx $t $lives $routine
        if ($px) {
          if ($t.kind -eq 'spotify' -and $t.mini) { $mh = Set-SpotifyMiniPlace $t $px; if ($mh) { $h = $mh; Say "[$($t.name)] miniplayer placed" } else { Say "[$($t.name)] open the miniplayer once in Spotify, then press Arrange" } }
          else { if ($t.kind -eq 'web' -and $t.clean) { try { [MiseWin]::StripCaption($h) } catch {} }; Set-WindowPlace $h $px; Say "[$($t.name)] placed" }
          Track-ForExit ([pscustomobject]@{ onExit = $t.exit; name = $t.name }) $h $ctx
        }
        if ($job.Started) { $timings = Add-Timing $timings (Get-TimingKey $t) ((Get-Date) - $job.Started).TotalSeconds }
        if (-not $t.exe -and (-not $t.appid -or "$($t.appid)" -notmatch '!') -and -not $t.proc -and $t.kind -eq 'app') { $w = $snap | Where-Object { $_.H -eq $h } | Select-Object -First 1; if ($w) { $learned[$t.id] = @{ proc = (Get-ProcName $w.Pid); cls = $w.Cls } } }
        $placed[$id] = [int64]$h; $todo.Remove($id); continue
      }
      if ((Get-Date) -gt $job.Deadline) {
        if (-not $job.Retried) { $job.Retried = $true; Say "[$($t.name)] slow to open - trying once more"; Start-Tile $t $browser | Out-Null; $job.Deadline = $lateEnd }
        elseif ((Get-Date) -gt $lateEnd -or -not $job.Started) { Say "[$($t.name)] did not open a window - skipped"; $todo.Remove($id) }
      }
    }
    if ($todo.Count) { Start-Sleep -Milliseconds 500 }
  }
  Save-Timings $timings
  # apps added from the list: remember which program they turned out to be, so later runs find them when already open
  if ($learned.Count -and $routine.id) {
    $c2 = Get-MiseConfig; $r2 = @($c2.routines) | Where-Object { $_.id -eq $routine.id } | Select-Object -First 1
    if ($r2) { foreach ($t2 in @($r2.tiles)) { if ($learned.ContainsKey($t2.id)) { $t2.proc = $learned[$t2.id].proc } }; Save-MiseConfig $c2 }
  }
  Save-ExitTrack $routine $ctx
  # 5. League ready (it places its own window where the League tile is)
  foreach ($p in @($ctx.Pending)) { $p.WaitForExit(); Say $(if ($p.ExitCode -eq 0) { "[riot] ready" } else { "[riot] needs a look (code $($p.ExitCode))" }) }
  # 6. some apps move themselves once loaded: put the placed ones back once
  Start-Sleep -Seconds 2
  foreach ($t in $tiles) {
    if (-not $placed.ContainsKey($t.id) -or ($t.kind -eq 'spotify' -and $t.mini)) { continue }
    $h = [IntPtr]$placed[$t.id]; $px = Get-TilePx $t $lives $routine
    if ($px -and [MiseWin]::IsWindow($h)) { $v = [MiseWin2]::Visible($h); if ($v -and ([Math]::Abs($v[0] - $px.X) -gt 3 -or [Math]::Abs($v[1] - $px.Y) -gt 3 -or [Math]::Abs($v[2] - $px.W) -gt 3 -or [Math]::Abs($v[3] - $px.H) -gt 3)) { Set-WindowPlace $h $px } }
  }
  Save-ExitTrack $routine $ctx
}
