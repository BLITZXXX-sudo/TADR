<#
.SYNOPSIS
  Build tplayx.dll, deploy it to TOTALA, commit+push any source changes,
  and cut a GitHub release with the built DLL attached.

.USAGE
  From this folder ("tplayx 2.0"), run:
    .\AUTO_COMMIT_RELEASE.ps1
    .\AUTO_COMMIT_RELEASE.ps1 -Message "fix: whatever"
    .\AUTO_COMMIT_RELEASE.ps1 -SkipPush          # build + commit locally only
    .\AUTO_COMMIT_RELEASE.ps1 -SkipRelease        # build + commit + push, no GitHub release
    .\AUTO_COMMIT_RELEASE.ps1 -NoBuild            # skip compiling, use the dll already on disk

  If the compile fails, NOTHING is committed, pushed, deployed, or released.
#>
param(
    [string]$Message,
    [switch]$SkipPush,
    [switch]$SkipRelease,
    [switch]$NoBuild,
    [string]$DeployPath = "C:\CAVEDOG\TOTALA\tplayx.dll",
    [string]$LazBuild   = "C:\Lazarus\lazbuild.exe"
)

$ErrorActionPreference = "Stop"

$RepoRoot   = Split-Path -Parent $PSScriptRoot          # ...\TADR_tplayx20_wt
$ProjectDir = Join-Path $PSScriptRoot "src\Recorder"
$LpiFile    = Join-Path $ProjectDir "tplayx.lpi"
$DllFile    = Join-Path $ProjectDir "tplayx.dll"

function Fail($msg) {
    Write-Host "`n*** FAILED: $msg ***" -ForegroundColor Red
    if ($OrigLocation) { Set-Location $OrigLocation }
    exit 1
}

$OrigLocation = Get-Location

# ---------------------------------------------------------------- 1. BUILD
if (-not $NoBuild) {
    Write-Host "==> Building (lazbuild --build-mode=Default) ..." -ForegroundColor Cyan
    if (-not (Test-Path $LazBuild)) { Fail "lazbuild.exe not found at $LazBuild (pass -LazBuild <path>)" }
    Set-Location $ProjectDir
    $buildLog = & $LazBuild --build-mode=Default "tplayx.lpi" 2>&1
    Set-Location $OrigLocation
    $buildLog | Out-File -Encoding utf8 (Join-Path $PSScriptRoot "last_build.log")

    $errors = $buildLog | Select-String -Pattern "Error:"
    if ($errors) {
        Write-Host "`nBuild FAILED:" -ForegroundColor Red
        $errors | ForEach-Object { Write-Host $_.Line -ForegroundColor Red }
        Fail "compiler reported errors - see `"$PSScriptRoot\last_build.log`". Nothing committed or deployed."
    }
    if (-not (Test-Path $DllFile)) {
        Fail "build reported success but $DllFile is missing"
    }
    Write-Host "Build OK: $DllFile ($((Get-Item $DllFile).Length) bytes)" -ForegroundColor Green
} else {
    Write-Host "==> Skipping build (-NoBuild), using existing $DllFile" -ForegroundColor Yellow
    if (-not (Test-Path $DllFile)) { Fail "$DllFile does not exist - can't skip the build" }
}

# ---------------------------------------------------------------- 2. DEPLOY
Write-Host "==> Deploying to $DeployPath ..." -ForegroundColor Cyan
$deployDir = Split-Path -Parent $DeployPath
if (-not (Test-Path $deployDir)) { Fail "deploy folder $deployDir does not exist" }
Copy-Item $DllFile $DeployPath -Force
Write-Host "Deployed." -ForegroundColor Green

# ---------------------------------------------------------------- 3. VERSION
$lpiText = Get-Content $LpiFile -Raw
function Get-VerPart($name) {
    if ($lpiText -match "<$name Value=`"(\d+)`"") { return $Matches[1] } else { return "0" }
}
$version = "{0}.{1}.{2}.{3}" -f (Get-VerPart "MajorVersionNr"), (Get-VerPart "MinorVersionNr"), `
                                  (Get-VerPart "RevisionNr"), (Get-VerPart "BuildNr")
Write-Host "Version: $version" -ForegroundColor Cyan

# ---------------------------------------------------------------- 4. COMMIT
Set-Location $RepoRoot
git add -A
$staged = git diff --cached --name-only
$hasChanges = [bool]$staged

if ($hasChanges) {
    if (-not $Message) {
        $fileList = ($staged -split "`n") -join ", "
        if ($fileList.Length -gt 200) { $fileList = $fileList.Substring(0,200) + " ..." }
        $Message = "tplayx $version : $fileList"
    }
    git commit -m $Message
    if ($LASTEXITCODE -ne 0) { Fail "git commit failed" }
    Write-Host "Committed: $Message" -ForegroundColor Green
} else {
    Write-Host "No source changes - skipping commit." -ForegroundColor Yellow
    if (-not $Message) { $Message = "tplayx $version" }
}

# ---------------------------------------------------------------- 5. PUSH
if (-not $SkipPush) {
    $branch = git rev-parse --abbrev-ref HEAD
    Write-Host "==> Pushing $branch ..." -ForegroundColor Cyan
    git push
    if ($LASTEXITCODE -ne 0) { Fail "git push failed - resolve manually (pull/rebase?) then re-run with -NoBuild" }
    Write-Host "Pushed." -ForegroundColor Green
} else {
    Write-Host "Skipping push (-SkipPush)." -ForegroundColor Yellow
}

# ---------------------------------------------------------------- 6. RELEASE
if (-not $SkipRelease -and -not $SkipPush) {
    $tag = "v$version"
    Write-Host "==> Tagging $tag ..." -ForegroundColor Cyan
    git tag -f $tag
    git push origin $tag --force

    $zipPath = Join-Path $env:TEMP "tplayx_$version.zip"
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Compress-Archive -Path $DllFile -DestinationPath $zipPath

    $ghCmd = Get-Command gh -ErrorAction SilentlyContinue
    if ($ghCmd) {
        Write-Host "==> Creating GitHub release $tag ..." -ForegroundColor Cyan
        gh release delete $tag --yes 2>$null
        gh release create $tag $zipPath --title "tplayx $version" --notes $Message
        Write-Host "Release $tag created with $zipPath attached." -ForegroundColor Green
    } else {
        Write-Host "gh CLI not found - skipping GitHub release. DLL zipped at $zipPath" -ForegroundColor Yellow
    }
} else {
    Write-Host "Skipping release." -ForegroundColor Yellow
}

Set-Location $OrigLocation
Write-Host "`nDone." -ForegroundColor Green
