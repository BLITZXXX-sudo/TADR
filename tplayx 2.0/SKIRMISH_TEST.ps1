<#
  SKIRMISH_TEST.ps1 - launch TotalA.exe, press S, S, S (Single Player ->
  Skirmish -> Start), let the battle run, then report crashes.
    -GameArgs '-d'   -BattleSeconds 40   -KeepRunning
  Result: _build\skirmish_result.txt  (PASS / FAIL + crash module/offset)
#>
param(
  [string]$GameDir       = 'C:\CAVEDOG\TOTALA',
  [string]$GameArgs      = '',      # fullscreen; '-d' = windowed (crashes the 2025 tdraw on battle load)
  [int]   $MenuWait      = 12,
  [int]   $BattleSeconds = 40,
  [switch]$KeepRunning
)
$out = Join-Path $PSScriptRoot '_build\skirmish_result.txt'
$null = New-Item -ItemType Directory -Force -Path (Split-Path $out)
$log = New-Object System.Collections.Generic.List[string]
function Say($m) { $log.Add($m); Write-Host $m }

Get-Process TotalA -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep 1
$errLog = Join-Path $GameDir 'ErrorLog.txt'
$errBefore = if (Test-Path $errLog) { (Get-Item $errLog).LastWriteTime } else { [datetime]::MinValue }
$t0 = Get-Date
Say "=== skirmish test $($t0.ToString('HH:mm:ss'))  tdraw=$((Get-FileHash (Join-Path $GameDir 'tdraw.dll') -Algorithm MD5).Hash)  tplayx=$(Test-Path (Join-Path $GameDir 'tplayx.dll'))"

if ($GameArgs.Trim()) { $p = Start-Process -FilePath (Join-Path $GameDir "TotalA.exe") -ArgumentList $GameArgs -WorkingDirectory $GameDir -PassThru }
else { $p = Start-Process -FilePath (Join-Path $GameDir "TotalA.exe") -WorkingDirectory $GameDir -PassThru }
Start-Sleep $MenuWait
$sh = New-Object -ComObject WScript.Shell
foreach ($k in 's','s','s') {
  $null = $sh.AppActivate($p.Id); Start-Sleep -Milliseconds 400
  $sh.SendKeys($k); Start-Sleep 3
}
Say "keys sent (S, S, S) - battle loading/running for $BattleSeconds s"
Start-Sleep $BattleSeconds
$p.Refresh()

$ev = Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Id = 1000; StartTime = $t0 } -ErrorAction SilentlyContinue |
      Where-Object { $_.Message -match 'TotalA\.exe' } | Select-Object -First 1
$crashedLog = (Test-Path $errLog) -and ((Get-Item $errLog).LastWriteTime -gt $errBefore)
if ($ev) {
  $mod = if ($ev.Message -match 'Faulting module name: ([^,]+)') { $Matches[1] } else { '?' }
  $off = if ($ev.Message -match 'Fault offset: (0x[0-9a-fA-F]+)') { $Matches[1] } else { '?' }
  Say "FAIL: crash at $($ev.TimeCreated.ToString('HH:mm:ss')) in $mod offset $off"
} elseif ($crashedLog) {
  Say 'FAIL: ErrorLog.txt written (TA exception handler)'
} elseif ($p.HasExited) {
  Say "FAIL: game exited (code $($p.ExitCode))"
} else {
  Say "PASS: battle running $BattleSeconds s, no crash"
}
Get-Process WerFault -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
if (-not $KeepRunning) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
$log | Set-Content -Encoding UTF8 $out
