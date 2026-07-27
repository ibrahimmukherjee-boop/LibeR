# LibeR bundled-runtime installer

This directory implements a second, parallel deployment path. It does not
replace the six R packages or the existing manual/GitHub installation flow.

The Windows installer contains:

- a private, versioned R runtime;
- an isolated R package library containing one exact `ecosystem.json` set;
- launchers for each LibeR GUI;
- integrity, package, licence, and source-provenance manifests;
- an optional developer component containing package sources and headers;
- a corresponding-source archive for the bundled R runtime and installed
  packages.

The installer is per-user and never writes to a system R library. Application
data remains outside the installation:

- LibeRation workspaces: `Documents/LibeR/workspace`;
- LibeRary data: `Documents/LibeR-data/library`;
- LibeRator patient workspaces: `Documents/LibeR-data/liberator-workspace`;
- LibeRtAD benchmark results: `Documents/LibeR-data/benchmarks`;
- large development caches: configurable through `LIBER_DEV_CACHE`.

## Profiles

`research` is the early-release default. It includes the developer component,
allowing source inspection and compilation-oriented workflows. Rtools is used
on the build machine but is not redistributed. Users who want to compile
packages inside the installed Research environment should install the matching
official Rtools release separately.

`runtime` creates the mature target layout: the private runtime and compiled
packages are retained, while toolchains, source archives, and exported
development headers are excluded.

## Build

From the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File installer/scripts/build-windows.ps1 -Profile Research
```

Use `-PlanOnly` to validate inputs and generate the build plan without copying
the runtime or installing packages.

The build requires Inno Setup 6 (`ISCC.exe`). The output installer and its
SHA-256 manifest are written to the external LibeR development cache by
default, not to the source checkout.

The installer and Start-menu icon is generated from the canonical LibeR dove.
After updating that source asset, regenerate the Windows icon with Python and
Pillow:

```powershell
python installer/scripts/build-icon.py `
  tools/assets/liber-dove-source.svg installer/windows/liber.ico
```

Each ecosystem release has its own application identifier and installation
directory. Research and runtime builds therefore remain isolated from a
manually installed R environment and from other LibeR versions.

## Security and release requirements

Production installers must be Authenticode-signed and their SHA-256 published
with the matching GitHub release. A build is rejected when package versions do
not match `ecosystem.json`, when required provenance is absent, or when the
source checkout has tracked changes unless an explicitly non-publishable
development build was requested.

Inno Setup 6.7 is currently suitable for non-commercial research distribution.
A commercial LibeR distribution must use an appropriately licensed Inno Setup
compiler or move the final packaging step to a permissively licensed backend.
The staged runtime is packaging-neutral, so that choice does not affect the R
runtime, package library, manifests, or launchers.

The package, source, and file manifests freeze the contents of a completed
installer. Every build also creates a companion corresponding-source archive.
The Research installer includes the same material in its developer component.
This avoids redistributing the much larger Rtools/MSYS2 toolchain and its
separate source-compliance surface.

Before a 1.0 production release, the build pipeline should additionally resolve
CRAN dependencies through a dated binary snapshot so that an installer can be
rebuilt from the same inputs after CRAN advances.
