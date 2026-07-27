# LibeR

LibeR is a six-package population PK/PD, optimal-design, and model-informed precision-dosing ecosystem with an R-facing
workflow and a single C++ numerical runtime.

- **LibeRtAD** owns the bundled CppAD tape, model-expression IR, derivatives,
  and the light R6/external-pointer interface.
- **LibeRation** owns NONMEM-style model specifications, event processing,
  ADVAN and matrix/ODE solvers, simulation, estimation, diagnostics, and the
  reactR workflow.
- **LibeRties** owns local and remote job execution, tenant isolation, quotas,
  durable job state, and the authenticated worker API.
- **LibeRary** owns the versioned pharmacometric model catalogue, probability-
  tiered literature discovery, Docling document bundles, independent text/PDF-
  vision extraction, automated reconciliation, and reviewed model provenance.
- **LibeRator** (Adaptive Therapeutic Optimisation and Recommendation) owns
  encrypted longitudinal patient evidence, Bayesian individualisation,
  time-varying patient states, versioned therapeutic endpoints, and
  uncertainty-aware regimen comparison. LibeRator remains for research and
  teaching, with a security and governance architecture intended for later
  clinical hardening.
- **LibeRality** owns model-informed optimal clinical trial design: expected
  information, local/Bayesian/robust/discrimination/decision criteria,
  constrained mixed-variable optimisation, Pareto analysis, complete-trial
  simulation, and an amber React workbench.

The implementation covers ADVAN1-14 using analytical kernels, arbitrary linear
matrix models, adaptive explicit and stiff implicit integration,
Michaelis--Menten elimination, and equilibrium DAE constraints,
analytical and nonlinear periodic steady state, overlapping infusions,
ADDL/II, and NONMEM modelled infusion rate/duration conventions. Exact CppAD
tapes cover prediction, likelihood, gradients, Jacobians, and Hessians.

Population workflows include FO, FOCE, FOCEI, Laplace, ITS, importance
sampling, SAEM, and Bayesian estimation; diagonal/full OMEGA, IOV, finite
mixtures, priors, M3/M4 BLQ likelihoods, AR1 residuals, stochastic simulation,
native-scale covariance diagnostics (including marginal IMP/SAEM information),
Bayesian posterior SDs and credible intervals, CWRES, continuous/binary
categorical/time-to-event VPCs, subject bootstrap, profile likelihood, and
stepwise covariate modelling (SCM). Supported NONMEM control streams can be
imported and exported with compatibility reporting and preservation of unknown
records. THETA parameters support explicit lower/upper bounds and default to
initial/1000 and initial*1000 when a bound is absent or invalid. Estimation can
retain compiled subject workers across iterations, simulations can distribute
replicates across workers, and queued fits can stream configurable population
gradient progress to the worker log. The React
workbench provides model and parameter editing, dataset import, all run methods,
diagnostics, jobs, and named model versions with nested, numbered estimation and
simulation runs.

LibeRties provides durable local workers and an authenticated typed-JSON remote
API with tenant-derived namespaces, scoped/expiring credentials, an
administrative audit chain, optional authenticated at-rest encryption (including
terminal worker logs),
cryptographic integrity checks, restart recovery, quotas, state-transition
locking, and monitored wall-time, CPU, process-tree memory, payload, result,
and storage limits. The built-in worker is a **restricted subprocess, not a
hostile-code sandbox**. Production deployments must add TLS termination and
host-level OS-account or container isolation; `ls_server_preflight()` requires
measured Linux container/cgroup evidence or a deployment-integrated isolation
probe and refuses a production start when the boundary is incomplete.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md),
[docs/VALIDATION.md](docs/VALIDATION.md), [docs/REMOTE.md](docs/REMOTE.md),
[SECURITY.md](SECURITY.md), [docs/RELEASE.md](docs/RELEASE.md),
[docs/STORAGE.md](docs/STORAGE.md), and the
[0.9 research-beta programme](docs/RESEARCH-BETA.md).

## Install

Use the [compatibility-checked installer](docs/INSTALL.md) for a released
ecosystem set. Use R 4.1 or newer and a C++17 toolchain. LibeRtAD bundles the exact official
CppAD 20260000.0 and Eigen 5.0.1 header releases, so neither needs to be
installed separately. After installing the other declared R dependencies, install the packages in dependency order
from the repository root:

```r
source("https://raw.githubusercontent.com/svdijkman/LibeR/main/tools/install-ecosystem.R")
liber_install()                    # newest published release, including research betas
# liber_install(channel = "stable") # newest non-prerelease
```

For a development checkout, install the exact local sources with:

```text
Rscript tools/install-local-stack.R
```

The equivalent manual package order is:

```text
R CMD INSTALL LibeRtAD
R CMD INSTALL LibeRation
R CMD INSTALL LibeRary
R CMD INSTALL LibeRator
R CMD INSTALL LibeRality
R CMD INSTALL LibeRties
```

After installation, verify the exact package set and inspect the declared
scientific evidence tiers:

```r
LibeRation::liber_doctor(strict = TRUE)
LibeRation::liber_support_matrix()
```

Create a redacted diagnostic archive for a bug report with
`LibeRation::liber_support_bundle()`.

The ecosystem-wide evidence campaigns, including independent comparisons with
KFAS, glmmTMB/hmmTMB, deSolve, SciML/Sundials, COPASI, pomp/bssm, advanced
nlmixr2 population fixtures, mapbayr/posologyr, PopED/PFIM, CmdStan when
configured, and NONMEM when licensed, are documented in
[`docs/VALIDATION.md`](docs/VALIDATION.md).

## Quick start

Three runnable teaching workflows are installed with LibeRation: oral
population PK simulation/FOCEI estimation, intermittent-infusion steady state,
and an ODE-linked PK/effect-compartment model. Locate them with:

```r
system.file("examples", package = "LibeRation")
```

```r
library(LibeRation)

model <- nm_model(
  INPUT = c("ID", "TIME", "EVID", "AMT", "CMT", "DV", "MDV"),
  ADVAN = 1,
  PRED = "CL=THETA(1)*exp(ETA(1))\nV=THETA(2)\nS1=V",
  ERROR = "Y=F*(1+ERR(1))",
  THETAS = data.frame(THETA = 1:2, Value = c(2, 20)),
  OMEGAS = data.frame(OMEGA = 1, Value = 0.1),
  SIGMAS = data.frame(SIGMA = 1, Value = 0.1)
)

data <- data.frame(
  ID = 1, TIME = c(0, 1, 2, 4), EVID = c(1, 0, 0, 0),
  AMT = c(100, 0, 0, 0), CMT = 1,
  DV = c(NA, 4.5, 4.1, 3.4), MDV = c(1, 0, 0, 0)
)

fit <- nm_est(model, data, method = "FOCEI")
predict(fit)

# Optional uncertainty and covariate workflows
nm_bootstrap(fit, n = 200)
nm_profile(fit, parameters = c("THETA1", "THETA2"))

# Semantic NONMEM control-stream round-trip
control <- nm_control_read("model.ctl")
nm_control_write(control, "model-roundtrip.ctl")

workspace <- nm_workspace("~/LibeR-workspace")
nm_workspace_migrate(workspace)
nm_workspace_verify(workspace)
liber_doctor(workspace)
liber_gui(model, data, workspace = workspace)
```

When `LibeRties` is installed, `liber_gui()` creates a persistent local queue
inside the workspace by default, so running and completed local jobs remain
visible in the Jobs tab. Pass `queue = FALSE` to run work in the current R
process instead. A LibeRties service and its admin application share durable
users and job history through the same `LIBERTIES_ROOT` environment variable
(or `options(LibeRties.root = ...)`).

The workbench keeps its selected queue and remote client definitions under the
workspace rather than the installed package, so package reinstallations and
upgrades do not remove them. Large datasets and saved run outputs are represented
by lightweight metadata when projects, model versions, or runs are selected.
Rows are transferred to the browser only when the Data explorer is opened and
explicitly loaded; diagnostic payloads are loaded on the first visit to their
corresponding tabs. GOF data are persisted with the run after their first
calculation. Plot panels remain mounted after first rendering, so returning to a
GOF/VPC/NPDE/NPC tab is a visibility change rather than a new download,
simulation, or SVG reconstruction. Continuous VPCs may additionally be
stratified by one dataset column, in which case the saved view contains the
overall VPC and one VPC per stratum.

Workspace schema v2 stores models, datasets, and results once in a
content-addressed object store and references them from model versions and
runs. Project writes are lock protected and atomic; `nm_workspace_backup()`
creates a portable archive, while `nm_workspace_gc(dry_run = TRUE)` reports
unreferenced objects without deleting them. Legacy workspaces are upgraded
explicitly by `nm_workspace_migrate()` and are never silently rewritten merely
by opening the GUI.

For a synthetic longitudinal dosing example, use `LibeRator::lator_example_aed()`
and see [LibeRator/README.md](LibeRator/README.md). LibeRator can import
validated LibeRary models, run its individual-fit jobs through LibeRties, and
uses LibeRation's persistent C++/automatic-differentiation objective. Its
current outputs are research hypotheses for qualified review, not autonomous
treatment instructions.

For optimal-design work, start with `LibeRality::lity_example()` and
`LibeRality::liberality_gui()`. Final designs can be exported as exact
LibeRation event templates or submitted as typed LibeRties jobs.

## Licensing

LibeRtAD, LibeRation, LibeRties, LibeRary, LibeRator, and LibeRality are MIT licensed. Bundled CppAD and other
third-party components retain their own licences. See
[LICENSES/README.md](LICENSES/README.md).
