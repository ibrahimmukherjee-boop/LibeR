# LibeR numerical-engine optimisation review

Date: 2026-08-07

## Policy boundary

`nonmem_compatibility` remains the default for matched NONMEM validation and
keeps the conservative numerical choices and reference orchestration.
`liber_optimized` is an explicit opt-in policy for accelerations that have a
paired equivalence test. Exact implementation improvements that cannot change
arithmetic—such as resolving an input name once instead of parsing it at every
solver stage—are shared by both policies.

Following the compatibility audit, exact affine-map reuse, invariant
population predictions, deterministic replicate reuse, identical OMEGA
factorisations, and accepted-history DDE lag lookups are also shared. Changes
to solver trajectories, random-number order, or marginal summation remain
opt-in.

## Algorithm audit and changes

| Area | Finding | Implementation |
|---|---|---|
| LibeRtAD scalar AD | `value_gradient()` performed the zero-order forward sweep twice. | Reuse the first `Forward(0)` state directly in `Reverse(1)`. |
| ADVAN1-4/11/12 | Specialized analytical AD kernels already avoid a generic matrix exponential. Repeated double-precision intervals still rebuilt the same affine map. | Retain the specialized AD path and cache exact `(K, input, dt)` affine maps per subject in both policies. |
| ADVAN5/7 | Arbitrary linear propagation is already native Eigen matrix-exponential code. | Reuse exact repeated affine maps in both policies; no approximation or topology restriction added. |
| ADVAN6/8/9/10/13/14/15/18 | Solvers are native C++; repeated program-input parsing and DAE/DDE name searches occurred inside right-hand-side stages. | Compile THETA/ETA/SIGMA/state, algebraic-variable, and lag bindings once. This lookup-only change is shared by both policies. |
| ADVAN16/17 | Clean-room Radau IIA simplified Newton was already mode-specific; repeated accepted-history lag interpolation was also identified. | Share only the arithmetic-neutral lag lookup cache. Retain the conservative compatibility Newton path and the validated optimized Radau path described in the 2026-08-06 review. |
| Simulation | R recomputed identical OMEGA roots and population predictions, repeated deterministic runs, and crossed into C++ for every prediction replicate. | Both policies cache invariant roots/PRED and reuse deterministic output. Optimized mode additionally batches random-effect replicates and generates ordinary AR(1) residual streams natively. |
| FO/FOCE/FOCEI/Laplace | The population objective, ETA modes, gradients, curvature, and determinant terms already use compiled C++/CppAD collections. FO still factored an observation-sized marginal covariance and exposed one population-tape output per subject. | Both policies use an ETA-dimensional determinant-lemma/Woodbury solve for eligible independent residual covariance and a scalar population tape. Conditioning and dense-equivalence guards automatically retain the dense route when required. Conditional estimators retain their established native objective. |
| ITS | Conditional subject modes and gradients already use batched native kernels. | No arithmetic change; it benefits from compile-once bindings and AD improvements. |
| IMP/GQ | Proposal preparation and marginal integration crossed R/C++ once per subject. | Batch eligible ETA modes and all fixed-proposal subject integrations in one C++ call in optimized serial runs. Signed sparse-grid cancellation and gradients retain the original formula. |
| SAEM/BAYES | Subject Metropolis evaluation is already batched, but identical OMEGA roots were repeatedly factorized and R's SAEM optimizer requested value and gradient through separate tape sweeps. | Reuse identical covariance roots, pair fixed-ETA value/gradient evaluation, retain fixed ETAs/tapes/buffers across R optimizer callbacks, and use native OMEGA/SIGMA sufficient statistics in both policies. Optimized eligible models can additionally use the native M-step. Population-prior, RNG, and proposal semantics remain unchanged. |
| HMC/NUTS | Leapfrog/tree construction and joint gradients are already native C++. | No migration; R remains the run-level coordinator and result formatter. |
| NPML/NPAG | Every subject/support grid evaluation crossed the R/C++ boundary and the EM responsibility loop ran in R. | Evaluate the complete tape grid in one native call and use a native EM kernel in optimized serial runs. |

The remaining R code is primarily validation, model/run orchestration,
optimizer policy, parallel/remote lifecycle, result construction, and methods
whose work is already delegated to a compiled population kernel. Moving those
parts wholesale to C++ would mostly duplicate policy and serialization logic,
increase maintenance risk, and provide little core-time benefit. The next
material scalability project remains structural tape sharing across subjects;
it is larger than a loop translation because dynamic event and observation
data must be separated from structural tape identity.

## Focused measurements

Measurements used the installed development build on the local AMD Ryzen 7
3700X machine, 100 synthetic theophylline subjects, one process, warm paths,
three counterbalanced repetitions, and fixed population parameters so the
kernel comparison is not obscured by different optimizer trajectories.

| End-to-end case | Compatibility | LibeR optimized | Speed-up |
|---|---:|---:|---:|
| Deterministic simulation, 100 replicates | 0.47 s | 0.11 s | 4.27x |
| Random-effect prediction, 50 replicates | 0.24 s | 0.21 s | 1.14x |
| IMP, 50 samples | 0.49 s | 0.47 s | 1.04x |
| GQ, order 3 | 0.47 s | 0.46 s | 1.02x |
| NPML, 25 supports | 0.51 s | 0.43 s | 1.19x |

FOCEI, SAEM, and BAYES were effectively unchanged in this deliberately short
end-to-end case (0.96-1.00x), as expected: they already use native population
kernels and startup/tape construction dominates at this scale. Focused warm
kernel measurements showed 1.47x for batched IMP value/gradient evaluation,
1.14x for the native NP support grid, 2.22x for the native nonparametric EM
loop, and 1.98x for LibeRtAD combined scalar value/gradient evaluation.

These are development measurements, not replacements for the matched NONMEM
validation matrix. Performance claims should be rerun on release binaries and
larger representative studies before being used externally.

## Full matched benchmark after safe compatibility promotion

The final benchmark used the standard one-compartment IV-bolus profile: 100
subjects, 800 records, all eight matched estimation methods, covariance where
supported, 100 simulation replicates, one warm-up, and three measured fresh
processes. NONMEM and both LibeRation numerical policies used the same controls
and one core. All 108 process runs completed successfully.

| Workload | NONMEM E2E | Compatibility E2E | Optimized E2E | NONMEM core | Compatibility core | Optimized core |
|---|---:|---:|---:|---:|---:|---:|
| FO | 4.55 s | 0.80 s | 0.78 s | 0.266 s | 0.47 s | 0.45 s |
| FOCE | 4.54 s | 0.75 s | 0.73 s | 0.578 s | 0.42 s | 0.40 s |
| FOCEI | 4.54 s | 0.72 s | 0.69 s | 0.875 s | 0.41 s | 0.38 s |
| Laplace | 5.57 s | 0.78 s | 0.75 s | 1.656 s | 0.45 s | 0.43 s |
| ITS | 11.62 s | 0.66 s | 0.62 s | 7.766 s | 0.33 s | 0.31 s |
| IMP | 71.24 s | 1.75 s | 1.47 s | 67.312 s | 1.44 s | 1.14 s |
| SAEM | 6.60 s | 4.75 s | 4.67 s | 3.219 s | 4.43 s | 4.35 s |
| BAYES | 24.75 s | 12.67 s | 12.45 s | 20.953 s | 12.35 s | 12.13 s |
| Simulation | 6.92 s | 0.93 s | 0.70 s | 3.125 s | 0.61 s | 0.40 s |

The shared compatibility-safe changes reduced the comparable simulation median
from the previous 1.08 s end-to-end / 0.77 s core reference to 0.93 s / 0.61 s.
The remaining optimized-policy advantage is largest for simulation (1.33x
end-to-end, 1.53x core) and IMP (1.19x, 1.26x), where RNG-sensitive batching
and marginal aggregation deliberately remain opt-in. The policies produced
identical median objectives and estimates for every method except IMP, whose
native aggregation differed by only `2.40e-8` in objective and less than
`6.4e-10` in any reported parameter.

Auditable output is stored in
`validation/benchmark/results/20260807-shared-safe-standard-compat` and
`validation/benchmark/results/20260807-shared-safe-standard-optimized`.

## Equivalence gate

Automated tests compare the two policies for seeded random-effect and residual
simulation, analytical/ODE ADVAN behavior, importance values and native
gradients, NP support likelihoods and gradients, EM weights/responsibilities,
and fixed-model objectives for FO, FOCE, FOCEI, Laplace, ITS, IMP, GQ, SAEM,
BAYES, NPML, and NPAG. HMC/NUTS retain their existing common native sampler
and validation suite because no mode-specific code was introduced there.

## Native SAEM M-step follow-up

Profiling the standard 100-subject SAEM workload attributed 2.55 seconds of a
4.59-second warm run to 1,847 R-coordinated objective calls and 1,847 separate
gradient calls. The optimized serial analytical path now keeps the complete
fixed-ETA M-step in C++: each trial point evaluates value and exact CppAD
gradient in one subject sweep, and bounded BFGS plus line search no longer call
back into R. Simple residual-error and OMEGA sufficient statistics are also
computed natively. Compatibility mode, adaptive ODE retaping, PSOCK workers,
active MU specialization, and explicitly requested R optimization retain the
established implementation.

Five fresh-process repetitions of the matched standard SAEM workload gave:

| Policy | Median end-to-end | Median core | M-step objective backend |
|---|---:|---:|---|
| NONMEM compatibility | 5.28 s | 4.93 s | R-coordinated population objective |
| LibeR optimized | 4.14 s | 3.78 s | Native fixed-ETA population objective |

This is a 1.30x core and 1.28x end-to-end speed-up (23.3% and 21.6% less time,
respectively). The optimized stochastic trajectory finished at a 2.64-unit
lower objective; relative changes in THETA1, THETA2, OMEGA1, and SIGMA1 were
0.33%, 0.005%, 0.39%, and 0.03%. These are not asserted to be bitwise-equivalent
paths: the native BFGS trial sequence changes subsequent seeded Metropolis
states. Tests instead require exact native-versus-R value/gradient agreement at
the same fixed ETAs, sufficient-statistic agreement, finite estimator results,
and explicit path/fallback telemetry.

## Clean-room FO implementation from the public formulation

The public NONMEM guide defines FO as an ETA-zero linearization followed by an
extended least-squares objective with subject covariance
`C_i = G_i OMEGA G_i' + R_i`. LibeRation implements that mathematical contract
without reference to NONMEM source. Two clean-room accelerations are now
available under both policies with conservative numerical guards:

1. With independent residual errors, write `U = G chol(OMEGA)` and use the
   determinant lemma and Woodbury identity. The factorization becomes
   `I + U' R^-1 U`, whose dimension is the number of ETAs rather than the
   number of observations. AR(1) and cross-endpoint residual structures remain
   on the dense path until structure-specific solves are separately validated.
2. Record the fused population sum as one dependent variable and obtain its
   gradient with `Reverse(1)`. Per-subject objective values are evaluated only
   when final state is requested. Dense/vector routes remain independently
   selectable for regression and diagnosis.

The remaining longer-range FO project is to fuse prediction and ETA-sensitivity
propagation in specialized ADVAN kernels. The existing structural tape pool
already shares tapes across compatible subject layouts; further gains require
careful dynamic event-design separation rather than another R-loop rewrite.

These conclusions come from the published objective and observable timing
behavior, not from NONMEM source code. The implemented paths have isolated
dense-versus-low-rank value/gradient, scalar-versus-vector population tape,
policy-isolation, IOV, residual-covariance fallback, and estimator regression
gates. Their compatibility promotion retains those gates plus conditioning,
dense-equivalence, fallback-reason, and fallback-count telemetry.

### Focused FO and SAEM measurements

On the local Ryzen 7 3700X, a 100-subject ADVAN2/theophylline case gave the
following warm measurements. In compatibility mode, one hundred fresh FO
value-plus-gradient points took 0.50 seconds with dense covariance/vector
outputs and 0.10 seconds with guarded low-rank covariance/scalar output.
Fused tape operations fell from 62,582 to 34,851. Four-run end-to-end FO
fitting medians were 0.72 and 0.55 seconds respectively, with the same reported
objective (`1294.306`) and all 100 subjects passing the low-rank guards.

For 100-iteration compatibility-mode SAEM, separate value/gradient callbacks
and R sufficient statistics took a 4.80-second median. Native sufficient
statistics alone reduced this to 4.62 seconds; paired value/gradient evaluation
alone reduced it to 3.38 seconds; together they took 3.22 seconds. All four
runs used the same seed and reported the same final objective (`207.0171`). A
subsequent matched ablation retained the fixed-ETA tapes, ETAs, and point
buffers across R optimizer callbacks: the median fell from 3.39 to 2.31
seconds (31.9% less time), again with objective `207.0171` and no fallbacks.

An R-level profile of the persistent route attributes the largest remaining
shares to native fixed-ETA tape replay, the already-native subject Metropolis
kernel, and construction/factorization of changing OMEGA state. The remaining
R-side cost is distributed across parameter decoding, prior/map handling, and
run orchestration; no additional loop migration is justified without a
targeted native-profile and a matched stochastic-trajectory gate. These are
development/ablation timings rather than replacements for the full
matched-control NONMEM benchmark.

A final 20-subject matched-control external smoke run also completed for FO
and SAEM. FO estimates agreed with NONMEM within 0.00023% for every reported
population parameter. SAEM completed in both engines but, as expected for
different stochastic update algorithms and random-number streams, is treated
as a matched-control runtime/sanity comparison rather than an estimate-by-
estimate equivalence assertion.

### Focused covariance-inclusive FO and SAEM benchmark

The updated focused benchmark used the standard 100-subject/800-record
IV-bolus case, one core, one warm-up, and three measured fresh processes.
Covariance was requested for both estimators. LibeRation core timing now
excludes initial context/tape construction and includes fit plus covariance;
end-to-end wall timing is unchanged.

| Method | Engine / policy | End-to-end | Core fit + covariance |
|---|---|---:|---:|
| FO | NONMEM | 4.67 s | 0.281 s |
| FO | LibeRation compatibility | 0.78 s | 0.110 s |
| FO | LibeRation optimized | 0.73 s | 0.110 s |
| SAEM | NONMEM | 7.70 s | 3.391 s |
| SAEM | LibeRation compatibility | 3.47 s | 2.880 s |
| SAEM | LibeRation optimized | 3.35 s | 2.770 s |

The automatic optimized SAEM route now uses the mature persistent R
L-BFGS-B coordinator. The revised native limited-memory optimizer remains an
explicit experimental choice. NONMEM did not expose separate fit/covariance
elapsed timers for these runs, so its core values use the listing's total CPU
fallback.
