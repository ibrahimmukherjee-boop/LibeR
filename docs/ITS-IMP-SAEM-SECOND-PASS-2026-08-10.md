# ITS, IMP, and SAEM second optimization pass

Date: 10 August 2026

## Scope and invariants

This pass reviewed both `nonmem_compatibility` and `liber_optimized` execution
after the estimator-identity corrections. Optimizations were accepted only if
they either preserve the defining estimator and operation order, or are
confined to the explicitly optimized policy with exact correction of any
proposal approximation.

## Implemented in both policies

- ITS skips an unused exact conditional-Hessian sweep for Gaussian first-order
  conditional covariance. Modes, prediction Jacobians, OMEGA contribution,
  covariance repair, sigma-point grid, and update order are unchanged.
- Defensive importance sampling uses its actual deterministic-mixture
  allocation in the proposal density when the requested number of draws is
  odd.
- Persistent weighted-ETA support grows geometrically rather than allocating
  and copying every preceding support row for every subject at each SAEM
  iteration. Active support order, weights, moments, and reductions are
  unchanged.
- The full accepted native weighted-Q gradient is returned to R. Simple
  residual SIGMA sufficient statistics are recovered from that sweep rather
  than a second complete-Q replay. A SIGMA prior disables this closed-form
  route because the posterior update is no longer conjugate.
- Persistent L-BFGS memory is retained across nearby weighted M-steps and is
  invalidated when parameter scaling changes by more than fourfold.

## Implemented only in `liber_optimized`

- IMP may use Fisher/Gauss--Newton curvature for proposal construction. The
  target and proposal densities are still evaluated exactly, so this changes
  Monte-Carlo efficiency rather than estimator identity.
- IMP's weighted E-step support feeds a persistent native C++ M-step directly.
  Eligible simple-residual and OMEGA blocks use exact complete-data
  sufficient-statistic updates, and the native L-BFGS history survives across
  MCEM iterations.

The native optimized IMP M-step is conservatively disabled for subject-PSOCK,
ODE/retaping, active MU specialization, and OMEGA-prior cases. Those cases
retain the exact persistent weighted objective with the established R
optimizer coordinator.

## What was not lost during fidelity work

The following remain present: persistent subject CppAD tapes and dynamic data,
batched importance-weight calculation, the shared weighted-ETA context,
reduced-domain stable-support population tapes, native SAEM/BAYES coordinators,
and eligible fused analytical ADVAN1--4/11/12 stochastic propagation. The
fidelity work changed two intentional scopes: default IMP became canonical
independent-E-step MCEM, and canonical SAEM retained a growing Robbins--Monro
support. Those properties prevent treating the old fixed finite-CRN IMP graph
or an always-stable SAEM aggregate graph as the default estimator.

## Remaining high-cost opportunities

1. A native subject-parallel weighted objective would remove the last serial
   subject loop for generic CppAD models. It requires CppAD thread-local tape
   ownership and deterministic reduction qualification.
2. A compatibility-native M-step could eliminate the R optimizer callback,
   but it must first reproduce the matched NONMEM control trajectory and
   stopping/boundary semantics. It is intentionally not enabled merely because
   the optimized native coordinator is faster.
3. MU/IOV-aware native IMP ECM and ODE-safe retaping can broaden the optimized
   native M-step. Both require explicit derivative and state-transition gates,
   not a silent fallback inside an accepted optimizer step.
4. C++ random-number generation is a small opportunity relative to conditional
   modes and weighted M-steps. It should be considered only with a declared,
   reproducible stream contract.
5. Sparse conditional curvature is likely useful only for larger ETA blocks;
   dense factorizations remain preferable for the common small-ETA models.

## Verification gates

The focused suite checks native/reference complete-data values and gradients,
SAEM recurrence moments and geometric support growth, SIGMA/OMEGA sufficient
statistics, ITS covariance, defensive-mixture density, IMP weights and policy
separation, native full-domain gradients, and the seeded compatibility SAEM
trajectory. Benchmark conclusions must continue to separate compatible and
optimized policies rather than interpreting them as identical control paths.
