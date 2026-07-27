# Independent external-comparator validation

This directory is the registry and executable entry point for independent
software comparisons that complement LibeR's analytic, metamorphic, NONMEM,
simulation-recovery, and property-based validation. Agreement with another
package is never treated as sufficient evidence by itself: implementations may
share numerical libraries, omit different likelihood constants, or encode
different statistical parameterisations.

`comparators.csv` records every proposed comparator, its independence class,
availability, adapter, and qualification boundary. It deliberately retains
licensed and deployment-only comparators as `manual`; their absence is not
silently converted into a pass.

## Portable open-source campaign

Install the small comparator set into an isolated library:

```text
Rscript validation/external-comparators/install-dependencies.R
```

Use `--extended` to install the heavier population, HMM, particle, Bayesian
state-space, and model-informed dosing packages. Optional non-R runtimes have
isolated installers:

```text
Rscript validation/external-comparators/install-cmdstan.R
julia validation/external-comparators/install-sciml.jl
```

The CmdStan installer pins 2.39.0 by default and records its exact version below
`$LIBER_DEV_CACHE/external-tools/cmdstan/`; the Julia installer creates a project and manifest
below `$LIBER_DEV_CACHE/external-tools/julia-project/` from exact top-level SciML versions and
includes both files in evidence provenance. The runner also detects a portable
COPASI installation at `$LIBER_DEV_CACHE/external-tools/COPASI/`. When
`LIBER_DEV_CACHE` is unset, the default is a `LibeR-dev-cache` sibling of the
source checkout.

Create the exact source-built LibeR validation library and run the campaign:

```text
Rscript tools/create-validation-library.R --source
Rscript validation/external-comparators/run-validation.R
```

The default gate executes:

- a scalar linear Gaussian state-space comparison with KFAS;
- when installed, replicated particle-likelihood comparisons with pomp and bssm;
- Bernoulli and zero-inflated Poisson likelihood comparisons with glmmTMB;
- when installed, HMM likelihood, smoothing, and Viterbi comparisons with
  hmmTMB;
- a QSP reaction-network trajectory comparison with deSolve; and
- when installed, nonlinear QSP comparison with COPASI and ADVAN14, DDE, DAE,
  QSP, and SDE comparisons with Julia SciML/Sundials; and
- when installed, FO, FOCE, and FOCEI population estimation with nlmixr2,
  including freely estimated OMEGA/SIGMA, full correlated OMEGA, IOV,
  M3/M4 BLQ likelihoods, and time-varying covariates;
- subject-level finite mixtures and all supported prior families against
  independent aggregated/closed-form likelihood calculations; and
- when its compiler-backed example model can be built, a MAP individual-fit
  comparison with mapbayr and a LibeRator MAP comparison with posologyr.

Missing **required** comparator packages make the campaign incomplete.
`--strict` additionally treats optional comparator unavailability as a failing
exit status. An installed comparator that errors or exceeds its declared
tolerance always fails.

The runner writes `comparisons.csv`, `coverage.csv`, `summary.json`,
`provenance.json`, `REPORT.md`, and a copy of the comparator registry below
`results/<timestamp>/`. Use `--output=<path>`, `--library=<path>`, or
`--external-library=<path>` to override defaults.

On Windows the runner explicitly selects the current Rtools compiler rather
than accepting an unrelated `gcc.exe` earlier in `PATH`. The nlmixr2 adapters
also keep temporary rxode2 model DLLs loaded for the lifetime of their
short-lived `Rscript` process, avoiding garbage-collection-driven unload races
and stale native references.

The remaining licensed and deployment-specific campaign is defined in
`MANUAL-COMPARATORS.md`, including the required provenance for imported
NONMEM, Monolix, Pumas, and production-deployment results.

## Other executable suites

- `validation/ad-backends/run-benchmark.R` optionally cross-checks LibeRtAD
  against CmdStan/Stan Math; TMB is useful engineering evidence but shares
  CppAD ancestry.
- `validation/nonmem/run-validation.R --run` is the direct NONMEM gate.
  ADVAN14 remains unavailable with NONMEM 7.3 and requires a 7.4+ runner.
- `validation/liberality/external/run-validation.R` performs the existing
  PopED/PFIM comparison.
- `validation/liberary/` contains the curated AED corpus gate.

Monolix and Pumas remain licensed/manual comparators. ASReview and document
parsers require corpus-level fixtures. The executable k6 and OWASP ZAP harness
for a disposable running LibeRties service is under
`validation/liberties/deployment/`; deployment isolation and penetration
qualification still require the intended Linux environment. These boundaries
remain explicit in `comparators.csv`; unavailable checks are never converted
into a pass.
