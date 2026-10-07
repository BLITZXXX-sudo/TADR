<#
  BUILD_AND_TEST.ps1 - one-click build + deploy + launch check for tplayx.dll
  ---------------------------------------------------------------------------
  1. Full rebuild with lazbuild (Free Pascal / Lazarus - this project is not
     a Delphi dcc32/msbuild project).
  2. Compiler gate:
       - any Error/Fatal                       -> FAIL
       - any NEW warning or hint vs. baseline  -> FAIL ("warnings as errors"
         for everything you add; the legacy ones are recorded in
         _build\warnings_baseline.txt the first time the script runs)
       - -Strict                               -> FAIL on ANY warning or hint
  3. Backs up the game's current tplayx.dll and copies the new one in.
  4. Launches TotalA.exe, waits, then checks:
       - the game process is still alive
       - tplayx_init.log has a new session with "All plugins registered",
         "InstallPlugins completed OK" and no "FAILED"
       - ErrorLog.txt was not written (no crash)
  5. Closes the game (unless -KeepRunning) and writes _build\last_result.txt.

  Double-click BUILD_AND_TEST.bat, or run:
    powershell -ExecutionPolicy Bypass -File BUILD_AND_TEST.ps1 [-Strict]
        [-NoLaunch] [-KeepRunning] [-UpdateBaseline] [-RunSeconds 25]
        [-GameDir C:\CAVEDOG\TOTALA] [-GameArgs "-d"]
  Exit code 0 = PASS, 1 = FAIL.
#>
param(
  [string]$ProjectDir = (Join-Path $PSScriptRoot 'src\Recorder'),
  [string]$GameDir    = 'C:\CAVEDOG\TOTALA',
  [string]$LazBuild   = 'C:\lazarus\lazbuild.exe',
  [string]$GameArgs   = '',            # '' = fullscreen (needed for the tdraw Wind/Tidal/Game Time bar); '-d' = old windowed mode
  [int]   $RunSeconds = 25,
  [switch]$Strict,
  [switch]$Debug,         # big DLL with DWARF debug info (build mode 'Debug'); default = small release DLL
  [switch]$NoLaunch,
  [switch]$KeepRunning,
  [switch]$UpdateBaseline
)

$ErrorActionPreference = 'Stop'
$stamp    = Get-Date -Format 'yyyyMMdd_HHmmss'
$buildDir = Join-Path $PSScriptRoot '_build'
$null     = New-Item -ItemType Directory -Force -Path $buildDir, (Join-Path $buildDir 'backup')
$buildLog = Join-Path $buildDir "build_$stamp.log"
$baseline = Join-Path $buildDir 'warnings_baseline.txt'
$result   = New-Object System.Collections.Generic.List[string]
$failed   = $false

function Say([string]$msg, [string]$color = 'Gray') { Write-Host $msg -ForegroundColor $color; $result.Add($msg) }
function Fail([string]$msg) { $script:failed = $true; Say "FAIL: $msg" 'Red' }

function Finish {
  $verdict = if ($script:failed) { 'RESULT: FAIL' } else { 'RESULT: PASS' }
  Say $verdict ($(if ($script:failed) { 'Red' } else { 'Green' }))
  $result | Set-Content -Encoding UTF8 (Join-Path $buildDir 'last_result.txt')
  if ($script:failed) { exit 1 } else { exit 0 }
}

Say "=== tplayx build + test  $stamp ===" 'Cyan'
Say "Project : $ProjectDir"
Say "Game    : $GameDir"

# ---------------------------------------------------------------- 0. sanity
if (-not (Test-Path $LazBuild))                         { Fail "lazbuild not found at $LazBuild"; Finish }
if (-not (Test-Path (Join-Path $ProjectDir 'tplayx.lpi'))) { Fail "tplayx.lpi not found in $ProjectDir"; Finish }
if (Get-Process TotalA -ErrorAction SilentlyContinue) {
  Fail 'TotalA.exe is running - close the game first (the DLL is locked while it runs)'; Finish
}

# lazbuild rewrites tplayx.res (version info) and tplayx.lpi (build number)
# on every build - a copy unpacked from an archive can arrive read-only.
$ro = Get-ChildItem (Join-Path $PSScriptRoot 'src') -Recurse -File -ErrorAction SilentlyContinue | Where-Object IsReadOnly
if ($ro) { $ro | ForEach-Object { $_.IsReadOnly = $false }; Say "Cleared read-only flag on $(@($ro).Count) file(s)" 'Yellow' }

# ---------------------------------------------------------------- 1. build
$modeArgs = if ($Debug) { @('--build-mode=Debug') } else { @() }
Say "--- 1. lazbuild --build-all $(if ($Debug) {'(Debug)'} else {'(Release: stripped + smart-linked)'}) ---" 'Cyan'
Push-Location $ProjectDir
try {
  & $LazBuild --build-all @modeArgs tplayx.lpi *> $buildLog
  $lazExit = $LASTEXITCODE
} finally { Pop-Location }
$lines = Get-Content $buildLog

$errors = $lines | Where-Object { $_ -match '\b(Error|Fatal):' }
if ($lazExit -ne 0 -or $errors) {
  Fail "build failed (lazbuild exit $lazExit) - see $buildLog"
  $errors | Select-Object -First 20 | ForEach-Object { Say "  $_" 'Red' }
  Finish
}
$dll = Join-Path $ProjectDir 'tplayx.dll'
Say ("Built   : tplayx.dll  {0:N0} bytes  {1}" -f (Get-Item $dll).Length, (Get-Item $dll).LastWriteTime) 'Green'

# ---------------------------------------------------------------- 2. warnings / hints gate
# Only messages for source files that live in this project folder (FPC RTL /
# package messages are not ours). Key = file + kind + message (no line
# numbers, so moving code around does not create "new" warnings).
$projFiles = @{}
Get-ChildItem (Join-Path $PSScriptRoot "src") -File -Include *.pas,*.pp,*.inc,*.dpr -Recurse -ErrorAction SilentlyContinue |
  ForEach-Object { $projFiles[$_.Name.ToLower()] = $true }

$rx = '^(?<file>.*?(?<leaf>[^\\/()]+\.(pas|pp|inc|dpr)))\((?<line>\d+)(,\d+)?\)\s+(?<kind>Warning|Hint):\s*(?<msg>.*)$'
$found = foreach ($l in $lines) {
  $m = [regex]::Match($l, $rx, 'IgnoreCase')
  if ($m.Success -and $projFiles.ContainsKey($m.Groups['leaf'].Value.ToLower())) {
    [pscustomobject]@{
      Key  = '{0}|{1}|{2}' -f $m.Groups['leaf'].Value, $m.Groups['kind'].Value, $m.Groups['msg'].Value.Trim()
      Kind = $m.Groups['kind'].Value
      Text = $l.Trim()
    }
  }
}
$warnCount = @($found | Where-Object Kind -eq 'Warning').Count
$hintCount = @($found | Where-Object Kind -eq 'Hint').Count
Say "Compiler: $warnCount warning(s), $hintCount hint(s) in project sources"

if ($UpdateBaseline -or -not (Test-Path $baseline)) {
  $found | ForEach-Object Key | Sort-Object | Set-Content -Encoding UTF8 $baseline
  Say "Baseline written: $baseline ($(@($found).Count) entries) - later builds fail on anything new" 'Yellow'
} else {
  # multiset compare: a key may legitimately appear N times
  $base = @{}
  Get-Content $baseline | ForEach-Object { $base[$_] = 1 + [int]$base[$_] }
  $new = foreach ($f in $found) {
    if ([int]$base[$f.Key] -gt 0) { $base[$f.Key]-- } else { $f }
  }
  if ($new) {
    Fail "$(@($new).Count) NEW warning/hint(s) since the baseline (treated as errors):"
    $new | Select-Object -First 30 | ForEach-Object { Say "  $($_.Text)" 'Red' }
  } else {
    Say 'No new warnings/hints vs. baseline' 'Green'
  }
}
if ($Strict -and @($found).Count -gt 0) {
  Fail "-Strict: $(@($found).Count) warning/hint(s) present"
  $found | Select-Object -First 30 | ForEach-Object { Say "  $($_.Text)" 'Red' }
}
if ($failed) { Finish }

# ---------------------------------------------------------------- 3. deploy
Say '--- 3. deploy ---' 'Cyan'
$gameDll = Join-Path $GameDir 'tplayx.dll'
if (Test-Path $gameDll) {
  $bak = Join-Path $buildDir "backup\tplayx_$stamp.dll"
  Copy-Item $gameDll $bak -Force
  Say "Backup  : $bak"
}
Copy-Item $dll $gameDll -Force
if ((Get-FileHash $dll).Hash -ne (Get-FileHash $gameDll).Hash) { Fail 'copy to the game folder did not verify'; Finish }
Say "Deployed: $gameDll" 'Green'

if ($NoLaunch) { Say 'Launch skipped (-NoLaunch)' 'Yellow'; Finish }

# ---------------------------------------------------------------- 4. launch + runtime check
Say "--- 4. launch TotalA.exe, watch $RunSeconds s ---" 'Cyan'
$exe      = Join-Path $GameDir 'TotalA.exe'
$initLog  = Join-Path $GameDir 'tplayx_init.log'
$errLog   = Join-Path $GameDir 'ErrorLog.txt'
foreach ($need in 'TotalA.exe','tdraw.dll','tplayx.dll') {
  if (-not (Test-Path (Join-Path $GameDir $need))) { Fail "$need missing in $GameDir (the game will not start)" }
}
if ($failed) { Finish }

$initBefore = if (Test-Path $initLog) { (Get-Item $initLog).Length } else { 0 }
$errBefore  = if (Test-Path $errLog)  { (Get-Item $errLog).LastWriteTime } else { [datetime]::MinValue }

$launchTime = Get-Date
Say "Command : `"$exe`" $GameArgs"
if ($GameArgs) { $proc = Start-Process -FilePath $exe -ArgumentList $GameArgs -WorkingDirectory $GameDir -PassThru }
else           { $proc = Start-Process -FilePath $exe -WorkingDirectory $GameDir -PassThru }
Start-Sleep -Seconds $RunSeconds
$proc.Refresh()
$alive = -not $proc.HasExited

# new part of tplayx_init.log only
$initNew = ''
if (Test-Path $initLog) {
  $fs = [IO.File]::Open($initLog, 'Open', 'Read', 'ReadWrite')
  try {
    if ($fs.Length -gt $initBefore) {
      $null = $fs.Seek($initBefore, 'Begin')
      $initNew = (New-Object IO.StreamReader($fs)).ReadToEnd()
    }
  } finally { $fs.Close() }
}
$crashed = (Test-Path $errLog) -and ((Get-Item $errLog).LastWriteTime -gt $errBefore)
# A crashed TotalA often stays "alive" behind TA's / Windows' error dialog, so
# also ask Windows: Application log 1000 (app crash) / 1001 (WER) for TotalA
$winCrash = Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Id = 1000, 1001; StartTime = $launchTime } -ErrorAction SilentlyContinue |
  Where-Object { $_.Message -match 'TotalA\.exe' } | Select-Object -First 1
$werOpen  = Get-Process WerFault -ErrorAction SilentlyContinue

if ($winCrash) {
  Fail "Windows recorded a TotalA crash at $($winCrash.TimeCreated):"
  ($winCrash.Message -split "`r?`n") | Where-Object { $_ -match 'Faulting module|Exception code|Fault offset|P4:|P7:|P8:' } |
    ForEach-Object { Say "  $($_.Trim())" 'Red' }
} elseif ($alive) { Say "Game    : still running after $RunSeconds s (pid $($proc.Id)), no Windows crash event" 'Green' }
else { Fail "game exited within $RunSeconds s (exit code $($proc.ExitCode))" }

if (-not $initNew)                                        { Fail 'tplayx_init.log got no new session - tplayx.dll did not initialise' }
elseif ($initNew -notmatch 'All plugins registered')      { Fail 'plugin registration did not finish (see tplayx_init.log)' }
elseif ($initNew -notmatch 'InstallPlugins completed OK') { Fail 'InstallPlugins did not complete (see tplayx_init.log)' }
else { Say 'Init    : all plugins registered, InstallPlugins completed OK' 'Green' }
$bad = ($initNew -split "`r?`n") | Where-Object { $_ -match 'FAILED' }
if ($bad) { Fail 'plugin failures in tplayx_init.log:'; $bad | ForEach-Object { Say "  $_" 'Red' } }

if ($crashed) {
  Fail 'ErrorLog.txt was written - the game crashed (newest entry):'
  $all = Get-Content $errLog -Raw
  $at  = $all.LastIndexOf('caused an')
  $entry = $all.Substring([Math]::Max(0, $at - 7)) -split "`r?`n"
  $entry | Where-Object { $_ -match 'caused an|module |Load Thread|Main Thread|Instruction pointer|Access violation:' } |
    Select-Object -First 6 | ForEach-Object { Say "  $($_.Trim())" 'Red' }
  # which module owns the crash address
  $ipLine = $entry | Where-Object { $_ -match 'Instruction pointer is ([0-9A-Fa-f]{8})' } | Select-Object -First 1
  if ($ipLine -and $ipLine -match '([0-9A-Fa-f]{8})') {
    $ip = [Convert]::ToUInt32($Matches[1], 16)
    foreach ($ml in ($entry | Where-Object { $_ -match '^\s*(\S+)\s*:\s*([0-9A-Fa-f]{8})\s*:\s*([0-9A-Fa-f]{8})' })) {
      $null = $ml -match '^\s*(\S+)\s*:\s*([0-9A-Fa-f]{8})\s*:\s*([0-9A-Fa-f]{8})'
      $b = [Convert]::ToUInt32($Matches[2], 16); $sz = [Convert]::ToUInt32($Matches[3], 16)
      if ($ip -ge $b -and $ip -lt $b + $sz) { Say ("  crash is in {0} at offset 0x{1:X}" -f $Matches[1], ($ip - $b)) 'Red' }
    }
  }
} else { Say 'Crash   : no new ErrorLog.txt entry' 'Green' }

# ---------------------------------------------------------------- 5. close
if ($werOpen) { $werOpen | Stop-Process -Force -ErrorAction SilentlyContinue }
if ($alive -and -not $KeepRunning) {
  Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
  Say 'Game closed (use -KeepRunning to leave it open)'
}
Finish
