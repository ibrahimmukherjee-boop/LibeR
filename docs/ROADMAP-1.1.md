# LibeR 1.1 clinical-pharmacology workflow roadmap

Status: planned
Roadmap baseline: 2026-07-26
Depends on: completion of the [LibeR 1.0 release roadmap](ROADMAP-1.0.md)

## Scope

Version 1.1 will extend the population-modelling ecosystem with the
clinical-pharmacology workflows that are deliberately outside the 1.0 scope:

1. **Noncompartmental analysis (NCA)**
   - linear, linear-up/log-down, and configurable trapezoidal integration;
   - auditable terminal-phase selection and sensitivity analysis;
   - AUC, partial AUC, AUMC, MRT, Cmax, Tmax, terminal half-life, clearance,
     volume, accumulation, fluctuation, and dose-normalized exposure;
   - single-dose, multiple-dose, steady-state, urine, and sparse/composite
     sampling workflows where statistically defensible; and
   - independent validation against an established NCA implementation.

2. **Bioavailability and bioequivalence (BA/BE)**
   - conventional average bioequivalence;
   - parallel, crossover, and replicate designs;
   - reference-scaled average bioequivalence where applicable;
   - food-effect and relative/absolute bioavailability analyses;
   - multiplicity, missing-period, sequence, period, and carryover handling;
   - auditable statistical models, diagnostics, and report tables; and
   - jurisdiction-specific rules treated as versioned policy profiles rather
     than hard-coded universal assumptions.

3. **Dose proportionality**
   - power-model estimation and confidence intervals;
   - ANOVA and pairwise dose-normalized exposure summaries;
   - prespecified proportionality bounds;
   - covariate-adjusted and repeated-dose options; and
   - integrated graphical and report outputs.

## Release conditions

- Public APIs and analysis contracts are serializable and versioned.
- Every result retains input-data, method, option, package, and environment
  provenance.
- Numerical and statistical results are externally validated on canonical and
  real-world fixtures.
- GUI workflows are non-blocking, keyboard accessible, and available through
  the same project/version/report architecture as LibeRation.
- The functionality remains research/teaching software unless separately
  qualified for a stated regulatory or clinical intended use.
