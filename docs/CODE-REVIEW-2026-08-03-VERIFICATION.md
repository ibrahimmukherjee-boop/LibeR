# LibeR Ecosystem - Post-Fix Verification Review

- **Date:** 2026-08-03
- **Reviewer:** single-pass whole-ecosystem read-only review (no delegation, no subagents)
- **Baseline reviewed against:** `docs/CODE-REVIEW-2026-08-02.md`
- **Repository root:** `C:\Users\svdijkman.DESKTOP-4OG10M4\Documents\LibeR`
- **Repository state:** `0.9.0-research-beta.10`; fixes present as **uncommitted working-tree changes**
- **Scope of change verified:** 146 files changed (+4,196 / -9,093), plus 40 new untracked files

This document verifies, item by item, whether the findings raised on 2 August were
actually implemented, records the concrete evidence, and lists what genuinely
remains. It also flags risks created by the changes themselves.

---

## 1. Executive verdict

**All 15 P0 items are genuinely fixed** - not relabelled, not suppressed. In several
cases the implementation is stronger than what was recommended (LibeRties isolation,
LibeRtAD matrix AD, LibeRality Weibull, LibeRation covariance).

The dominant theme of the previous review - *documentation describing an
aspiration the code did not enforce* - has been addressed in the right direction:
where a claim and the code disagreed, the team overwhelmingly chose to **make the
code enforce the claim** rather than soften the claim. Governance labels that were
previously inert metadata are now real gates that raise errors.

Residual items are few, individually minor, and all are of the "known and scoped"
kind rather than the "silently wrong" kind.

**The single largest outstanding risk is not a defect in the diff: it is that this
large a change set (including a C++ translation-unit split) has not been
compile-and-test verified in this review.**

---

## 2. P0 verification - 15 / 15 fixed

| # | Package | Finding (2 Aug) | Status | Evidence |
|---|---|---|---|---|
| 1 | LibeRtAD | No `abort_recording` guard; mid-record throw poisons the thread recorder | **Fixed** | `src/ad_engine.cpp:28-40` RAII `RecordingGuard`; applied at all 7 `Independent` sites (248, 426, 437, 452, 478, 863, 872); `release()` after successful `Dependent` (261) |
| 2 | LibeRation | Covariance bread used `stats::optimHess` (finite differences) | **Fixed** | `R/diagnostics.R:911-931` native `.liberation_population_objective_hessian()`; `hessian_backend = auto/cppad/numerical`; `bread_source`/`bread_exact` recorded |
| 3 | LibeRation | Silent FD outer-gradient fallback | **Fixed** | `R/estimation.R:1109-1116` hard error unless `allow_fd_gradient=TRUE` (default FALSE); warn + count when enabled |
| 4 | LibeRties | Cancel killed by PID without create-time check (PID reuse) | **Fixed** | `R/queue.R:213` `.ls_pid_matches(pid, metadata$pid_started)` before `.ls_kill_process_tree()` |
| 5 | LibeRties | `.claimed` latch never cleared on success -> stuck jobs | **Fixed** | Cleared on cancel (`queue.R:221`) and terminal reap (`519`); stale-claim recovery loop (`360-372`) |
| 6 | LibeRties | `unwrap` accepted plaintext RDS while encryption active | **Fixed** | `R/utils.R:179-186` refuses plaintext when a storage key is configured, with migration guidance |
| 7 | LibeRties | Isolation preflight satisfiable by `touch /.dockerenv` | **Fixed** | `R/security.R:47-69` markers now return `active = FALSE` / `unattested-linux-container`; real attestation via systemd preflight |
| 8 | LibeRator | `residual = TRUE` did not affect attainment (IPRED preferred) | **Fixed** | `R/regimen.R:492` `endpoint_value_column <- if (residual) "DV" else "IPRED"`, threaded through every evaluation (510-551, 723) |
| 9 | LibeRator | MAP/Laplace draws presented as a "posterior" | **Fixed** | `R/regimen.R:788-798` `interval_type = "pointwise_conditional_prediction_interval"`; `population_parameter_uncertainty = FALSE`; explicit "not a full Bayesian posterior predictive interval" |
| 10 | LibeRator | MIC resolved with `max()` over the interval | **Fixed** | `R/endpoints.R:969-983` time-aligned `.lator_endpoint_covariate(patient, var, time)`; pointwise `value / mic`; hard error when unresolved |
| 11 | LibeRator | Default covariate policy silently LOCF-filled missing values | **Fixed** | `R/covariates.R:176` default is now `list(method = "none")`; scheduled-missing rows raise explicit warnings |
| 12 | LibeRality | Allocation optimiser always used D-optimal sensitivity | **Fixed** | `R/optimise.R:143-185` criterion-specific directional derivatives for D/A/c/prediction_variance/L/Ds; hard error for unsupported criteria |
| 13 | LibeRality | TTE FIM used `lambda*delta`, simulation used `lambda` | **Fixed** | Both now call `.lity_tte_interval_exposure()` (`information.R:232`, `simulation.R:34`) |
| 14 | LibeRality | Weibull accepted in the API but ignored in the FIM | **Fixed** | `R/information.R:173-187` true cumulative-hazard increment `(t+delta)^shape - t^shape`, reducing to the exponential case at shape 1 |
| 15 | LibeRary | Deterministic consistency gate did not block synthesis | **Fixed** | `R/ingest-deliberative.R:994-1033` synthesis skipped entirely; returns review-only stub with `synthesis_skipped = TRUE`; plus new `.library_synthesis_binding_checks()` quarantine (727-, 1082) |

---

## 3. P1 verification - claim/enforcement alignment

| Item | Status | Evidence |
|---|---|---|
| Truth-in-labeling pass | **Done** | Support matrix, DESCRIPTIONs, READMEs and vignettes revised across all six packages |
| `ARCHITECTURE.md` model-contract drift (v3 vs v4) | **Fixed** | `docs/ARCHITECTURE.md:311,317` now `liberation.model/4` / "Model contract v4" |
| Surface gradient/covariance provenance in `summary(fit)` and GUI | **Fixed** | `diagnostics.R:1951-1974` `derivative_provenance` (gradient_class, bread_source, bread_exact) printed; `gui.R:712-726` exposes gradient class and fallback count |
| `nm_objective` "no finite differences" over-claim | **Fixed** | `R/objective.R:1-8` scoped to "a valid smooth tape path" and explicitly excludes outer marginal estimation, conditional-mode sensitivity, and the covariance bread |
| ADVAN14 labelled as externally validated | **Fixed** | `support-matrix.csv` = `verified`, with "external NONMEM 7.3 lacks ADVAN14" and independent SciML Rodas5P agreement |
| DESCRIPTION LibeRtAD floor vs `compatibility.json` | **Fixed** | Both now `0.7.13` |
| LibeRtAD `thread_state` over-claim | **Fixed** | `ad_engine.cpp:892` "single-threaded evaluation per tape; use independent tape instances per worker" |
| LibeRtAD "matrix operations" over-claim | **Fixed by implementing** | New `R/matrix-ad.R` (611 lines) + `ADMatrixModel`, tests, vignette: fixed-shape matrix IR with matmul, Cholesky, triangular/SPD solve, logdet, Pade matrix-exp, shape guards, and an honest `path` field naming the `fixed-no-pivot` route |
| LibeRator `qualified` status was an inert label | **Fixed** | `R/endpoints.R:9-27` hard error unless `qualification_attestation` (issuer, reviewer, reviewed_at, evidence, scope) **and** `research_acknowledged = TRUE` |
| LibeRality `model_average` mislabel | **Fixed** | `criterion-guidance.R:139-147` renamed "Scenario-averaged information criterion"; explicit "It is not structural-model averaging" |
| LibeRality simulation `coverage` over-claim | **Fixed by implementing** | `simulation.R:351-368` real empirical CI coverage with `coverage_available` and `coverage_reason` |
| LibeRality FIM approximation configurability | **Fixed** | `approximation = full_gaussian / fo_block` exposed and documented; `diagnostics$method` names the convention used |
| LibeRality `bayesian` vs `robust` alias | **Documented** | `criteria.R:43-48` explains identical computation and differing interpretation |
| LibeRary inferred OMEGA scale from prose | **Fixed** | `ingest-catalog.R:54-56` "Never infer a variability scale from magnitude or prose"; only schema-declared `reported_metric` converted; `reported_metric` is a required schema enum |
| LibeRary fabricated WT/AGE in qualification smoke | **Fixed** | `library-api.R:181-189` requires publication-grounded covariates; blocks with `qualification_covariates_unavailable` |
| LibeRary `max_gap_rounds` default of 1 | **Fixed** | Default now 2 (`constants.R:87`, clamped 0-3) |
| LibeRary brittle chromote scrape | **Addressed** | New `ingest_manual_inbox_requests()` manual-inbox path |
| LibeRties `jobs:write` checked after decode | **Fixed** | `remote.R:159-160` scope authenticated **before** `ls_job_decode()` |
| LibeRties weak admin token / no lockout | **Fixed** | `admin.R:78-79` minimum 32 chars; `admin.R:428-455` 5-failure / 60-second lockout, constant-time compare, idle tracking |
| LibeRties soft, poll-only resource limits | **Fixed** | New `R/systemd.R` + `inst/systemd/`: transient units with `MemoryMax`, `MemorySwapMax=0`, `CPUQuota=100%*n_cores`, `TasksMax`, wall-time, `NoNewPrivileges`, emptied `CapabilityBoundingSet`, `ProtectSystem=strict`, `ProtectHome=tmpfs`, `PrivateTmp`, dynamic identity |
| CI did not gate on NOTEs | **Fixed** | `tools/ci-check.R:97-139` allowlist-driven; fails on "unexplained NOTE(s)" |
| Windows at-rest permissions gap | **Fixed** | `tools/shared/liber-durability.R:17-96` `icacls`-based owner/SYSTEM/Administrators ACL, with `LibeR.strict_windows_acl` to make failure fatal |

---

## 4. P2 verification - structure, tests, maintainability

| Item | Status | Evidence |
|---|---|---|
| Split the 9,391-line `pk_engine.cpp` | **Done** | Now 952 lines + six seam-aligned `.ipp` units (event_advan 1247, differential_systems 703, ad_propagation 1685, likelihood 2416, population 1614, state_space 856); all six wired via `#include` |
| Package-local FOCEI/Laplace recovery test | **Done** | `test-estimation.R:14-24` recovers an analytic population fixture to `tolerance = 0.08` |
| Numeric assertion on subgraph Jacobian | **Done** | `test-engine.R` asserts an exact 128x32 expected matrix |
| Kink/Hessian tests for `abs`/`ifelse` | **Done** | New test with explicit "branch derivative, not a smoothness claim" wording |
| LibeRtAD GUI deps in `Imports` | **Done** | Moved to `Suggests`; only `Rcpp` remains an Import |
| Install GPL-2.0 text for CppAD dual licence | **Done** | `inst/LICENSES/GPL-2.0.txt` |
| Submit idempotency keys | **Done** | `liberties.idempotency` records; `Idempotency-Key` header honoured (`remote.R:161`) |
| Documentation coverage | **Verified clean** | 0 undocumented exports in all six packages (alias-resolved) |
| New: covariance repair | **Added, well-designed** | `R/covariance-repair.R` GMW modified Cholesky + PSD projection; `method` defaults to `"none"`, errors on indefiniteness, warns on material repair, returns auditable diagnostics |

---

## 5. Residual and partial items

These are the honest remainders. None is a silent-wrongness defect.

### Medium

1. **LibeRtAD pointer ownership still public.** `program_ptr` and `tape_ptr` remain public R6 fields (`R/ad-model.R:27-34`). A user can still null, swap, or attempt to serialise them and break GC ownership. Recommendation stands: make them private or active-binding.

2. **LibeRation ADDL expansion still lives in R.** `R/data.R:6 .nm_expand_addl()` expands ADDL and sorts events in R; C++ treats `ADDL` only as a structure key (`pk_engine_likelihood.ipp:47`). Any path that bypasses `nm_dataset(expand_addl = TRUE)`, or orders events differently, can still diverge from NONMEM. Unchanged from the previous review.

3. **LibeRary same-model dual-lane is still the default.** `require_independent_extraction_models` defaults to `FALSE` (`constants.R:107`), so text and vision lanes may share a provider/model unless the operator opts in. It is now enforced when enabled (`ingest-dual.R:565`) and exposed in the GUI job parameters, but "independent" remains opt-in.

### Low

4. **LibeRator covariate staleness is still tolerated.** `.lator_endpoint_covariate()` defaults to `max_age = Inf` (`endpoints.R:616-617`), and the beta-lactam path hardcodes `max_age = Inf`. Unresolved values now hard-error, but an arbitrarily stale MIC is still accepted without complaint.

5. **Marginal-method covariance still uses `optimHess`.** `marginal <- fit$method %in% c("GQ","IMP","SAEM")` (`diagnostics.R:842`) excludes those methods from the native Hessian. This is disclosed via `bread_source`, and is defensible for Monte-Carlo/quadrature objectives, but the "exact CppAD Hessian" statement does not cover them.

6. **LibeRality default approximation is not the validated one.** `full_gaussian` remains the default while the PopED/PFIM parity evidence is for `fo_block`. The convention is now named in `diagnostics$method`, but there is no active warning when a user compares against an external engine without switching.

---

## 6. Risks created by this change set

1. **Nothing here has been compiled or tested as part of this review.** 146 changed files, six new C++ include units, a new `population_objective_api` translation unit, a new matrix-AD frontend, and a new systemd executor. Static reading cannot confirm the build. **This is the top priority before anything else.**

2. **The fixes are uncommitted and unversioned.** All six package versions are unchanged (LibeRtAD 0.7.13, LibeRation 0.9.8, LibeRties 0.7.7, LibeRary 0.7.11, LibeRator 0.3.5, LibeRality 0.2.12) and `ecosystem.json` still declares `0.9.0-research-beta.10`. The published compatibility contract therefore does **not** yet describe this behaviour. Behaviour-changing fixes - notably `allow_fd_gradient = FALSE` and the `qualified`-endpoint attestation gate - are **breaking changes** for existing callers and need version bumps and NEWS entries before release.

3. **Several fixes deliberately convert silent degradation into hard errors.** That is correct, but it means previously "working" user scripts will now fail: non-finite gradients, `status = "qualified"` endpoints without attestation, plaintext LibeRties records under an active storage key, indefinite covariance without an explicit repair method, and unsupported allocation criteria. These need to be prominent in release notes.

4. **`.ipp` split is organisational, not a compilation-unit split.** The six files are `#include`d into `pk_engine.cpp`, so they still compile as one translation unit. Maintainability improves; compile time and blast radius do not.

---

## 7. Recommended next steps, in order

1. **Build and test everything.** `Rscript tools/ci-check.R` (all six packages, `--as-cran`, now NOTE-gated), then `Rscript tools/integration-check.R`. This is the gate that this review cannot substitute for.
2. **Re-run the affected validation campaigns**, since numerics changed: `validation/estimation-methods/`, `validation/liberality/external/` (PopED/PFIM, and confirm the TTE/Weibull changes did not move the continuous-FO baselines), `validation/liberation/run-covariance-repair-smoke.R`, and the new `validation/libertad/` and `validation/liberties/deployment/` suites.
3. **Bump versions, update `ecosystem.json`, and write NEWS entries** that call out the breaking behaviour changes listed in section 6.3.
4. **Close the four Medium/Low residuals** in section 5 - the cheapest meaningful wins are making the LibeRtAD pointers private and defaulting `require_independent_extraction_models` to `TRUE`.
5. **Decide the ADDL question explicitly**: either move expansion into the C++ event engine or document it permanently as an R-side preprocessing contract with a parity test against NONMEM-generated tables.

---

## 8. Overall assessment

The remediation is thorough, honest, and in several places exceeds what was asked.
The team consistently chose the harder and more correct option: implementing matrix
AD rather than deleting the claim; implementing a native Hessian rather than
documenting the finite-difference one; implementing real coverage rather than
removing the word; making container markers *fail* attestation rather than
loosening the check; and converting inert governance labels into enforced gates.

The ecosystem's stated philosophy - that a defect must not be able to hide behind
agreement between two paths, and that missing evidence is never converted into a
pass - is now visibly encoded in the code itself rather than only in its
documentation. Subject to a clean build, test, and validation run, this change set
materially closes the gap between what LibeR claims and what it enforces.
