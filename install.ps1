<#
  Mise (shared edition) installer. Double-click INSTALL.cmd.
  Copies Mise to %LOCALAPPDATA%\MiseApp, adds a desktop icon (opens the Mise window), starts the tray helper with Windows.
  Your routines live in %APPDATA%\Mise\config.json and are kept when you update or uninstall.
#>
param([switch]$Uninstall, [switch]$Quiet)
$ErrorActionPreference = 'Stop'
# every install writes a log next to this file, so a failed install can be looked at
try { Start-Transcript -Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'install-log.txt') -Force | Out-Null } catch {}
trap { Write-Host ''; Write-Host "Install failed: $($_.Exception.Message)" -ForegroundColor Red; Write-Host "at line $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())"; try { Stop-Transcript | Out-Null } catch {}; if (-not $Quiet) { Read-Host 'Press Enter to close' | Out-Null }; exit 1 }
$src = Split-Path -Parent $MyInvocation.MyCommand.Path
$dst = Join-Path $env:LOCALAPPDATA 'MiseApp'
$desk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Mise.lnk'
$startM = Join-Path ([Environment]::GetFolderPath('Programs')) 'Mise.lnk'
$startup = Join-Path ([Environment]::GetFolderPath('Startup')) 'Mise tray.lnk'
$ps = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"

function Stop-Tray {
  Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*mise-tray.ps1*' -or $_.CommandLine -like '*mise-builder.ps1*' -or $_.CommandLine -like '*mise-home.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

if ($Uninstall) {
  Stop-Tray
  Remove-Item -LiteralPath $desk, $startM, $startup -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $dst -Recurse -Force -ErrorAction SilentlyContinue
  Write-Host "Mise removed. Your routines are still in $env:APPDATA\Mise"
  if (-not $Quiet) { Read-Host 'Press Enter to close' | Out-Null }; exit 0
}

Write-Host 'Installing Mise...'
Stop-Tray
New-Item -ItemType Directory -Force -Path $dst, (Join-Path $dst 'modules') | Out-Null
foreach ($f in 'mise-core.ps1', 'mise-layout.ps1', 'mise-engine.ps1', 'mise-look.ps1', 'mise-ui.ps1', 'mise-home.ps1', 'mise-builder.ps1', 'mise-run.ps1', 'mise-tray.ps1', 'mise.ico', 'README.txt') { Copy-Item -LiteralPath (Join-Path $src $f) -Destination $dst -Force }
Copy-Item -LiteralPath (Join-Path $src 'modules\riot-league.ps1') -Destination (Join-Path $dst 'modules') -Force
Remove-Item -LiteralPath (Join-Path $dst 'mise-arrange.ps1') -Force -ErrorAction SilentlyContinue   # 0.6: replaced by the builder's map
Get-ChildItem -LiteralPath $dst -Recurse -File | Unblock-File
$ico = Join-Path $dst 'mise.ico'

# tiny launcher exe: opens the editor with no PowerShell window
$cs = @'
using System; using System.Diagnostics; using System.IO;
class MiseLauncher { static void Main() {
  string d = AppDomain.CurrentDomain.BaseDirectory;
  ProcessStartInfo t = new ProcessStartInfo("powershell.exe", "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + Path.Combine(d, "mise-tray.ps1") + "\"");
  t.UseShellExecute = false; t.CreateNoWindow = true; Process.Start(t);
  ProcessStartInfo e = new ProcessStartInfo("powershell.exe", "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + Path.Combine(d, "mise-home.ps1") + "\"");
  e.UseShellExecute = false; e.CreateNoWindow = true; Process.Start(e);
} }
'@
$csFile = Join-Path $dst 'launcher.cs'; $exe = Join-Path $dst 'Mise.exe'
Set-Content -LiteralPath $csFile -Value $cs -Encoding UTF8
$csc = @("$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe", "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
$useExe = $false
if ($csc) { & $csc /nologo /target:winexe "/win32icon:$ico" "/out:$exe" $csFile | Out-Null; $useExe = ($LASTEXITCODE -eq 0) -and (Test-Path $exe) }
Remove-Item -LiteralPath $csFile -ErrorAction SilentlyContinue

$sh = New-Object -ComObject WScript.Shell
function New-Lnk($path, $target, $lnkArgs, $style) {
  $s = $sh.CreateShortcut($path); $s.TargetPath = $target; $s.Arguments = "$lnkArgs"; $s.WorkingDirectory = $dst; $s.IconLocation = "$ico,0"
  $s.Description = 'Mise - everything in its place before you play'; if ($style) { $s.WindowStyle = $style }; $s.Save()
}
$editorArgs = "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $dst 'mise-home.ps1')`""
$trayArgs = "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $dst 'mise-tray.ps1')`""
if ($useExe) { New-Lnk $desk $exe '' 0; New-Lnk $startM $exe '' 0 } else { New-Lnk $desk $ps $editorArgs 7; New-Lnk $startM $ps $editorArgs 7 }
New-Lnk $startup $ps $trayArgs 7

Start-Process $ps -WindowStyle Hidden -ArgumentList $trayArgs
Write-Host ''
Write-Host 'Done. Mise is running in the tray (near the clock); the Mise window opens on first run.'
Write-Host "(mise = short for 'mise en place': everything in its place before service.)"
if (-not $Quiet) { Read-Host 'Press Enter to close' | Out-Null }
