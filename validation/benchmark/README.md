# NONMEM versus LibeRation benchmark

This benchmark measures the same estimation and simulation workload in NONMEM
and LibeRation at two deliberately separate scopes:

- **End to end** is wall-clock time outside a fresh process. For NONMEM this
  covers PsN `execute`, NMTRAN/compilation, model execution, report/table
  creation, and process exit. For LibeRation it covers fresh `Rscript` startup,
  package/model/data loading, `nm_est()` or `nm_simulate()`, result
  serialization, and process exit.
- **Core** is the engine-reported estimation plus covariance elapsed time, or
  the timed simulation call. NONMEM simulation uses its total CPU time when the
  listing has no simulation-only elapsed timer. Fit and covariance times are
  also retained separately.

Fixture construction and post-run parsing/report generation happen outside the
timed sections for both engines. Each engine is constrained to one core. Runs
are grouped by engine and method so that warm-ups precede measured repetitions.

The default fixture is a one-compartment IV bolus model (ADVAN1/TRANS2). The
scenario matrix also covers oral absorption, two- and three-compartment PK,
full OMEGA, analytical steady-state infusion, IOV, and ADVAN6/ADVAN13 ODEs.
Both engines receive the same generated records, initial values, bounds,
variance parameterization, algorithm family, and iteration/sample controls.
NONMEM FO runs request `POSTHOC` so their estimation timer includes individual
ETA estimation comparable to LibeRation's returned FO fit.
IOV currently runs as a LibeRation-native validation case because its expanded
occasion ETA layout needs a scenario-specific NONMEM control stream.

## Run it

From the repository root:

```powershell
Rscript validation/benchmark/benchmark.R --profile=quick --methods=deterministic
```

Profiles are:

- `smoke`: harness check only (8 subjects, 4 samples per subject).
- `quick`: development comparison (20 subjects, 7 samples per subject).
- `standard`: more stable comparison (100 subjects, 7 samples per subject).
- `large`: scalability profile (1,000 subjects, 7 samples per subject).
- `very-large`: stress profile (5,000 subjects, 4 samples per subject).

The large profiles additionally make worker-payload size, result-payload size,
startup time, and peak R-heap use visible. They are opt-in and are not run on
every commit.

The default deterministic method set is FO, FOCE, FOCEI, and LAPLACE. Use
`--methods=all` to add ITS, IMP, and SAEM, or provide a comma-separated subset.
BAYES is excluded until matched NONMEM priors are specified.

Useful options include:

```text
--repeats=3              measured fresh-process repetitions
--warmups=1              unmeasured repetitions before measurements
--subjects=100           override the selected profile
--simulations=100        simulation replicates
--no-covariance          omit the covariance step
--no-simulation          estimate only
--engines=NONMEM         run one engine for diagnosis
--output=<directory>     fixed output directory
--resume                 keep successful rows and rerun failed/missing rows
--scenario=oral          select a model/data scenario
--population-objective=cpp  use the persistent C++ objective (`r` is the legacy comparator)
```

Available scenarios are `iv-bolus`, `oral`, `two-compartment`,
`three-compartment`, `full-omega`, `infusion-steady-state`, `iov`, `advan6`,
and `advan13`. Use `--engines=LIBERATION` for the current IOV case.

PsN's `execute` command and LibeRation must be available to the R process. The
script also recognises the external development cache selected by
`LIBER_DEV_CACHE` (by default, the sibling directory `LibeR-dev-cache`).

## Outputs

Each result directory contains:

- `REPORT.md`: concise paired timing report and interpretation limits.
- `raw-results.csv`: every warm-up and measured result, timing phase, status,
  estimates, convergence result, simulation checksum, payload sizes, and peak
  R-heap use.
- `summary.csv`: median/minimum/maximum measurements by engine and workload.
- `paired-timing-comparison.csv`: NONMEM/LibeRation timing ratios.
- `parameter-estimates.csv`: median estimates by method and engine.
- `parameter-comparison.csv`: paired estimates and relative differences for a
  numerical sanity check.
- `metadata.rds`: exact profile, versions, paths, and host information.
- Per-run control/configuration files, logs, listings, tables, and serialized
  results for audit and failure diagnosis.

Use end-to-end wall time as the primary operational comparison. Very small
NONMEM core times may be rounded by its listing, so the `standard` profile is
preferred for stable core ratios.
