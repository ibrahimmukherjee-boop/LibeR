param(
  [ValidateSet("Research", "Runtime")]
  [string]$Profile = "Research",
  [string]$Root = "",
  [string]$StageDirectory = "",
  [string]$OutputDirectory = "",
  [string]$ISCC = "",
  [switch]$PlanOnly,
  [switch]$AllowDirty
)

$ErrorActionPreference = "Stop"
if (-not $Root) {
  $Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}
$Root = (Resolve-Path -LiteralPath $Root).Path
$manifest = Get-Content -LiteralPath (Join-Path $Root "ecosystem.json") -Raw |
  ConvertFrom-Json
$release = [string]$manifest.release
$devCache = if ($env:LIBER_DEV_CACHE) {
  [IO.Path]::GetFullPath($env:LIBER_DEV_CACHE)
} else {
  $cacheName = (Split-Path $Root -Leaf) + "-dev-cache"
  [IO.Path]::GetFullPath(
    (Join-Path (Split-Path $Root -Parent) $cacheName)
  )
}
if (-not $StageDirectory) {
  $StageDirectory = Join-Path $devCache "installer\stage\$release-$($Profile.ToLower())"
}
if (-not $OutputDirectory) {
  $OutputDirectory = Join-Path $devCache "installer\output\$release"
}

$stageArguments = @{
  Profile = $Profile
  Root = $Root
  StageDirectory = $StageDirectory
  PlanOnly = $PlanOnly
  AllowDirty = $AllowDirty
}
& (Join-Path $PSScriptRoot "stage-runtime.ps1") @stageArguments
if ($PlanOnly) { exit $LASTEXITCODE }

if (-not $ISCC) {
  $candidates = @(
    $env:INNO_SETUP_HOME | ForEach-Object {
      if ($_) { Join-Path $_ "ISCC.exe" }
    },
    "$env:ProgramFiles(x86)\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
  ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
  $ISCC = $candidates | Select-Object -First 1
}
if (-not $ISCC) {
  throw "Inno Setup 6 was not found. Install it or pass -ISCC."
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$definition = @(
  "/Qp",
  "/DStageDir=$StageDirectory",
  "/DOutputDir=$OutputDirectory",
  "/DAppVersion=$release",
  "/DVersionInfoVersion=$($release -replace '[^0-9.].*$', '' -replace '-.*$', '').0",
  "/DInstallerProfile=$($Profile.ToLower())"
)
& $ISCC @definition (Join-Path $Root "installer\windows\LibeR.iss")
if ($LASTEXITCODE -ne 0) { throw "Inno Setup compilation failed." }

$installers = Get-ChildItem -LiteralPath $OutputDirectory -File -Filter "*.exe"
$checksums = foreach ($file in $installers) {
  "{0}  {1}" -f (
    Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256
  ).Hash, $file.Name
}
$checksums | Set-Content -LiteralPath (Join-Path $OutputDirectory "SHA256SUMS") `
  -Encoding ascii
Write-Host "Built installers in $OutputDirectory"
