# ITS, IMP, and SAEM optimization implementation

Date: 10 August 2026

## Compatibility-safe changes

- A persistent weighted-ETA C++ context now owns subject objective tapes,
  dynamic inputs, parameter workspaces, ETA support, and normalized weights.
  It evaluates complete-data values and exact CppAD gradients in deterministic
  subject/support order, so the execution change does not alter the estimator.
- ITS first-order conditional covariances are calculated in one native subject
  sweep. The conditional modes, curvature formula, positive-definite guard,
  sigma point grid, and population update are unchanged.
- IMP evaluates every subject/sample objective and its normalized posterior
  weights in one native call. Dynamic observations and covariates are installed
  explicitly for every shared tape, and tape-path changes remain guarded.
- SAEM's exact Robbins--Monro empirical mixture is advanced in C++. Recursive
  first and second ETA moments provide the exact mean and OMEGA sufficient
  statistics without reconstructing historic ETA matrices in R. For simple
  Gaussian residual models, the exact complete-data gradient algebraically
  recovers the same SIGMA sufficient statistic as the former repeated
  simulation sweep.
- Phase timers and native/fallback telemetry expose normal generation,
  conditional sampling, expectation construction, stochastic approximation,
  M-step, SIGMA, and OMEGA work separately for diagnosis. Compatibility mode
  retains fixed sample/M-step schedules, random Gaussian importance draws,
  fresh conditional modes, and random-walk SAEM.
- Conditional-mode searches no longer repeat a zero-order sweep at accepted
  line-search points. Unchanged CppAD dynamic inputs are not reinstalled, and
  optimized mode searches reuse a positive-definite per-subject inverse-
  curvature state while retaining the exact gradient and convergence guards.
- Gaussian ITS no longer requests an exact conditional-objective Hessian that
  its first-order covariance formula does not consume. Defensive IMP uses the
  realised Gaussian/Student-t allocation in its deterministic-mixture density,
  including odd draw counts.
- SAEM's native weighted M-step returns its accepted full-domain gradient so
  the exact simple-residual SIGMA update does not cause a second weighted-Q
  sweep. Stochastic support matrices grow geometrically, eliminating the
  former quadratic history-copy pattern while leaving active support order and
  Robbins--Monro weights unchanged.

## LibeR-optimized changes

- ITS can progressively increase inner M-step effort and apply a safeguarded
  vector Aitken extrapolation. An extrapolated point is accepted only inside
  bounds and only when it improves the current auxiliary objective.
- ITS can use an inexact early conditional-mode tolerance schedule, returning
  geometrically to the requested tolerance and recomputing the final
  conditional distribution at that exact tolerance.
- IMP can progressively increase both sample count and M-step effort, use
  randomized shifted-Halton quasi-Monte-Carlo, antithetic, or ordinary random
  Gaussian/covariance-matched Student-t draws, assign the fixed aggregate draw
  budget toward subjects with low prior ESS, combine Gaussian and Student-t as
  a defensive 50:50 proposal, and reuse a previous conditional mode while the
  population point remains close and effective sample size remains adequate.
  Exact proposal densities and importance reweighting make stale-mode reuse a
  valid proposal optimization rather than a target approximation.
- Optimized IMP and SAEM can stop after repeated parameter/objective
  stationarity confirmation. SAEM selects the exact Metropolis-corrected
  f-SAEM independence kernel for any eligible non-zero ETA dimension.
- Optional SAEM support pruning/capping is available as an explicitly
  approximate memory/runtime control. Its defaults are zero, preserving the
  full Robbins--Monro support and the canonical auxiliary function.
- Optimized weighted-Q evaluations can be nested into one reduced-domain
  CppAD population tape whose independent variables are only THETA, SIGMA, and
  OMEGA; ETA support, weights, observations, and covariates are dynamic inputs.
  A two-million-operation guard and cross-update support-shape gate fall back
  to deterministic subject tapes. Progressive IMP does not repeatedly record
  large aggregate graphs as its sample count changes.
- Optimized SAEM continues every stochastic approximation update while
  thinning expensive numerical M-steps during burn-in and after burn-in. It
  applies standard post-burn Polyak averaging in the transformed parameter
  domain. Both features are disabled in the compatibility policy.
- Fused analytical ADVAN stochastic kernels now retain a native worker pool
  for the lifetime of the fit rather than creating and joining threads for
  every evaluation. Results are still reduced in subject order.
- Automatic optimized IMP uses antithetic draws. Randomized shifted-Halton
  quasi-Monte-Carlo remains explicitly selectable, but a standard-profile
  benchmark found that independent shifts increased both draw generation and
  MCEM optimizer work at this budget; it is therefore an accuracy option, not
  the default speed policy.
- ESS-directed subject allocation likewise remains explicit. It is useful when
  a small subset of difficult subjects dominates Monte-Carlo error, but the
  moving allocation increased outer optimizer work on the standard fixture;
  automatic optimized IMP therefore retains a fixed per-subject allocation.
- Optimized IMP can use Fisher/Gauss--Newton conditional curvature for its
  proposal, while retaining exact target/proposal reweighting. Its weighted
  population M-step now uses the same persistent native L-BFGS coordinator as
  SAEM; simple SIGMA and OMEGA blocks are then solved by exact complete-data
  sufficient-statistic updates. Compatibility mode deliberately retains exact
  proposal curvature and its established R L-BFGS-B trajectory until a
  matched-control optimizer-trajectory qualification permits otherwise.

## Fusion and boundary audit after estimator-fidelity corrections

The fidelity corrections did **not** remove persistent subject tapes, the
weighted-ETA context, batched IMP weights, native SAEM/BAYES coordinators, or
eligible fused ADVAN1--4/11/12 propagation. Two scopes changed deliberately:

- the old repeatedly optimized finite-common-random-number IMP surface is now
  the explicitly named `marginal_ml` alternative; canonical IMP defaults to
  independent-E-step MCEM, so proposal support must be refreshed between
  iterations;
- SAEM's canonical growing Robbins--Monro support changes the aggregate tape
  shape unless support is explicitly capped, so the stable-shape reduced
  population tape correctly falls back to persistent subject tapes.

Compatibility execution also continues to exclude fused/native trajectories
whose arithmetic or optimizer sequence has not yet passed a matched NONMEM
qualification. These are policy guards, not lost infrastructure. The present
pass restores arithmetic-neutral boundary reductions and adds native optimized
IMP M-step fusion without applying a trajectory-changing optimizer to the
compatibility path.

## Verification gates

Focused tests compare native and retained reference execution for weighted
complete-data objectives and gradients, SAEM recurrence weights/moments,
OMEGA and SIGMA sufficient statistics, ITS covariance, IMP posterior weights,
and the complete seeded compatibility SAEM trajectory. The existing optimized
numerics, estimation, and advanced-inference suites are also required to pass.
Benchmark outputs must report the numerical policy, resolved stochastic
kernel/proposal, sample and M-step schedules, retained support, early stopping,
and phase timing so unlike algorithms are not presented as matched runs.

## Measured results

The standard 100-subject, 800-record IV-bolus benchmark includes covariance,
uses three measured fresh-process repetitions after one warm-up, and records
both end-to-end and post-initialization core time. Median seconds were:

| Engine / policy | Method | Core | End-to-end | Relative observation |
|---|---:|---:|---:|---|
| NONMEM | ITS | 7.859 | 11.78 | reference |
| LibeRation compatible | ITS | 9.910 | 10.44 | 1.26x slower core, 1.13x faster end-to-end |
| LibeRation optimized | ITS | 9.150 | 9.69 | 1.08x faster than compatible core |
| NONMEM | IMP | 69.031 | 73.20 | reference |
| LibeRation compatible | IMP | 53.820 | 54.36 | 1.28x faster core |
| LibeRation optimized | IMP | 18.020 | 18.55 | 2.99x faster than compatible core; 3.83x faster than NONMEM core |
| NONMEM | SAEM | 3.188 | 6.55 | reference |
| LibeRation compatible | SAEM | 17.350 | 17.86 | 5.44x slower core |
| LibeRation optimized | SAEM | 10.580 | 11.13 | f-SAEM; 1.64x faster than compatible, but not a matched random-walk trajectory |
| nlmixr2 | SAEM | 37.390 | 39.72 | external comparator |

The compatibility-safe native implementation was also paired directly with
the retained R fallback without covariance. It produced identical recorded
objectives and reduced median elapsed time from 2.22 to 0.98 seconds for ITS,
4.41 to 3.44 seconds for IMP, and 4.47 to 1.03 seconds for SAEM. These paired
results isolate orchestration improvements; the optimized-policy rows above
also change valid algorithmic controls and therefore are not equivalence
claims. nlmixr2 ITS has no exact estimator mapping, while its IMP comparator
was excluded after repeated singular-system repair made no parameter progress.

Evidence is retained in:

- `validation/benchmark/results/20260810-its-imp-saem-focused/timing.csv`
- `validation/benchmark/results/20260810-its-imp-saem-compatible-v2/`
- `validation/benchmark/results/20260810-its-imp-saem-optimized-v4/`
