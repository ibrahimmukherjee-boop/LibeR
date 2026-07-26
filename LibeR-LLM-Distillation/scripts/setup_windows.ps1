param(
    [switch]$Training,
    [string]$PythonVersion = "3.12"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Python = Join-Path $Root ".venv\Scripts\python.exe"

Push-Location $Root
try {
    if (-not (Test-Path -LiteralPath $Python)) {
        py "-$PythonVersion" -m venv .venv
    }
    & $Python -m pip install --upgrade pip setuptools wheel
    if ($Training) {
        # CUDA 12.8 wheels include support required by the RTX 50 generation.
        & $Python -m pip install torch --index-url https://download.pytorch.org/whl/cu128
        & $Python -m pip install -e ".[train,test]"
    } else {
        & $Python -m pip install -e ".[test]"
    }
    & $Python -m liber_distill --config configs/default.yaml doctor
} finally {
    Pop-Location
}
