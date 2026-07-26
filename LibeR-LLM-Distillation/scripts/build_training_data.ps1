param(
    [string]$Config = "configs/default.yaml",
    [string[]]$Overlay = @(),
    [int]$Limit = 0
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Python = Join-Path $Root ".venv\Scripts\python.exe"
$Arguments = @("-m", "liber_distill", "--config", $Config)
foreach ($Item in $Overlay) {
    $Arguments += @("--overlay", $Item)
}
$Arguments += "build-training-data"
if ($Limit -gt 0) {
    $Arguments += @("--limit", $Limit)
}

Push-Location $Root
try {
    & $Python @Arguments
} finally {
    Pop-Location
}
