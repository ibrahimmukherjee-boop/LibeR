# Deterministic subject-parallel CppAD and native IMP extension

## Implemented scope

The optimized ITS and IMP weighted complete-data objective can now run
independent subject CppAD tapes through a persistent native worker pool. The R
coordinator no longer creates PSOCK workers for this eligible path. Subject
assignment is a fixed contiguous partition, dynamic observations and
covariates are installed serially before dispatch, and all values and gradients
are reduced on the main thread in subject order. This keeps the result
independent of worker completion order.

CppAD is configured with stable thread-local allocator identifiers. Worker IDs
occupy slots 1 through 47 and the R/main thread remains slot 0. A construction
guard verifies that every subject owns a distinct mutable `ADFun`; shared tapes
force a serial fallback. The worker count is also capped by the subject count
and CppAD's configured thread limit.

For ODE objectives, each subject/support pair owns its own retained tape, so
different adaptive trajectories do not repeatedly invalidate one another. A
changed recorded path is reported by the worker rather than retaped there. The
main thread rebuilds each affected support tape using the retained model engine
and subject data and redispatches the calculation. This preserves R API safety
while allowing stable evaluations to remain parallel. Reduced population tapes
remain disabled for ODE models because a single nested aggregate tape is not an
appropriate owner for support-specific retaping.
The default retained ODE support-tape limit is 4,096 and is configurable with
`options(LibeRation.ode_weighted_tape_limit = ...)`; larger grids fall back
before allocating the tape collection.

Optimized IMP's weighted native M-step is now eligible for multicore,
MU-referenced, and ODE models. MU recentering still occurs at the established
algorithmic boundary after the fixed-support M-step, so the MCEM target is not
changed. OMEGA-prior cases retain the existing fallback: the fast native M-step
currently freezes OMEGA while its no-prior path uses the exact conditional
second-moment update; pretending that this is valid under a non-conjugate prior
would be incorrect.

## Native optimizer applicability

LibeRation contains two related native optimizers:

- The general box-constrained dense BFGS can consume a compiled population
  objective directly. It removes R callbacks for FO, FOCE, FOCEI, and Laplace
  when the user selects the native backend. It can also coordinate an arbitrary
  R objective, but that adapter does not remove the R boundary. `auto`
  intentionally retains R's mature L-BFGS-B coordinator until the native
  trajectory is preferable across the validation matrix.
- The persistent limited-memory BFGS is used for repeated SAEM and IMP
  fixed-support M-steps. It retains curvature pairs between stochastic
  iterations and therefore suits this problem better than restarting the
  general dense optimizer each time.

BFGS cannot replace an estimator's defining stochastic algorithm. For BAYES,
HMC, and NUTS it is useful only for a mode or proposal initializer; for NPML and
NPAG it can optimize a smooth parameter block but cannot replace support-point
EM; and for SAEM/IMP it is restricted to the legitimate deterministic M-step.

## Verification

- Serial and two-worker weighted objectives agree for both value and gradient
  at tight tolerances.
- The worker telemetry records actual CppAD dispatches.
- A MU-referenced optimized IMP fit completed every requested native M-step
  without fallback.
- A two-subject ADVAN6 weighted objective and complete optimized IMP fit both
  completed through the parallel native path while safely recording and
  retaping ODE support trajectories on the main thread.
- The focused stochastic-native test file passes 71 expectations, the advanced
  inference file passes 80 expectations, and the core estimation file passes
  its full regression set, including the existing parallel worker tests.
