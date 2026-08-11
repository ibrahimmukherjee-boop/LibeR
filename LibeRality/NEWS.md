# LibeRality 0.3.1

- Reuses bounded, guarded LibeRation prediction plans across repeated design
  evaluations instead of recording the same CppAD prediction tape on every
  optimizer visit. Cache hits, misses, and automatic retapes are reported in
  information diagnostics; numerical information remains unchanged.
- Accumulates endpoint/stratum/arm Fisher-information blocks and matrix
  diagnostics in one native Eigen pass. Pure allocation optimisation records
  each fixed arm once per scenario and subsequently reweights those matrices
  instead of rebuilding prediction tapes at every allocation update.
- Makes the externally cross-validated FO block-diagonal information
  approximation the default for new designs. `full_gaussian` remains an
  explicit supported alternative.
- Advances the serializable design schema to version 2 and deterministically
  migrates legacy saved designs to `fo_block`, preventing a silent change of
  their historical interpretation.
- Retains criterion-specific allocation derivatives, fixed-shape Weibull TTE
  information, matched simulation/FIM exposure conventions, and genuine
  estimator-interval coverage diagnostics.
- Records the active approximation in information, evaluation, history, and
  external-validation provenance.

# LibeRality 0.2.12

- Adds fixed-shape Weibull time-to-event working information and simulation
  using matched cumulative-hazard interval increments. The endpoint contract
  explicitly uses `H(t) = lambda * t^shape` and requires the shape value.
- Adds a regulatory-informed first-in-human single-ascending-dose wizard
  template with five editable active-dose cohorts, rich PK sampling, explicit
  escalation order, and retained sentinel/placebo/review-gate planning
  metadata. Compound-specific starting-dose justification, safety limits,
  placebo implementation, stopping rules, and escalation governance remain
  deliberately outside the automatic template.
- Uses criterion-specific allocation sensitivities for D, Ds, A, E, c,
  prediction-variance, and L optimality instead of routing non-D criteria
  through a D-optimal allocation update. Unsupported or non-smooth cases fail
  explicitly.
- Replaces ordinal and supported residual-model finite differences with
  analytic derivatives, adds a default analytic one-compartment FIM regression,
  and reports empirical estimator-interval coverage only when covariance
  estimates are actually available.

# LibeRality 0.2.11

- Adds simulated endpoint profiles and tabular summaries to the Simulation tab,
  including native LibeRation NCA exposure summaries where scientifically
  applicable.
- Marks Robustness complete after all configured scenario information has been
  evaluated and makes feasibility results clickable with plain-language rule,
  observed-value, limit, and violation details.

# LibeRality 0.2.10

- Consolidates the workflow progress row and content tabs into one navigation
  row. Model, trial-design, objective, evaluation, optimisation, and simulation
  tabs now carry their numbered or completed stage indicator directly.
- Uses `#B87333` for the dark-theme active-tab underline and completed workflow
  circles; completed stages retain white checkmarks for clear status contrast.

# LibeRality 0.2.9

- Uses the same warm mineral-slate header in light and dark themes, with
  explicit high-contrast header text. Primary study-design controls now use
  the selected-arm copper as their button surface and the sidebar surface as
  their text colour.
- Extends the design wizard with regulatory-informed starting layouts for
  standard 2×2 bioequivalence, full-replicate RSABE, food-effect, fixed-sequence
  DDI, TQT, concentration-QTc, renal-impairment, and hepatic-impairment studies.
  Each template states its framework and compound/protocol-specific limitations
  and remains an editable design—not a claim of regulatory adequacy.
- Adds persistent, immutable design histories under the shared LibeR
  workspace. The GUI groups current and previous designs with sequential
  versions, exposes unsaved-change state, and requires the user to save or
  explicitly discard edits before switching.
- Keeps portable RDS import/export separate from the workspace-backed design
  history, and exports `lity_design_history()`, `lity_design_version_save()`,
  and `lity_design_version_load()` for scripted reproducibility.

# LibeRality 0.2.8

- Aligns the application header with the selected-arm accent surface and uses
  the warmer copper active-tab colour for primary study-design actions.
- Labels direct `$PRED` models by their actual execution route rather than
  exposing the inert ADVAN1/TRANS1 compatibility fields retained by the shared
  model schema.
- Adds classical ED-optimality, maximizing the expected determinant over
  weighted parameter scenarios using a stable `log E[det(F)]` calculation,
  with full criterion guidance in the GUI.
- Adds a guided trial-design wizard with editable templates for rich
  single-dose PK, staggered sparse population PK, repeated-dose steady state,
  parallel dose-ranging, infusion, paediatric sparse, and exposure-response
  studies. Templates produce the ordinary serializable `lity_design` object.
- Adds an editable model workspace for `$PK`, direct/post-ADVAN `$PRED`, `$DES`,
  `$ERROR`, THETA values and bounds, OMEGA, and SIGMA. Rebuilding and
  validation are delegated to LibeRation's shared `nm_model_update()` API.
- Replaces free-text endpoint link and distribution fields with
  outcome-specific selections and validates the same choices in the R API.

# LibeRality 0.2.7

- Redesigns the workbench around a visible Model → Trial design → Objectives →
  Evaluate → Optimise → Simulate workflow, with contextual actions and
  automatic navigation to newly completed results.
- Adds complete GUI editors for design identity, arms, endpoints, uncertainty
  scenarios, optimisable variables, and typed constraints, including
  confirmation for destructive changes and stale-result invalidation.
- Groups all 29 supported design criteria by purpose, shows a one-line
  explanation in the selector, and adds a `?` dialog covering the statistical
  construction, prerequisites, strengths, limitations, and use cases of every
  criterion.
- Replaces the amber workbench with the Mineral Slate and Copper palette,
  including accessible light/dark surfaces, a restrained copper action colour,
  slate headers, and responsive workflow controls.
- Adds explicit simulation seeds, clearer optimiser names and run summaries,
  deployment-aware file-path warnings, and richer design/reproducibility
  inspection.

# LibeRality 0.2.6

- Adds a unified model browser for built-in LibeRation templates, existing
  LibeRation project versions and completed estimation runs, reviewed
  LibeRary entries, and local NONMEM control streams.
- Adds a dedicated Model tab with compartment structure, outcomes, nominal
  parameters, parameter-source semantics, and immutable import provenance.
- Lazily resolves full workspace and catalogue models only when previewed;
  model changes remap compatible schedules, request missing design covariates,
  clear dimension-dependent results, and retain an auditable revision history.
- Adds `lity_model_from_liberation()` and fixes review-status handling in the
  LibeRary importer.
- Uses a lighter amber application header in the light theme with
  high-contrast branding. The dark theme uses a warmer amber header and
  reserves the lighter primary-action amber for the active theme-switch rail.
- Advances the browser asset identifier so an upgraded installation cannot
  reuse the former header stylesheet from cache.

# LibeRality 0.2.5

- Applies the ecosystem-wide non-fading busy-state behavior while retaining
  the existing asynchronous design-analysis task channel.
- Increments the workbench asset version to invalidate cached GUI resources
  after upgrading.

# LibeRality 0.2.4

- Removes generated native build products from the standalone source mirror
  and adds cross-platform publication safeguards after Linux deployment
  exposed an incompatible Windows object file.

# LibeRality 0.2.3

- Publishes LibeRality in the LibeR 0.9 research-beta compatibility set with
  PopED/PFIM-matched capabilities separated from internally verified advanced
  design criteria.

# LibeRality 0.2.2

- Restores the established high-resolution LibeR dove and aligns the workbench
  header, typography, controls, panels, and spacing with the shared shell.
- Adds the shared LibeR theme preference, accessible focus-managed dialogs,
  consistent keyboard focus, and a transparent amber dove asset.

# LibeRality 0.2.1

- Expands analytic information-matrix and design-criterion regression coverage
  and runs all maintained PopED/PFIM external-validation fixtures repeatedly.
- Adds a runnable example and browser-level workbench startup coverage.

# LibeRality 0.2.0

- Adds a public typed-contract restore boundary for safe LibeRties result
  decoding, including Pareto optimisation results.
- Aligns package compatibility, continuous integration, validation gates,
  citation, and release provenance with the consolidated ecosystem release.

# LibeRality 0.1.3

- Allows the GUI to return its Shiny application object for hosted deployment.

# LibeRality 0.1.2

- Replaces the RcppEigen dependency with the direct Eigen 5.0.1 interface
  exported by LibeRtAD. Expected-information assembly now shares the same
  pinned C++ linear-algebra implementation as LibeRation.
- Replaces the provisional workbench mark with the high-resolution,
  transparent LibeR dove, recoloured in LibeRality's warm amber design palette
  and shared by the browser favicon and application header.
- Extends the ecosystem favicon build pipeline with a reproducible LibeRality
  amber variant.

# LibeRality 0.1.1

- Adds executable, versioned external validation against PopED 0.7.0 and PFIM
  7.0.3 using complete Fisher matrices, RSEs, determinants, matched D-optimal
  searches, and cold/warm runtime benchmarks.
- Adds the explicit `fo_block` information convention used for interoperable
  PopED/PFIM comparisons while retaining the fuller Gaussian convention as the
  default.
- Adds permanent fixtures, dependency/runner scripts, machine-readable result
  artifacts, tests, an HTML report, and a reproducibility vignette.

# LibeRality 0.1.0

- Introduces the complete serialisable optimal-design object model.
- Adds population expected-information calculations backed by exact
  LibeRation prediction derivatives and an Eigen C++ assembler.
- Implements local, robust, Bayesian, discrimination, power, clinical-decision,
  cost, burden, compound, constrained, and Pareto criteria.
- Adds continuous, discrete, integer, allocation, and hybrid optimisation.
- Adds complete-trial simulation, operating characteristics, reports,
  LibeRary/LibeRation/LibeRator adapters, and LibeRties queue execution.
- Adds the React optimal-design workbench with persistent light/dark theme.
