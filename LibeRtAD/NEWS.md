# LibeRtAD 0.8.2

- Introduces an R-independent `ProgramIR` value representation in the
  standalone `LibeRtAD/program_ir.hpp` header and makes the numerical `Program`
  own only standard C++ containers after construction. The R list is now an
  explicit adapter input rather than retained numerical state, providing a
  stable seam for CLI/service/desktop consumers.
- Avoids a redundant zero-order CppAD forward sweep in combined scalar
  `value_gradient()` evaluation by reusing the recorded Taylor state for the
  reverse sweep. The scalar value and gradient remain numerically identical.
- Routes CppAD value-graph `printf` diagnostics through R's console adapter,
  preventing GCC from linking direct `puts`/`putchar` calls into LibeRtAD or
  downstream engine packages.

# LibeRtAD 0.8.0

- Makes native program and tape pointers private lifecycle state. Callers can
  inspect `has_tape()` but can no longer replace, null, or serialize raw
  external pointers; semantic tape-cache restoration remains supported.
- Completes the fixed-shape matrix-AD contract and adds recording guards that
  always abort an interrupted CppAD recording before control returns to R.
- Clarifies that a tape is evaluated by one thread at a time and strengthens
  matrix, subgraph, branch-derivative, cache-tamper, and pointer-lifetime tests.
- This is a breaking lifecycle release for code that accessed `$tape_ptr` or
  `$program_ptr` directly. Such code must use the documented model methods.

# LibeRtAD 0.7.13

- Adds a public, serializable fixed-shape matrix IR and `ADMatrixModel` wrapper
  for guarded differentiable matrix multiplication, solves, Cholesky/logdet,
  matrix exponential, rank updates, quadratic forms, and intrinsically valid
  covariance construction, including semantic tape-cache round trips.
- Publishes the final shared asynchronous task-state runtime under a new
  immutable package version after the 0.7.12 release tag.
- Hardens portable tape caches with a versioned semantic contract: source IR,
  domain/dynamic/range layout, recorded values, multiple deterministic probes,
  and finite Jacobians must agree before a cached CppAD graph is accepted.
- Adds numeric subgraph, kink-convention, cache-tamper, cache-swap, and recovery
  tests; moves GUI-only dependencies to `Suggests` and installs the complete
  CppAD GPL-2.0 alternative-license text alongside EPL-2.0.

# LibeRtAD 0.7.12

- Adopts the shared asynchronous task-state refresh improvements used across
  the ecosystem so unchanged background state does not trigger unnecessary
  full-widget updates.

# LibeRtAD 0.7.11

- Publishes the shared, configurable LibeR storage-root behavior and its
  regression coverage under a new immutable package version.
- Refreshes the benchmark GUI integration guidance and source documentation
  that had advanced on the package mirror after the 0.7.10 tag.

# LibeRtAD 0.7.10

- Streams benchmark runtime-log updates without rebuilding the full React
  workbench and adopts the shared non-fading busy-state behavior.
- Increments the htmlwidget dependency version so browsers cannot reuse a
  cached pre-asynchronous workbench bundle after upgrading.

# LibeRtAD 0.7.9

- Publishes LibeRtAD in the LibeR 0.9 research-beta compatibility set with an
  explicit engine support/evidence declaration and scheduled large-study
  provenance.
- Retains the independently validated CppAD/Eigen build used by the 0.8.3
  consolidation baseline.

# LibeRtAD 0.7.8

- Restores the established high-resolution LibeR dove artwork in the purple
  benchmark workbench and browser favicon.
- Aligns the benchmark workbench with the LibeR design system, shared
  light/dark theme preference, transparent dove branding, and visible
  keyboard focus.
- Replaces hidden narrow-screen navigation and configuration panels with
  accessible responsive drawers.

# LibeRtAD 0.7.7

- Adds measured sparse-Hessian selection with cached CppAD sparsity/coloring
  work and retains dense directional sweeps for small or dense objectives.
- Reports tape memory proxies and CppAD allocator state, with lifetime stress
  tests proving pointer finalizers release repeatedly recorded tapes.
- Expands domain/nonsmooth/high-dimensional derivative regression coverage and
  adds a reproducible, gracefully skipping LibeRtAD/TMB/CmdStan benchmark
  harness.

# LibeRtAD 0.7.6

- Adds randomized value, derivative, and conditional-expression property tests.
- Makes CppAD temporary-file handling safe in debug R builds and converts CppAD
  assertion exits into catchable R errors instead of terminating the session.
- Adds browser-level GUI startup coverage and a non-launching app return path.

# LibeRtAD 0.7.5

- Adds ecosystem compatibility metadata, continuous-integration coverage, and
  reproducible release provenance for the consolidated LibeR release.
- Retains the validated CppAD 20260000.0 and Eigen 5.0.1 numerical ABI; this is
  an integration release and deliberately does not alter tape mathematics.

# LibeRtAD 0.7.4

- Corrects CppAD conditionals whose comparison operands are fixed parameters.
  The selected AD expression is now retained instead of being collapsed to its
  value at tape-recording time. Dynamic-parameter conditions remain replayable
  without retaping. This restores exact emission gradients for categorical,
  Markov, and hidden Markov likelihoods driven by fixed observed data.

# LibeRtAD 0.7.3

- Upgrades the bundled Eigen headers from 3.4.0 to the official Eigen 5.0.1
  release, with pinned source provenance, release checksum, and installed
  Apache-2.0/MPL-2.0/MINPACK licence texts.
- Preserves exact derivatives through data-driven `ifelse()` branches when a
  comparison contains only CppAD parameters. This fixes gradients for
  categorical, Markov, and hidden Markov emissions that select a
  parameter-dependent likelihood using an observed outcome.
- Bundles CppAD's upstream Eigen scalar
  adapter directly, with pinned source provenance and installed licence texts.
- Removes the RcppEigen build dependency. A small explicit dense-vector and
  dense-matrix R bridge replaces the handful of conversions used by LibeRation.
- Exposes the bundled Eigen version and source commit through
  `ad_engine_info()` and installs the public Eigen compatibility headers for
  downstream packages using `LinkingTo: LibeRtAD`.

# LibeRtAD 0.7.2

- Installs the complete bundled CppAD header tree under `include/cppad`, so
  downstream packages using `LinkingTo: LibeRtAD` can include
  `<cppad/cppad.hpp>` without a separate system CppAD installation.

# LibeRtAD 0.7.1

- Added a C++ Golub--Welsch Gauss--Hermite rule and guarded tensor-grid
  generator for deterministic marginal-likelihood integration in LibeRation,
  plus consolidated signed-weight Smolyak sparse grids with odd-linear growth.

- Replaced the archived RcppEigenAD build dependency with official CppAD
  headers, owned and versioned directly by LibeRtAD, and advanced the bundled
  release to CppAD 20260000.0.
- Added explicit CppAD version and source-commit reporting to engine metadata.
- Retained the established persistent-tape API and R-console output adapter.
- Added CppAD dynamic parameters for recorded inputs outside the active
  differentiation domain, including zero-to-nonzero updates without retaping.
- Added portable optimized-graph caches with exact CppAD provenance checks via
  `ADModel$save_tape()` and `ad_load_tape()`.
- Added automatic dense multi-direction Forward and sparse subgraph-Reverse
  Jacobian strategies with tape telemetry.
- Added exact, nested-AD-safe `chkpoint_two` ADVAN1 and 2x2 matrix prototypes.
  Benchmarks intentionally leave these outside the production path because
  their overhead exceeds direct taping for the current small kernels.

# LibeRtAD 0.6.0

- Replaced the legacy R-level AD implementation with a persistent
  RcppEigenAD/CppAD C++ engine.
- Added a serializable, validated expression intermediate representation.
- Added a light R6/external-pointer interface for values, gradients,
  Jacobians, Hessians, and combined value/gradient evaluation.
- Added conditional-expression support and strict rejection of unsupported
  runtime constructs.
- Added registered native routines and C++17 package integration for use by
  LibeRation.

This release is an architectural and API break from the 0.4.x series.
