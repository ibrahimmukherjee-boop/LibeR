# NONMEM, LibeRation, and nlmixr2 benchmark

This benchmark measures the same estimation and simulation workload in NONMEM,
LibeRation, and nlmixr2 at two deliberately separate scopes:

- **End to end** is wall-clock time outside a fresh process. For NONMEM this
  covers PsN `execute`, NMTRAN/compilation, model execution, report/table
  creation, and process exit. For LibeRation it covers fresh `Rscript` startup,
  package/model/data loading, `nm_est()` or `nm_simulate()`, result
  serialization, and process exit. nlmixr2 uses the same fresh-process boundary
  through its nlmixr2est/rxode2 stack.
- **Core** is post-initialization estimation plus covariance elapsed time, or
  the timed simulation call. LibeRation excludes initial model/context/tape
  construction from estimation core time but retains it in end-to-end wall
  time. NONMEM uses its reported estimation/covariance timers when available
  and otherwise its total CPU time. nlmixr2 core time is its complete estimator
  call, including estimator-internal preparation and covariance because the
  public result does not expose stable separate timers for those phases.
  Simulation likewise uses the timed engine call, with NONMEM falling back to
  total CPU time when the listing has no simulation-only timer. Fit and
  covariance times are retained separately when an engine exposes them.

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
nlmixr2 FO likewise requests posthoc ETAs. Exact nlmixr2 mappings are included
for FO, FOCE, FOCEI, LAPLACE, IMP, and SAEM. ITS and BAYES remain in the full
NONMEM/LibeRation benchmark but are shown as not applicable for nlmixr2 rather
than being replaced by a different algorithm.
The benchmark has one matched-control track. SAEM burn-in and stationary
iterations are counted separately in NONMEM but are converted to the same total
for LibeRation; its nominal samples/proposals per iteration are also matched.
All stochastic controls use the same recorded seed, while the engine-specific
random-number generators are intentionally not treated as identical streams.
LibeRation is run with `numerical_mode = "nonmem_compatibility"`; the faster
LibeR-specific policy is deliberately excluded from the matched reference
track and can be benchmarked separately as an optimisation experiment.
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
`--methods=all` to add ITS, IMP, SAEM, and BAYES, or provide a comma-separated
subset. BAYES uses a dedicated matched posterior: every free THETA has the
same explicit normal prior in both engines, OMEGA and SIGMA are fixed, and the
burn-in and retained-iteration counts are identical. This avoids presenting
different default priors as a meaningful Bayesian comparison.

Useful options include:

```text
--repeats=3              measured fresh-process repetitions
--warmups=1              unmeasured repetitions before measurements
--subjects=100           override the selected profile
--simulations=100        simulation replicates
--no-covariance          omit the covariance step
--no-simulation          estimate only
--engines=NONMEM         run one engine for diagnosis (also LIBERATION,NLMIXR2)
--nlmixr-library=<dir>   optional library containing nlmixr2est/rxode2
--nlmixr-methods=<list>  exact nlmixr2 mappings to execute (diagnostic override)
--output=<directory>     fixed output directory
--resume                 keep successful rows and rerun failed/missing rows
--scenario=oral          select a model/data scenario
--numerical-mode=liber_optimized  compare the opt-in LibeR solver policy
--population-objective=cpp  use the persistent C++ objective (`r` is the legacy comparator)
--saem-kernel=auto       `random_walk` or optimized `fsaem`
--fsaem-refresh=25       refresh interval for Laplace independence proposals
--fsaem-rescue-probability=0.1  exact random-walk mixture probability
--fsaem-parameter-refresh=0.15  early-refresh relative parameter drift
--fsaem-low-acceptance=0.1      early-refresh acceptance threshold
--bayes-outer-kernel=auto  `isotropic` or optimized `adaptive_metropolis`
--bayes-adaptive-start=50  retained states before covariance adaptation
--bayes-adaptive-interval=10  iterations between covariance updates
```

`auto` retains the established random-walk/isotropic kernels under
`nonmem_compatibility`. Under `liber_optimized`, eligible SAEM models with one
or more ETAs select the Laplace-independent f-SAEM kernel, BAYES learns a full population proposal
covariance during burn-in, and BAYES uses Laplace ETA proposals only for
multivariate ETAs (one-ETA models retain the cheaper random walk). The explicit
selectors make it possible
to benchmark each algorithm at the same iteration budget; for stochastic
methods, effective samples per second and estimate stability should accompany
raw elapsed time.

Available scenarios are `iv-bolus`, `oral`, `two-compartment`,
`three-compartment`, `full-omega`, `infusion-steady-state`, `iov`, `advan6`,
`advan13`, `advan16-radau`, `advan17-radau`, and `advan18-dde`. Use
`--engines=LIBERATION` for the current IOV case. When the installed NONMEM
licence lacks RADAR5NM, the ADVAN16/17 scenarios use the same equation under
licensed NONMEM ADVAN18 and label the result as an equivalent-numerics rather
than direct-ADVAN comparison.

PsN's `execute` command and LibeRation must be available to the R process.
Selecting NLMIXR2 additionally requires `nlmixr2`, `nlmixr2est`, and `rxode2`.
The script also recognises the external development cache selected by
`LIBER_DEV_CACHE` (by default, the sibling directory `LibeR-dev-cache`).

## Outputs

Each result directory contains:

- `REPORT.md`: concise cross-engine timing report and interpretation limits.
- `raw-results.csv`: every warm-up and measured result, timing phase, status,
  estimates, convergence result, simulation checksum, payload sizes, and peak
  R-heap use.
- `summary.csv`: median/minimum/maximum measurements by engine and workload.
- `paired-timing-comparison.csv`: NONMEM/LibeRation timing ratios.
- `engine-timing-comparison.csv`: NONMEM-to-comparator ratios for LibeRation
  and nlmixr2.
- `timing-comparison.png` and `timing-comparison.svg`: grouped end-to-end and
  core timing charts.
- `parameter-estimates.csv`: median estimates by method and engine.
- `parameter-comparison.csv`: paired estimates and relative differences for a
  numerical sanity check.
- `metadata.rds`: exact profile, versions, paths, and host information.
- Per-run control/configuration files, logs, listings, tables, and serialized
  results for audit and failure diagnosis.

Use end-to-end wall time as the primary operational comparison. Very small
NONMEM core times may be rounded by its listing, so the `standard` profile is
preferred for stable core ratios.

## Subject-data layout benchmark

`subject-data-layout.R` compares the former copied list of per-subject event
frames with the native canonical-table row-view representation. It reports
incremental subject-storage bytes, split/store construction time, complete FO
context initialization time, minimal-projection counts, and any unexpected
subject-frame materializations while retaining identical tape construction:

```powershell
Rscript validation/benchmark/subject-data-layout.R `
  --subjects=2000 --context-subjects=500 --records=8
```

The canonical dataset itself is excluded from the incremental-storage comparison
because both layouts already retain the canonical normalized dataset in the
fit context.

`subject-native-calculations.R` separately compares the native, batched
by-reference MU and observation-count kernels with the retained R
projection/evaluation references:

```powershell
Rscript validation/benchmark/subject-native-calculations.R `
  --subjects=500 --records=8 --repetitions=20
```
