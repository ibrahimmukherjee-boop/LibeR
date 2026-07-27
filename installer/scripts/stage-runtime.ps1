param(
  [ValidateSet("Research", "Runtime")]
  [string]$Profile = "Research",
  [string]$Root = "",
  [string]$RHome = "",
  [string]$RtoolsHome = "",
  [string]$StageDirectory = "",
  [switch]$PlanOnly,
  [switch]$AllowDirty
)

$ErrorActionPreference = "Stop"
if (-not $Root) {
  $Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}
$Root = (Resolve-Path -LiteralPath $Root).Path.TrimEnd("\")
if (-not (Test-Path -LiteralPath (Join-Path $Root "ecosystem.json"))) {
  throw "The source root does not contain ecosystem.json: $Root"
}

$manifest = Get-Content -LiteralPath (Join-Path $Root "ecosystem.json") -Raw |
  ConvertFrom-Json
$installerConfig = Get-Content -LiteralPath (
  Join-Path $Root "installer\config\installer.json"
) -Raw | ConvertFrom-Json
if ([string]$installerConfig.schema -ne "liber.installer/1") {
  throw "Unsupported installer configuration schema."
}
$release = [string]$manifest.release
if (-not $RHome) {
  $RHome = & Rscript -e "cat(normalizePath(R.home(), winslash='/', mustWork=TRUE))"
}
$RHome = (Resolve-Path -LiteralPath $RHome).Path
$bundledRscript = Join-Path $RHome "bin\Rscript.exe"
if (-not (Test-Path -LiteralPath $bundledRscript)) {
  throw "The selected R home does not contain bin\Rscript.exe: $RHome"
}
$rVersion = & $bundledRscript --vanilla -e "cat(as.character(getRversion()))"
$rPlatform = & $bundledRscript --vanilla -e "cat(R.version`$platform)"
if ($rVersion -ne [string]$installerConfig.runtime.r_version -or
    $rPlatform -ne [string]$installerConfig.runtime.r_platform) {
  throw (
    "The selected R runtime is $rVersion ($rPlatform); installer configuration " +
    "requires $($installerConfig.runtime.r_version) " +
    "($($installerConfig.runtime.r_platform))."
  )
}

if (-not $RtoolsHome) {
  $candidate = @(
    $env:RTOOLS_HOME,
    $env:RTOOLS45_HOME,
    "C:\rtools45"
  ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } |
    Select-Object -First 1
  if ($candidate) { $RtoolsHome = (Resolve-Path -LiteralPath $candidate).Path }
}
$rtoolsCompiler = if ($RtoolsHome) {
  Join-Path $RtoolsHome "x86_64-w64-mingw32.static.posix\bin\g++.exe"
} else {
  ""
}
if (-not $RtoolsHome -or -not (Test-Path -LiteralPath $rtoolsCompiler)) {
  throw (
    "Building either installer profile requires an Rtools " +
    "$($installerConfig.runtime.rtools_series) toolchain."
  )
}
$rtoolsPaths = @(
  (Join-Path $RtoolsHome "x86_64-w64-mingw32.static.posix\bin"),
  (Join-Path $RtoolsHome "usr\bin")
)
$env:PATH = @($rtoolsPaths + $env:PATH) -join [IO.Path]::PathSeparator
$env:R_MAKEVARS_USER = Join-Path $Root "tools\Makevars.rtools45"

if (-not $StageDirectory) {
  $devCache = if ($env:LIBER_DEV_CACHE) {
    [IO.Path]::GetFullPath($env:LIBER_DEV_CACHE)
  } else {
    $cacheName = (Split-Path $Root -Leaf) + "-dev-cache"
    [IO.Path]::GetFullPath(
      (Join-Path (Split-Path $Root -Parent) $cacheName)
    )
  }
  $StageDirectory = Join-Path $devCache "installer\stage\$release-$($Profile.ToLower())"
}
$StageDirectory = [IO.Path]::GetFullPath($StageDirectory).TrimEnd("\")
if ($StageDirectory -eq $Root -or
    $Root.StartsWith($StageDirectory + "\", [StringComparison]::OrdinalIgnoreCase)) {
  throw "The stage directory may not contain the source checkout."
}

$tracked = @(git -C $Root status --porcelain=v1 --untracked-files=all)
if ($tracked.Count -and -not $AllowDirty) {
  throw "A publishable installer requires a clean tracked worktree."
}

$includeDeveloper = $Profile -eq "Research"
$plan = [ordered]@{
  schema = "liber.installer-plan/1"
  release = $release
  profile = $Profile.ToLower()
  source_root = $Root
  stage_directory = $StageDirectory
  r_home = $RHome
  r_version = $rVersion
  r_platform = $rPlatform
  build_rtools_home = $RtoolsHome
  include_developer = $includeDeveloper
  bundled_rtools_home = if ($includeDeveloper) { $RtoolsHome } else { $null }
  publishable = -not [bool]$tracked.Count
  source_commit = (git -C $Root rev-parse HEAD).Trim()
  created_at_utc = [DateTime]::UtcNow.ToString("o")
}

if ($PlanOnly) {
  $plan | ConvertTo-Json -Depth 6
  exit 0
}
if (Test-Path -LiteralPath $StageDirectory) {
  $resolved = (Resolve-Path -LiteralPath $StageDirectory).Path
  $markerPath = Join-Path $resolved ".liber-installer-stage.json"
  if (-not (Test-Path -LiteralPath $markerPath)) {
    throw "Refusing to replace an unmarked stage directory: $resolved"
  }
  $marker = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
  if ([string]$marker.schema -ne "liber.installer-stage/1" -or
      -not [string]::Equals(
        [IO.Path]::GetFullPath([string]$marker.stage_directory).TrimEnd("\"),
        $resolved.TrimEnd("\"),
        [StringComparison]::OrdinalIgnoreCase
      )) {
    throw "Refusing to replace a stage directory with an invalid marker: $resolved"
  }
  Remove-Item -LiteralPath $resolved -Recurse -Force
}
New-Item -ItemType Directory -Path $StageDirectory -Force | Out-Null
$stageMarker = [ordered]@{
  schema = "liber.installer-stage/1"
  stage_directory = $StageDirectory
  source_root = $Root
  release = $release
  created_at_utc = [DateTime]::UtcNow.ToString("o")
}
$stageMarker | ConvertTo-Json -Depth 4 |
  Set-Content -LiteralPath (
    Join-Path $StageDirectory ".liber-installer-stage.json"
  ) -Encoding UTF8
$runtime = Join-Path $StageDirectory "runtime"
$developer = Join-Path $StageDirectory "developer"
$app = Join-Path $StageDirectory "app"
$privateLibrary = Join-Path $StageDirectory "library"
New-Item -ItemType Directory -Path $runtime,$app,$privateLibrary -Force |
  Out-Null

Copy-Item -LiteralPath $RHome -Destination (Join-Path $runtime "R") -Recurse
$bundledR = Join-Path $runtime "R"
# Do not redistribute machine-specific installer state or site startup files.
# All product shortcuts also use --vanilla, but sanitising the copied runtime
# protects child R processes that may be launched without that flag.
@(
  (Join-Path $bundledR "unins000.dat"),
  (Join-Path $bundledR "unins000.exe"),
  (Join-Path $bundledR "unins000.msg"),
  (Join-Path $bundledR "MD5"),
  (Join-Path $bundledR "etc\Renviron.site"),
  (Join-Path $bundledR "etc\Rprofile.site"),
  (Join-Path $bundledR "bin\RSetReg.exe"),
  (Join-Path $bundledR "bin\x64\RSetReg.exe")
) | ForEach-Object {
  if (Test-Path -LiteralPath $_) {
    Remove-Item -LiteralPath $_ -Force
  }
}
Copy-Item -LiteralPath (Join-Path $Root "installer\launchers\launch.R") `
  -Destination $app
Copy-Item -LiteralPath (Join-Path $Root "installer\launchers\doctor.R") `
  -Destination $app
Copy-Item -LiteralPath (Join-Path $Root "installer\windows\liber.ico") `
  -Destination $app
Copy-Item -LiteralPath (Join-Path $Root "ecosystem.json") -Destination $app
Copy-Item -LiteralPath (Join-Path $Root "LICENSES") -Destination $app -Recurse

if ($includeDeveloper) {
  New-Item -ItemType Directory -Path $developer -Force | Out-Null
  $bundledRtools = Join-Path $developer "rtools"
  New-Item -ItemType Directory -Path $bundledRtools -Force | Out-Null
  foreach ($name in @(
      "x86_64-w64-mingw32.static.posix", "usr", "etc", "var"
    )) {
    $source = Join-Path $RtoolsHome $name
    if (Test-Path -LiteralPath $source) {
      Copy-Item -LiteralPath $source -Destination (
        Join-Path $bundledRtools $name
      ) -Recurse
    }
  }
  foreach ($name in @("autorebase.bat", "msys2.exe", "msys2_shell.cmd")) {
    $source = Join-Path $RtoolsHome $name
    if (Test-Path -LiteralPath $source) {
      Copy-Item -LiteralPath $source -Destination $bundledRtools
    }
  }
  $sources = Join-Path $developer "sources"
  New-Item -ItemType Directory -Path $sources -Force | Out-Null
}

& (Join-Path $RHome "bin\Rscript.exe") `
  (Join-Path $Root "installer\scripts\populate-library.R") `
  "--root=$Root" "--library=$privateLibrary" `
  "--profile=$($Profile.ToLower())"
if ($LASTEXITCODE -ne 0) { throw "Unable to populate the private R library." }

if ($includeDeveloper) {
  $oldRLibs = $env:R_LIBS
  $env:R_LIBS = @(
    $privateLibrary,
    (Join-Path $RHome "library")
  ) -join [IO.Path]::PathSeparator
  Push-Location $sources
  try {
    foreach ($package in $manifest.packages.PSObject.Properties.Name) {
      & (Join-Path $RHome "bin\R.exe") CMD build --no-manual `
        --no-build-vignettes (Join-Path $Root $package)
      if ($LASTEXITCODE -ne 0) {
        throw "Unable to build source archive: $package"
      }
    }
  } finally {
    Pop-Location
    $env:R_LIBS = $oldRLibs
  }
}

if ($Profile -eq "Runtime") {
  $rInclude = Join-Path $runtime "R\include"
  if (Test-Path -LiteralPath $rInclude) {
    Remove-Item -LiteralPath $rInclude -Recurse -Force
  }
  Get-ChildItem -LiteralPath $privateLibrary -Directory | ForEach-Object {
    $packageInclude = Join-Path $_.FullName "include"
    if (Test-Path -LiteralPath $packageInclude) {
      Remove-Item -LiteralPath $packageInclude -Recurse -Force
    }
  }
}

$plan | ConvertTo-Json -Depth 6 |
  Set-Content -LiteralPath (Join-Path $StageDirectory "build-plan.json") `
    -Encoding UTF8
$files = Get-ChildItem -LiteralPath $StageDirectory -Recurse -File
$index = foreach ($file in $files) {
  [pscustomobject]@{
    path = $file.FullName.Substring($StageDirectory.Length + 1).Replace("\", "/")
    bytes = $file.Length
    sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
  }
}
$index | Export-Csv -LiteralPath (Join-Path $StageDirectory "files.csv") `
  -NoTypeInformation -Encoding UTF8
Write-Host "Staged LibeR bundled runtime at $StageDirectory"
