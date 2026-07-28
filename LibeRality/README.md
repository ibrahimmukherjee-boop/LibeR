# LibeRality

LibeRality is the optimal-design package in the LibeR ecosystem. It evaluates,
optimises, simulates, and reports model-informed clinical trial designs using
the same NONMEM-compatible model objects and C++ prediction engine as
LibeRation.

The package is intended for research and teaching. Its outputs support design
decisions; they do not replace protocol, statistical, ethics, regulatory, or
clinical review.

LibeRality is distributed as part of the LibeR 0.9 research beta. Use the
[ecosystem installer](../docs/INSTALL.md) and inspect
`LibeRation::liber_support_matrix("LibeRality")` to see which design paths have
matched PopED/PFIM and which currently have internal verification only.

## What it covers

- Exact LibeRation/CppAD prediction sensitivities and native Eigen information
  matrix assembly.
- Continuous, binary, ordinal, count, recurrent-event, and time-to-event
  endpoints, including multi-endpoint designs.
- Population strata, covariate distributions, parameter/model uncertainty,
  dropout, adherence, and missed-sample scenarios.
- D-, A-, E-, Ds-, c-, L-, RSE-, and prediction-optimality.
- Bayesian/robust, minimax/maximin, model-average, precision-probability,
  T- and KL-discrimination, power, superiority, non-inferiority, target
  attainment, correct-dose selection, expected utility, cost, and burden.
- Compound criteria, explicit constraints, and unscalarised Pareto frontiers.
- Continuous, integer, discrete, categorical, allocation, coordinate-exchange,
  particle-swarm, Fedorov-Wynn, multiplicative, and hybrid optimisation.
- Empirical complete-trial simulation, optional LibeRation re-estimation,
  operating characteristics, HTML reports, and typed LibeRties jobs.
- A unified model browser for curated templates, LibeRation model versions or
  completed fitted runs, reviewed LibeRary entries, and NONMEM control streams.
  Full models are loaded only when previewed, and selected copies retain source
  and parameter provenance.
- Executable external validation of complete population-FO Fisher matrices,
  RSEs, D-optimal rankings, and cold/warm runtimes against PopED and PFIM.
- A responsive React workbench with light/dark themes and an amber LibeR dove.

## Quick start

```r
library(LibeRality)

example <- lity_example()
design <- example$design

evaluation <- lity_evaluate(design, list(
  precision = lity_criterion_D(),
  robustness = lity_criterion_robust(lity_criterion_D()),
  worst_rse = lity_criterion_rse(summary = "max"),
  cost = lity_criterion_cost()
))

optimised <- lity_optimise(
  design,
  lity_criterion_compound(
    list(information = lity_criterion_D(), cost = lity_criterion_cost()),
    weights = c(0.8, 0.2),
    reference = c(1, 100000)
  ),
  method = "hybrid"
)

simulation <- lity_simulate_trials(optimised$design, n = 100)
liberality_gui(optimised$design)
```

The final event template can be returned directly to LibeRation with
`lity_to_liberation()`. When LibeRties is installed, `lity_job()` creates a
typed `optimal_design` job for a local or remote queue.

## Design objects

A design is deliberately serialisable. It contains the model, elementary arm
schedules, endpoint definitions, population strata, uncertainty scenarios,
optimisable variables, constraints, optional prior information, and provenance.
Compiled pointers are rebuilt by LibeRation in the process or worker that needs
them.

Use `lity_validate()` before a long run and retain the returned design,
criterion, seed, numerical diagnostics, and package versions with every design
decision.

## External validation

The versioned validation suite in `validation/liberality/external` installs
PopED and PFIM into an isolated repository library, evaluates matched oral and
IV population-PK designs, harmonises residual standard-deviation and variance
parameterisations, and compares the complete Fisher matrices. Run it from the
ecosystem repository root with:

```powershell
Rscript validation/liberality/external/install-dependencies.R
Rscript validation/liberality/external/run-validation.R --repetitions=10
```

The run writes machine-readable matrices, comparison and timing tables, an RDS
result, a JSON manifest, and a self-contained HTML report. PFIM 7.0.3's
`Combined1` convention is not mathematically equivalent to independent
additive-plus-proportional error, so that fixture is explicitly covered by
LibeRality and PopED only.

## AI-assisted development

GPT-5.6 was used as an AI engineering collaborator to help implement and review
the design criteria, optimisation workflows, GUI, tests, documentation, and PopED/PFIM validation harness.
Scientific direction, architecture, validation criteria, and release decisions remain the responsibility of the project owner.
