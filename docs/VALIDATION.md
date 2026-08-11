# Validation strategy

Validation is layered so a defect cannot hide behind agreement between two
paths sharing the same implementation.

The versioned ecosystem capability declaration is installed at
`LibeRation/inst/ecosystem/support-matrix.csv` and exposed through
`LibeRation::liber_support_matrix()`. It distinguishes independently
**validated**, internally **verified**, and **experimental** capabilities.
`tools/support-matrix-check.R` is an ordinary CI gate.

Published performance results are now **correctness gated**. A timing record is
publishable only when `nm_validation_gate()` passes the declared objective,
parameter, ETA, and prediction tolerances and at least three post-warm-up timing
repetitions are present. Reports must retain `nm_benchmark_provenance()`, which
records the R/platform, package and compiled-engine versions, commit identifier,
warm-up count, and repetition count. A fast run with materially different
estimates is a failed validation, not a speed result.

1. **Closed-form unit tests**: one-compartment bolus, infusion, oral input,
   accumulation ratios, equal-rate limits, and mass balance.
2. **Backend cross-checks**: optimized ADVAN predictions against the independent
   matrix backend across randomized parameters, routes, and event schedules.
   ADVAN6/10 are checked against integrated equations, ADVAN8/13/14 against
   deliberately stiff systems, and ADVAN9 against both stiff and equilibrium
   DAE systems with known solutions.
3. **Derivative checks**: AD Jacobians/Hessians against high-accuracy finite
   differences, including nearly coincident rates and steady-state solves.
4. **NONMEM/PsN comparisons**: generated control streams run through `execute`
   and compared on predictions, objectives, gradients where exposed, estimates,
   covariance results, ETAs, and simulation summaries.
5. **Method matrix**: FO, FOCE, FOCEI, Laplace, ITS, IMP, SAEM, BAYES, mixtures,
   IOV, BLQ/censoring, and priors each receive deterministic compact fixtures.
6. **Queue parity**: the same serialized job must produce equivalent local and
   LibeRties-worker results, with package/version fingerprints recorded.

### August 2026 ADVAN and performance campaign

The 6 August 2026 Windows campaign directly passed NONMEM prediction
comparisons for ADVAN1–15 and ADVAN18, plus bolus/infusion steady state and
RATE1/RATE2 dosing. The installed NONMEM licence lacks RADAR5NM, so ADVAN16/17
are explicitly `not-run` as direct comparators; equation-matched ADVAN18 checks
passed with maximum prediction differences of `4.61e-9`. The clean-room
implementation and full timing interpretation are recorded in
[`RADAU-BENCHMARK-2026-08-06.md`](RADAU-BENCHMARK-2026-08-06.md).

A repeated 100-subject ADVAN1 benchmark (one warm-up, three measured
fresh-process repetitions) found lower median LibeRation end-to-end times for
all tested methods and simulation. A supplementary structural smoke matrix
also exposed non-finite exact gradients in selected three-compartment and ODE
conditional estimators and severe ADVAN6/13 retaping. Those failures remain
visible evidence and are not converted to passes with finite-difference
fallback.

## Independent software comparators

`validation/external-comparators/` adds a versioned registry and a portable
open-source comparison gate. It distinguishes direct compatibility references,
independent implementations, component comparators, licensed software, and
deployment verification frameworks. Missing software is recorded as
`not-run`; an unavailable comparator is never converted into a pass.

The executable portable campaign currently compares:

- the linear Gaussian state-space objective, filtered states, and filtered
  uncertainty with KFAS;
- Bernoulli and zero-inflated Poisson objectives and fitted parameters with
  glmmTMB;
- HMM objective, smoothed probabilities, and Viterbi path with hmmTMB when
  installed;
- replicated particle objectives with pomp and bssm against an exact matched
  linear-Gaussian likelihood;
- QSP reaction-network trajectories and conservation with deSolve;
- nonlinear Brusselator QSP trajectories with headless COPASI when installed;
- ADVAN14 stiff ODE, SDE, general DDE, nonlinear DAE, and QSP trajectories or moments
  with Julia SciML/Sundials when installed;
- FO, FOCE, and FOCEI population parameters and conditional modes with
  nlmixr2, including freely estimated OMEGA/SIGMA, full correlated OMEGA,
  IOV, M3/M4 BLQ likelihoods, and time-varying covariates;
- subject-level finite mixtures and normal, log-normal, half-normal, and
  inverse-gamma priors against independent analytic likelihoods; and
- MAP individual ETA estimates with mapbayr and posologyr.

The LibeRtAD backend runner now gates values, gradients, and Hessians and can
require CmdStan/Stan Math with `--require-cmdstan`. TMB remains useful
cross-frontend evidence but is not independent at the AD-library layer because
it also uses CppAD. PopED/PFIM and NONMEM retain their dedicated suites.

Run the open-source gate against the exact source tree:

```text
Rscript validation/external-comparators/install-dependencies.R
Rscript validation/external-comparators/install-dependencies.R --extended
Rscript validation/external-comparators/install-cmdstan.R
julia validation/external-comparators/install-sciml.jl
Rscript tools/create-validation-library.R --source
Rscript validation/external-comparators/run-validation.R
```

The complete registry also tracks NONMEM 7.6 RADAR5NM ADVAN16/17, Monolix, Pumas, Stan
HMMs, ASReview, document-parser comparisons, and deployment isolation.
nlmixr2, pomp/bssm, and posologyr now have executable optional gates. The
nlmixr2 gate deliberately separates its fixed-variance algorithm fixture from
advanced feature fixtures so a parameterisation mismatch cannot hide a
regression in the core estimator. OWASP ZAP
and k6 have a scheduled disposable-service harness under
`validation/liberties/deployment/`; deployment-specific saturation, restart,
TLS, and hostile-code isolation remain manual. Missing prerequisites never
become a pass.

## Estimation-method validation

`validation/estimation-methods/run-validation.R` is the release gate for every
algorithm exposed by `nm_est()`: FO, FOCE, FOCEI, Laplace, ITS, GQ, IMP, SAEM,
BAYES, HMC, NUTS, NPML, and NPAG. A returned fit is not sufficient evidence;
each method has numerical and diagnostic acceptance criteria recorded in
`validation/estimation-methods/methods.csv`.

FO, FOCE, FOCEI, and Laplace use direct matched NONMEM 7.3 controls. ITS, IMP,
and SAEM use aligned NONMEM controls and independent checks appropriate to
their finite stochastic runs. GQ is checked against adaptive base-R integration
of the one-dimensional subject likelihood. BAYES, HMC, and NUTS are checked
against an independently normalized marginal posterior, with sampler
diagnostics gated where applicable. NPML and NPAG are checked against an
independent fixed/adaptive-support EM calculation.

The 10 August 2026 Windows release-profile campaign passed every declared check
for all 13 methods. The largest direct deterministic NONMEM THETA difference
was `1.34e-4`; ITS differed by `5.10e-3`. Decision-grade 3,000-sample NONMEM
IMP differed from the independently integrated optimum by `1.90e-2`, while
LibeRation IMP differed by `3.93e-3`. LibeRation SAEM differed from the
independent optimum by `1.42e-2` and from the finite NONMEM SAEM run by
`6.33e-2`. GQ matched the exact marginal optimum within `2.39e-7`; the largest
HMC/NUTS posterior-quantile difference was `2.61e-2`. NPML support weights
agreed within `3.45e-12`, and the NPAG likelihood improvement agreed within
`5.87e-9`.

Run the portable independent-reference campaign:

```text
Rscript tools/create-validation-library.R --source
Rscript validation/estimation-methods/run-validation.R
```

Run the complete local release gate, including PsN/NONMEM:

```text
Rscript validation/estimation-methods/run-validation.R --run-nonmem
```

Without `--run-nonmem`, direct/aligned NONMEM rows remain explicitly
`not-run`, and the result is not marked complete.

The estimator-identity gate is complemented by a broader structural and
numerical fidelity matrix:

```text
Rscript validation/estimation-methods/run-fidelity-matrix.R
```

Its manifest is `validation/estimation-methods/fidelity-scenarios.csv`. The
matrix covers all 13 public estimators across correlated ETAs with covariates
and combined error, posterior geometry, multidimensional nonparametric
supports, IOV, ADVAN6 ODE execution, BLQ likelihood, compiled Markov/user
likelihood, and near-boundary parameters across the applicable compatibility
and optimized policies. It also checks hard final-mode acceptance, fixed-support NPML,
likelihood-monotone NPAG pruning, explicit Bayesian objective semantics, and
common-score SAEM replicate selection. This is an internal fidelity gate, not
a substitute for the matched external NONMEM and independent-reference rows.

## Non-PK likelihood and latent-state validation

`validation/nonpk/run-validation.R` is the evidence-producing campaign for
categorical, count, event-time, observed/hidden Markov, and Gaussian
state-space models. It does not use continuous PK predictions as a proxy for
these families.

The release gate uses independent mathematical references wherever possible:

- Bernoulli, categorical, Poisson, and negative-binomial likelihoods are
  checked against normalized base-R probabilities.
- TTE, recurrent-event, and competing-risk objectives are checked against
  independently factorized piecewise-exponential/counting-process
  likelihoods.
- Observed discrete Markov likelihoods are checked by direct transition
  factorization; two-state CTMC transitions use the analytic matrix
  exponential rather than LibeRation's matrix routine.
- HMM likelihoods, retrospective smoothing probabilities, and Viterbi paths
  are checked by exhaustive enumeration of every latent state path. CT-HMM
  likelihoods use an analytic two-state transition and an independent forward
  recursion.
- The linear Gaussian state-space objective, filtered means, variances, and
  exact AD gradient are checked against a separate scalar Kalman recursion and
  central finite differences.

For faithful overlap, generated NONMEM 7.3 `LIKELIHOOD` fixtures additionally
compare every row likelihood and the total objective for Bernoulli,
interval-TTE, and observed Markov models. There is no first-class NONMEM
reference result for LibeRation's smoothing/Viterbi, CT-HMM, particle-filter,
or nonlinear state-space outputs; those are not mislabeled as NONMEM
comparisons.

The July 2026 Windows campaign passed 25 independent deterministic comparisons
and six direct NONMEM comparisons. The largest direct NONMEM row-likelihood
difference was `2.08e-10`, and the largest total-objective difference was
`3.73e-9`. The largest exact-reference HMM probability difference was
`2.50e-16`; the Viterbi path agreed exactly.

Run the exact source-built campaign from the repository root:

```text
Rscript tools/create-validation-library.R --source
Rscript validation/nonpk/run-validation.R --run-nonmem
```

`--skip-nonmem` produces portable independent-reference evidence. Particle and
switching-state families retain verified status pending broader
simulation-calibration campaigns; computational validation is not clinical
qualification.

## Experimental numerical-family validation

`validation/experimental-families/run-validation.R` is the evidence-producing
campaign for the canonical numerical contracts underlying SDE, DDE, nonlinear
index-1 DAE, QSP reaction-network, and offline hybrid-component models. These
families have no single universal external reference engine, so the campaign
uses independently derived analytic solutions, convergence laws,
conservation/metamorphic properties, finite-difference derivatives, and seeded
Monte Carlo calibration:

- an exact Ornstein--Uhlenbeck transition and independent scalar Kalman
  recursion test SDE likelihoods, gradients, EKF/UKF equivalence, and
  fixed-step Euler/Milstein simulation moments;
- a closed-form two-interval method-of-steps solution tests a smooth-history
  linear DDE, second-order refinement, and the parameterized-delay derivative;
- ADVAN16/17 additionally exercise the clean-room Radau IIA order-five path,
  including its explicit solver-scope boundary, collocation history, and AD
  parameter/delay sensitivities; ADVAN18 remains an RK4 comparator;
- a nonlinear algebraic constraint with an analytic reduced solution tests
  index-1 DAE predictions and implicit sensitivities;
- a closed-form irreversible two-species reaction tests QSP amounts,
  parameter sensitivity, and mass conservation; and
- independent dense-network, spline, and Gaussian-process calculations test
  hybrid outputs, likelihoods, gradients, and learned dynamics.

The July 2026 Windows campaign passed all 19 comparisons. Representative
maximum absolute differences were `1.01e-3` for the finest discretized OU
objective, `1.58e-6` for its AD gradient, `4.21e-8` for the DDE trajectory,
`1.75e-4` for DDE sensitivities, `7.78e-10` for the DAE sensitivity,
`5.25e-8` for the QSP sensitivity, and `7.17e-10` for the hybrid likelihood
gradient. The seeded SDE terminal mean and variance differed from their
fixed-step theoretical moments by `2.16e-3` and `1.29e-3`, within the declared
six-standard-error calibration limits.

Run the exact source-built campaign from the repository root:

```text
Rscript tools/create-validation-library.R --source
Rscript validation/experimental-families/run-validation.R
```

The evidence claim is deliberately narrow. Delay sensitivities are validated
for continuous histories in this canonical campaign. General nonlinear or
large systems still require dimension- and application-specific evidence.

### Experimental-family edge campaign

`validation/edge-families/run-validation.R` widens the numerical envelope with
27 deliberately difficult comparisons:

- geometric Brownian motion checks exact fixed-step Euler and diagonal
  Milstein moments, while a nonlinear logistic SDE is compared with an
  independent 50,000-path Milstein implementation;
- a seeded particle SDE likelihood is checked for resolution convergence to a
  discrete scalar Kalman reference. Its AD gradient is compared on a
  fixed-ancestry path because resampling is a discrete, non-smooth operation;
- closed-form superposition checks parameterized delays crossing two separate
  bolus discontinuities, and a high-rate smooth-history DDE checks stiff
  trajectories and sensitivities;
- analytic reductions check a six-block nonlinear DAE and a coupled,
  high-rate index-1 DAE;
- exact Erlang and reversible-reaction laws check a ten-species QSP chain, a
  stiff reversible system, mass conservation, sensitivities, and compact
  parameter recovery; and
- direct calculations check stable softplus values at `-1000` and `1000`,
  ReLU branches, spline boundaries/extrapolation, an anisotropic
  Gaussian-process component, combined gradients, and rejection of a modified
  immutable component payload.

The July 2026 Windows edge campaign passed all 27 comparisons. The largest
particle-likelihood difference was `3.24e-2`; the largest nonlinear SDE
Monte Carlo moment difference was `9.76e-3`. The delayed-event DDE trajectory
and delay-sensitivity differences were `5.45e-9` and `9.19e-5`; the largest
stiff-DDE sensitivity difference was `3.88e-3`. DAE, QSP, recovery, and hybrid
deterministic differences were all below `8e-9`, apart from their declared
stochastic checks.

Run both numerical-family campaigns against one exact source build:

```text
Rscript tools/create-validation-library.R --source
Rscript validation/experimental-families/run-validation.R
Rscript validation/edge-families/run-validation.R
```

Delayed discontinuities are handled by retaining left/right history states,
splitting integration at parameterized delayed-event boundaries, and carrying
the right-limit sensitivity across observation records. Passing these fixtures
does not imply unlimited scaling: arbitrary very-large, strongly nonlinear,
application-specific, or clinical systems still require their own validation.

## LibeRality external optimal-design validation

`tools/external-validation.R` creates a version-exact isolated LibeR stack and
then independently constructs
matched population-FO designs in LibeRality, PopED 0.7.0, and PFIM 7.0.3. The
suite compares complete Fisher matrices after transforming PFIM residual-error
standard deviations to LibeRality's variance scale. It additionally compares
RSEs and log determinants, records setup, cold, warm-core, and end-to-end
runtimes, and checks that all engines select the same candidate in a matched
D-optimal grid search.

Fixtures cover one-compartment oral/proportional, IV-bolus/additive, and
oral/independent-combined designs. PFIM's `Combined1` implements
`(a + b*f)^2`, not the independent `a^2 + b^2*f^2` convention used by
LibeRality and PopED; the suite records that coverage limitation explicitly
instead of comparing non-equivalent models. Every run writes complete matrices,
CSV summaries, RDS and JSON results, and a self-contained HTML report, and
exits non-zero when a declared numerical or design-ranking tolerance fails.

The July 2026 Windows baseline passed all seven supported comparisons. Across
the suite, the largest absolute FIM element difference was `3.57e-6`, the
largest relative Frobenius difference was `3.67e-11`, and the largest RSE
difference was `3.79e-9` percentage points. LibeRality, PopED, and PFIM all
selected the `0.1 h` candidate and agreed on the D-optimal log determinant to
better than `3.1e-10`.

The first hosted Linux PopED/PFIM workflow for the 0.8.3 consolidation also
passed on 23 July 2026 and retained its matrices, comparisons, timings, and
provenance as a GitHub Actions artifact.

NONMEM tests are opt-in and skip with an explicit reason when `execute` is not
available. Test fixtures contain generated data and model code, not proprietary
NONMEM examples.

The specialized ADVAN1-4/11/12 AD transitions are additionally checked against
the retained general Pade affine propagator for complete prediction values and
every THETA/ETA/SIGMA Jacobian column. The comparison covers bolus and periodic
steady-state infusion event paths. Arbitrary matrix graphs are asserted to stay
on the general kernel. Prediction-tape metadata exposes the selected kernel and
optimized operation count so a dispatch regression cannot silently pass only
on numerical equivalence.

## Current NONMEM 7.3 prediction benchmark

`validation/nonmem/run-validation.R` executes independent generated fixtures
through PsN and compares observation-record `IPRED` values with LibeRation.
The July 2026 Windows benchmark produced:

| Fixture | Maximum absolute difference | Compared records |
|---|---:|---:|
| ADVAN1 | 1.43683332e-9 | 6 |
| ADVAN2 | 2.99838998e-9 | 6 |
| ADVAN3 | 4.42779680e-9 | 6 |
| ADVAN4 | 1.09334830e-9 | 6 |
| ADVAN5 | 3.16553717e-9 | 6 |
| ADVAN6 | 3.30286110e-9 | 6 |
| ADVAN7 | 3.16553717e-9 | 6 |
| ADVAN8 | 1.38853029e-9 | 6 |
| ADVAN9 (stiff, no equilibrium compartment) | 1.38853029e-9 | 6 |
| ADVAN9 (equilibrium compartment) | 9.34286026e-9 | 6 |
| ADVAN10 | 5.07415976e-9 | 6 |
| ADVAN11 | 4.55660842e-9 | 6 |
| ADVAN12 | 1.91085725e-9 | 6 |
| ADVAN13 | 7.83511256e-10 | 6 |
| ADVAN14 | 1.38853029e-9 | 6 |
| ADVAN15 (equilibrium DAE) | 3.13036250e-8 | 10 |
| ADVAN16-equivalent dynamics (NONMEM ADVAN18 reference) | 2.04385033e-8 | 14 |
| ADVAN17-equivalent delayed equilibrium (NONMEM ADVAN18 reference) | 5.24029886e-9 | 14 |
| ADVAN18 | 2.04385033e-8 | 14 |
| ADVAN1 repeated bolus steady state | 3.46666562e-9 | 4 |
| ADVAN1 intermittent-infusion steady state | 3.99814670e-9 | 6 |
| ADVAN1 modelled rate (`RATE=-1`, `R1`) | 4.35503544e-9 | 6 |
| ADVAN1 modelled duration (`RATE=-2`, `D1`) | 4.35503544e-9 | 6 |

The August 2026 campaign used NONMEM 7.6 and directly passed ADVAN1-15 and
ADVAN18. ADVAN16 and ADVAN17 share NONMEM's separately licensed RADAR5NM
runtime; the installed licence reaches the runtime but explicitly rejects both
routines before model evaluation. The runner records both direct cases as
`not-run` and therefore keeps `complete = false`. It separately validates their
delay equations against NONMEM's independent ADVAN18 DDE solver; ADVAN17's
equilibrium component is also exercised directly by ADVAN15. These equivalent
checks are supporting numerical evidence, not substitutes for a future direct
RADAR5NM comparison.

The compact FOCEI benchmark estimates clearance with fixed residual and random
effect variances, then compares the final fixed effect, every subject ETA, and
the covariance-step standard error. Against NONMEM, the current compact benchmark
gave absolute differences of `1.33651e-4` for THETA1, `6.07381e-5` for ETA1,
and `3.04130e-3` for the THETA1 standard error.

Create the exact isolated stack and run the benchmark from the repository root:

```text
Rscript tools/create-validation-library.R --source
Rscript validation/nonmem/run-validation.R --run
```

Without `--run`, existing NONMEM tables are reused. The runner still checks
record alignment and numerical tolerances, and it fails if PsN reports success
without producing a NONMEM listing and the expected table.

LibeRator has a separate deterministic analytic virtual-patient runner at
`validation/liberator/run-validation.R`. LibeRary's strict corpus gate is
documented in `validation/liberary/README.md`; machine-generated Tier C/D data
can support development but cannot qualify a release as gold-standard evidence.
