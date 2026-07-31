# AED model individual-fit audit — 2026-07-30

## Scope

This bounded computational audit exercised every one of the 19 AEDapt-derived
LibeRary model artifacts through LibeRator's individual-fit and prediction
path. Synthetic, model-consistent concentration evidence and the required
covariates were supplied. Each check required optimizer convergence, finite
ETA estimates, finite individual predictions, and a finite post-dose profile
where the published model structure supports one.

This is a **software-integration audit**, not source verification, external
validation, clinical qualification, or evidence that a model is suitable for
a particular patient.

## Results

| Family | Catalogue models checked | Result |
|---|---:|---|
| Carbamazepine | Delgado; Jiao | Pass |
| Clobazam | Lamba; Saruwatari | Pass |
| Clonazepam | Yukawa | Pass as steady-state-mean-only |
| Lamotrigine | He; Rivas | Pass |
| Levetiracetam | Toublanc | Pass |
| Lorazepam | Gonzalez | Pass |
| Oxcarbazepine | Park | Pass |
| Phenobarbital | Goto | Pass |
| Phenytoin | Odani; Yukawa | Pass, including ADVAN13 execution |
| Topiramate | Girgis; Jovanovic | Pass |
| Valproate | Blanco adult; Blanco paediatric | Pass |
| Zonisamide | Hashimoto; Okada | Pass, including ADVAN13 execution |

All 19 model artifacts returned converged, finite individual fits in the
bounded scenarios.

## Important interpretation findings

- The Rivas lamotrigine model is not computationally flat. In the reproducible
  70 kg, 100 mg every 12 hours steady-state check with a 5 mg/L TDM result, the
  fitted ETA was -0.12834 and the 15-minute profile ranged from 4.4293 to
  5.1480 mg/L. Its time-weighted peak-to-trough fluctuation was 14.9%, which is
  visually shallow because lamotrigine elimination is slow relative to a
  12-hour interval.
- The Yukawa clonazepam artifact is structurally different: its published
  `$PRED` relationship calculates average steady-state concentration directly
  from daily dose and clearance. It does not contain the volume or absorption
  information needed to identify a peak, trough, or transition curve.
  LibeRator must therefore present it as a steady-state-mean-only model.
- Candidate regimens must replace dose-derived covariates such as
  `DAILY_DOSE` and `DOSE_MG_KG_DAY`. Carrying their historical values into a
  new regimen silently evaluates the wrong exposure. Interaction covariates
  that describe another medication, such as `CBZ_DAILY_DOSE` in a topiramate
  model, must not be overwritten.

## Rivas regimen check

Using eight posterior draws from the fitted Rivas scenario:

| Regimen | Median mean Css | Median trough | Median peak | Endpoint attainment (3–15 mg/L mean target) | Horizon within 5% of steady state |
|---|---:|---:|---:|---:|---:|
| 100 mg every 12 h | 5.3723 | 4.9750 | 5.6941 | 100% | 100% |
| 100 mg every 24 h | 2.6862 | 2.2679 | 3.0719 | 12.5% | 12.5% |

The exact values depend on patient evidence and posterior draws. The purpose
of this check is to demonstrate why a declining transition curve must be
supplemented by an independently calculated periodic steady-state cycle.

## AEDapt parity check

The subsequently reported AEDapt comparison was locked into the automated
test suite:

- Weight: 90 kg.
- Dose: 100 mg every 12 hours, established steady state.
- TDM concentration: 12 mg/L at 12 hours after dose.
- No interacting co-medications.

LibeRator estimates ETA1 = -1.1010 and CL/F = 0.8380 L/h. The individual
steady-state curve ranges from 9.6246 to 10.1857 mg/L and has a time-weighted
mean of 9.944 mg/L. The independently generated 95% similar-patient prediction
interval ranges approximately from 1.67--2.23 mg/L at its lower boundary to
5.41--5.97 mg/L at its upper boundary over the interval. This band samples
OMEGA/ETA variability only and deliberately excludes residual measurement
error; it must not be labelled a confidence interval.
