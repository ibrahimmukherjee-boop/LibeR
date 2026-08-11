# Native boundary optimisation — 2026-08-09

This change set reduces R/C++ crossings and R-owned temporary objects while
retaining R as the package, model-language, workflow, and presentation layer.
The NONMEM-compatible numerical path remains available; changes that alter RNG
ordering or optimizer coordination are confined to `liber_optimized`.

## Shared engine

- Event columns resolve ALTREP and bind read-only numeric/integer addresses once
  per view. Row access no longer constructs an Rcpp vector.
- The native population optimizer calls the persistent compiled population
  objective directly. The R callback adapter remains for arbitrary objectives.
- Custom Gaussian ETA priors are incorporated in the C++ conditional objective,
  gradient, and Hessian rather than optimized through an R closure.
- ADDL expansion uses one native source-row layout and one data-frame subset;
  event ordering is a stable native tuple sort.
- Optimized simulation generates all ETA draws in one PSD-guarded native batch.
- WAIC and NPML/NPAG responsibility and gradient reductions use contiguous
  native loops.
- Optimized adaptive and fixed Gaussian quadrature now keep proposal
  construction, conditional-mode solves, signed finite-grid reduction, score
  search, and exact finite-grid refinement in one persistent C++ coordinator.
  The NONMEM-compatible policy retains its established R/L-BFGS-B coordinator;
  explicit R optimization, PSOCK orchestration, and mapped MU models retain
  documented fallbacks rather than silently changing estimator semantics.

## LibeRtAD

`ProgramIR` is a standard-C++ value object declared in the standalone
`LibeRtAD/program_ir.hpp` header, which has no R or Rcpp dependency. Once the R
adapter has translated a parsed model, `Program` owns no R list or R vector.
This preserves the current R parser while establishing a reusable core
representation for future CLI, service, or desktop consumers.

## LibeRality

Information blocks are accumulated and diagnosed in Eigen. During pure
allocation optimization, each arm/scenario information contribution is
calculated once and only its weight is changed at subsequent iterations. Any
optimization that changes sample times, doses, covariates, or model structure
continues through the general re-evaluation path.

## LibeRator

Candidate regimens are grouped into bounded chunks and sent through one
LibeRation simulation per chunk. Transition and periodic steady-state lanes
share the same conditional ETA draw, after which endpoint-specific evaluation
remains in R because endpoints are intentionally user-extensible clinical
policy objects.

## Deliberately retained in R/Rcpp

- model parsing, validation, formula discovery, reports, GUIs, queues, and audit
  orchestration;
- extensible endpoint and design-policy functions;
- final conversion to user-facing lists, matrices, and data frames;
- reference implementations used for arithmetic-equivalence tests.

Removing these boundaries would add serialization and maintenance cost without
reducing a material numerical hot loop.
