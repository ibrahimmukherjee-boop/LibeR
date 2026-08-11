# FO and SAEM focused performance investigation

Date: 2026-08-07

## FO

The investigation first established that the former LibeRation `core` timer
covered all of `nm_est()`, including context creation and tape recording,
whereas NONMEM's value was its listing's total executable CPU fallback after
NMTRAN/Fortran compilation. LibeRation now reports post-initialization model
fitting plus covariance as core time. Initial model/context/tape construction
remains in literal fresh-process end-to-end wall time and is retained as
`fit$timing$initialization_seconds` for audit.

Five warm phase decompositions of the 100-subject/800-record case gave:

| LibeRation phase | Compatibility | Optimised |
|---|---:|---:|
| Context and 100 conditional tapes | 0.20 s | 0.20 s |
| FO and fused population tapes | 0.06 s | 0.05 s |
| Outer optimization | <0.01 s | 0.01 s |
| Batched posthoc ETA modes | 0.02 s | <0.01 s |

Before the changes, both policies used 66 objective and 66 gradient callbacks,
54 unique compiled population parameter evaluations, 101 recorded tapes, and
99 shared prediction tapes. The analytical Gaussian FO path now also shares
conditional-objective operation sequences for subjects with identical event
and observation structures, while observations and eligible covariates are
supplied as CppAD dynamic parameters inside the batched posthoc kernel. Complex
likelihood structures conservatively retain ordinary subject tapes.

Serial eligible FO contexts are cached across repeated in-process GUI runs.
The cache key contains the complete model, dataset and tape-affecting options;
hash matches are followed by exact equality, and changed data or options cannot
reuse a context. The cache is bounded and can be disabled.

Recommended order:

1. **Completed:** separate initialization from the user-facing core
   fit-plus-covariance timer while retaining initialization audit telemetry.
2. **Completed for the eligible FO surface:** share conditional objective-tape
   structure with subject-specific dynamic values in batched posthoc kernels.
3. **Completed:** cache exact compatible compiled FO contexts between repeated
   local runs.
4. Only then assess whether direct specialised ADVAN FO sensitivity kernels
   justify replacing more of the CppAD recording path.

## SAEM native optimizer

The optimised native M-step made 5,319 function and 5,319 gradient evaluations;
the persistent R L-BFGS-B path made 1,847 paired evaluations. Across 260 native
M-steps:

- median accepted BFGS iterations per M-step: 4;
- median complete evaluations per M-step: 20;
- mean trial evaluations per accepted step: approximately 4.6;
- accepted steps at or below 0.125: 47.6%;
- 25th percentile accepted step: 0.015625;
- median initial absolute objective: 1,036;
- median initial projected-gradient norm: 310.

The causes are identifiable in the implementation:

1. Every rejected Armijo trial computes both `Forward(0)` and `Reverse(1)`.
2. The raw objective/gradient are used to initialize BFGS, whereas R's optimizer
   divides them by the initial objective magnitude.
3. Line search uses halving only rather than safeguarded interpolation or a
   strong-Wolfe/More-Thuente strategy.
4. The inverse-Hessian approximation is discarded at every SAEM iteration.
5. Bound clipping is simpler than L-BFGS-B's generalized Cauchy/subspace step.

Implemented response:

1. Persistent R L-BFGS-B is again the automatic route; the native optimizer is
   selected only by explicit `optimizer_backend = "native"`.
2. The native fixed-ETA API now uses value-only trial evaluation and
   value-plus-gradient accepted-point evaluation.
3. Optimizer values and gradients are normalized by the initial objective
   magnitude.
4. Blind halving is replaced by safeguarded quadratic interpolation; the
   bound-aware Armijo test uses the actual projected displacement, and a
   strong-Wolfe curvature check gates retention of L-BFGS memory.
5. The dense inverse-BFGS matrix is replaced by damped limited-memory BFGS;
   memory is retained between adjacent M-steps and cleared on a non-descent
   direction or excessive backtracking.
6. Native automatic selection remains deferred until matched evaluation-count,
   seeded-trajectory, convergence, and runtime tests across simple, full-OMEGA,
   covariate, IOV, and ODE models.

On the same 260-M-step, 100-subject diagnostic after the implementation, the
explicit native route completed in 2.69 seconds with 893 value and 888 gradient
evaluations, versus 5,319 of each before the change. All 260 M-steps completed
without fallback. This is a strong local result, but the automatic route remains
R L-BFGS-B until the broader seeded scenario gate above is complete.

A value-only general-native ablation retained 5,319 function evaluations but
reduced gradient evaluations to 1,363. R callback overhead made that diagnostic
path slower overall, so the split must be implemented inside the persistent
C++ SAEM context to realize its benefit.

## Covariance-inclusive benchmark after implementation

The updated focused benchmark used the standard 100-subject/800-record
ADVAN1/TRANS2 IV-bolus case, one core, one warm-up, and three measured fresh
processes. Covariance was requested for FO and SAEM; simulation was excluded.

| Method | Engine / policy | End-to-end | Core fit + covariance |
|---|---|---:|---:|
| FO | NONMEM | 4.67 s | 0.281 s |
| FO | LibeRation compatibility | 0.78 s | 0.110 s |
| FO | LibeRation optimized | 0.73 s | 0.110 s |
| SAEM | NONMEM | 7.70 s | 3.391 s |
| SAEM | LibeRation compatibility | 3.47 s | 2.880 s |
| SAEM | LibeRation optimized | 3.35 s | 2.770 s |

Against the reported values, NONMEM took 2.56x as long as either LibeR FO core
and 5.99x/6.40x as long end to end for compatibility/optimized FO. NONMEM took
1.18x/1.22x as long as compatibility/optimized SAEM core and 2.22x/2.30x as
long end to end. The NONMEM listing did not expose separate estimation and
covariance elapsed timers in these runs, so its core uses total CPU fallback.
The LibeR compatibility medians split into `0.03 + 0.08` seconds for FO and
`2.72 + 0.16` seconds for SAEM.

The combined table, PNG and SVG are under
`validation/benchmark/results/20260807-fo-saem-covariance-comparison/`.
