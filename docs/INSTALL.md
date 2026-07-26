# Installing a compatible LibeR ecosystem

The consolidated release is the source of truth. Do not mix arbitrary package
versions from different release dates.

## Compatibility-checked installer

Source the current installer and let it resolve the newest published release.
The default `latest` channel includes research prereleases:

```r
source("https://raw.githubusercontent.com/svdijkman/LibeR/main/tools/install-ecosystem.R")
liber_install()
```

The installer reads `ecosystem.json`, installs the six packages in dependency
order, checks the exact versions, and runs `LibeRation::liber_doctor(strict =
TRUE)`. Source packages are the portable default. On Windows with the matching
R release, `liber_install(binary = TRUE)` uses the published precompiled
packages.

Select the newest stable release only, or pin an exact compatibility set for a
reproducible environment:

```r
liber_install(channel = "stable")
liber_install(tag = "v0.9.0-research-beta.4")
```

`LIBER_RELEASE_CHANNEL` and `LIBER_RELEASE_TAG` provide equivalent
non-interactive overrides. `LIBER_CRAN_MIRROR` changes the dependency mirror;
it defaults to `https://cloud.r-project.org`.

## Local source checkout

For development from the repository root, install the package sources in the
current checkout:

```text
Rscript tools/install-local-stack.R
```

This local command does not select a GitHub release: the checkout itself is the
version being installed. Use `--dependencies-only` to install only its missing
external R dependencies.

## Diagnose an installation

```r
LibeRation::liber_doctor()
LibeRation::liber_support_matrix()
```

The doctor reports the compatibility set, compiled CppAD/Eigen provenance,
wire contracts, queue capabilities, and optional workspace health.
