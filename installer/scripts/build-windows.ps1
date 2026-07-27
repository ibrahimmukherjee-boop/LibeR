param(
  [ValidateSet("Research", "Runtime")]
  [string]$Profile = "Research",
  [string]$Root = "",
  [string]$StageDirectory = "",
  [string]$OutputDirectory = "",
  [string]$ISCC = "",
  [switch]$PlanOnly,
  [switch]$AllowDirty,
  [switch]$SkipStage
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

if ($SkipStage -and $PlanOnly) {
  throw "-SkipStage and -PlanOnly cannot be combined."
}
if (-not $SkipStage) {
  $stageArguments = @{
    Profile = $Profile
    Root = $Root
    StageDirectory = $StageDirectory
    PlanOnly = $PlanOnly
    AllowDirty = $AllowDirty
  }
  & (Join-Path $PSScriptRoot "stage-runtime.ps1") @stageArguments
  if ($PlanOnly) { exit $LASTEXITCODE }
} else {
  $tracked = @(git -C $Root status --porcelain=v1 --untracked-files=all)
  if ($tracked.Count) {
    throw "-SkipStage requires a clean source checkout."
  }
  $stageMarker = Join-Path $StageDirectory ".liber-installer-stage.json"
  $planPath = Join-Path $StageDirectory "build-plan.json"
  if (-not (Test-Path -LiteralPath $stageMarker) -or
      -not (Test-Path -LiteralPath $planPath)) {
    throw "-SkipStage requires a marked, completed stage directory."
  }
  $plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
  $currentCommit = (git -C $Root rev-parse HEAD).Trim()
  if ([string]$plan.schema -ne "liber.installer-plan/1" -or
      [string]$plan.release -ne $release -or
      [string]$plan.profile -ne $Profile.ToLower() -or
      [string]$plan.source_commit -ne $currentCommit -or
      -not [bool]$plan.publishable) {
    throw "The existing installer stage does not match the current source."
  }
}

if (-not $ISCC) {
  $candidates = @()
  if ($env:INNO_SETUP_HOME) {
    $candidates += Join-Path $env:INNO_SETUP_HOME "ISCC.exe"
  }
  $candidates += @(
    "$env:ProgramFiles(x86)\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
  )
  $ISCC = $candidates |
    Where-Object { $_ -and (Test-Path -LiteralPath $_) } |
    Select-Object -First 1
}
if (-not $ISCC) {
  throw "Inno Setup 6 was not found. Install it or pass -ISCC."
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$sourceDirectory = if ($Profile -eq "Research") {
  Join-Path $StageDirectory "developer\sources"
} else {
  Join-Path $OutputDirectory "$release-corresponding-source"
}
if ($Profile -eq "Runtime") {
  $sourceMarker = Join-Path $sourceDirectory ".liber-corresponding-source.json"
  if (Test-Path -LiteralPath $sourceDirectory) {
    if (-not (Test-Path -LiteralPath $sourceMarker)) {
      throw "Refusing to replace an unmarked corresponding-source directory."
    }
    $marker = Get-Content -LiteralPath $sourceMarker -Raw | ConvertFrom-Json
    if ([string]$marker.schema -ne "liber.corresponding-source/1" -or
        [string]$marker.release -ne $release) {
      throw "The existing corresponding-source marker is invalid."
    }
    Remove-Item -LiteralPath $sourceDirectory -Recurse -Force
  }
  New-Item -ItemType Directory -Path $sourceDirectory -Force | Out-Null
  & (Join-Path $StageDirectory "runtime\R\bin\Rscript.exe") `
    (Join-Path $Root "installer\scripts\collect-sources.R") `
    "--root=$Root" "--library=$(Join-Path $StageDirectory 'library')" `
    "--destination=$sourceDirectory"
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to collect the corresponding-source archive."
  }
  [ordered]@{
    schema = "liber.corresponding-source/1"
    release = $release
    created_at_utc = [DateTime]::UtcNow.ToString("o")
  } | ConvertTo-Json | Set-Content -LiteralPath $sourceMarker -Encoding UTF8
}
if (-not (Test-Path -LiteralPath (Join-Path $sourceDirectory "sources.csv"))) {
  throw "The staged corresponding-source manifest is missing."
}
$sourceArchive = Join-Path (
  $OutputDirectory
) "LibeR-$release-corresponding-source.zip"
if (Test-Path -LiteralPath $sourceArchive) {
  Remove-Item -LiteralPath $sourceArchive -Force
}
Compress-Archive -Path (Join-Path $sourceDirectory "*") `
  -DestinationPath $sourceArchive -CompressionLevel Optimal

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

$artifacts = Get-ChildItem -LiteralPath $OutputDirectory -File |
  Where-Object { $_.Extension -in @(".exe", ".zip") }
$checksums = foreach ($file in $artifacts) {
  "{0}  {1}" -f (
    Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256
  ).Hash, $file.Name
}
$checksums | Set-Content -LiteralPath (Join-Path $OutputDirectory "SHA256SUMS") `
  -Encoding ascii
Write-Host "Built installers in $OutputDirectory"
