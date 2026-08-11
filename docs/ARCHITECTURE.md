# Architecture

## Invariants

1. A production fit uses one complete C++ numerical path. Model parsing,
   orchestration, presentation, and reporting may run in R.
2. A model is stored as serializable data, never as an external pointer. Pointer
   objects are disposable compiled caches and are recreated in workers.
3. Model semantics and graphical layout are separate. Moving a diagram node is
   not a numerical model change.
4. The event table has stable ordering. Generated ADDL and infusion-stop events
   retain their source-record identity.
5. Solver choice is a compilation decision: known ADVAN topology, otherwise a
   general linear matrix backend, otherwise an ODE backend. Advanced users may
   override an eligible choice.
6. Numerical comparisons cover predictions, objective values, gradients, and
   Hessians--not just final parameter estimates.

## Compilation flow

```text
R/C++ model specification or graphical editor
                    |
                    v
      serializable canonical model IR
       /             |              \
 expression IR   compartment IR   layout IR
       |             |
       +------ model compiler ------+
                    |
       optimized ADVAN | matrix | ODE
                    |
       LibeRtAD C++ differentiable objective
                    |
     simulation / estimation / diagnostics
```

The R expression compiler accepts the established LibeRation syntax: assignment
statements, `THETA(i)`, `ETA(i)`, `SIGMA(i)`, `ERR(i)`, arithmetic, common math
functions, and explicit `ifelse()` conditionals. Unsupported R constructs fail
at compile time with source context; they never fall back to evaluation inside
the numerical loop.

## Pointer ownership

`LibeRtAD::ADModel` owns two external pointers:

- an immutable compiled expression program;
- an optional persistent CppAD tape recorded for chosen inputs and outputs.

The tape owns its program through shared C++ ownership, so R garbage collection
order cannot leave a dangling program pointer. Pointer objects are not serialized
to LibeRties jobs; their serializable IR is sent and compiled by the worker.
CppAD diagnostic and error-stream branches are compiled against an R console
stream supplied by LibeRtAD. LibeRtAD owns the official CppAD 20260000.0 and
Eigen 5.0.1 header snapshots directly; the console adapter prevents CppAD from linking
`std::cout` into either package and keeps all native output within R's console
API.

## Concurrency contract

LibeR's supported parallel unit is an **R process**, not a shared mutable AD
tape. PSOCK workers and LibeRties job workers receive serializable model/data
contracts and construct their own C++ programs, CppAD tapes, optimizer work,
and RNG streams. Concurrent independent R processes are therefore isolated;
the regression suite launches simultaneous fits to enforce this contract.

An `ADModel`, LibeRation prediction tape, objective tape, or evaluator must
only be used by the R thread that owns its external pointer. `ADFun` evaluation
updates internal Taylor and sparsity work buffers, so the same pointer must
not be called concurrently from OpenMP threads or another native thread.
CppAD `parallel_setup()` is deliberately not enabled globally: it requires
correct application-specific thread-number and in-parallel callbacks and
would not make an existing mutable tape safe to share. Future native
thread-parallel kernels must allocate one tape/work object per thread and
install those callbacks within a scoped runtime.

R options are configuration read at model compilation or job construction,
not storage for active tapes. Per-fit caches and mutable estimator state live
in execution-local environments; GUI/server state is owned by its R6 or Shiny
session. Worker initialization currently uses a single private worker-state
binding inside each disposable PSOCK process and never shares it across
processes.

`LibeRtAD/eigen.hpp` establishes one include order for both libraries and uses
CppAD's upstream `cppad/example/cppad_eigen.hpp` scalar adapter. LibeRation then
instantiates Eigen containers with CppAD scalars without RcppEigenAD or
RcppEigen. The adapter provides type interoperability; numerical stability and
execution speed remain properties of the selected algorithms and kernels.

## Linear solvers and steady state

Known ADVAN models and arbitrary linear compartment graphs both compile to
`dA/dt = K A + u`. The matrix backend uses scaling-and-squaring with a Pade
approximant, avoiding eigendecomposition and its unstable derivatives near
repeated eigenvalues.

The AD prediction path selects topology-specific propagation for
ADVAN1-4/11/12. ADVAN1 uses a scalar exponential; ADVAN2 uses a stable divided
exponential; ADVAN3 uses the closed two-by-two trace/discriminant form; and
ADVAN4 composes that form with a stable depot-to-disposition divided
exponential. ADVAN11/12 use the native three- or four-state Pade transition,
without the affine augmentation used by arbitrary matrix graphs. Non-zero
inputs are propagated with a `phi_1` series for short intervals and an exact
linear affine solve otherwise. Repeated-rate limits use `sinh(z)/z` series, so
the kernels do not introduce singular differences of exponentials. Arbitrary
matrix graphs, including the ADVAN5/7 contracts, continue to use the general
matrix-exponential path.

Kernel selection is fixed when a persistent CppAD tape is recorded. Tape
metadata reports the selected propagation kernel and its optimized operation
and variable counts. The internal development option
`options(LibeRation.specialized_advan = FALSE)` retains the former general
matrix-exponential path as a numerical and performance comparator; it is not a
second production backend.

Steady state is solved as a periodic affine map. For a bolus dose `D` and
`Phi = exp(K * II)`, the pre-dose state satisfies
`(I - Phi) A_pre = Phi D`. Infusions use the composed on/off affine maps. The
solver diagnoses non-existent or ill-conditioned steady states rather than
silently truncating an infinite-dose superposition.

## Nonlinear ODE solvers

ADVAN6 compiles `$DES` assignments to the same scalar expression IR used by the
parameter model and integrates them with an adaptive Dormand-Prince 5(4)
method. ADVAN10 uses that path with its standard integrated VM/KM
Michaelis--Menten equation. ADVAN8/9/13/14 use adaptive step-doubled implicit
trapezoidal integration with a numerically assembled Newton Jacobian, providing
an A-stable path for stiff systems. ADVAN9 can additionally solve semi-explicit
index-1 equilibrium constraints on the CppAD tape. These are NONMEM-compatible
model and event contracts; they do not claim algorithm identity with NONMEM's
solver implementations. All paths split integration intervals at infusion
stops and apply bolus, reset, and compartment events in the shared C++ event
engine.

Nonlinear periodic steady state uses a converged periodic shooting solve for
bolus and finite/overlapping infusion regimens. The entire accepted shooting
trajectory remains on the scalar-generic AD tape, including modelled infusion
duration boundaries. Failure to reach the periodic fixed point is diagnosed;
the engine never substitutes a silently truncated repeated-dose sum.

## Estimation and inference

The joint likelihood is recorded once as a persistent CppAD tape. FO uses the
first-order marginal Gaussian covariance; FOCE freezes residual variance at
ETA zero; FOCEI retains interaction; Laplace uses exact conditional curvature.
ITS, importance-sampling Monte-Carlo EM, SAEM, and Bayesian MCMC share the
same C++ prediction and likelihood path. Full covariance OMEGA,
occasion-expanded ETAs, mixtures, priors, censoring, and correlated residuals
are composed in that same objective.

Frequentist uncertainty is transformed back to the native THETA/SIGMA/OMEGA
scale. Deterministic FO/ITS/FOCE/FOCEI/Laplace covariance uses a native CppAD
population Hessian behind `population_objective_api.hpp`; conditional methods
include implicit mode sensitivities, curvature/log-determinant derivatives,
and nonlinear parameter transforms. The numerical gradient-Jacobian Hessian
is retained as a labelled comparator/fallback. Indefinite covariance repair is
available only through the explicit, audited `nm_covariance_repair()` API.
IMP and SAEM perform post-fit marginal importance-information calculations
for frequentist covariance. Bayesian runs report
posterior SDs, posterior CVs, 95% credible intervals, and posterior
covariance/correlation matrices directly from the saved chain.

The compiled engine is organized as one coordinator translation unit with
separate internal implementation units for event/ADVAN logic, differential
systems, differentiable propagation, likelihood tapes, population objectives,
and state-space decoding. Keeping the CppAD/Eigen template units in one
translation unit avoids duplicate template instantiation; the stable
population-objective R boundary is compiled separately.

Model, data, fit, and diagnostic state are stored as immutable model versions
and runs. Workspace schema v2 writes canonical semantic models, datasets, and
results to a SHA-256 content-addressed object store; manifests retain only
typed references. Repeated versions therefore share immutable objects instead
of copying large data frames. Writes are atomic and project-scoped locks guard
concurrent sessions. External pointers are never persisted and are rebuilt
when a model is opened locally or by a worker. Version-1 workspaces remain
readable and are upgraded only by the explicit migration operation.

## Optimal-design path

LibeRality treats a trial design as serialisable semantic data. It retains a
LibeRation model, elementary arm schedules, endpoint distributions, population
strata, uncertainty/operational scenarios, optimisable variables, constraints,
prior information, and provenance. Compiled pointers are never stored in the
design or sent through a queue.

```text
LibeRary model / LibeRation model / LibeRator endpoint
                         |
                         v
       arms + schedules + populations + scenarios
                         |
       LibeRation C++ predictions and exact sensitivities
                         |
          native Eigen expected-information assembly
            /                 |                 \
   precision criteria   decision criteria   discrimination
            \                 |                 /
          constraints + mixed-variable optimisation
                         |
        complete-trial simulation and operating checks
                         |
       LibeRation hand-off / LibeRties typed job / report
```

Continuous outcomes use joint mean/covariance information at population FO
level. Non-continuous endpoints use distribution-aware working information;
event endpoints use a counting-process interval representation. Local,
scenario-averaged, worst-case, discrimination, power, target, cost, compound,
and Pareto objectives share one criterion interface with explicit optimisation
direction. Constraints remain separate from scalarisation and are reported
whether or not they are active in an optimisation.

## Package boundary

LibeRtAD installs a small supported C++ header/API. LibeRation does not call
unexported R internals. LibeRties treats a LibeRation job specification as data
and never evaluates arbitrary submitted R expressions on the server.

The packages remain separately installable, so common runtime code is
maintained as a small number of canonical, generated contracts rather than a
new required package dependency:

- `tools/shared/liber-durability.R` owns atomic publication, recoverable reads,
  directory locks, and safe path components;
- `tools/shared/liber-paths.R` owns user-data root conventions;
- `tools/shared/gui/` owns cross-package browser theme and accessibility
  primitives;
- `ecosystem.json` and the external-validation baseline manifest are canonical
  packaged contracts.

Run `tools/sync-shared-runtime.R`, `tools/sync-gui-assets.R`, and
`tools/sync-packaged-contracts.R` after editing a canonical source. Generated
package copies carry a warning header and CI/release checks fail if they drift.
This keeps duplication mechanical and verified while avoiding dependency
cycles between independently distributed packages.

LibeRties also owns the common background-process supervision façade. It wraps
`processx` or `callr` processes with one lifecycle API for polling, output,
exit status, cancellation, and process-tree termination. Packages may use it
when LibeRties is installed and retain a local fallback where making LibeRties
a hard dependency would create an inappropriate package edge.

LibeRary owns literature acquisition, structured evidence, review state, and
catalogue versions. Its literature path is staged and resumable:

```text
PubMed search snapshot
        |
title/abstract triage ---- Low -> durable later-pass backlog
        |
 High + Intermediate
        |
 PDF acquisition -> content-addressed document bundle
        |                         |
 Docling standard parse      original PDF pages
        |                         |
 evidence map + model          independent vision
 reconnaissance                    extraction
        |
 six domain investigators
        |
 skeptical review -> targeted gap search
        |
 optional page-level claim verification
        |
 deterministic consistency gate
        |
 evidence-constrained synthesis
        +-------------+-----------+
                      |
             field-level comparison
                   |
       third-model adjudication
                   |
 machine-consistent / machine-adjudicated / major review exception
                   |
        versioned LibeRary catalogue
                   |
        LibeRation parser/compiler
```

The parsed-text path is a fact-finding investigation rather than a one-shot
prompt. Reconnaissance distinguishes base, final, validation, bootstrap, and
external models. Separate investigators cover structure, THETA/covariates,
OMEGA/IOV, SIGMA/observation model, population/dosing, and reproduction data.
Claims have stage-scoped ids, pharmacometric domains, status, dependencies,
locators, and evidence. A skeptical review can close questions or trigger a
targeted gap search; deterministic gates prevent an incomplete ledger from
receiving a terminal machine-qualified state. Every stage is content-addressed,
resumable, and retains failure attempts.

The independent vision-extraction lane still never consumes Docling text. An
additional verification stage may challenge material ledger claims directly
against original pages before synthesis. Provider/model choices may differ.
Same-model use remains supported but is recorded as a correlated-error warning.
Content hashes, parser/fallback details, evidence ledger, source locators, both
raw lane results, comparison, and adjudication are retained. Machine
qualification states never imply human validation.

LibeRary passes a generated control stream through LibeRation's public
parser/compiler before import and stores catalogue identity plus qualification
metadata in the immutable model-version provenance. LibeRation only suggests
LibeRary, avoiding a required dependency cycle.

Remote jobs cross the HTTP boundary through `liber.job.wire/2`, a typed JSON
format that rejects functions, calls, environments, and external pointers. The
server discards any client-side compiled representation and rebuilds expression
IR from the versioned `liberation.model/4` contract through `nm_model()`. Wire
version 1 remains readable for queue migration but is never emitted by new
clients. RDS remains an internal durable-queue format only, after
authentication and validation, and may be authenticated-encrypted at rest with
a server-owned key.

Model contract v4 retains separate `$PK` and `$PRED` sources plus one of three
execution modes. The conventional path is `$PK -> ADVAN/$DES -> $ERROR`; the
direct path is `$PRED -> $ERROR`; and the combined LibeRation extension is
`$PK -> ADVAN/$DES -> post-ADVAN $PRED -> $ERROR`. The last stage consumes the
raw prediction as `F_ADVAN` and remains part of the same double/CppAD event
engine, including dynamic covariate inputs and generated-output selection.

`library_triage`, `library_parse`, `library_index`, `library_dual_extract`,
`library_assess`, and `library_adjudicate` use the same wire envelope but have a
separate typed data payload. Their only worker entry point is
`LibeRary::library_worker_task()`. Provider/model settings may travel with a
job, while API keys are resolved from named worker environment variables. The
worker returns evidence results and never mutates a catalogue implicitly.
