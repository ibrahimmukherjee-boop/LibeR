# Clean-room Radau implementation and speed benchmark — 6 August 2026

## Outcome

LibeRation now has an independently written three-stage Radau IIA order-five
delay solver for ADVAN16 and ADVAN17 only. ADVAN18 and the general DDE engine
continue to use the existing RK4 method-of-steps path. No NONMEM, RADAR5, or
other vendor source was inspected, copied, translated, linked, or used as an
implementation reference; the derivation and compatibility boundary are
recorded in [CLEAN-ROOM-RADAU-DDE.md](CLEAN-ROOM-RADAU-DDE.md).

The implementation includes coupled simplified-Newton stages, an independently
derived embedded order-three error estimator, collocation-polynomial delay
history, delayed-discontinuity mesh insertion, differentiable CppAD replay,
recorded pivot order, and recording-time convergence certification. The
reported propagation kernels make the scope auditable:

- ADVAN16: `dde-advan16-radau-iia5-collocation`
- ADVAN17: `ddae-advan17-radau-iia5-collocation`
- ADVAN18: `dde-advan18-rk4-method-of-steps`

## Numerical evidence

The focused ADVAN and experimental-family test suites pass. At three hours in
the canonical delay fixtures, the maximum absolute differences between CppAD
sensitivities and central finite differences were `1.30e-5` for ADVAN16 and
`1.82e-4` for ADVAN17.

The final local NONMEM campaign is stored under
`validation/nonmem/results/20260806T212302` (raw result directories are not
versioned).
Direct prediction comparisons passed for ADVAN1–15 and ADVAN18. The maximum
absolute ADVAN18 prediction difference was `2.04e-8`. The installed NONMEM
licence does not include the optional RADAR5NM runtime, so direct ADVAN16/17
runs are correctly recorded as **not run**. Equation-matched NONMEM ADVAN18
comparators passed for ADVAN16 and ADVAN17 with maximum differences of
`4.61e-9`; these are equivalent-equation checks, not direct ADVAN matches.

## Repeated standard benchmark

The primary timing run used 100 subjects, 800 input records, 100 simulation
replicates, covariance where applicable, one unmeasured warm-up, and three
measured fresh-process repetitions. Both engines were restricted to one core.
End-to-end time includes process startup, package or NMTRAN/compilation setup,
the run, output creation, and process exit. Core time is the engine-reported
fit/covariance or simulation interval. Values below are medians in seconds; an
NM/LibeR ratio above one favours LibeRation.

| Workflow | Mapping | NONMEM E2E | LibeRation E2E | E2E NM/LibeR | NONMEM core | LibeRation core | Core NM/LibeR |
|---|---:|---:|---:|---:|---:|---:|---:|
| FO | direct | 4.47 | 0.72 | 6.21 | 0.250 | 0.400 | 0.63 |
| FOCE | direct | 4.52 | 0.69 | 6.55 | 0.641 | 0.360 | 1.78 |
| FOCEI | direct | 4.51 | 0.67 | 6.73 | 0.734 | 0.350 | 2.10 |
| Laplace | direct | 4.52 | 0.73 | 6.19 | 1.047 | 0.400 | 2.62 |
| ITS | aligned controls | 9.55 | 0.64 | 14.92 | 5.703 | 0.320 | 17.82 |
| IMP | aligned controls | 72.20 | 1.74 | 41.49 | 68.250 | 1.420 | 48.06 |
| SAEM | aligned controls | 6.53 | 4.09 | 1.60 | 3.156 | 3.780 | 0.83 |
| Simulation | direct | 6.91 | 1.08 | 6.40 | 3.141 | 0.770 | 4.08 |

The direct deterministic estimates were close: the largest relative THETA
difference was `0.036%`, and the largest relative difference across THETA,
OMEGA, and SIGMA was `0.615%` (FOCEI SIGMA). ITS, IMP, and SAEM controls are
only approximately aligned and their estimates differ more; their timing rows
must not be interpreted as proof of estimator equivalence. Full output,
min/max timings, parameter comparisons, and provenance are in the local report
`validation/benchmark/results/20260806-radau-standard-iv-bolus-release/REPORT.md`.

## Delay-family benchmark

The delay-family run used the quick profile: 20 subjects, 160 records, 25
simulation replicates, FO without covariance, one measured fresh-process run,
and no warm-up. ADVAN16/17 are compared with the same equations executed by
licensed NONMEM ADVAN18 because RADAR5NM is unavailable. These rows therefore
measure practical equation-matched workload, not direct RADAR5-versus-Radau
implementation speed.

| LibeRation path | Comparison | NONMEM E2E fit | LibeR E2E fit | NONMEM E2E sim | LibeR E2E sim |
|---|---|---:|---:|---:|---:|
| ADVAN16 Radau | equivalent NONMEM ADVAN18 | 4.33 | 15.83 | 5.39 | 7.57 |
| ADVAN17 Radau + algebraic solve | equivalent NONMEM ADVAN18 | 4.31 | 30.11 | 5.41 | 70.57 |
| ADVAN18 RK4 | direct NONMEM ADVAN18 | 4.34 | 1.33 | 5.39 | 2.17 |

The corresponding LibeRation/NONMEM core-time disadvantages were about `21.5×`
for ADVAN16 FO, `42.3×` for ADVAN17 FO, and `1.42×` for ADVAN18 FO. ADVAN17
simulation is the clearest remaining hotspot because every collocation RHS
evaluation currently performs a nested differentiable algebraic root solve.
Raw local reports are available under
`validation/benchmark/results/20260806-radau-quick-advan16`,
`validation/benchmark/results/20260806-radau-quick-advan17`, and
`validation/benchmark/results/20260806-radau-quick-advan18`.

Two implementation refinements made during profiling were material. On the
same 8-subject ADVAN16 smoke fixture, end-to-end FO time fell from `20.64 s` to
`6.44 s` after freezing/reusing the simplified-Newton Jacobian. ADVAN17 fell
from `103.82 s` to `23.49 s` after algebraic convergence and pivot decisions
were removed from CppAD replay paths. These single-run diagnostic differences
show the direction and magnitude of the engineering improvement, but the quick
profile above is the final cross-engine result.

## Breadth matrix and limitations found

An 8-subject smoke matrix exercised oral, two- and three-compartment,
correlated-OMEGA, steady-state infusion, IOV, ADVAN6, and ADVAN13 cases across
FO, FOCE, FOCEI, and Laplace. It deliberately retained exact-gradient mode;
finite-difference substitution was not enabled.

| Scenario | LibeRation estimator result | LibeR E2E range | NONMEM E2E range | Interpretation |
|---|---|---:|---:|---|
| Oral | 4/4 succeeded | 0.37–0.40 s | 3.50–3.55 s | Healthy smoke result |
| Two compartment | 4/4 succeeded | 0.38–0.49 s | 3.50–4.58 s | Healthy smoke result |
| Full OMEGA | 4/4 succeeded | 0.37–0.42 s | 3.45–4.56 s | Healthy smoke result |
| Steady-state infusion | 4/4 succeeded | 0.38–0.42 s | 13.81–18.91 s | Healthy smoke result |
| IOV | 4/4 succeeded | 0.39–0.41 s | not mapped | LibeRation-native fixture |
| Three compartment | FO succeeded; FOCE/FOCEI/Laplace failed | 0.58 s | 3.46–3.53 s | Non-finite exact population gradient |
| ADVAN6 | FO/Laplace succeeded; FOCE/FOCEI failed | 32.30–322.14 s | 3.64–4.60 s | Severe adaptive-path retaping |
| ADVAN13 | FO/Laplace succeeded; FOCE/FOCEI failed | 45.22–542.06 s | 3.58–3.68 s | Severe adaptive-path retaping |

The complete local matrix is in
`validation/benchmark/results/20260806-radau-broad-smoke`.
The ADVAN6/13 and three-compartment findings are pre-existing objective/tape
limitations exposed by the wider benchmark, not regressions in the new
ADVAN16/17 kernel. They are now concrete optimization and correctness targets:
stabilize exact conditional gradients, replace adaptive ODE branch replay with
accepted-mesh recording, and reduce retaping before publishing broad
deterministic performance claims.

## Overall interpretation

The clean-room Radau implementation is numerically sound in its tested scope,
differentiable, auditable, and restricted to the same ADVAN families for which
NONMEM selects RADAR5. It materially improves stiff-delay robustness relative
to treating ADVAN16/17 as generic RK4 DDEs, but it is not yet speed competitive
with the equation-matched NONMEM ADVAN18 comparator—especially for ADVAN17.
The ordinary analytical PK path remains very competitive end to end; FO core,
SAEM core, ADVAN16/17, and adaptive ADVAN6/13 are the principal performance
priorities revealed by this campaign.
