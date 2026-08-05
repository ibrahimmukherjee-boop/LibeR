# LibeR Ecosystem - Third Review (Residual Closure Verification)

- **Date:** 2026-08-03 (evening)
- **Reviewer:** single-pass whole-ecosystem read-only review (no delegation)
- **Reviewed against:** `docs/CODE-REVIEW-2026-08-03-VERIFICATION.md` (this morning) and
  `docs/CODE-REVIEW-2026-08-02.md` (original)
- **Repository state:** `0.9.0-research-beta.12`, all package work **committed**; working
  tree clean apart from untracked generated reference manuals

## 1. Verdict

**Five of the six residual findings are closed, and both outstanding action items are
done.** The remaining item is the one I had already classified as defensible by design.

More importantly, the two things I said this review could not substitute for -
compiling and validating - have now been evidenced in-repo, and the critical
regression check passed.

There are no new defects. No `FIXME`/`HACK`/`XXX`/`WIP` markers exist anywhere in the
six packages' R or C++ sources.

## 2. Release state

| Package | 2 Aug | Now |
|---|---|---|
| LibeRtAD | 0.7.13 | **0.8.1** |
| LibeRation | 0.9.8 | **0.10.1** |
| LibeRties | 0.7.7 | **0.8.0** |
| LibeRary | 0.7.11 | **0.8.0** |
| LibeRator | 0.3.5 | **0.4.0** |
| LibeRality | 0.2.12 | **0.3.0** |

`ecosystem.json` advanced to `0.9.0-research-beta.12`. Minor/major bumps correctly
signal the breaking behaviour changes, and each `NEWS.md` documents them with
migration guidance.

## 3. Residual closure - 5 of 6

| # | Residual (this morning) | Status | Evidence |
|---|---|---|---|
| 1 | LibeRtAD `program_ptr`/`tape_ptr` public | **Closed** | Now `private$program_ptr_` / `private$tape_ptr_` (`R/ad-model.R:296-297` declarations; all access via `private$`). NEWS: callers may inspect `has_tape()` but "can no longer replace, null, or serialize raw external pointers" |
| 2 | LibeRation ADDL expansion only in R | **Closed** | C++ now calls `liberation::require_materialized_addl(data)` at every native entry point (`pk_engine.cpp:64,76,88,100,117,157,217,231,...`); guard **hard-errors**: "Native execution requires ADDL/II doses to be materialized by `nm_dataset()`; a non-zero or invalid ADDL value reached C++." |
| 3 | LibeRary same-model dual-lane default | **Closed** | `independence_policy <- cfg$llm$extraction_independence %||% "required"` (`ingest-dual.R:569`); same-model pairing **stops before extraction** unless `preferred`/`off` chosen. Legacy boolean migrated deterministically (`TRUE`->`required`, `FALSE`->`preferred`); preferred same-model runs are review-only, not publishable |
| 4 | LibeRator MIC staleness tolerated (`max_age = Inf`) | **Closed** | `mic_max_age` is now a validated endpoint rule defaulting to **168 h** (`endpoints.R:164,184,197,396`). NEWS: a stale-evidence override "requires an actor and reason and is retained in the assessment audit record"; GUI exposes endpoint-specific MIC freshness |
| 5 | LibeRality default was `full_gaussian`, not the validated `fo_block` | **Closed** | `lity_design(information_approximation = c("fo_block", "full_gaussian"))` (`design.R:335`); `lity_information()` resolves `design$information_approximation %||% "fo_block"` (`information.R:392`). Design schema advanced to v2 with deterministic migration of legacy designs to `fo_block` (`design.R:374-379`), avoiding silent reinterpretation |
| 6 | GQ/IMP/SAEM covariance still uses `optimHess` | **Open (by design)** | `marginal <- fit$method %in% c("GQ","IMP","SAEM")` still excluded from the native Hessian (`diagnostics.R:904,973`). Disclosed via `bread_source`; defensible for Monte-Carlo/quadrature objectives |

Note on #5: the internal helper `.lity_endpoint_information()` still lists
`c("full_gaussian", "fo_block")` in its signature, but it is always invoked with an
explicit value resolved by `lity_information()`, so the argument order is inert. I
checked this specifically because the NEWS entry and the signature appeared to
disagree; they do not.

## 4. Action items - both discharged

### 4.1 Build and validation evidence

Previously I flagged that a 146-file change set including a C++ split had not been
compiled or tested. There is now direct evidence of both:

- **Compilation exercised.** LibeRtAD 0.8.1 exists specifically because a real
  toolchain defect was found and fixed: "Routes CppAD value-graph `printf`
  diagnostics through R's console adapter, preventing GCC from linking direct
  `puts`/`putchar` calls into LibeRtAD or downstream engine packages." That is a
  CRAN-compliance issue only discoverable by building, and LibeRation 0.10.1 was
  released solely to raise its LibeRtAD floor to 0.8.1.
- **PopED/PFIM external validation re-run and passed** -
  `validation/liberality/external/results/post-review-20260803/` (`"passed": true`).
  This was the critical regression check, because the default approximation changed
  to `fo_block` and the TTE/Weibull information was reworked:

  | Fixture | vs PopED (max abs / Frobenius rel) | vs PFIM |
  |---|---|---|
  | oral_proportional | 3.23e-06 / 1.42e-11 | 3.40e-07 / 1.44e-12 |
  | bolus_additive | 1.07e-07 / 3.66e-11 | 1.60e-09 / 5.34e-13 |
  | oral_combined | 1.88e-06 / 1.52e-11 | recorded "not supported by common convention" |

  Continuous-FO parity is preserved at the same publication grade as before, and the
  PFIM `Combined1` convention limitation is still honestly recorded as *not-run*
  rather than converted into a pass.
- **New systemd deployment campaigns run and passed** -
  `validation/liberties/deployment/results/post-review-systemd-{smoke,concurrency}.json`
  (both `"passed": true`), with genuinely measured attestation:
  `os_isolation_active: true`, provider `systemd-transient-service`, evidence
  `pid1=systemd`, `cgroup_v2=TRUE`, `service_user`, `manager=user`,
  `worker_slice=liberties-workers.slice`, live transient sandbox completed,
  `issues: []`. The concurrency run correctly capped 8 queued jobs at
  `maximum_running: 2` for 2-core jobs under a 4-worker slice.

  This is exactly the substantive replacement for the forgeable `/.dockerenv` probe.
- Two new campaign directories now exist: `validation/liberation/` and
  `validation/libertad/`.

### 4.2 Versions, contracts, and breaking-change documentation

All six packages bumped and committed; `ecosystem.json` at beta.12; NEWS entries
explicitly describe the behaviour changes that will break existing callers - default
no-imputation covariates, attestation-gated `qualified` endpoints, fail-closed
plaintext queue records, disabled silent FD gradient recovery, and required
independent extraction models with a documented legacy migration.

## 5. Improvements beyond my findings

- **LibeRation**: compiled engine pointer made read-only; all engine input routed
  through one canonical ADDL materializer.
- **LibeRties**: credential-mounted encrypted storage and network isolation added to
  the systemd executor; administrative audit journalling strengthened; reproducible
  WSL/Linux smoke and concurrent multi-core queue campaigns added.
- **LibeRator**: stale-evidence overrides require an actor and reason and are audited;
  MIC freshness surfaced per endpoint in the GUI and propagated through combined
  endpoint assessments.
- **LibeRality**: active approximation now recorded in information, evaluation,
  history, and external-validation provenance.
- **LibeRary**: independence policy, model comparison, gate result, and warnings
  persisted into decision, assessment, and audit provenance.

## 6. Remaining observations

None are defects; all are scoped and disclosed.

1. **GQ/IMP/SAEM covariance remains numerical** (`optimHess`). Disclosed via
   `bread_source`. Reasonable for stochastic/quadrature objectives; worth a short note
   in the covariance documentation stating that the exact-Hessian guarantee covers
   FO/FOCE/FOCEI/Laplace only.
2. **Live worker logs are plaintext until terminal.** Now surfaced honestly in the
   preflight output ("Live logs are plaintext while a worker runs and are encrypted
   when it becomes terminal"). Acceptable, but it is the one at-rest window that
   remains open on an otherwise encrypted path.
3. **The `.ipp` split is organisational, not a translation-unit split.** The six files
   are `#include`d into `pk_engine.cpp`. Maintainability improved; compile time and
   blast radius unchanged.
4. **Generated reference manuals are untracked** in `docs/manuals/` (including both
   0.10.0 and 0.10.1, 0.8.0 and 0.8.1 variants). Cosmetic; decide whether they belong
   in version control or in the ignore list.
5. **Cross-platform `R CMD check` results are not visible in-repo.** The systemd
   campaigns necessarily ran on Linux/WSL. Confirming the Windows and macOS legs of the
   GitHub Actions matrix for beta.12 would complete the picture.

## 7. Assessment

This round closes the review loop properly. The residuals were not merely patched -
each was resolved in the stronger direction: pointers became private lifecycle state
rather than merely documented; ADDL became a fail-closed native precondition rather
than a moved responsibility; independent extraction models became the enforced
default with a deterministic legacy migration; MIC staleness gained a finite default
plus an audited override; and the validated FO convention became the default with
schema-versioned migration so historical designs are not silently reinterpreted.

Critically, the change set is now evidenced rather than asserted: a real build defect
was found and fixed, external PopED/PFIM parity was re-established after the
numerics changed, and OS isolation is now demonstrated by measurement instead of by
marker files. Combined with the version bumps and honest NEWS entries, beta.12 is a
materially more trustworthy release than beta.10, and the gap between what LibeR
claims and what it enforces is now small and explicitly documented.
