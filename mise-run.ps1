<# Mise runner: runs a routine from the config. Used by the Mise window, the tray, hotkeys and the builder.
   mise-run.ps1 -Routine <id|name> [-Account NAME] [-Exit] [-Arrange] [-StatusFile path]
   mise-run.ps1 -RoutineFile <json> -Arrange      (the builder's Preview: places an unsaved routine)
   -Exit closes what the routine said to close and brings the taskbars back; -Arrange only places what is open. #>
param([string]$Routine = '', [string]$RoutineFile = '', [string]$Account = '', [switch]$Exit, [switch]$Arrange, [switch]$DryRun, [string]$StatusFile = '')
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'mise-core.ps1'); . (Join-Path $here 'mise-layout.ps1'); . (Join-Path $here 'mise-engine.ps1')
if ($StatusFile) {
  function Write-Host { param([Parameter(ValueFromRemainingArguments = $true)]$Object) $m = "$Object"; Microsoft.PowerShell.Utility\Write-Host $m; try { Add-Content -LiteralPath $StatusFile -Value $m -Encoding UTF8 } catch {} }
}
$cfg = Get-MiseConfig
if ($RoutineFile) { try { $r = Get-Content -LiteralPath $RoutineFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $r = $null } }
else { $r = $cfg.routines | Where-Object { $_.id -eq $Routine -or $_.name -eq $Routine } | Select-Object -First 1 }
if (-not $r) { Write-Host "No routine called '$Routine$RoutineFile'."; exit 1 }
$ctx = New-Ctx; $ctx.Account = $Account; $ctx.StatusFile = $StatusFile
if ($DryRun) { foreach ($t in @($r.tiles)) { Write-Host "  would place: $($t.kind) $($t.name) on $($t.monitor)" }; exit 0 }
$mode = if ($Exit) { 'exit' } elseif ($Arrange) { 'arrange' } else { 'run' }
Invoke-TileRoutine $cfg $r $ctx $mode
Write-Host "Mise ready."
exit 0
