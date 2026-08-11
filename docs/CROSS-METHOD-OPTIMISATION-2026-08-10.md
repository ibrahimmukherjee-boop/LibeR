# Cross-method estimation architecture and benchmark

Date: 10 August 2026

## Implemented architecture

- Eligible analytical ADVAN1--4/11/12 value sweeps now fuse propagation and
  subject likelihood evaluation. Every fused subject is checked against its
  recorded CppAD tape, with automatic generic fallback and telemetry.
- Eligible optimized SAEM/BAYES jobs can partition immutable native event data
  across bounded C++ threads. R objects, RNG, retaping, and mutable `ADFun`
  instances remain on the owning thread; PSOCK remains the portable fallback.
- IMP and adaptive GQ share an execution-local conditional-state cache for
  modes, values, curvature/proposal state, and parameter anchors. Optimized
  FOCE/FOCEI/Laplace and GQ also preserve `MU + ETA` when warm-starting modes.
- Eligible optimized adaptive/fixed GQ jobs additionally keep their complete
  proposal-and-grid coordinator in C++. A fast normalized-score search is
  followed by native finite differences of the complete moving-grid objective,
  so the returned refinement remains stationary for the actual finite-grid
  estimator rather than for a frozen-node surrogate.
- BAYES, HMC, and NUTS report rank-normalized split R-hat, bulk/tail ESS, and
  mean Monte Carlo standard error. HMC/NUTS additionally retain per-transition
  energy, E-BFMI, robust initialization provenance, and three-stage warmup
  telemetry; diagonal, dense, and population/subject block metrics share the
  same native and reference Hamiltonian implementation. SAEM reports parameter/objective
  stationarity and can aggregate independently seeded replicates; automatic
  stopping remains disabled in compatibility mode and is conservatively
  enabled by default in the optimized policy.
- Eligible optimized HMC/NUTS models use exact MU-aware non-centred geometry:
  ETA is whitened through the OMEGA Cholesky factor and the transform Jacobian,
  population chain rule, and latent chain rule are included in both native and
  retained R targets. IOV, general random-effect, incomplete-MU, and
  non-positive-definite layouts retain centred geometry with a recorded reason.
- Optimized one-ETA BAYES defaults to its inexpensive OMEGA-scaled random walk;
  multivariate models retain curvature-informed Laplace proposals. Serial
  fused ADVAN evaluation is opt-in because CppAD zero-order replay is faster on
  the canonical one-core workload; native threaded jobs retain the fused path.

## Verification

Focused tests cover fused/generic equivalence, seeded stochastic trajectories,
conditional-cache reuse, MU recentering, stochastic diagnostics, SAEM
replicates/stationarity, and native-versus-reference HMC target/gradient
equivalence. The affected estimator suites completed without failures; two
PSOCK-only tests were skipped under their existing CRAN guard.

## Full matched-control benchmark

The table below was refreshed on 11 August after the final estimator-fidelity
changes. It supersedes the earlier 10 August timing table.

The standard fixture is ADVAN1/TRANS2 IV bolus with 100 subjects and 800
records. Covariance was requested where applicable. Values below are medians
of three fresh processes after one unmeasured warm-up. LibeRation core time
excludes context/tape construction; NONMEM core uses its reported estimation
plus covariance time when available. nlmixr2 does not expose an equivalent
stable internal boundary, so its core column contains the complete estimator
call.

| Method | NONMEM E2E | NONMEM core | LibeR compatibility E2E | LibeR compatibility core | LibeR optimized E2E | LibeR optimized core | nlmixr2 E2E | nlmixr2 core |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| FO | 4.540 | 0.266 | 0.670 | 0.120 | 0.670 | 0.130 | 10.940 | 8.770 |
| FOCE | 4.500 | 0.594 | 0.610 | 0.110 | 0.600 | 0.110 | 12.980 | 10.680 |
| FOCEI | 4.510 | 0.875 | 0.590 | 0.080 | 0.580 | 0.090 | 13.170 | 10.950 |
| Laplace | 5.530 | 1.625 | 0.650 | 0.150 | 0.660 | 0.160 | 13.220 | 11.050 |
| ITS | 11.590 | 7.641 | 7.250 | 6.780 | 6.830 | 6.350 | -- | -- |
| IMP | 73.250 | 69.125 | 54.430 | 53.950 | 31.930 | 31.450 | -- | -- |
| SAEM | 6.570 | 3.219 | 17.880 | 17.400 | 9.030 | 8.560 | 38.690 | 36.410 |
| BAYES | 24.810 | 21.109 | 1.440 | 0.970 | 16.450 | 15.990 | -- | -- |
| Simulation | 6.940 | 3.172 | 0.930 | 0.620 | 0.730 | 0.420 | 4.600 | 3.940 |

ITS and BAYES have no exact nlmixr2 mapping in this harness. The nlmixr2 IMP
attempt repeatedly entered singular-system repair and did not serialize a
valid result, so it is deliberately reported as unavailable rather than as
zero or as a substituted method.

The tracked, scrubbed timing tables and PNG/SVG plot are in
`docs/benchmarks/20260811-final/`. Raw engine working directories remain in the
ignored local validation-results directory and are not published.
