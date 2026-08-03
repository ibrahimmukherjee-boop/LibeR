# LibeR P2 hardening programme

Last reviewed: 2026-08-03

This programme converts the P2 findings in `CODE-REVIEW-2026-08-02.md` into
ordered engineering gates. A checkbox is closed only when code, tests, and
truth-in-labeling agree.

Status: all original P2 gates and the subsequently agreed covariance and public
matrix-AD follow-ons are implemented. The latter extend the original scalar
model contract; they were not unreported defects in it.

## Gate 1 - numeric truth before structural refactoring

- [x] Add local analytic FOCEI/Laplace parameter-recovery fixtures.
- [x] Retain ADDL, steady-state, and infusion event-order fixtures and exercise
  the paired NONMEM comparator on demand. Generated NONMEM listing files and
  license-bearing artifacts remain outside source control.
- [x] Add estimation coverage for ADVAN5/7/8/9/10/14 at the evidence tier
  supported by the installed external comparator.
- [x] Validate LibeRtAD cached graph semantics against the source IR, inputs,
  outputs, and dynamic-parameter contract before reconstruction.

## Gate 2 - deterministic marginal curvature

- [x] Expose a native population Hessian for deterministic FO/ITS/FOCE/FOCEI/
  Laplace objectives.
- [x] For conditional approximations, differentiate the converged conditional
  mode with the implicit-function theorem, including curvature/log-determinant
  dependence.
- [x] Retain the numerical gradient-Jacobian Hessian as an explicit comparator
  and fallback, never as an unlabelled "exact" path.
- [x] Validate analytic, native, and high-accuracy numerical Hessians on small
  smooth models and record the selected covariance bread source.

## Gate 3 - engine seams

- [x] Move the population-objective R-facing boundary behind the stable
  `population_objective_api.hpp` seam without changing exported R entry points.
- [x] Split `pk_engine.cpp` into named internal event/ADVAN, differential-system,
  differentiable-propagation, likelihood-tape, population-objective, and
  state-space implementation units. They are deliberately included into one
  coordinator translation unit so CppAD/Eigen template definitions remain
  visible without duplication; the stable population R API is compiled as a
  separate translation unit.
- [x] Require prediction, derivative, objective, and telemetry equivalence for
  every completed seam before accepting it.

## Gate 4 - durable and secure execution

- [x] Deduplicate limit enforcement.
- [x] Add user-scoped submit idempotency keys with atomic claim semantics.
- [x] Add append-only hash-chained audit records and optional external mirror.
- [x] Add concurrent-quota and complete HTTP authorization-matrix tests.

## Gate 5 - optimal-design statistical completion

- [x] Add criterion-specific allocation directional derivatives and simplex
  updates for supported smooth criteria; reject unsupported/non-smooth cases.
- [x] Replace ordinal and supported residual finite-difference derivatives with
  analytic forms.
- [x] Add a default-CI analytic one-compartment information regression.
- [x] Implement estimator-interval coverage and omit the claim when estimator
  intervals are unavailable.

## Gate 6 - patient-workflow durability

- [x] Bound and archive assessment history while retaining an auditable index.
- [x] Store model registry id, version, and content hash in durable assessments;
  embed a full model only for explicit portable export.
- [x] Document and sensitivity-test dynamic-ETA `process_scale`.
- [x] Keep opaque patient identifiers at queue boundaries.

### Audited covariance-repair policy

- [x] Add the explicit `nm_covariance_repair()` policy with `none`, round-off
  eigenvalue clipping, diagonal loading/jitter, and Higham nearest-PSD repair.
  These are opt-in, named operations rather than an invisible change to a fitted
  covariance matrix.
- [x] Record original/repaired eigenvalues, adjustment norm, relative change,
  rank, threshold, diagonal shift, and convergence. Never silently repair a
  materially indefinite clinical uncertainty matrix.
- [x] Add a pivoted modified-Cholesky repair if a use case requires a
  well-conditioned positive-definite matrix rather than merely a PSD matrix;
  label it explicitly as a factorisation-based repair, not a nearest-matrix
  method.
- [x] Prefer intrinsically valid parameterizations (Cholesky/log-Cholesky,
  standard deviations plus a correlation transform, or factor structures)
  when a covariance matrix is estimated, so repair is a recovery/diagnostic
  operation rather than the primary constraint mechanism.
- [x] Add downstream sensitivity reporting for any repaired covariance used in
  a clinical decision or design calculation.

## Gate 7 - evidence-extraction resilience

- [x] Make the vision lane independently falsifying rather than a duplicate
  one-shot synthesis path.
- [x] Expose bounded extra gap rounds when an investigation is not ready.
- [x] Enforce ledger-superset-of-synthesis invariants.
- [x] Replace fixed browser sleeps with bounded readiness checks where supported
  and a durable manual-inbox fallback otherwise.

## Longer-range public matrix AD

- [x] Design a fixed-shape, serializable matrix IR for the public LibeRtAD API.
- [x] Start with matrix construction, transpose, multiplication, solve,
  Cholesky/log-determinant, and matrix exponential, with explicit pivot/path
  validity contracts.
- [x] Add statistically useful primitives only where their derivative contract
  is unambiguous: triangular solves, symmetric rank updates, quadratic forms,
  stable `logdet`, and Cholesky-parameterized covariance construction.
- [x] Treat decompositions with eigenvector degeneracy, pivoting, or rank changes
  as guarded operations requiring retaping or an explicit smooth surrogate; do
  not promise derivatives through arbitrary SVD/eigendecomposition.
- [x] Reuse the existing native CppAD tape engine through fixed-shape scalar-IR
  lowering and add analytic, finite-difference, cache-roundtrip, sparsity, and
  guarded-path tests; downstream Eigen/CppAD kernels retain their existing C++
  interfaces.
- [x] Keep the public scalar IR stable and do not claim arbitrary/dynamic-shape
  matrix support until those semantics are implemented and validated.
