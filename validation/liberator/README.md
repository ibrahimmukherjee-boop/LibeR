# LibeRator analytic validation

`run-validation.R` exercises the patient-assessment and regimen-forecast path
with a one-compartment virtual patient whose individual ETA and concentrations
are known analytically. It verifies longitudinal evidence assimilation,
individual prediction accuracy, dose-response ordering, and creation of the
explicit future-prediction artifact.

Run it from the repository root after creating an isolated validation library:

```powershell
Rscript tools/create-validation-library.R --source
Rscript validation/liberator/run-validation.R
```

Each run writes comparisons, a machine-readable summary, and exact package,
source, input, seed, tolerance, R, and platform provenance under `results/`.
The scenario is software validation for research use; it is not a clinical
dosing recommendation.

`AED-MODEL-INDIVIDUAL-FIT-AUDIT-20260730.md` records a bounded integration
audit of all 19 AEDapt-derived LibeRary models, including the distinction
between time-resolved models and a published steady-state-mean-only model.
