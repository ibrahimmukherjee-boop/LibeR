# LibeR Ecosystem — Independent Code Review & Fix Work Order

- **Date:** 2026-08-02
- **Repository baseline:** `0.9.0-research-beta.10` (`ecosystem.json`)
- **Repository root:** `C:\Users\svdijkman.DESKTOP-4OG10M4\Documents\LibeR`
- **Packages reviewed:** LibeRtAD 0.7.13, LibeRation 0.9.8, LibeRties 0.7.7, LibeRary 0.7.11, LibeRator 0.3.5, LibeRality 0.2.12
- **Nature:** Read-only review. No code was changed. This document is a work order for an implementing agent (GPT-5.6 Sol) to plan and apply fixes.

This document contains:

1. **Section 0** — how the implementing agent should use this document (context, build/test/validate, verification protocol, guardrails).
2. **Section 1** — executive cross-package synthesis.
3. **Section 2** — consolidated, prioritized fix checklist (P0/P1/P2) with `file:line` pointers.
4. **Section 3** — the six detailed per-package reports, verbatim.
5. **Appendix A** — cross-cutting findings from the lead reviewer (ecosystem-level).

---

## 0. Instructions for the implementing agent

You are implementing fixes for the findings below. Work package-by-package, P0 first.

### 0.1 Verification protocol (read before editing)

- **Line numbers may have drifted.** Every finding cites `file:line` as of this review. Before changing anything, open the cited file, locate the described construct by content (not by line number alone), and confirm the finding still holds. If a finding no longer applies, record that and move on.
- **Reproduce before you fix.** For correctness bugs (P0), write a failing test or a minimal reproduction that demonstrates the defect first, then fix, then show the test passing.
- **Preserve the project's honesty philosophy.** A recurring theme in this review is that documentation over-claims relative to enforced behaviour. Do **not** fix a "claim vs code" gap by making the claim louder; fix it by either (a) making the code enforce the claim, or (b) softening the claim to match the code and marking the capability with the correct `support-matrix.csv` tier (`validated` / `verified` / `experimental`).
- **Do not weaken tests or tolerances** to make things pass. If a numerical tolerance must change, justify it.
- **Keep changes minimal and reversible.** Prefer the smallest change that resolves the finding. Avoid opportunistic refactors except where a P2 item explicitly asks for one.

### 0.2 Build / rebuild

Dependency (install) order — LibeRtAD is the foundation:

```text
R CMD INSTALL LibeRtAD
R CMD INSTALL LibeRation
R CMD INSTALL LibeRary
R CMD INSTALL LibeRator
R CMD INSTALL LibeRality
R CMD INSTALL LibeRties
```

- Exact local dev stack: `Rscript tools/install-local-stack.R`
- During development, `pkgload::load_all("LibeRtAD")` (etc.) recompiles changed C++ without a full install. When you change LibeRtAD C++/headers, dependents that `LinkingTo` it (LibeRation, LibeRality) must be rebuilt.
- Windows toolchain is Rtools45 + C++17. `tools/ci-check.R` sets `R_MAKEVARS_USER` to `tools/Makevars.rtools45` automatically; replicate that if building by hand.

### 0.3 Test

- Full CI gate (all packages, `R CMD check --as-cran`, fails on errors/warnings, plus hygiene/contract/installer gates): `Rscript tools/ci-check.R`
- Cross-package contracts: `Rscript tools/integration-check.R`
- Per package: `Rscript -e "pkgload::load_all('LibeRation'); testthat::test_local('LibeRation')"` (or `testthat::test_file(...)` for one file).
- Some suites are opt-in and are otherwise skipped: browser E2E (`LIBER_RUN_BROWSER_TESTS=true` + `shinytest2`); LibeRality external engines (`_LIBERALITY_RUN_EXTERNAL_VALIDATION_=true`, needs PopED/PFIM).

### 0.4 Validate (scientific gates)

Build an isolated version-exact stack, then run the relevant campaign:

```text
Rscript tools/create-validation-library.R --source
Rscript validation/estimation-methods/run-validation.R      # 13 estimators
Rscript validation/nonpk/run-validation.R                   # categorical/count/TTE/Markov/state-space
Rscript validation/experimental-families/run-validation.R   # SDE/DDE/DAE/QSP/hybrid
Rscript validation/edge-families/run-validation.R
Rscript validation/external-comparators/run-validation.R    # KFAS/glmmTMB/hmmTMB/pomp/bssm/nlmixr2/...
Rscript tools/external-validation.R                          # LibeRality vs PopED/PFIM
Rscript validation/nonmem/run-validation.R --run            # needs PsN/NONMEM
```

After any change to numerics or inference, re-run the campaign(s) touching that area and confirm the recorded tolerances still hold. Performance results are correctness-gated (`nm_validation_gate()`); do not publish a timing that comes with different estimates.

### 0.5 Environment notes (only if running as a Cursor agent on this Windows machine)

- The Cursor `Write` tool on this machine has been observed to emit **UTF-16LE**. `Rscript` cannot parse UTF-16 and dies on the first character. Convert any scratch `.R` file you create to UTF-8 (no BOM) before running it. Robust PowerShell prefix:
  `$p="file.R"; $b=[System.IO.File]::ReadAllBytes((Resolve-Path $p)); $enc=[System.Text.Encoding]::UTF8; if ($b.Length -gt 1 -and $b[1] -eq 0) { $enc=[System.Text.Encoding]::Unicode }; $t=[System.IO.File]::ReadAllText((Resolve-Path $p),$enc); $t=$t.TrimStart([char]0xFEFF); [System.IO.File]::WriteAllText((Resolve-Path $p).Path,$t,(New-Object System.Text.UTF8Encoding($false)))`
- Some shell commands need elevated/unrestricted permissions to run outside the sandbox.
- These notes are environment-specific; ignore them if they don't apply to your toolchain.

---

## 1. Executive synthesis (cross-package)

### Bottom line

This is an unusually ambitious and, in its foundations, genuinely well-engineered ecosystem — a coherent six-package PK/PD → design → dosing → repository stack with one C++/CppAD numerical spine, real cross-package contracts, runnable independent-validation campaigns, and a serious 1.0 release plan. For a solo author (with AI assistance), the scope and quality of the core numerics are remarkable.

The single systemic problem is not the code — which is largely real and often excellent — but a consistent **gap between what the documentation claims and what the code actually enforces or validates**. Every one of the six reviews independently landed on some version of this. The good news is that most of the highest-impact remediation is *labeling, gating, and testing* work, not rewriting engines.

### The thread connecting all six packages

**1. Docs describe the aspirational surface; code enforces a narrower one.** The DESCRIPTION/README/vignette layer reads like a finished product; the `support-matrix.csv` + fit/telemetry layer is the actual truth. Concretely: LibeRtAD advertises "matrix operations in C++" (it's scalar-only) and thread-safety it doesn't have; LibeRation's "exact AD / one complete C++ numerical path / thirteen methods" coexists with silent FD gradient fallbacks, an `optimHess` (finite-difference) covariance bread, R-orchestrated SAEM/PSOCK outer loops, and admittedly incomplete IMP/GQ gradients; LibeRality's "exact CppAD sensitivities" are exact for the mean but finite-difference for much of the variance block; LibeRary's "deterministic consistency gate before synthesis" is an *ordering*, not an *enforcement*; LibeRator's "without silently inventing values" runs a default LOCF fill that does exactly that. There's even a concrete doc drift: `ARCHITECTURE.md` still says model contract v3 while `ecosystem.json` and the algorithm review say v4.

**2. "Soft gates": safety/quality flags that are written but never read.** LibeRary computes its consistency checks and then synthesizes a full model regardless (status is only *demoted*). LibeRator assigns `research_only` and endpoint `qualified` but no control-flow path ever reads them, and its `residual = TRUE` flag doesn't actually change the endpoint metric. LibeRties' production isolation preflight can be satisfied by touching `/.dockerenv`, its resource limits are poll-only, and its "encryption" still loads plaintext RDS. Across the stack, a lot of governance is advisory metadata rather than an enforced constraint.

**3. Uncertainty propagation is thinnest exactly where consequences are highest.** LibeRation's covariance uses a finite-differenced Hessian; LibeRality finite-differences much of the FIM variance derivatives; and most importantly LibeRator presents a MAP/Laplace ETA covariance as a "posterior" while excluding residual, THETA, and model uncertainty — and that under-stated uncertainty feeds *dosing* comparisons.

**4. Tests cover the machinery well but the "truth" thinly.** A large fraction of tests are smoke (`is.finite`, `maxit = 1–5`) or mock the LLM/network, and the real parameter-recovery / analytic-reference / NONMEM-parity evidence lives in `validation/` *outside* the package trees, gated behind opt-in env vars. "Finite ≠ correct." Browser E2E and external comparators are opt-in, so default CI proves far less than the validation docs describe.

### What's genuinely strong (protect this)

- A **real** CppAD population objective with tape sharing/retape telemetry, native in-C++ HMC/NUTS trajectories, and a provenance-checked graph cache.
- **Publication-grade** continuous FO Fisher-information parity with PopED and PFIM (≈1e-6 to 1e-11) under the `fo_block` convention, with checked-in baselines.
- A **substantially real** LLM literature-ingestion pipeline in LibeRary (content-addressed bundles, deliberative investigators, dual-lane reconciliation, layered machine-vs-human qualification).
- Honest engineering hygiene: a candid self-authored `ALGORITHM-REVIEW`, a frank `TODO.md`/support matrix, a layered validation philosophy ("a defect cannot hide behind agreement between two paths"; missing comparators never become a pass), solid atomic-durability/locking primitives, a 3-OS CI matrix with contract-drift and installer gates, and truthful security disclaimers (restricted subprocess ≠ sandbox).
- LibeRator's deliberate human-in-the-loop, non-autonomous UX and immutable audited evidence model; LibeRties' typed non-executable wire with server-side model revalidation.

### Per-package one-line verdict

| Package | Verdict | Top risk to address |
|---|---|---|
| LibeRtAD (§3.1) | Solid scalar IR→CppAD foundation | No `abort_recording` guard; thread-safety/matrix over-claims |
| LibeRation (§3.2) | Real C++/CppAD engine, oversold as fully-exact | FD covariance + silent FD gradient fallback vs "exact AD" |
| LibeRties (§3.3) | Carefully threat-modeled, honest disclaimers | Forgeable isolation preflight; PID-unsafe cancel; plaintext RDS |
| LibeRary (§3.4) | Pipeline is largely real, not aspirational | Consistency gate doesn't block synthesis; keyword-only retrieval |
| LibeRator (§3.5) | Careful research MIPD, real crypto/audit | Incomplete uncertainty; LOCF "inventing"; labels aren't gates |
| LibeRality (§3.6) | Excellent continuous-FO parity; edges simplified | Allocation ignores criterion; TTE FIM/sim mismatch; Weibull ignored |

### Strategic recommendation

The surface is enormous for one maintainer. The highest-leverage move for 1.0 is to **narrow the *supported* scope to the independently-validated core** (continuous FO/FOCE/FOCEI PK, D-family design, the classical outcome families) and mark everything else `experimental` in code, not just prose. Your own `ROADMAP-1.0` already gestures at this; make it decisive.

---

## 2. Consolidated prioritized fix checklist

`file:line` references are as of this review — verify before editing (see §0.1). Package tag in brackets.

### P0 — Correctness, clinical-safety, and security (do first)

- [ ] **[LibeRator]** `residual = TRUE` does not affect endpoint metrics (they prefer `IPRED`). Evaluate attainment on residualised predictions when requested, or remove/rename the flag; add tests; expose in GUI. `endpoints.R:588`; `regimen.R:384–385`.
- [ ] **[LibeRator]** Stop presenting MAP/Laplace ETA draws as a full "posterior" unless θ + residual + model uncertainty are included, or explicitly flag them as excluded with a blocking warning. `regimen.R:756–758`.
- [ ] **[LibeRator]** Fix MIC resolution: time-align MIC; never `max()` over the interval for AUC/MIC or peak/MIC. `endpoints.R:575–583`.
- [ ] **[LibeRator]** Covariate honesty: default to `method = "none"` (or require explicit policy); do not numeric-fill explicitly-missing scheduled times unless opted in; align DESCRIPTION wording. `covariates.R:176, 118–123`.
- [ ] **[LibeRation]** Replace the `stats::optimHess` covariance bread with a CppAD Hessian, or document it as approximate and default to the sandwich estimator. `diagnostics.R:900`.
- [ ] **[LibeRation]** Make the silent FD outer-gradient fallback opt-in (`allow_fd_gradient`), not automatic recovery; warn/fail when `gradient_fallbacks > 0`. `estimation.R:1036–1104`.
- [ ] **[LibeRtAD]** Wrap every `Independent…Dependent` region in `try/catch` + `CppAD::AD<double>::abort_recording()` (tape create + checkpoint helpers). Add a regression that throws mid-record and still allows a second compile. `ad_engine.cpp:228–239, 404–448`.
- [ ] **[LibeRties]** Cancel must verify `pid_started` (process create-time) before `ps_kill`, like the recovery path does — otherwise PID reuse can kill an innocent process. `queue.R:201–203` (cf. `queue.R:320–323`).
- [ ] **[LibeRties]** Fix the `.claimed` latch lifecycle: it is only cleared on start failure, so a crash after claim leaves jobs stuck `queued` forever. `queue.R:406–436`.
- [ ] **[LibeRties]** Fail closed on plaintext RDS when a storage key is configured (reject non-`liberties.encrypted-rds`). `utils.R:125–128`.
- [ ] **[LibeRties]** Harden the production isolation preflight: a bare `/.dockerenv` (or spoofable cgroup text) must not count as isolation proof. `security.R:47–61`.
- [ ] **[LibeRality]** Allocation optimisers (`multiplicative`/`fedorov_wynn`) always use D-optimal sensitivity regardless of the chosen criterion. Use criterion-specific directional derivatives or hard-reject non-D criteria. `optimise.R:167–172`.
- [ ] **[LibeRality]** Align the TTE FIM (uses λ·Δt) with simulation (uses λ), or document/simulate true waiting times. `information.R:140` vs `simulation.R:29`.
- [ ] **[LibeRality]** Weibull is accepted in the API but ignored in the FIM. Implement its use or reject the distribution. `design.R:107–129` vs `information.R`.
- [ ] **[LibeRary]** Make the consistency gate hard: when `!checks$ready`, skip synthesis or emit a review-only artifact — do not publish a full synthesized control stream as if investigation succeeded. Add a post-synthesis check that every major field binds to a ledger claim id. `ingest-deliberative.R:900–937`.

### P1 — Claim/enforcement alignment (labeling & gating)

- [ ] **[ecosystem]** Truth-in-labeling pass: reconcile every DESCRIPTION/README/vignette capability claim against `support-matrix.csv` tiers and actual fit telemetry; downgrade over-claims.
- [ ] **[docs]** Fix model-contract drift: `docs/ARCHITECTURE.md` says "model contract v3"; `ecosystem.json` and `ALGORITHM-REVIEW-1.0.md` say v4.
- [ ] **[LibeRation]** Surface provenance in `summary(fit)` and the GUI: gradient class (exact / score-incomplete / FD-fallback), objective backend (persistent-C++ vs R-orchestrated), covariance Hessian source (`optimHess` vs CppAD).
- [ ] **[LibeRation]** Correct the `nm_objective` man page claim that finite differences are not used (they are, in the estimation/covariance pipeline). `objective.R:3–5`.
- [ ] **[LibeRation]** Label ADVAN14 as not externally validated (no NONMEM 7.3 reference) wherever ADVAN1–14 is advertised.
- [ ] **[LibeRation]** Align the `DESCRIPTION` `LibeRtAD (>= 0.7.10)` floor with `compatibility.json` (0.7.13).
- [ ] **[LibeRtAD]** Soften the `thread_state` metadata and docs (single-threaded per tape); fix the "matrix operations execute in C++" claim (language is scalar-only); qualify "exact" gradients (false at kinks / NaN domains).
- [ ] **[LibeRator]** Gate `status = "qualified"` (endpoints and any clinical export) behind issuer attestation + research acknowledgement; enforce `research_only` on prints/exports/GUI watermark rather than only storing it. Currently assigned but never read for control flow.
- [ ] **[LibeRality]** Gate marketing claims for non-continuous/TTE FIM to "internally verified working approximations"; fix the `coverage` over-claim (`simulation.R:297`) and `model_average` mislabel (`criteria.R:479–484`); make the FIM approximation default configurable and warn when comparing to PopED without `fo_block`.
- [ ] **[LibeRary]** Default to (or strongly warn for) independent text/vision models when adjudication is enabled; stop inferring OMEGA metrics from prose (`ingest-catalog.R:54–62`); stop fabricating WT/AGE in the qualification smoke test (`library-api.R:108–112`).
- [ ] **[LibeRties]** Check `jobs:write` scope before decoding on `POST /v1/jobs` (`remote.R:157–160`); raise admin-token entropy and add lockout / session TTL (`admin.R:78–79`); document/enforce hard OS resource limits (cgroup v2, separate uid) in production rather than marketing soft `ps` polls as isolation.
- [ ] **[CI]** Gate on NOTEs too — `tools/ci-check.R` currently fails only on errors/warnings, but `ROADMAP-1.0` requires "no errors, warnings, or unexplained notes."
- [ ] **[security]** Document/mitigate the Windows at-rest permissions gap — `chmod 0600` is skipped on Windows in the shared durability layer. `tools/shared/liber-durability.R:19–21`.

### P2 — Structure, tests, maintainability

- [ ] **[LibeRation]** Split `src/pk_engine.cpp` (9,391 lines) along event / ADVAN / ODE-DAE-DDE / likelihood / population-objective seams.
- [ ] **[LibeRation]** Add package-local numeric-truth tests: FOCEI + Laplace parameter recovery on a small fixture; ADDL/SS/infusion ordering vs NONMEM-generated tables; estimation coverage for ADVAN5/7/8/9/10/14 (not just prediction/GUI smoke). Note ADDL expansion currently happens in R (`data.R`), not C++.
- [ ] **[LibeRtAD]** Add numeric asserts for subgraph Jacobian values; add kink/Hessian tests for `abs`/`min`/`ifelse`; validate tape-cache IR↔graph consistency; move GUI deps (shiny/reactR/htmlwidgets/callr/processx) to `Suggests` or split a GUI package; install the GPL-2.0 text alongside EPL for CppAD dual-license completeness.
- [ ] **[LibeRties]** Deduplicate limit-enforcement helpers; add submit idempotency/dedup keys; make the audit log append-only/externally mirrored; add tests for the `.claimed` stuck state, cancel PID reuse, encryption-plaintext reject, concurrent quota races, and the full HTTP authz matrix.
- [ ] **[LibeRary]** Mirror a thinner deliberative path on the vision lane (or use vision only as falsification); raise default `max_gap_rounds` or expose "not ready → force another gap round"; add ledger⊇synthesis invariant tests; replace the chromote `sleep(3)` + CSS scrape with a download-event interception or a manual-inbox UX.
- [ ] **[LibeRator]** Cap/archive assessment history (avoid unbounded encrypted patient blobs; store a model hash + registry id rather than the full model); strip/rename `ID` to opaque codes in queue payloads; add tests for TRANS/STEADY `eta` row alignment and non-PSD `eta_covariance`; document and sensitivity-test `process_scale`.
- [ ] **[LibeRality]** Add an analytic continuous-FIM regression (known 1-cmt formulas) to default CI (not only the PopED opt-in gate); replace ordinal/residual FD derivatives with analytic ones where the error model allows; implement real `coverage` in `lity_operating_characteristics` or delete the vignette claim; collapse/document the `bayesian`≡`robust` alias.

---

## 3. Detailed package reports (verbatim)

### 3.1 LibeRtAD 0.7.13

> _Reviewer summary:_ LibeRtAD 0.7.13 is a solid scalar IR→CppAD tape foundation with careful R/CppAD error bridging and good derivative/lifetime tests, but it lacks nested `jacobian_elem` operators, has no `abort_recording` guard (tape-pollution risk), overclaims thread-safety, and carries a GUI-heavy surface relative to the AD core.

# LibeRtAD 0.7.13 — Critical Read-Only Review

**Verdict:** A focused, mostly well-engineered scalar AD foundation (IR → persistent CppAD tape) with strong R↔CppAD hygiene and meaningful numerical tests. The hardest advertised areas are uneven: forward/reverse Hessian/Jacobian paths look correct, but nested-AD/`jacobian_elem` is **not** in the production IR, tape-recording exception safety is incomplete, and thread-safety claims overreach.

---

## 1. OVERVIEW

**Purpose:** Compile a restricted R-like scalar language to a serializable IR; record/evaluate persistent CppAD tapes for values, Jacobians, gradients, Hessians; expose Gauss–Hermite quadrature; ship a React/Shiny benchmark workbench.

| Metric | Value |
|--------|------|
| Version | 0.7.13 (`DESCRIPTION`) |
| Approx R LOC | **~1,670** (11 files under `R/`) |
| Approx owned C++ LOC | **~2,720** (`src/` ~2,030 + `inst/include/LibeRtAD/` ~690); excludes vendored CppAD/Eigen |
| Exported symbols | **16** exports + 2 S3 methods (`NAMESPACE`) |
| Test files | **12** `test-*.R` |
| Vignettes | 1 (`automatic-differentiation.Rmd`) |
| Man pages | 17 `.Rd` |

**Structure:** Thin R API (`ir-compiler.R`, `ad-model.R`, `quadrature.R`, `benchmark.R`) + large GUI layer (`gui*.R`, `aaa-shared-*.R`) + one real engine TU (`ad_engine.cpp`) + IR/program headers + vendored CppAD graph JSON helpers in `src/json_*.cpp` / `cpp_graph_op.cpp`.

---

## 2. ARCHITECTURE & DESIGN

### Key modules

| Layer | Path | Role |
|-------|------|------|
| IR compiler | `R/ir-compiler.R` | Parse assignments → opcode DAG |
| R6 owner | `R/ad-model.R` | Holds IR + `program_ptr` / `tape_ptr` |
| Program / tape | `inst/include/LibeRtAD/program.hpp` | IR eval + `TapeHandle` |
| Engine | `src/ad_engine.cpp` | Record, Forward/Reverse, Hessian, quadrature, checkpoints |
| Sparse Hessian | `inst/include/LibeRtAD/sparse_hessian.hpp` | Sparsity analyse + colored sparse Hessian |
| CppAD R bridge | `inst/include/LibeRtAD/cppad_r_output.hpp` | Redirect `cout`/`cerr`/`exit`; force `NDEBUG` around CppAD |
| Tape cache | `ADModel$save_tape` / `ad_load_tape` | JSON graph + CppAD commit pin |

### How it fits

```
model text → ad_ir() → libertad_ir
 ↓
 ProgramHandle (XPtr + shared_ptr<Program>)
 ↓ Independent(wrt) + dynamic params
 TapeHandle (ADFun + metadata)
 ↓ Forward(0) / Forward|Reverse / sparse_hes
 R6 ADModel methods
```

### Design strengths
- Clear split: serializable IR vs process-local pointers.
- Dynamic parameters for non-`wrt` inputs (`libertad_tape_create`).
- Provenance-gated tape cache (version + CppAD commit).

### Design concerns / inconsistencies
1. **GUI dominates the package surface** (~690 R LOC for GUI/async/paths vs ~630 for IR+ADModel+quadrature+benchmark). A “C++ AD foundation” Imports `shiny`, `reactR`, `htmlwidgets`, `callr`, `processx` as hard deps.
2. **`jacobian_elem` / nested custom operators: absent.** Nested AD exists only as diagnostic `chkpoint_two` + `base2ad` in `ad_checkpoint_probe()`, explicitly outside production (NEWS/vignette).
3. **DESCRIPTION/README claim “matrix operations”** — model language is scalar-only; Eigen is for quadrature / a tiny R bridge (`eigen_r.hpp`), not AD matrix ops.
4. **JSON graph TUs in `src/`** are CppAD-local copies (SPDX Bradley Bell) — maintenance fork risk vs including from headers only.

---

## 3. CODE QUALITY

### Readability / consistency
- Owned C++ is compact and readable; IR opcodes shared between R and C++ enums.
- CondExp helpers are repetitive but intentional (Parameter vs Dynamic special cases — fixed in 0.7.3/0.7.4).

### Complexity hotspots
| File | Lines | Notes |
|------|------:|-------|
| `src/ad_engine.cpp` | 861 | Recording, Jacobian policy, Hessian, quadrature, checkpoints |
| `inst/include/LibeRtAD/program.hpp` | 402 | Full IR interpreter |
| `R/ad-model.R` | 359 | Public API + cache |
| `R/gui.R` + `aaa-shared-async.R` | 284+265 | Outsized vs AD core |
| `src/json_parser.cpp` | 330 | Vendored CppAD graph parser |

### Error handling
- Good: IR validation (future refs, arity), duplicate names, dimension checks on tape points.
- Good: CppAD `exit` → R exception; `R_tmpnam2` for temp files (`cppad_r_output.hpp`).
- Weak: no RAII/`abort_recording` around `Independent`…`Dependent` (see Correctness).

### Global / mutable state
- CppAD `thread_alloc` + tape recording state (process/thread globals).
- `TapeHandle` mutates `derivative_strategy`, `jacobian_nonzeros`, `hessian_cache` during eval — fine single-threaded; races if shared across threads.
- Forced `#define NDEBUG` while including CppAD disables `CPPAD_ASSERT_UNKNOWN` even in debug builds of dependents that include `LibeRtAD/cppad_r_output.hpp`.

### Fragile / hacky (but documented)
```29:40:C:\Users\svdijkman.DESKTOP-4OG10M4\Documents\LibeR\LibeRtAD\inst\include\LibeRtAD\cppad_r_output.hpp
#define cout cppad_r_output
#define cerr cppad_r_error
#define exit cppad_r_exit
#pragma push_macro("NDEBUG")
#ifndef NDEBUG
#define NDEBUG
#endif
#include <cppad/cppad.hpp>
#pragma pop_macro("NDEBUG")
```
Necessary for R embedding; still a sharp include-order/macro surface for LinkingTo consumers.

### Duplication
- CondExp Parameter specializations ×6; unary scalar wrappers.
- FD Jacobian/Hessian only in benchmarks (appropriate), but accuracy path always runs FD even when timing FD is disabled.

---

## 4. CORRECTNESS RISKS / BUGS

### High

**H1. Tape pollution if recording throws after `Independent`**

```228:239:C:\Users\svdijkman.DESKTOP-4OG10M4\Documents\LibeR\LibeRtAD\src\ad_engine.cpp
 CppAD::Independent(independent, dynamic);
 // ...
 std::vector<AD> dependent = program.eval_outputs(full_inputs, selected);
 CppAD::ADFun<double> fun;
 fun.Dependent(independent, dependent);
```

No `try { … } catch { AD<double>::abort_recording(); throw; }`. Same pattern in checkpoint helpers (`Independent` at 404, 412, 424, 448). A throw leaves a live CppAD recording; next `Independent` fails (“previous recording”). Grep shows **zero** `abort_recording` in owned code.

**H2. Thread-safety overclaim**

```837:837:C:\Users\svdijkman.DESKTOP-4OG10M4\Documents\LibeR\LibeRtAD\src\ad_engine.cpp
 Rcpp::Named("thread_state") = "one independent tape per ADModel"
```

`ADFun` Taylor buffers are mutable; concurrent `jacobian`/`hessian` on the same tape races. Checkpoints use `use_in_parallel=false`. No `parallel_setup`. Claim implies safer concurrency than exists.

### Medium

**M1. Nested Jacobian / `jacobian_elem` not implemented**
Review focus area: production path has no custom nested Jacobian atomic. Only probe:

```804:805:C:\Users\svdijkman.DESKTOP-4OG10M4\Documents\LibeR\LibeRtAD\src\ad_engine.cpp
 CppAD::chkpoint_two<double> advan_checkpoint(
 advan_inner, "libertad_advan1_interval", true, true, true, false);
```

(`internal_bool`, `use_hes_sparsity`, `use_base2ad=true`, `use_in_parallel=false`). Nested safety exercised via `base2ad()` then hardcoded `nested_ad_safe = true` after success — fair as a smoke test, not a production nested-Hessian stack.

**M2. R6 GC / ownership exposure**
`program_ptr` / `tape_ptr` are **public** fields. Users can null, swap, or serialize them. Lifetime is “hope the R6 object stays alive” (vignette). `shared_ptr<const Program>` between handles is good; public XPtrs are not.

**M3. Tape cache integrity is dimensional, not semantic**
`libertad_tape_from_graph_json` checks Domain/Range/dyn sizes vs metadata, not that graph matches IR. Tampered/mismatched RDS can load wrong math with matching dims.

**M4. Nonsmooth ops (`abs`, `min`/`max`, `ifelse` kinks)**
`abs` at 0 → subgradient 0 (tested). `min`/`max` via CondExp; equal-branch / Hessian of nonsmooth models undefined — no Hessian tests for these.

**M5. Sparse Jacobian test does not check numeric values**
Strategy + nnz only (`test-engine.R` ~111–114); a wrong subgraph fill could pass.

**M6. FD always used for benchmark accuracy**
Even with `finite_difference = FALSE`, lines 163–180 of `benchmark.R` still compute FD refs for `accuracy`. Not an AD fallback, but the flag is misleading.

### Low / numerical

**L1. Domain failures propagate IEEE NaN/Inf** (explicitly tested) — good for transparency, bad if callers assume finite gradients.
**L2. `pow` / `log` / `sqrt`** — no domain guards at tape record time.
**L3. Dense Hessian** Forward-over-Reverse packing `reverse[k * 2 + 1]` looks CppAD-correct; sparse path + triangular fill is reasonable.

### Forward vs reverse policy (looks correct)

```97:126:C:\Users\svdijkman.DESKTOP-4OG10M4\Documents\LibeR\LibeRtAD\src\ad_engine.cpp
 if (n <= m) { /* multi-direction Forward(1, r, seed) */ }
 else { /* Reverse(1) per output */ }
```

Multi-dir seed layout `xq[r*j+ell]` matches CppAD `Forward(q,r,xq)`. Hessian dense path: `Forward(0)` → `Forward(1)` → `Reverse(2)`. Sparse: `for_hes_sparsity` + `sparse_hes(..., "cppad.symmetric")`.

### FD fallbacks
- **Not** used for production AD evaluation.
- Used only as independent check/comparator in `R/benchmark.R` (`.ad_fd_jacobian` / `.ad_fd_hessian`) and GUI async flags.
- Vignette correctly describes FD as agreement check, not the engine.

### Disabled / skipped / “not yet”
| Location | What |
|----------|------|
| `tests/testthat/test-browser-e2e.R:2-3` | `skip_if_not_installed("shinytest2")`; skip unless `LIBER_RUN_BROWSER_TESTS=true` |
| NEWS / vignette | Checkpoint prototypes **outside production** until overhead justified |
| Owned code TODO/FIXME/HACK/XXX/BUG/WIP | **None** in `R/`, `src/` (owned), `inst/include/LibeRtAD/` (except NDEBUG pragma) |

---

## 5. TESTS

**Breadth:** Solid for a small package — exact gradient/Hessian, dynamic params, static/data-driven `ifelse`, Jacobian strategy selection, sparse Hessian reuse, tape cache reload, allocator lifetime, property tests, quadrature, benchmarks, GUI smoke.

**Assertion quality:** Engine tests often use tight tolerances (`1e-10`–`1e-12`) against analytic refs — meaningful. Property tests (100 cubics, 50 conditionals) are a real strength.

**Gaps:**
- No numeric assert on subgraph Jacobian entries.
- No Hessian tests for `abs`/`min`/`ifelse` kinks.
- No abort-recording / exception-during-record regression.
- No multi-thread / parallel stress (despite `thread_state` metadata).
- No nested production path (only checkpoint probe).
- GUI/CSS tests dilute AD signal (`test-gui-consistency.R`).
- Browser e2e normally skipped.

**Superficial spots:** `nested_ad_safe` is “did `base2ad` not throw”; `test-installed-headers.R` is file-existence only.

---

## 6. DOCUMENTATION

**Strengths:** Vignette covers compile/record/dynamic/cache/lifetime well; roxygen on `ADModel` methods is complete; NEWS tracks real numerical fixes (CondExp Parameter collapse).

**Over-claims / accuracy issues:**
| Claim | Reality |
|-------|---------|
| “matrix operations … execute in C++” (`DESCRIPTION`, README, package doc) | Scalar IR; Eigen for GH grids / bridge |
| `thread_state = "one independent tape per ADModel"` | Ownership model, not concurrency safety |
| “exact” gradients/Hessians in API docs | True for smooth tapes; false at kinks / NaN domains |
| Checkpoint “nested-AD-safe” in production narrative | Probe-only; production remains direct taping |

`ad_supported()` honestly lists scalar-only limitations.

---

## 7. DEPENDENCIES & VENDORING

| Dep | Assessment |
|-----|------------|
| Rcpp LinkingTo | Appropriate |
| R6 | Appropriate for pointer ownership |
| shiny/reactR/htmlwidgets/callr/processx | Heavy for an AD foundation; Suggests would fit better |
| LibeRties Suggests | Optional process supervisor in GUI only |

**Vendoring:**
- CppAD **20260000.0**, commit `5d51b2aa…` pinned in `cppad_r_output.hpp` / tests.
- Eigen **5.0.1**, commit `bc3b3987…`; `EIGEN_MPL2_ONLY`; macros confirm WORLD=3, MAJOR=5 (`Eigen/Version`).
- Scale: **~415** CppAD headers + **~408** Eigen entries under `inst/include/` (large install footprint by design for LinkingTo).
- Licenses installed: EPL-2.0, MPL-2.0, Apache-2.0-Eigen, BSD-3, MINPACK. README notes CppAD EPL-2.0 **or GPL-2.0-or-later**, but **GPL-2 text is not** under `inst/LICENSES/`. Package `LICENSE` is MIT stub (YEAR/HOLDER only).

---

## 8. TOP STRENGTHS

1. Clean persistent-tape API with dynamic parameters and provenance-checked graph cache.
2. Careful CondExp Parameter vs Dynamic handling (real LibeRation bugfix, with tests).
3. Measured Jacobian (multi-Forward / subgraph-Reverse) and sparse-Hessian strategy with telemetry.
4. R-safe CppAD embedding (`exit`→exception, temp files, console redirect).
5. Allocator finalizer stress test + analytic/property derivative coverage.
6. Explicit, restricted language (rejects `if` / unknown calls) — right for AD safety.

---

## 9. PRIORITIZED RECOMMENDATIONS

### High
1. Wrap all `Independent`…`Dependent` regions with `try/catch` + `CppAD::AD<double>::abort_recording()` (tape create + checkpoint helpers); add a regression that throws mid-record and still allows a second `ad_compile`.
2. Soften or rewrite `thread_state` / docs: document **single-threaded use per tape**; do not imply concurrent ADModel safety without locking or CppAD parallel setup.
3. Make `program_ptr` / `tape_ptr` private (or active-binding) so GC ownership cannot be casually broken.

### Medium
4. Add numeric asserts for subgraph Jacobian (e.g. expect `2*x` on the sparse case).
5. Either implement production nested-AD/`jacobian_elem` (if LibeRation needs it) or stop implying nested checkpoint readiness outside `ad_checkpoint_probe`.
6. Validate tape-cache IR↔graph consistency (hash IR / op counts / sample Forward(0) vs program eval).
7. Move GUI deps to Suggests, or split `LibeRtAD.gui` — keep LinkingTo headers lean for dependents.
8. Install GPL-2.0 text alongside EPL for CppAD dual-license completeness; clarify MIT+file LICENSE body.

### Low
9. Gate FD accuracy computation behind `finite_difference` (or rename flag).
10. Avoid forcing `NDEBUG` for debug builds of LibeRtAD itself (keep release-only), or document that LinkingTo consumers lose CppAD unknown asserts.
11. Add kink/Hessian policy docs + tests for `abs`/`min`/`ifelse`.
12. Prefer upstream CppAD JSON graph sources over forked `src/json_*.cpp` when possible.

---

**Bottom line:** Trust this package for **smooth scalar tapes**, dynamic data, dense/sparse Jacobian/Hessian, and cache reload on one thread. Do **not** treat it as a finished nested-Jacobian/`jacobian_elem` layer, a thread-safe AD runtime, or a matrix-AD engine — those are either probes, overclaims, or missing.

---

### 3.2 LibeRation 0.9.8

> _Reviewer summary:_ LibeRation 0.9.8 is a large research-beta PK/PD stack (~23–28k R LOC, ~11k C++ LOC, 116 exports, 38 test files) with a serious C++/CppAD core, but the “exact AD / one C++ numerical path” story is overstated: FD gradient fallbacks, optimHess covariance, R-orchestrated SAEM/PSOCK, and incomplete IMP/GQ gradients remain. Highest priorities are documenting those deviations, hardening covariance to exact Hessians, and tightening estimation/ADVAN coverage beyond smoke fits.

# LibeRation 0.9.8 — Critical Read-Only Review

**Verdict:** Architecturally ambitious and unusually honest for a research beta (support matrix, TODO, experimental gates), but marketing language (“exact AD”, “one C++ numerical path”, “thirteen methods”) systematically oversells what production fits actually do. The C++ core is real; the R orchestration layer still owns outer loops, several gradients, covariance Hessians, ADDL expansion, and silent FD recovery.

---

## 1. OVERVIEW

**Purpose:** NONMEM-compatible population PK/PD specification, simulation, estimation (~13 methods), diagnostics/uncertainty, NCA, NONMEM control-stream I/O, content-addressed workspaces, and a reactR/Shiny workbench — backed by one large C++ numerical runtime (`pk_engine.cpp`) linked to LibeRtAD/CppAD.

**Size (approx., from file lengths):**
| Layer | Estimate | Notes |
|--------|----------|--------|
| R | **~23–28k LOC** | ~52 files under `R/`; largest: `gui.R` (~2398), `zzz-gui-app.R` (~2379), `estimation.R` (~2074), `diagnostics.R` (~1908), `model.R` (~1424), `estimation-stochastic.R` (~1390) |
| C++ | **~11–12k LOC** | `pk_engine.cpp` **9391**, `hmc_sampler.h` ~950, `nca.cpp` ~273, `native_optimizer.cpp` ~212 + exports |
| JS GUI | ~1855 | `inst/htmlwidgets/liberWorkbench.js` |
| Exports | **116** `export(...)` in `NAMESPACE` |
| Tests | **38** `test-*.R` files |
| Docs | 4 vignettes, 117 `.Rd`, `README`/`TODO`/`ENGINE_MODEL_ROADMAP`/`NEWS` |

**Major subsystems**

| Path | Role |
|------|------|
| `R/model.R`, `model-contract.R`, `model-templates.R`, `model-update.R` | `nm_model()` IR compile via `LibeRtAD::ad_ir`, contracts/templates |
| `R/engine.R` | `NMEngine` R6; serializable model + C++ pointer |
| `R/data.R` | Event normalize; **ADDL expansion in R** |
| `R/estimation.R` | Subject evaluators, tape sharing/retape, FO/FOCE*/Laplace, outer optim + FD fallback |
| `R/estimation-stochastic.R` | ITS/GQ/IMP/SAEM/BAYES dispatch |
| `R/estimation-hmc.R`, `estimation-nonparametric.R` | HMC/NUTS, NPML/NPAG |
| `R/mu-specialization.R` | MU classification + estimator specialization |
| `R/diagnostics.R`, `advanced-inference.R`, `bayesian-diagnostics.R`, `workflows.R` | Cov/GOF/VPC, SIR/compare/bootstrap, PPC/WAIC/LOO, SCM/profile |
| `R/nonmem.R` | Control-stream read/write / PRED-mode markers |
| `R/nca.R` + `src/nca.cpp` | Native NCA + ncar/NonCompart fallback |
| `R/workspace.R` | Content-addressed object store / projects |
| `R/gui.R`, `zzz-gui-app.R`, `gui-async.R`, `gui-ollama.R` + `inst/htmlwidgets/*` | Workbench state, jobs, AI |
| `R/hmm.R`, `state-space.R`, `factorial-hmm.R`, `switching-state-space.R`, `qsp.R`, `dde-dae.R`, `experimental.R`, `hybrid-components.R` | Advanced/experimental families |
| `src/pk_engine.cpp` | Event engine, ADVAN/ODE/SS, tapes, `PopulationObjective`, likelihoods |
| `src/hmc_sampler.h` | Native HMC/NUTS (no R callback in trajectory) |
| `src/native_optimizer.cpp` | Experimental native BFGS |
| `inst/ecosystem/support-matrix.csv` | Capability × evidence tier |
| `tests/testthat/` | Unit/property/GUI/NCA/estimation coverage |
| External | README points to monorepo `validation/*` (not inside this package tree) |

---

## 2. ARCHITECTURE & DESIGN

### Model IR / compiler
R parses `$PK`/`$PRED`/`$DES`/`$ERROR` into LibeRtAD IR (`LibeRtAD::ad_ir`), then packs a serializable spec into C++:

```79:120:C:\Users\svdijkman.DESKTOP-4OG10M4\Documents\LibeR\LibeRation\R\engine.R
.nm_model_spec <- function(model) {
 list(
 version = model$version,
 pred_mode = model$PRED_MODE %||% "pk",
 advan = model$ADVAN,
 ...
 pred_ir = model$pred_ir,
 post_pred_ir = model$post_pred_ir %||% NULL,
 ...
 )
}
```

Three PRED modes (`pk` / `pred` / `pk_pred`) are a deliberate NONMEM extension; round-trip folds combined prediction into marked `$ERROR` (`R/nonmem.R`).

### Solver selection
C++ event loop branches on direct-PRED vs ODE vs matrix/ADVAN topology; SS=0/1/2, infusions, modelled RATE=-1/-2 (`pk_engine.cpp` ~1840–1980). Specialized ADVAN can be disabled via `LibeRation.specialized_advan`.

### Estimation objective sharing
Persistent `PopulationObjective` is the intended single-process path; PSOCK disables it and forces R coordination:

```863:871:C:\Users\svdijkman.DESKTOP-4OG10M4\Documents\LibeR\LibeRation\R\estimation.R
.nm_cpp_population_objective <- function(...) {
 if (!isTRUE(getOption("LibeRation.cpp_population_objective", TRUE))) {
 return(list(pointer = NULL, reason = "disabled by option"))
 }
 if (!is.null(context$parallel)) {
 return(list(pointer = NULL, reason = "PSOCK workers require R coordination"))
 }
```

Methods share CppAD subject tapes / population object for FO/FOCE*/Laplace; stochastic methods reuse evaluators but keep outer SAEM/IMP/GQ loops in R.

### Workspace
SHA-256 content-addressed `objects/` store with atomic publish, locks, snapshot hydration (`R/workspace.R` ~57–145). Solid design.

### GUI state
Shiny `reactiveValues` owns model/data/fit/jobs/AI/report (`zzz-gui-app.R` ~209–248); React widget patches via custom messages; AI context is request-scoped and invalidated on model/run changes.

### Concerns / inconsistencies
1. **“One complete C++ numerical path for a production fit” is false as stated.** Outer optim defaults to R (`optimizer_backend == "auto"` → `"r"`); ETA-mode falls back to `stats::optim` (`backend = "r-fallback"`); SAEM outer loop is R; ADDL is R; covariance R-matrix uses `optimHess`.
2. **Documentation vs telemetry:** fit objects record `population_gradient` strings that admit incomplete derivatives (IMP/GQ), while README/DESCRIPTION speak as if all methods are exact AD.
3. **Monolith:** ~9.4k-line `pk_engine.cpp` mixes event engine, ADVAN, ODE/DAE/DDE, HMM/Kalman/SDE, tapes, and population objective — high blast radius.
4. **Version policy drift:** `DESCRIPTION` Imports `LibeRtAD (>= 0.7.10)` but `compatibility.json` expects `0.7.13`.

---

## 3. CODE QUALITY

**Complexity hotspots**
- `src/pk_engine.cpp` (9391 lines) — primary maintenance risk.
- `R/gui.R` + `R/zzz-gui-app.R` + `liberWorkbench.js` — UI+jobs+AI surface larger than the estimation API.
- `R/estimation.R` / `estimation-stochastic.R` / `diagnostics.R` — nested evaluators, parallel, covariance, many method branches.

**Duplication**
Double-precision event/propagate path and templated AD path (`event_infusion_rate` vs `event_infusion_rate_t`, etc.) — expected for AD, but increases drift risk between simulate and tape paths.

**Consistency**
Generally careful telemetry (`tape_retapes`, `fo_population_fallbacks`, MU fallback reasons, gradient fallbacks). Experimental features require explicit `nm_experimental_config(enabled = TRUE)` — good gatekeeping.

**Error handling**
Domain errors for SS, RATE, ill-conditioned SS, tape path changes with retape retry (3 attempts then rethrow path). Objective returns `1e100` / Inf barriers on failed evals — can hide numerical pathology inside “successful” optim.

**Global / fragile state**
- Options: `LibeRation.cpp_population_objective`, `tape_guard_radius`, `fo_population_batch`, `specialized_advan`.
- PSOCK workers stash evaluators in `.GlobalEnv` (`.liber_parallel_subjects`) — fragile under concurrent sessions.
- Adaptive ODE tape validity uses a heuristic radius (default 0.5), not path-equality alone:

```202:212:C:\Users\svdijkman.DESKTOP-4OG10M4\Documents\LibeR\LibeRation\R\estimation.R
# Adaptive ODE solvers ... deliberately retaped.
radius <- getOption("LibeRation.tape_guard_radius", 0.5)
distance <- max(abs(point - anchor) / pmax(abs(anchor), 1), na.rm = TRUE)
if (is.finite(distance) && distance > radius) {
 self$record_tapes(theta, sigma, omega, eta, retape = TRUE)
```

**Hacky / half-finished spots**
- `narrative_stub` report section is literally blank prompts (`R/report.R` ~124–129).
- ETA-mode R BFGS fallback after C++ failure (`estimation.R` ~421–480).
- FO batched population path can silently demote to per-subject tapes (`pk_engine.cpp` ~7322–7329).

---

## 4. CORRECTNESS RISKS / BUGS

### High-severity architectural risks

**A. Finite-difference gradient recovery contradicts “no FD” claims**

Documented recovery (NEWS 0.9.4) and live code:

```1085:1104:C:\Users\svdijkman.DESKTOP-4OG10M4\Documents\LibeR\LibeRation\R\estimation.R
if (length(value) != length(parameters) || any(!is.finite(value))) {
 ...
 fallback <- finite_difference_gradient(parameters, point_value)
 if (... all(is.finite(fallback))) {
 gradient_fallbacks <<- gradient_fallbacks + 1L
 value <- fallback
```

vs:

```3:5:C:\Users\svdijkman.DESKTOP-4OG10M4\Documents\LibeR\LibeRation\R\objective.R
#' recorded by CppAD, so gradients and Hessians do not use finite differences.
```

Test explicitly expects FD recovery (`test-estimation.R` ~466–489). A production fit can therefore optimize on mixed AD/FD gradients without failing.

**B. Covariance “R” matrix is not an exact CppAD Hessian**

```898:901:C:\Users\svdijkman.DESKTOP-4OG10M4\Documents\LibeR\LibeRation\R\diagnostics.R
bread <- tryCatch(
 information_scale * stats::optimHess(
 at, objective, gr = attr(objective, "gradient", exact = TRUE)
```

With `gr` supplied, `optimHess` finite-differences the gradient. Comments acknowledge tape-domain concerns (~620–625). This is a first-class FD path in the uncertainty pipeline.

**C. Incomplete stochastic gradients (admitted in diagnostics, soft-pedaled in marketing)**

```625:633:C:\Users\svdijkman.DESKTOP-4OG10M4\Documents\LibeR\LibeRation\R\estimation-stochastic.R
population_gradient = if (imp_gradient == "score") {
 paste0(
 "normalized importance-score CppAD gradient (proposal derivative ",
 "omitted)", ...
```

```755:758:C:\Users\svdijkman.DESKTOP-4OG10M4\Documents\LibeR\LibeRation\R\estimation-stochastic.R
"normalized quadrature-score CppAD gradient (node derivative omitted)"
```

TODO §5 still open: full IMP proposal differentiation.

**D. Event engine: ADDL not in C++**

```6:32:C:\Users\svdijkman.DESKTOP-4OG10M4\Documents\LibeR\LibeRation\R\data.R
.nm_expand_addl <- function(data) {
 ...
 for (k in seq_len(n)) {
 row$TIME <- row$TIME + k * row$II
 ...
 }
 data$ADDL <- 0L
```

C++ only lists `ADDL` as a structure key (`pk_engine.cpp:3845`). Ordering is R sort (`TIME`, `.sort_priority`, `.source_row`). Risk: any path that bypasses `nm_dataset(expand_addl=TRUE)` or reorders events differently will disagree with NONMEM.

**E. Silent FO population fallback**

```7322:7329:C:\Users\svdijkman.DESKTOP-4OG10M4\Documents\LibeR\LibeRation\src\pk_engine.cpp
} catch (const TapePathChange&) {
 fo_population_.reset();
 ++fo_population_fallbacks_;
 fo_population_error_ = "A batched tape path changed; using subject tapes.";
}
```

Correctness may hold if subject tapes are equivalent, but performance and “batched exact path” assumptions break quietly.

### Other risks
- Mixture + Kalman: “not yet available” hard stops (`pk_engine.cpp` ~7604, ~7893).
- Experimental DDE forbids SS ≠ 0 (`pk_engine.cpp` ~1947–1948).
- Correlated-OMEGA element profiling unsupported (`workflows.R`).
- Legacy IOV ineligible for closed-form MU M-step (`mu-specialization.R` ~297).
- ADVAN14: support matrix admits no NONMEM 7.3 external validation; still advertised in DESCRIPTION alongside ADVAN1–14.

### TODO / FIXME / WIP inventory
Classic `FIXME`/`HACK`/`XXX` markers are scarce. Incomplete work lives mainly in:
- `TODO.md` (tape sharing unfinished for observation tapes/dynamic doses; IMP full proposal AD; SAEM outer loop still R; native optimizer secondary; ADVAN14 NONMEM; profile for correlated OMEGA; etc.)
- `ENGINE_MODEL_ROADMAP.md` (adaptive/higher-order SDE still open)
- Code: `narrative_stub`, “not yet supported/available” strings above

### FD / workarounds / skipped tests (explicit)
| Kind | Location |
|------|----------|
| FD outer gradient fallback | `R/estimation.R:1036–1104`; NEWS 0.9.4; test at `test-estimation.R:466` |
| FD covariance Hessian | `R/diagnostics.R:900` (`optimHess`) |
| FD helper for score checks | `R/diagnostics.R:681` (used in tests) |
| FD test oracles | `test-ad-prediction.R`, `test-objective.R` |
| IMP finite-CRN derivative-free refinement | `estimation-stochastic.R:558–633` |
| ETA-mode R `optim` fallback | `estimation.R:458–480` |
| NCA ncar fallback | `nca.R:205–209` (`engine="auto"`) |
| Skips | `test-nca.R` (ncar/NonCompart); `test-browser-e2e.R` (env gate); `test-gui.R`/`test-concurrency.R` (LibeRties/callr); `test-gui-ollama.R` (deploy launcher); `test-report-workflow.R` (Pandoc); `skip_on_cran` in estimation/simulation |

---

## 5. TESTS

**Breadth:** Strong for a research package — FO tape sharing, Laplace retape anchors, GQ grids, IMP/SAEM/BAYES smoke, HMC/NUTS/NP, ADVAN surface, AD prediction vs central differences, NONMEM round-trip, workspace, GUI/async/ollama safety, experimental families, HMM/state-space.

**Assertion quality:** Mixed. Best tests compare native vs reference gradients at tight tolerances (`test-estimation.R` FO ~2e-11 / 3e-6). Many method tests are `maxit = 1–5` + `is.finite(objective)` — smoke, not recovery.

**Gaps**
- End-to-end parameter recovery for FOCEI/IMP/SAEM vs known truth is largely delegated to external `validation/` (outside package).
- ADVAN5/7/8/9/10/14 estimation paths under-tested vs ADVAN1/2/6/13 prediction tests.
- Parallel/`n_cores>1` estimation lightly covered.
- Covariance numerical accuracy vs exact Hessian not clearly asserted.
- FD-fallback path tested with a toy objective, not a real Laplace/ODE fit.
- Browser e2e opt-in only (`LIBER_RUN_BROWSER_TESTS`).

---

## 6. DOCUMENTATION

**Strengths:** README labels “research beta”; support matrix distinguishes validated/verified/experimental; TODO and ENGINE roadmap are unusually frank; vignettes correctly say IR is not re-eval’d in R.

**Over-claims / mismatches**
1. **DESCRIPTION** packs experimental SDE/DDE/DAE/QSP/particle language into the package Description without the matrix’s “Experimental research only” qualifier.
2. **`nm_objective` / man page:** “do not use finite differences” — false for the estimation/covariance pipeline as a whole.
3. **README “exact automatic differentiation” + HMC/NUTS “exact joint CppAD target”** — true for those kernels; not true for IMP score default, GQ score default, outer FD fallback, or `optimHess` cov.
4. **ADVAN14** listed with ADVAN1–13; matrix says verified only, NONMEM 7.3 cannot validate.
5. **Validation campaigns** referenced as `../validation/...` — not shippable evidence inside the CRAN/package tree; consumers may think package tests alone prove NONMEM parity.

---

## 7. AI ASSISTANT (ellmer) REVIEW

**What it does:** Local help + report drafting via (1) WebLLM in a browser worker, or (2) Ollama through `ellmer::chat_ollama` from the Shiny session. No tools; cannot mutate project state (prompt + UI consent).

**Prompt/response handling**
- System prompt built in JS with evidence rules, scope, clipped JSON context (`liberWorkbench.js` ~1272–1278).
- Ollama message sanitization: role whitelist, 48-message cap, 160 kB/message, 400 kB total (`gui-ollama.R` ~122–145).
- Params clamped (`max_tokens` 64–4096, temperature, top_p).

**Safety (relatively strong for local AI)**
- Loopback-only URL regex; reject remote Ollama (`gui-ollama.R` ~8–15).
- Disabled for hosted env vars, non-loopback Shiny host, forwarded headers, `session_workspace` (`gui-ollama.R` ~47–76).
- Consent UI; privacy copy that tools are absent (`liberWorkbench.js` ~1783).
- Tests force Ollama → webllm when disallowed (`test-gui-ollama.R` ~114).

**Failure modes**
- Prompt injection / hallucinated PK numbers still possible despite instructions (soft constraint only).
- Large model/code context is clipped — assistant may invent from truncated `$DES`.
- Compromised local Ollama/browser still in threat model (UI admits this).
- Report path can emit placeholder text when AI not run (`report-workflow.R` ~206).

---

## 8. TOP STRENGTHS

1. **Real CppAD population objective** with tape sharing, retape telemetry, FO fusion, and native HMC/NUTS trajectories (`hmc_sampler.h` “no R callbacks”).
2. **Honest internal engineering ledger** (`TODO.md`, support matrix, experimental acknowledgements) rare in pharmacometrics software.
3. **Broad model surface** (ADVAN1–14, outcome families, HMM/state-space, MU specialization) with serializable contracts for remote queues.
4. **Durable workspace** (content-addressed, integrity-checked objects).
5. **AI privacy design** (loopback lock, no tools, consent) better than typical “LLM in the GUI” bolts-ons.
6. **NONMEM PRED-mode round-trip design** with explicit markers for the LibeRation `pk_pred` extension.

---

## 9. PRIORITIZED RECOMMENDATIONS

### High
1. **Stop over-claiming exact AD / one C++ path.** Surface in `summary(fit)` / GUI: gradient class (exact / score-incomplete / FD-fallback), objective backend (persistent-cpp vs R-orchestrated), cov Hessian source (`optimHess` vs CppAD). Fail or warn when `gradient_fallbacks > 0` unless `allow_fd_gradient=TRUE`.
2. **Replace `stats::optimHess` covariance bread with CppAD Hessian** (or document as approximate and default sandwich). This is the largest claim/implementation gap in inference.
3. **Make FD outer-gradient fallback opt-in**, not silent recovery; keep for research debugging only.
4. **Package-local recovery tests** for FOCEI + Laplace on a small analytic/NONMEM fixture (not only external validation/).
5. **Align version floors:** `DESCRIPTION` LibeRtAD lower bound with `compatibility.json` (0.7.13).

### Medium
6. Finish IMP proposal differentiation or demote IMP “validated exact gradient” messaging; same for GQ node derivatives.
7. Move SAEM outer SA loop into C++ (already on TODO) or clearly label R-orchestrated SAEM.
8. Split `pk_engine.cpp` along event / ADVAN / likelihood / population-objective seams.
9. Expand ADDL/SS/infusion ordering tests against NONMEM-generated tables (including ADDL expansion edge cases and SS=2 accumulation).
10. Estimation coverage for ADVAN5/7/8/9/10/14 beyond GUI/template smoke.

### Low
11. Replace `narrative_stub` with real report blocks or drop the name.
12. Reduce PSOCK `.GlobalEnv` coupling.
13. Profile correlated OMEGA elements (TODO §7) or document permanent limitation in `nm_profile` docs.
14. Promote checkpoint kernels only with benchmarks (TODO §11) — do not advertise until production-default.

---

**Bottom line:** LibeRation is a serious research-beta engine with a genuine C++/CppAD center of gravity, not vaporware — but the production-fit invariant is currently “C++ evaluation with R outer control and several documented/undocumented FD or incomplete-gradient escapes.” Treat DESCRIPTION/README capability lists as a menu of interfaces; treat `support-matrix.csv` + fit telemetry as the truth.

---

### 3.3 LibeRties 0.7.7

> _Reviewer summary:_ LibeRties 0.7.7 is a carefully designed job-execution layer with honest sandbox disclaimers, solid wire/auth primitives, and real gaps: forgeable isolation preflight, PID-reuse on cancel, stuck `.claimed` jobs, soft poll-only limits, and encryption that still accepts plaintext RDS.

# LibeRties 0.7.7 — Critical Read-Only Review

**Verdict:** Strong application-layer design with unusually honest sandbox language, but several security/correctness gaps remain between “production-ready controls” and what the code actually enforces. Treat the built-in boundary as a **cooperative restricted worker**, not a multi-tenant hostile-code host.

---

## 1. OVERVIEW

| Item | Detail |
|------|--------|
| **Purpose** | Durable local/remote execution of typed LibeR jobs (`liber.job.wire/2`) via `callr` workers, per-tenant FS namespaces, plumber API, optional at-rest AEAD, admin Shiny GUI |
| **Version / path** | 0.7.7 — `C:\Users\svdijkman.DESKTOP-4OG10M4\Documents\LibeR\LibeRties` |
| **Approx LOC** | ~3.4k non-empty lines under `R/` (14 R files); tests/vignettes/man on top |
| **Exports** | **33** (`NAMESPACE`) — R6 classes + `ls_*` helpers |
| **Test files** | **13** under `tests/testthat/` |
| **Structure** | `R/` (queue, worker, wire, server, remote/API, security, audit, admin, utils, shared durability/async, process supervisor); `inst/admin-assets/`; 2 vignettes; roxygen `man/` |

Key modules: `queue.R` / `worker.R` (execution), `wire.R` (contract), `server.R` + `remote.R` (auth + HTTP), `security.R` (preflight/policy), `utils.R` (crypto/paths/locks).

---

## 2. ARCHITECTURE & DESIGN

**Queue state machine:** `queued → running → {completed|failed|cancelled}` with locked metadata updates (`allowed_status`), payload/result digests, `.claimed` start latch, `poll()` = enforce limits → reap → recover untracked → seal logs → start work.

**Local vs remote:** Local `LibeRQueue` stores **RDS** jobs and runs `.ls_run_job`. Remote path is **JSON wire only** (`ls_api` / `LibeRRemote`) — no RDS upload route. Server core `LibeRServer` maps bearer token → tenant queue; callers cannot nominate another tenant on the server path.

**Worker lifecycle:** `callr::r_bg` with scrubbed env (`R_PROFILE_USER` cleared, thread caps), `wd = job_dir`, checksum before run, typed package entry points (`nm_simulate` / `library_worker_task` / …), process-tree kill on cancel/limit.

**Server/API:** Plumber `/v1/*`, security headers, minute-bucket rate limits, trusted-proxy XFF, production preflight gate in `ls_run_api`. Admin GUI is separate Shiny app with hashed admin token.

---

## 3. CODE QUALITY

**Hotspots:** `wire.R` (~426 lines), `admin.R` (~521), `server.R` / `queue.R` / `remote.R` — dense but coherent.

**Duplication:** Limit enforcement logic is copy-pasted between `enforce_limits` and `recover_untracked` (`queue.R` ~262–365). Resource accounting duplicated again for cancel paths.

**Consistency:** Isolation labeled `restricted-subprocess` in metadata and capabilities — good. Local `submit(..., user=)` still allows nominating another namespace (`queue.R:52–54`), unlike the server boundary.

**Error handling:** Generally fail-closed with `.ls_stop`; durable read recovers `.previous` generation. Audit/registry locks use different strategies than job locks (stale reclaim only on job locks).

**Global / process state:** Storage key from env/`options`; rate-limit env per API process (not shared across workers); in-memory `private$queues` / `self$processes`.

**Fragile spots:** Soft limits only while something calls `poll()`; `.claimed` never cleared on success; cancel-by-PID without create-time check; isolation probe forgeable.

---

## 4. SECURITY REVIEW (core)

### Auth & credentials

**Strengths**
- Tokens: `lr_<date>_<64 hex>` = 256-bit (`server.R:60–61`); only SHA-256 digest persisted (`server.R:101–104`, `171–176`).
- Constant-time hash compare (`server.R:107–115`); auth loop does not early-return on first match (`118–125`).
- Scopes `jobs:read` / `jobs:write`; optional expiry; rotation revokes old token.
- Admin token hashed then `rm()`’d (`admin.R:81–82`); constant-time login (`408–409`).

**Weaknesses**
- Token digests are **unsalted** SHA-256 — fine for 256-bit secrets; weak if operators ever issue low-entropy tokens.
- Non-expiring tokens allowed; production only **warns** (`security.R:191–194`).
- Admin minimum length **16 chars** (`admin.R:78–79`) — weak for a full control plane.
- Admin Shiny session: no evident idle timeout / lockout after failed logins.
- API `POST /v1/jobs` authenticates **without** write scope before decode (`remote.R:157–160`); write check is inside `submit`. Read-only tokens can force JSON decode / CPU work up to their payload ceiling.

### Wire protocol & deserialization

**Strengths**
- Pack rejects functions, environments, language, externalptr/weakref (`wire.R:10–12`).
- Remote rebuilds models via LibeRation contract, not trusted IR (`wire.R:225–228`, `280`).
- API docs/claim: no RDS deserializer on the wire (`remote.R:99–102`); test checks router printout for `rds` (`test-remote.R:1–9`).
- Result attribute/class allowlists (`wire.R:358–372`).
- Fuzz rejects garbage JSON (`test-fuzz-contract.R`).

**Weaknesses / gap vs claim**
- **Local workers still `readRDS` / `unserialize` job payloads** (`worker.R:19`, `utils.R:150–158`). Integrity depends on FS control + checksums (`worker.R:5–10`), not on “never deserialize untrusted RDS.”
- `.ls_storage_unwrap` **accepts plaintext** objects when schema ≠ encrypted (`utils.R:125–128`). With encryption “on”, a planted plaintext RDS still loads (FS attacker / confused migration).
- After AEAD decrypt, `unserialize` is used (`utils.R:134`) — OK **if** AEAD holds; plaintext bypass undermines that assumption.

### Tenant isolation & path safety

**Strengths**
- Safe components: `^[A-Za-z0-9][A-Za-z0-9_.-]*$`, rejects `.`/`..` (`aaa-shared-durability.R:132–140`).
- Job path must stay under root (`utils.R:93–97`).
- Server derives tenant from token only (`server.R:337–341`).
- Traversal test exists (`test-contract.R:28–30`).

**Weaknesses**
- Isolation is **directory + env scrub**, not OS user/namespace separation. Worker still inherits `R_LIBS_USER` / `PATH` (`utils.R:40–50`) and loads full package libs — code execution inside the worker = full user library authority.
- Local queue `user=` override is a footgun on shared hosts.

### Quotas & resource limits

**Strengths**
- Per-tenant limits validated (`server.R:27–57`); payload/queue/storage checked on submit; result size in worker + download path.
- Process-tree RSS/CPU via `ps` (`utils.R:53–73`); kill tree (`76–83`).
- Test that memory limit kills worker (`test-local-worker.R:61–80`).

**Weaknesses (enforcement gaps)**
- Limits are **soft and poll-driven** (`queue.R:94–100`, `262–303`). No poll ⇒ no enforcement.
- Not cgroup/`setrlimit` hard caps — cross-platform measurement only; short spikes and fork bombs can exceed before next poll.
- Defaults are huge: 86400s CPU/wall, 4096 MB, 5 GB storage (`server.R:34–36`).
- Quota check TOCTOU: two concurrent submits can both pass storage/queued checks (`server.R:388–397` / `queue.R:59–66`).
- HTTP result path deserializes then size-checks (`server.R:437–443`) — memory amplification before reject.

### At-rest encryption

**Strengths**
- `sodium::data_encrypt` / `data_decrypt` (secretbox AEAD) (`utils.R:115–136`).
- 256-bit hex key; key_id fingerprint; terminal logs sealed to encrypted RDS (`utils.R:167–191`).
- Checksums cover ciphertext on disk.

**Weaknesses**
- Encryption **optional**; production can be started with `require_storage_encryption = FALSE` (test does exactly that — `test-security.R:62–66`).
- Live worker logs remain plaintext until terminal (`security.R:200–201`) — window for secret leakage (tokens in library-job args, etc.).
- Key in process env/`options` — dumpable; no rotation/versioned multi-key unwrap beyond `key_id` label.
- Plaintext-accepting unwrap (above) is the main crypto-boundary hole.

### Durable queue / races

**Strengths**
- Atomic publish with `.previous` recovery (`aaa-shared-durability.R:9–80`).
- Metadata lock with stale reclaim 30s (`utils.R:207–212`).
- Recovery checks `pid_started` vs `ps_create_time` within 1s (`queue.R:320–323`).
- Explicit state transitions via `allowed_status`.

**Weaknesses**
- **`.claimed` is only removed on start failure** (`queue.R:408–429`). On success it remains forever. Crash after claim + `r_bg` but before `status=running` ⇒ job stuck `queued` forever (recovery only handles `running`).
- Cancel of untracked jobs kills by PID **without** `pid_started` check (`queue.R:201–203`) — **PID reuse → kill innocent process**. Recovery path does the check; cancel does not.
- Cancel can return `TRUE` even if metadata update no-ops due to race (`queue.R:190–208`).
- No idempotency / dedup keys — duplicate submission is trivial.
- Audit chain is hash-linked but **fully rewriteable** by anyone who can write `audit.rds` (`audit.R:9–31`); not OS append-only / WORM.

### Preflight & production refusal

**Strengths**
- Non-loopback needs `behind_tls_proxy` (`security.R:174–176`).
- Env label `LIBERTIES_OS_ISOLATION` is **not** accepted as proof (`183–188`); tests cover this (`test-security.R:46–60`).
- `ls_run_api(..., production=TRUE)` uses `strict` preflight (`remote.R:212–214`).

**Weaknesses / dishonest edge**
- Default probe: `file.exists("/.dockerenv")` **or** cgroup regex (`security.R:47–61`). On a bare-metal host, creating `/.dockerenv` (or spoofable cgroup text in some setups) can make production “ready.” This is **evidence theater**, not a sandbox attestation.
- `behind_tls_proxy` is a boolean honor system — no TLS verification.
- Custom `isolation_probe` returning `active=TRUE` always passes (`security.R:69–87`) — intentional escape hatch, easy to misuse.

### Subprocess restriction vs sandbox disclaimer

**Honesty: largely good.** README/NEWS/vignettes state restricted subprocess ≠ hostile-code sandbox; capabilities list external OS sandbox (`job.R:124–130`).

**What it actually restricts:** env scrub, per-job cwd, typed entry points, soft resource monitors, tenant dirs, no remote `eval` of submitted functions.

**What it does not:** syscall/FS/network jail, separate UID, seccomp, preventing native code in loaded packages, preventing worker from reading other readable paths on the host as the service user.

Admin UI text that workers run with “enforced resource limits” (`admin.R:202`) is **over-strong** relative to poll-interval soft kills.

---

## 5. CORRECTNESS RISKS / BUGS

| Risk | Evidence |
|------|----------|
| Stuck jobs after crash during claim/start | `.claimed` never cleared on success (`queue.R:408–436`) |
| Cancel PID reuse | No `pid_started` on cancel (`queue.R:201–203`) vs recovery (`320–323`) |
| Soft limits / no poll | Enforcement only in `poll` (`queue.R:94–100`) |
| Quota races | Check-then-act submit |
| Misleading cancel success | Returns TRUE after unlockable state change |
| Audit lock deadlock → hard fail | Custom 5s timeout, no stale steal (`audit.R:13–16`) |
| Registry lock `stale_after=Inf` | (`server.R:19–24`) — dead holder blocks admin ops |

**TODO/FIXME/HACK/XXX/BUG/WIP:** None found in package R/tests/docs (grep).

**Skipped tests:**
- `skip_if_not_installed("LibeRation"|LibeRality|…)` — many wire/worker tests
- `test-browser-e2e.R`: shinytest2 + `LIBER_RUN_BROWSER_TESTS != "true"`
- `test-remote.R`: plumber

---

## 6. TESTS

**Breadth (good):** scopes/expiry/audit; encryption schema; preflight TLS/isolation label rejection; XFF trust; rate-limit bounding; log redaction; log sealing; path traversal; cancel queued; dead-worker recovery; interrupted RDS recovery; memory-limit kill; wire executable reject; fuzz decode; tenant isolation; token rotation.

**Gaps (security-critical):**
- No test for `.claimed` stuck-queue failure mode
- No cancel + PID reuse / `pid_started` test
- No test that unwrap rejects plaintext when encryption required
- No concurrent quota/submit race test
- No constant-time auth timing test (only functional)
- No end-to-end authenticated HTTP submit/result (router smoke only)
- No isolation-probe forgeability / `/.dockerenv` negative test
- Resource limits besides memory sparsely covered; wall/CPU less so
- Admin auth brute-force / session hardening untested

Assertion quality is generally specific (status, error substrings, schemas).

---

## 7. DOCUMENTATION

**Accurate / honest:** DESCRIPTION production OS+TLS requirement; README sandbox caveat; vignette “application-level isolation”; NEWS 0.7.0/0.7.1 boundaries; preflight refuses env-label-as-proof.

**Over-claims / soft spots:**
- “monitored resource limits” / admin “enforced resource limits” imply harder guarantees than poll-based RSS/CPU kills.
- “verifiable external OS isolation” for default Linux probe overstates what `/.dockerenv` + cgroup grep proves.
- `ls_queue_capabilities()$remote_target` includes Windows/macOS (`job.R:126`) while DESCRIPTION frames remote as Linux-oriented — mild inconsistency.
- Vignette: reverse proxy “not technically required” on loopback (`server-administration.Rmd:74–76`) is fine; operators may miss that production non-loopback **is** gated.

---

## 8. TOP STRENGTHS

1. Clear threat-model language: restricted subprocess ≠ OS sandbox.
2. Typed non-executable remote wire with model revalidation.
3. Token hashing + constant-time compare; tenant from credential only.
4. Atomic durable metadata with restart/previous-generation recovery and PID create-time checks on recovery.
5. Production preflight that rejects “env var = isolation.”
6. AEAD via sodium secretbox; log redaction + response ceilings; security headers; swagger off.
7. Meaningful security-focused tests (not only happy-path).

---

## 9. PRIORITIZED RECOMMENDATIONS

### High
1. **Fix `.claimed` lifecycle** — clear on terminal states / allow reclaim if still `queued` and worker dead; add regression test (`queue.R:406–436`).
2. **Cancel must verify `pid_started`** (same as recovery) before `ps_kill` (`queue.R:201–203`).
3. **Fail closed on plaintext RDS when storage key is configured** (or when `require_storage_encryption`) — reject non-`liberties.encrypted-rds` in unwrap (`utils.R:125–128`).
4. **Harden isolation preflight** — do not treat bare `/.dockerenv` as sufficient alone; require probe that checks usable isolation (e.g. non-writable host paths, uid mapping, cgroup controllers) or force explicit signed deployment attestation (`security.R:47–61`).
5. **Document + enforce hard OS limits in production** (cgroup v2 memory/CPU, separate uid) — do not market soft `ps` polls as tenant isolation.

### Medium
6. Check `jobs:write` **before** `ls_job_decode` on `POST /v1/jobs` (`remote.R:157–160`).
7. Raise admin token entropy requirements; add lockout / session TTL (`admin.R:78–79`).
8. Make limit enforcement independent of polite clients (supervisor thread / always-on reaper).
9. Serialize quota reservation under a per-tenant lock to close TOCTOU.
10. Size-check HTTP bodies before full JSON parse/materialization where plumber allows.
11. Disallow `http://` remote clients unless explicitly opted in (`remote.R:261–264`).

### Low
12. Deduplicate limit-enforcement helpers; unify audit/registry locks with stale reclaim policy.
13. Add idempotency keys for submit; append-only or externally mirrored audit log.
14. Expand tests for claim stuck-state, cancel PID reuse, encryption plaintext reject, concurrent quotas, full HTTP authz matrix.
15. Soften admin UI copy from “enforced” to “monitored/terminated on poll.”

---

**Bottom line:** LibeRties is one of the more carefully threat-modeled R execution packages in this ecosystem, and its sandbox disclaimer is mostly honest. For multi-tenant or hostile-input production, the critical failures are not missing marketing language — they are **forgeable “isolation” preflight**, **PID-unsafe cancel**, **stuck claim latch**, **plaintext-tolerant “encryption,”** and **soft, poll-only resource controls**. Fix those before trusting it as a security boundary.

---

### 3.4 LibeRary 0.7.11

> _Reviewer summary:_ LibeRary’s elaborate pipeline is largely real code—not aspirational stubs—especially deliberative investigation, dual-lane reconciliation, and catalogue/qualification gates. The main gaps are soft consistency gates that don’t block synthesis, asymmetric text vs vision depth, keyword-only retrieval, and tests that mock LLMs rather than exercising live network paths.

# LibeRary 0.7.11 — Critical Read-Only Review

**Verdict:** The elaborate README/vignette pipeline is largely **implemented**, not vaporware. The deliberative investigation, dual-lane reconciliation, content-addressed bundles, and qualification state machine have real depth. The weakest spots are **soft gates** (consistency checks do not block synthesis), **asymmetric lane depth** (deliberative text vs one-shot vision), **keyword-only retrieval**, and **tests that mock LLMs** rather than proving end-to-end extraction quality.

---

## 1. OVERVIEW

| Item | Finding |
|------|---------|
| **Purpose** | Versioned pharmacometric model catalogue + PubMed→PDF→LLM extraction pipeline with dual-lane reconciliation, machine vs human status separation, clinical-use qualifications, LibeRation import |
| **Version** | `0.7.11` (`DESCRIPTION`) |
| **Structure** | 41 files under `R/`; `inst/catalog/` (AEDapt + gold entries); three Shiny apps (`inst/shiny`, `shiny-ingest`, `shiny-reference`); 2 vignettes; no separate `ARCHITECTURE.md` (architecture lives in `README.md` + vignette) |
| **Approx R LOC** | ~14–16k lines across `R/` (largest: `ingest-deliberative.R` ~956, `ingest-catalog.R` ~646, `ingest-extract.R` ~586, `ingest-dual.R` ~575, `model-semantics.R` ~550+) plus large `inst/shiny*` apps |
| **Exported functions** | **95** `export(...)` entries in `NAMESPACE` (plus 4 S3 `print` methods) |
| **Test files** | **15** `tests/testthat/test-*.R` |
| **Key deps** | `digest`, `httr2`, `jsonlite`, `rentrez`, `tools`, `xml2`; Suggests LibeRation, LibeRties, chromote, pdftools, shiny, DT, yaml |

Persistent data is intentionally outside the package install (`LIBERARY_HOME` / `Documents/LibeR-data/library`).

---

## 2. PIPELINE IMPLEMENTATION REALITY

This is the core of the review. Stages mapped to actual code depth.

### Stage map (concrete)

| Claimed stage | Reality | Evidence |
|---------------|---------|----------|
| **1. PubMed snapshot** | **Implemented** | `ingest_discover()` → `ingest_entrez_search` / `ingest_entrez_fetch_metadata`; throttle + XML parse + per-PMID cache (`ingest-discover.R:17–120`, `ingest-entrez.R:8–96`, `ingest-throttle.R:6–18`) |
| **2. Triage (H/I/L + backlog)** | **Implemented** | LLM schema + deterministic thresholds + keyword fallback; low backlog CSV (`ingest-triage.R:10–99`, `ingest-discover.R:117–120`) |
| **3. PDF acquisition** | **Implemented** (institutional path depends on network/VPN) | Unpaywall/PMC/Europe PMC (`ingest-oa.R`); institutional fetch + optional chromote (`ingest-fetch.R:19–145`, `155–179`) |
| **4. Content-addressed bundle** | **Implemented** | `documents/<id>/<sha16>/` with source PDF, Docling outputs, page images, `bundle.json` (`ingest-docling.R:183–273`) |
| **5. Docling + pdftools fallback** | **Implemented** | Standard pipeline subprocess; explicit `pdftools_fallback` (`ingest-docling.R:68–127`, `207–224`) |
| **6. Six domain investigators** | **Implemented (substantial)** | Topics: structure, theta_covariates, omega_iov, sigma_observation, population_dosing, reproduction_data (`ingest-deliberative.R:279–334`, orchestrated `775–803`) |
| **7. Skeptical review / falsification** | **Implemented** | `falsification_1` + optional follow-up rounds (`822–864`) |
| **8. Gap search** | **Implemented but thin by default** | `max_gap_rounds` default **1** (`constants.R:86`; loop `829–864`) |
| **9. “Claim verification”** | **Partially named / split** | Deliberative: falsification + optional `visual_verification`. Legacy: `ingest_assess_model()`. No separate stage literally named “claim verification” |
| **10. Deterministic consistency gate** | **Implemented but soft** | `.library_ledger_consistency_checks()` is real (`610–690`); runs before synthesis (`900–906`) but **does not stop synthesis** |
| **11. Evidence-constrained synthesis** | **Implemented (prompt-constrained)** | Synthesis stage with lane schema (`908–954`); constraint is LLM prompt + ledger dump, not a hard verifier that every field cites a claim id |
| **12. Independent vision extraction** | **Implemented as one-shot dual schema** | `ingest_extract_vision_lane()` — full `.library_lane_schema()`, not deliberative (`ingest-dual.R:198–226`) |
| **13. Field comparison** | **Implemented** | Fingerprinted `library_model_comparison` (`311–360`) |
| **14. Third-model adjudication** | **Implemented** | `ingest_adjudicate_extractions()` (`399–438`); status logic `523–538` |
| **15. machine_consistent / machine_adjudicated** | **Implemented** | Status machine in `ingest_dual_extract` (`521–549`); publish quarantine blocks `validated` (`ingest-catalog.R:422–427`) |
| **16. Versioned catalogue + provenance** | **Implemented** | Staging swap, version archive, ledger copy, audit JSON (`ingest-catalog.R:405–585`) |
| **17. Computational qualification → validated** | **Implemented** | `library_qualification_check` + `library_review` gate (`library-api.R:128–218`, `342–378`) |
| **18. Clinical-use qualification** | **Implemented** | Append-only, issuer-scoped, model hash bound; `qualified` requires catalogue `validated` (`clinical-qualification.R:88–178`, `252–292`) |
| **19. LibeRation handoff** | **Implemented** | `library_use_in_workspace` → `nm_control_read` / `nm_project_save` (`library-workspace.R:14–63`) |
| **20. Reproduction plan/run** | **Implemented** | Fail-closed blockers; auto-run off by default (`reproduction.R`, `constants.R:70–76`) |
| **21. LibeRties queues** | **Implemented** | Typed jobs + worker entry (`liberties-integration.R:30–119`) |
| **22. Legacy one-shot path** | **Still present** | `ingest_extract_batch` / `ingest_extract_model`; deliberative off → one-shot text (`ingest-dual.R:147–189`, `ingest-catalog.R:608–645`) |

### Depth callouts (most important)

**Genuinely deep — not stubs**

```716:803:C:\Users\svdijkman.DESKTOP-4OG10M4\Documents\LibeR\LibeRary\R\ingest-deliberative.R
ingest_deliberative_extract <- function(...) {
 # ... chunk map → reconnaissance → 6 topic investigations →
 # falsification → gap rounds → visual_verification →
 # consistency checks → synthesis
}
```

Stage caches are content-addressed (source hash + prompt version + provider/model + messages):

```356:424:C:\Users\svdijkman.DESKTOP-4OG10M4\Documents\LibeR\LibeRary\R\ingest-deliberative.R
fingerprint <- digest::digest(list(
 source_sha256 = bundle$source$sha256 %||% "",
 prompt_version = LIBRARY_PROMPT_VERSION,
 stage = stage, provider = endpoint$provider, model = endpoint$model,
 ...
), algo = "sha256", serialize = TRUE)
```

**Thin / softer than documentation implies**

1. **Consistency gate does not gate synthesis.** Checks are computed and written into the ledger, then synthesis always runs:

```900:937:C:\Users\svdijkman.DESKTOP-4OG10M4\Documents\LibeR\LibeRary\R\ingest-deliberative.R
checks <- .library_ledger_consistency_checks(ledger)
...
synthesis <- run_stage("synthesis", ..., .library_lane_schema(), ...)
```

Only later does dual-extract demote status:

```542:549:C:\Users\svdijkman.DESKTOP-4OG10M4\Documents\LibeR\LibeRary\R\ingest-dual.R
if (isTRUE(cfg$deliberative$enabled) && isTRUE(model_present) &&
 is.list(checks) && !isTRUE(checks$ready)) {
 status <- "needs_review"
```

So a failing gate still produces a full synthesized extraction object — quarantine is status-level, not pipeline-level.

2. **“Independent dual-lane” is asymmetric under default deliberative mode.** Text lane = multi-stage investigation; vision lane = single multimodal extraction into the same schema. Docs acknowledge independence of *representations*, but the investigative depth is not mirrored.

3. **Retrieval is keyword scoring, not semantic search.** `.library_retrieve_chunks()` counts keyword hits (`ingest-deliberative.R:259–270`). Fine for a first cut; not the “document intelligence” language some readers will infer.

4. **Chromote fetch is heuristic.** Navigate, `Sys.sleep(3)`, CSS selectors for `.pdf` links (`ingest-fetch.R:167–179`). Real code, fragile against modern publisher sites.

5. **`ingest_stub_extraction` is a real fallback**, not aspirational — used when LLM unavailable (`ingest-extract.R:188–191`, `277–295`).

---

## 3. ARCHITECTURE & DESIGN

**Strengths**
- Clear separation: catalogue status ≠ computational qualification ≠ clinical-use qualification.
- Content-addressed document roots: `documents/<pmid>/<sha16>/` (`ingest-docling.R:189`).
- Resumability at two levels: stage caches + article `decision.json` keyed by source hash + pipeline + prompt version (`ingest-process.R:81–96`).
- Atomic catalogue publish with staging directory + rollback (`ingest-catalog.R:429–580`).
- Shared durability helpers (`aaa-shared-durability.R`) for atomic writes.
- Remote content opt-in: `llm.allow_remote_content` (`llm-provider.R:236–238`).
- Secrets scrubbed from saved config (documented; keys via env).

**Concerns**
- **Ledger compaction drops claims** when JSON exceeds char budget (`ingest-deliberative.R:519–548`) — synthesis may never see material claims.
- **Default same model for roles** (`provider = "same"` in `constants.R:108–112`) undermines independence; `require_independent_extraction_models` defaults **FALSE**.
- **Worker path forces** `cfg$llm$allow_remote_content <- TRUE` (`liberties-integration.R:52`, `82`) — intentional for queues, but a footgun if operators assume the local config guard still applies.
- **Generated CTL templates** still inject defaults for missing parameters (`ingest-catalog.R:1–15` templates) — mitigated by `generated_suggestion` / review flags, but still invents structure for incomplete extractions.
- No separate `ARCHITECTURE.md`; README/vignette are the architecture docs and occasionally oversell gate hardness.

---

## 4. CODE QUALITY

**Hotspots (complexity)**
- `ingest-deliberative.R` — orchestration + ledger + schemas (~1k LOC)
- `ingest-catalog.R` — CTL mapping + omega conversion + publish
- `ingest-extract.R` — schemas + JSON repair + structured retries
- `model-semantics.R` — population/structure enrichment
- Shiny ingest app — large operational surface

**Positive patterns**
- Schema validation with `additionalProperties: FALSE` and required fields.
- Structured-output retries with length-limit recovery that **does not** re-feed truncated JSON (`ingest-extract.R:518–525`).
- Probability normalization for `83` / `"79%"` LLM mistakes (`ingest-extract.R:543–584`).
- UTF-8 awareness on Windows in chunk retrieval (tested).

**Fragile / inconsistent spots**
- Claim equality uses 2% relative tolerance + whitespace/case fold (`ingest-dual.R:289–297`) — unit mismatches (“L/h” vs “L/hr”) and scale errors can look “equal” or spuriously disagree.
- OMEGA metric inference heuristics can guess `cv_percent` from description text (`ingest-catalog.R:54–62`) — review flag is set, but values can still land in CTL.
- Qualification smoke-test covariates fabricate WT=70, AGE=40 (`library-api.R:108–112`) — models can “qualify” computationally with dummy covariates.
- Duplication between legacy one-shot prompts (`EXTRACTION_SYSTEM_PROMPT`) and dual/deliberative prompts — maintenance drift risk.
- Error handling generally fail-soft (`continue_on_error = TRUE` default in `ingest_process_batch`) — good for batches, easy to miss silent lane failures unless logs are watched.

---

## 5. LLM & EXTERNAL-API INTEGRATION

**Providers:** `none`, `ollama`, `openai`, `openai_compatible` (`llm-provider.R:10–17`).

**Roles:** triage, indexing, vision, assessment, adjudication (`llm-provider.R:20`).

**Prompt construction**
- Role defaults + optional per-role `instruction` overrides.
- Deliberative stages concatenate stage-specific prompts; historical role defaults intentionally suppressed except synthesis (`ingest-deliberative.R:48–56`).
- Vision/adjudication use `library_image_message` → data URLs; Ollama adapter unwraps to `images` array (`llm-provider.R:332–374`).

**Output validation**
- Provider schema (`format` / `response_format`) + local `.library_validate_structured_value` after parse.
- JSON fence strip, first-complete-object extraction, trailing-comma repair; refuses inventing truncated string values (`ingest-extract.R:314–371`).

**Retries / cost**
- `structured_retries` default 1, capped at 3 (`ingest-extract.R:475–477`).
- Token usage retained in audits; no cost accounting / budget guard.
- Ollama context expansion on length failures (up to 32768).

**Hallucination handling**
- Prompt discipline + schema + ledger prompts + consistency checks + dual-lane comparison + adjudication.
- **No** hard post-synthesis claim-id binding or quote-existence check against source text for the final schema (legacy assess path does optional quote grepping when LLM assessment unavailable — weak).

**External APIs**
- Entrez: email required; throttle via `requests_per_second`; optional `ENTREZ_KEY` (`ingest-throttle.R:20–38`).
- Unpaywall/Europe PMC/PMC OA: throttled; failures → `NULL` / empty (soft).
- PDF download validates magic bytes (`test-ingest-utils.R:22–27`).
- Docling timeout configurable (default 1800s).

**Secrets**
- API keys from env (`OPENAI_API_KEY`, `OLLAMA_API_KEY`, `LIBERARY_LLM_API_KEY`, `ENTREZ_KEY`).
- Documented never written to `config.yml`.
- `ingest_configure_entrez` can `Sys.setenv(ENTREZ_KEY=...)` from in-memory config for the session.

---

## 6. CORRECTNESS RISKS / BUGS

### High-impact risks

1. **Soft consistency gate** — failed checks still synthesize a complete model; only status becomes `needs_review`. Downstream UIs that emphasize “extraction complete” can over-trust content.
2. **Prompt-only evidence constraint** — synthesis is instructed to use only the ledger; nothing verifies field↔claim linkage programmatically.
3. **Asymmetric dual lane** — deliberative text vs one-shot vision; “agreement” can mean two different methods agreed, not two equal investigations.
4. **CTL generation with inferred metrics / template defaults** — can produce runnable but wrong control streams; relies on review flags.
5. **Untrusted document ingestion** — PDFs/HTML from publishers fed to local/remote LLMs and Docling; remote guard exists, but queue worker disables it. No sandboxing of Docling/chromote beyond OS process.

### Medium

6. Ledger compaction can omit high-value low-confidence claims (sorted by confidence then truncated).
7. Adjudication prompt dumps **both full lane JSON + comparison + parser text + page images** — huge context; truncation/`max_pdf_chars` can hide the decisive evidence.
8. Clinical `qualified` correctly requires catalogue `validated`, but computational qualification’s dummy covariates weaken the compile/simulate gate’s meaning.
9. Resume logic treats `needs_review` as terminal (`ingest-process.R:90–92`) — good for not looping, bad if users expect automatic re-try after fixing models.

### TODO / FIXME / HACK / BUG / WIP

Grep across `R/` and docs found **no meaningful `TODO`/`FIXME`/`HACK`/`XXX`/`BUG`/`WIP` markers**. “stub” appears as a **first-class status**, not unfinished code. That is unusual — either very clean, or unfinished work isn’t tagged.

### Half-finished relative to marketing language

- “Claim verification” as a named pipeline stage: **not present**; covered by falsification/assessment.
- Semantic/docling-structure-aware retrieval: **not present** (keyword chunks).
- Hard evidence→field proof for synthesis: **not present**.

---

## 7. TESTS

**Breadth — good for unit/integration of machinery; thin for live LLM/network truth.**

| Area | Coverage quality |
|------|------------------|
| Chunk retrieval / UTF-8 | Strong (`test-deliberative-pipeline.R`) |
| Stage cache resume | Strong (fake chat, call count = 1) |
| Consistency gate unit | Present (conflict + missing evidence) |
| Full deliberative orchestration | Present with **schema fixture chat** (not a real model) |
| Dual comparison | Strong |
| Document bundle / Docling runner hook | Strong with mocks |
| JSON parse/repair/retries | Strong (`test-ingest-utils.R`) |
| Clinical qualification | Strong |
| Catalogue quarantine / AEDapt | Present |
| Reproduction blockers / ADVAN inference | Present |
| Browser E2E | **Skipped** unless `LIBER_RUN_BROWSER_TESTS=true` (`test-browser-e2e.R:1–3`) |
| Packaged catalogue API | `skip_if_not(dir.exists(system.file("catalog"...)))` |
| Live PubMed / Unpaywall / Ollama | **Not exercised** in CI-style tests; network paths mocked |

**Assertion quality:** Generally specific (pipeline stage names, fingerprints, blocker ids). Fixture-driven deliberative test forces `overall_ready <- FALSE` and still expects synthesis success — which **documents** that failed readiness does not abort the pipeline.

**Gaps:** No property tests that synthesized fields ⊆ ledger claims; no adversarial PDF/HTML; no rate-limit/error injection for rentrez beyond throttle timing; no real vision-model fixture images.

---

## 8. DOCUMENTATION vs CODE

Docs are **mostly accurate** about structure and are unusually careful about “machine ≠ validated”. Over-claims / soft language:

| Documentation claim | Code reality |
|---------------------|--------------|
| Deterministic checks “run before” synthesis and readiness language (`vignettes/LibeRary-workflow.Rmd:113–115`, README) | Checks run, but **do not block** synthesis; only demote status later |
| “Evidence-constrained synthesis” | Prompt + ledger dump; **not** a hard verifier |
| Independent dual extraction | True for modalities; **false for investigative depth** when deliberative is on |
| “Searchable document evidence map” | Keyword chunk score, not embeddings/structure graph |
| Chromote institutional acquisition | Real but brittle heuristic |
| LibeRties “same typed job envelope” | Real and implemented |
| Clinical qualification “never imply human validation” for machine states | **Sound** for `machine_*` vs `validated` vs clinical `qualified` |

README example still shows `library_search(..., status = "validated")` and synthetic theo — fine, but operators must not equate AEDapt `review`/`candidate` packaged models with validated clinical readiness (NEWS correctly stresses this).

---

## 9. TOP STRENGTHS

1. **Deliberative pipeline is real engineering**, not a README fiction — schemas, caches, ledger, gap rounds, visual falsification.
2. **Honest status vocabulary** (`machine_consistent` / `machine_adjudicated` / quarantine from `validated`) with publish-time enforcement.
3. **Layered qualification**: computational gate + human review + issuer-scoped clinical records bound to model hash/version.
4. **Operational durability**: content-addressed bundles, atomic catalogue swaps, resumable decisions/stages.
5. **Defensive LLM JSON handling** (repair only safe damage; expand context on truncation; normalize percent confidences).
6. **Conservative reproduction planning** — blockers instead of silent unit guesses.
7. **Substantial packaged research corpus** (AEDapt migrations with provenance) plus reference-corpus / release-gate tooling.

---

## 10. PRIORITIZED RECOMMENDATIONS

### High
1. **Make consistency gate hard-optional:** if `!checks$ready`, skip synthesis or emit an explicit non-model / review-only artifact; never publish a full synthesized CTL as if investigation succeeded.
2. **Post-synthesis binding check:** every major field in the final schema must reference ledger claim ids whose values match (or mark unresolved).
3. **Default or strongly warn for independent text/vision models** when adjudication is enabled; keep correlation warning but treat same-model as non-independent by default.
4. **Stop inventing OMEGA metrics from prose** without an explicit reported_metric; leave review-required nulls instead.

### Medium
5. Mirror a thinner deliberative path on vision (or feed vision only as falsification, not a competing full extraction) to make “dual lane” semantics coherent.
6. Raise default `max_gap_rounds` or make GUI expose “not ready → force another gap round” before synthesis.
7. Add tests: ledger⊇synthesis invariants; failing consistency ⇒ no `machine_*` status; worker `allow_remote_content` behavior documented in UI.
8. Replace chromote `sleep(3)` + CSS scrape with download-event interception or clearer “manual inbox drop” UX when automation fails.
9. Qualification smoke test: require declared covariates from extraction or skip simulate rather than fabricating WT/AGE.

### Low
10. Extract shared prompt fragments to reduce one-shot vs dual drift.
11. Add cost/token budgets per batch.
12. Publish a short `ARCHITECTURE.md` that marks stages **hard gate / soft gate / prompt-only** to match reality.
13. Tag unfinished work with `TODO` if any remaining aspirational features (e.g. semantic retrieval) are planned.

---

**Bottom line:** LibeRary 0.7.11 is a **serious, largely complete** literature→model repository. The README pipeline is not aspirational theater. Treat `machine_consistent` / synthesized CTLs as **research candidates under soft gates**, and treat documentation’s “deterministic consistency before synthesis” as **ordering**, not **enforcement**.

---

### 3.5 LibeRator 0.3.5

> _Reviewer summary:_ LibeRator 0.3.5 is a carefully designed research MIPD workbench (~8.5k R LOC) with strong audit/encryption scaffolding and deliberate non-prescription UX, but several clinical-correctness gaps remain: MAP/Laplace uncertainty treated as posterior, residual error likely ignored in endpoint metrics, default LOCF filling explicitly missing covariates, and `research_only`/`qualified` labels that are metadata-only rather than enforced gates.

# LibeRator 0.3.5 — Critical Read-Only Review

**Verdict:** Strong research-workbench architecture with real honesty about non-device status in UX and docs, but several **clinical-correctness gaps** undercut the Bayesian / covariate / uncertainty story. Encryption and immutability are serious for a local research tool; they are **not** institutional clinical-grade controls. `research_only` and endpoint `qualified` are **labels, not gates**.

---

## 1. OVERVIEW

| Item | Finding |
|------|---------|
| **Purpose** | Longitudinal MIPD: encrypted patient timelines, AD-backed MAP individualisation via LibeRation, versioned endpoints, regimen ranking under ETA uncertainty, Shiny/React workbench. Explicitly Research / not a medical device. |
| **Version** | 0.3.5 (`DESCRIPTION`) |
| **Approx LOC** | **~8,500** lines under `R/` (largest: `endpoints.R` ~1,626; `gui.R` ~1,515; `assessment.R` ~1,024; `regimen.R` ~760; `patient.R` ~617). Tests ~2,500 lines. |
| **Exported functions** | **51** `export()` symbols + 5 S3 `print` methods (`NAMESPACE`) |
| **Test files** | **14** `test-*.R` + `helper-model.R` |
| **Structure** | `R/` (core + GUI + shared durability/async), `tests/testthat/`, `inst/htmlwidgets/` (React workbench), `man/`, one vignette, `SECURITY.md`, `README.md`, `NEWS.md`. Teaching examples live in `R/example.R` (not `inst/lator_example_aed`). |

Key deps match stated role: LibeRation, sodium, digest, jsonlite, shiny/reactR/htmlwidgets, callr, stats.

---

## 2. ARCHITECTURE & DESIGN

**Patient timeline / state**
- Append-only events; corrections via `supersedes` + mandatory reason/actor (`patient.R`).
- Therapies, endpoint snapshots, assessments, model selections hang off the patient record; persisted as one encrypted blob.

**Endpoint versioning**
- Serializable `lator_endpoint` with `id@version`, status enum, multi-endpoint sets with hard chance constraints + utility (`endpoints.R`).
- Patient-specific snapshots + supersession metadata in GUI.

**Individualisation engine**
- Dataset assembly (doses/TDM/covariates/OCC) → `LibeRation::nm_individual_fit` → assessment artifact with hashes, ETA, covariance, profiles (`assessment.R`).
- Dynamic mode remaps model to IOV-on-`OCC` + random-walk prior covariance.

**Recommendation / comparison flow**
- Grid → batched `nm_simulate` with ETA draws → endpoint scoring → rank → **explicit** `select_regimen` / `lator_regimen_predict` (no auto-prescribe).

**Concerns**
- Full `model` stored inside assessments (`assessment.R` ~1029) → large, sensitive patient blobs; unbounded assessment history.
- Complexity concentrated in `gui.R` + `endpoints.R` + `assessment.R` (hard to audit end-to-end).
- Governance status (`qualified`) on endpoints is **caller-asserted**, unlike fail-closed LibeRary model selection.

---

## 3. CLINICAL-SAFETY & CORRECTNESS (core)

### Bayesian individualisation & uncertainty

**What it actually does:** empirical-Bayes / MAP via LibeRation’s C++/AD objective, not MCMC.

```949:972:C:\Users\svdijkman.DESKTOP-4OG10M4\Documents\LibeR\LibeRator\R\assessment.R
 prepared_model <- if (mode == "dynamic") .lator_dynamic_model(model) else model
 ...
 fit <- do.call(LibeRation::nm_individual_fit, c(fit_arguments, list(...)))
```

Regimen “posterior” draws:

```415:415:C:\Users\svdijkman.DESKTOP-4OG10M4\Documents\LibeR\LibeRator\R\regimen.R
 eta_samples <- .lator_sample_mvn(assessment$eta, assessment$eta_covariance, nsim)
```

**Critical issues**
1. **Laplace/MAP covariance treated as clinical posterior.** Forecasts claim `"individual_eta_posterior"` (`regimen.R` 756–760) while excluding residual and θ uncertainty — honest in fields, easy to over-trust as full Bayesian predictive.
2. **`residual = TRUE` is almost certainly ineffective for attainment.** Endpoint metrics prefer `IPRED` over `PRED`/`DV`:

```586:589:C:\Users\svdijkman.DESKTOP-4OG10M4\Documents\LibeR\LibeRator\R\endpoints.R
 value <- intersect(c("IPRED", "PRED", "DV", "value", "concentration"), names(predictions))[1L]
```

Docs say residual affects attainment (`regimen.R` 384–385); **no test uses `residual = TRUE`**. Likely silent understatement of predictive uncertainty.
3. **Default `residual = FALSE`**; GUI never exposes residual (`gui.R` optimise path ~1315).
4. **Dynamic RW prior** `process_scale = 0.1` of Ω is uncalibrated (`assessment.R` 905, 222–238). Math form `Ω + (min(i,j)-1)·Q` is a standard RW prior, but clinically arbitrary.
5. **Sparse / misspecified data:** readiness checks for dynamic mode are good; static mode still fits with few TDM points; no automatic escalation for non-identifiability beyond convergence diagnostics.
6. **MIC aggregation bug risk:** vancomycin/aminoglycoside path uses `max(resolved$value)` for MIC over the interval (`endpoints.R` 575–583) — wrong if MIC is time-varying (beta-lactam path is time-aligned; inconsistency).

**Numeric bright spots:** analytic virtual-patient ETA recovery (`test-analytic-validation.R`); Rivas/AEDapt lamotrigine parity (`test-assessment.R` 376–441); known bad LibeRary translation rejected (`models.R` 42–54).

### Covariate “never invent values”

**Enforced for population inventing; not for LOCF inventing.**

Default policy if caller omits policies:

```176:176:C:\Users\svdijkman.DESKTOP-4OG10M4\Documents\LibeR\LibeRator\R\covariates.R
 policy <- policies[[name]] %||% policies[[toupper(name)]] %||% list(method = "locf")
```

Unresolved required covariates hard-stop (`assessment.R` 213–216) — good; tested (`test-assessment.R` 226–228).

But **explicitly missing scheduled values still get a numeric LOCF fill** labelled `resolved_after_missing` (`covariates.R` 118–123, 106–107; vignette lines 40–40). DESCRIPTION’s broader “without silently inventing values” overclaims relative to default LOCF.

Endpoint MIC helper also hardcodes `method = "locf", max_age = Inf` (`endpoints.R` 577–578) with no age honesty.

### Recommendation framing / autonomous-instruction risk

**Mostly well guarded**
- Comparison sets `research_only = TRUE` (`regimen.R` 638, 777).
- `lator_regimen_predict` requires explicit `candidate_id`; docs: ranking is not automatic dosing (`regimen.R` 642–648).
- GUI: “does not issue an autonomous prescription”; “Ranking is not an automatic dose recommendation” (`liberatorWorkbench.js` 149, 421).
- Unlock banner: Research / not clinically validated (`gui.R` 428).
- Loopback bind by default (`gui.R` 52–53).

**Soft instruction pressure**
- Top eligible row gets `lr-best` + “highest ranked” (`liberatorWorkbench.js` 426–430).
- Drug presets prefill guideline-like numerics (phenytoin 10–20, vancomycin 400–600, warfarin INR 2–3) (`endpoints.R` 1180–1246) — editable and sourced, but look clinical.
- Package title “Optimisation and Recommendation” vs “does not issue … instructions” — branding tension.

**No code path blocks clinical-looking output** when `research_only` is true; flag is never read for control flow (only written).

### Edge cases
- 24 h dosing-interval fallback with `assumed = TRUE` warning (`assessment.R` 349–356, 850–852).
- Steady-state-mean-only models correctly refuse peak/trough curves.
- Extrapolation beyond evidence horizon is the whole point of regimen compare — uncertainty incomplete (above).
- Assessments discarded on concurrent evidence change in GUI (good) (`gui.R` 1431–1444).

---

## 4. PATIENT-DATA PROTECTION

### Encryption design
| Piece | Behaviour |
|-------|-----------|
| Cipher | `sodium::data_encrypt` → documented as libsodium XSalsa20-Poly1305 (`workspace.R` 81, 153–163) — AEAD secretbox w/ random nonce inside payload |
| KDF | Argon2id preferred; scrypt fallback on Windows memory failure (`workspace.R` 67–76) |
| Managed key | 32-byte raw key; passphrase path blocked (`workspace.R` 95) |
| Filenames | HMAC/`data_tag` tokens, not clear patient IDs (`workspace.R` 192–193) |
| Atomic write | temp → rename + `.previous` recovery (`aaa-shared-durability.R`) |

### Gaps (High / Medium)
1. **Key in memory** on unlocked `lator_workspace`; SECURITY.md admits compromised R session wins (`SECURITY.md` 20–21).
2. **`workspace.json` cleartext:** salt, verifier, kdf, `research_only` (`workspace.R` 79–84) — expected for KDF, still attack surface for offline guessing.
3. **No RBAC / SSO / session expiry / dual control** (`SECURITY.md` 25–26) — single passphrase = full decrypt.
4. **Audit chain is key-holder–tamperable:** hash chain verified only after decrypt (`workspace.R` 219–230); no WORM / external timestamp (`SECURITY.md` 24).
5. **Audit stores `object_token`, not object_id** (`workspace.R` 205) — accountability requires knowing the id.
6. **Queue de-ID is heuristic** on column names (`jobs.R` 21–22); `ID`/`patient_id` not blocked; assessment datasets set `ID = patient$patient_id` (`assessment.R` 132).
7. **Background `callr` jobs** receive full patient/assessment objects (no key — good; data still in process).
8. **Catalog/labels encrypted**, but teaching/demo labels and study_ids are still content once unlocked.

Tests do verify ciphertext doesn’t contain clear pseudonym (`test-workspace.R` 16–18) — good for at-rest scope.

---

## 5. CODE QUALITY

**Hotspots:** `gui.R` (~1.5k), `endpoints.R` (~1.6k), `assessment.R` (~1k) — mixed UI, clinical math, and storage.

**Strengths:** optimistic revision locks; immutable corrections; shared durability helpers; fail-closed model selection; known-bad model rejection.

**Fragile spots**
- Default LOCF + Inf `max_age` on endpoint covariates.
- `rbind(eta_samples, eta_samples)` for TRANS/STEADY batching (`regimen.R` 473–475) — depends on LibeRation ID/`eta` row alignment; easy to break silently.
- Eigenvalue clamp `pmax(eig$values, 0)` in sampling (`regimen.R` 43) can hide non-PSD Hessian issues.
- GUI complexity: many event actions; stale-result discard logic is careful but dense.
- Generated shared files (`aaa-shared-*.R`) — sync discipline required.

**Error handling:** generally `.lator_stop` with clear messages; decrypt failures authenticated.

**Duplication:** endpoint kind evaluators + template builders are verbose but consistent.

---

## 6. CORRECTNESS RISKS / BUGS

| Risk | Severity | Evidence |
|------|----------|----------|
| Residual flag doesn’t affect endpoint metrics (IPRED preference) | **High** | `endpoints.R` 588; `regimen.R` 384–385; no `residual=TRUE` tests |
| MIC via `max()` over interval | **High** | `endpoints.R` 575–583 |
| Default LOCF invents values at explicitly missing times | **High** (honesty / safety) | `covariates.R` 176, 118–123; DESCRIPTION vs README nuance |
| MAP/Laplace sold as “posterior” in UX/schema | **Medium–High** | `regimen.R` 756–758; package docs |
| `research_only` / endpoint `qualified` not enforced | **Medium** | grep: only assigned, never gated |
| Uncalibrated `process_scale` | **Medium** | `assessment.R` 905 |
| Assessment history unbounded in encrypted patient | **Medium** | `assessment.R` 1032–1035; GUI append |
| Queue ID leakage | **Medium** | `assessment.R` 132; `jobs.R` 21–22 |
| Soft “highest ranked” UI cue | **Low–Medium** | `liberatorWorkbench.js` 426–430 |

**TODO/FIXME/HACK/XXX/BUG/WIP:** essentially **none** in `R/` (only UI “placeholder” on passphrase input). Incomplete features show up as metadata flags and SECURITY “not solved” list rather than TODOs.

**Skipped tests**
- `test-gui-async.R:63` — `skip_if_not_installed("callr")`
- `test-models-jobs.R:24` — LibeRties ≥ 0.6.1
- `test-browser-e2e.R:2–3` — shinytest2 + `LIBER_RUN_BROWSER_TESTS=true`

---

## 7. TESTS

| Area | Coverage | Quality |
|------|----------|---------|
| Individualisation numerics | Analytic ETA; AEDapt parity; static/dynamic smoke | **Strong** where present |
| Covariates | Provenance, LOCF-after-missing, linear, supersede, COMED | Good; **does not** assert “refuse invent” |
| Crypto / audit | Encrypt, wrong passphrase, managed key, revision conflict, delete+audit | Solid for local AEAD |
| Endpoints / multi-endpoint | Joint draws, presets, MIC LOCF | Good breadth |
| Regimen + uncertainty metadata | Rank order, forecast labels | Checks schema fields; **nsim=4** often |
| Residual predictive uncertainty | **Absent** | Gap |
| Laplace covariance calibration | **Absent** | Gap |
| Browser E2E | Opt-in skip | Thin |
| Jobs | Minimal | Thin |

Assertion quality is generally behaviour-focused (convergence, ETA tolerance, hashes), not just “doesn’t error.”

---

## 8. DOCUMENTATION

**Accurate / honest**
- DESCRIPTION + README + SECURITY: Research label = validation status; not a medical device; not autonomous instructions.
- SECURITY.md threat model is unusually candid (session key, weak passphrase, no IdP).
- Uncertainty exclusions documented on forecast artifacts.
- Vignette correctly explains LOCF-after-missing with provenance.

**Over-claims / inconsistencies**
1. DESCRIPTION: “without silently inventing values” vs default LOCF inventing with only status labels.
2. README “empirical-Bayes” vs UI/schema “posterior.”
3. `residual` docs vs IPRED evaluation.
4. Endpoint `qualified` “not a certification” (`endpoints.R` 13–14) but UI offers the status freely — easy to misread as certified.
5. Teaching vignette runs `mode = "dynamic"` on example that *does* have boundaries — OK; still easy to copy without understanding identifiability.

---

## 9. TOP STRENGTHS

1. **Deliberate human-in-the-loop regimen selection** (API + GUI + callouts).
2. **Immutable evidence + correction tombstones** with actor/reason/hash lineage.
3. **At-rest AEAD + Argon2id + opaque filenames + optimistic concurrency.**
4. **Fail-closed LibeRary qualification gates** (models), plus known-bad translation reject.
5. **Covariate provenance model** (status/age/source) and hard-stop on unresolved *required* covariates when no fallback.
6. **Concrete numeric regression tests** (analytic VP, AEDapt) uncommon in dosing R packages.
7. **Honest SECURITY.md** clinical-hardening boundary.

---

## 10. PRIORITIZED RECOMMENDATIONS

### High (clinical-safety first)
1. **Fix residual uncertainty path:** evaluate attainment on residualised predictions when `residual=TRUE` (or remove/rename the flag); add tests; expose in GUI with clear wording.
2. **Stop calling MAP/Laplace draws a full “posterior” in clinician-facing UI** unless θ + residual + model uncertainty are included or explicitly unavailable with blocking warnings.
3. **Fix MIC resolution:** time-align MIC (or reject unresolved/stale); never `max()` over the window for AUC/MIC or peak/MIC.
4. **Tighten covariate honesty:** default to `method = "none"` (or require explicit policy); do not numeric-fill times with `scheduled_missing` unless policy opt-in; align DESCRIPTION language with behaviour.
5. **Gate `status = "qualified"`** (endpoint and any clinical export) behind issuer attestation + research acknowledgement; keep draft as default for all auto-presets.

### Medium
6. Enforce or surface `research_only` on exports/print/GUI watermark; never omit in PDF/CSV if those appear later.
7. Audit: store salted object id or dual fields; optional external append-only log.
8. Queue payload: strip/rename `ID` to opaque study codes; broaden identifier heuristics.
9. Document and sensitivity-test `process_scale`; require explicit value for dynamic mode in GUI.
10. Cap or archive assessments; avoid embedding full models if a hash + registry id suffices.
11. Add tests for TRANS/STEADY `eta` row alignment and non-PSD `eta_covariance`.

### Low
12. Soften “highest ranked” / `lr-best` styling; prefer neutral rank numbers.
13. Expand browser E2E in CI; reduce LibeRties skip fragility.
14. Rename product language away from “Recommendation” in clinical-adjacent surfaces if device positioning remains Research-only.

---

**Bottom line:** LibeRator is one of the more carefully framed research MIPD codebases in this ecosystem — encryption, immutability, and non-autonomous UX are real. For anything approaching clinical decision support, the weak links are **incomplete uncertainty propagation (especially residual/IPRED)**, **default LOCF inventing “missing” covariates**, **MIC aggregation**, and **governance labels that do not constrain behaviour**.

---

### 3.6 LibeRality 0.2.12

> _Reviewer summary:_ LibeRality’s continuous FO FIM matches PopED/PFIM to ~1e-6–1e-11 under fo_block, but non-continuous/TTE paths, allocation optimisation, and several criteria are simplified or misdocumented relative to the marketing surface.

# LibeRality 0.2.12 — Critical Read-Only Review

## 1. OVERVIEW

**Purpose.** Model-informed evaluation / optimisation / robustness / simulation of clinical-trial designs for NLME PK/PD, reusing LibeRation models and LibeRtAD-backed prediction sensitivities. Design objects are serialisable; an amber→Mineral Slate React workbench sits on top.

**Scale (approx., from file ends).**
| Layer | Approx LOC | Notes |
|---|---|---|
| R (`R/*.R`, 23 files) | ~6,500 | Dominated by GUI/templates/criteria |
| C++ (`src/`) | ~180 | `information.cpp` (~130) + `RcppExports.cpp` (~50) |
| Tests (`tests/testthat/`) | ~14 files, **41** `test_that` blocks | Heavy GUI skew |

**Exports.** **62** `export(...)` entries in `NAMESPACE` (criteria helpers inflate the count; core API is smaller).

**Structure.**
- Math: `R/information.R`, `src/information.cpp`, `R/criteria.R`, `R/optimise.R`, `R/simulation.R`
- Design model: `R/design.R`, `R/variables-constraints.R`, `R/design-templates.R`, `R/example.R`
- Validation: `R/external-validation.R`, `inst/extdata/external-validation-baseline.json`, vignette
- Integration: `R/integration.R` (LibeRary / LibeRation / LibeRties)
- UI: `R/gui*.R`, `R/model-browser.R`, `inst/htmlwidgets/`
- Docs: `README.md`, `NEWS.md`, 3 vignettes, dense `man/`

**Verdict in one line.** Continuous population-FO FIM vs PopED/PFIM is genuinely excellent under `fo_block`; the broader “29 criteria / 5 outcome types / hybrid optimiser” surface is largely **implemented enough to run**, but several non-continuous, TTE, allocation, and criterion paths are **working approximations or misdescribed** relative to the package claims.

---

## 2. OPTIMAL-DESIGN MATH (CORE)

### 2.1 Continuous FIM assembly — largely sound

C++ assembler implements the MVN expected information with mean + covariance terms:

```68:86:C:\Users\svdijkman.DESKTOP-4OG10M4\Documents\LibeR\LibeRality\src\information.cpp
 Eigen::MatrixXd information = Dmu.transpose() * inverse * Dmu;
 ...
 const double covariance_information =
 0.5 * (products[static_cast<std::size_t>(i)] *
 products[static_cast<std::size_t>(j)]).trace();
 information(i, j) += covariance_information;
```

That is the standard form
\(\partial\mu^\top V^{-1}\partial\mu + \tfrac12\mathrm{tr}(V^{-1}\partial_i V\,V^{-1}\partial_j V)\).

R-side population FO:

```195:259:C:\Users\svdijkman.DESKTOP-4OG10M4\Documents\LibeR\LibeRality\R\information.R
 V <- if (ncol(G)) G %*% omega_matrix %*% t(G) + residual else residual
 ...
 # PopED and PFIM use the conventional block-diagonal population-FO FIM:
 if (identical(approximation, "fo_block") && length(theta_rows)) {
 dV[theta_rows] <- replicate(length(theta_rows), matrix(0, nrow(V), ncol(V)), simplify = FALSE)
 }
 assembled <- lity_fim_cpp(Dmu, V, dV, tolerance)
```

- Default `full_gaussian` keeps \(\partial V/\partial\theta\) (extra fixed-effect covariance information).
- `fo_block` zeros those derivatives → conventional PopED/PFIM block structure. Explicit and correct intent.

**Sensitivity source — mixed exact / FD (overclaim risk).**
- Mean Jacobian: `LibeRation::nm_prediction_derivatives` → diagnostics claim `"exact CppAD"` (`information.R:368`).
- OMEGA → \(V\): analytic (`information.R:231–237`).
- Residual / \(\partial V/\partial\theta\) / \(\partial V/\partial\sigma\): **centred finite differences** (`information.R:207–248`, `.lity_numerical_matrix_derivative`).

So “exact sensitivities” is true for \(\partial\mu/\partial\theta,\partial\mu/\partial\eta\), **not** for the full FIM.

### 2.2 Non-continuous / TTE — simplified working models

```106:144:C:\Users\svdijkman.DESKTOP-4OG10M4\Documents\LibeR\LibeRality\R\information.R
.lity_response_moments <- function(mu, H, G, endpoint, time) {
 ...
 if (endpoint$type == "ordinal") {
 ...
 step <- pmax(1e-6, abs(mu) * 1e-6)
 derivative <- vapply(...) # FD of category mean
 }
 ...
 } else {
 hazard <- pmax(response, 1e-12)
 ...
 response <- hazard * delta # TTE / fallback: Poisson interval counts
 variance <- response
 }
```

| Outcome | What code actually does | Concern |
|---|---|---|
| Binary | Bernoulli variance, then **same MVN FIM** | Quasi / working-Gaussian, not exact GLMM FIM |
| Count / NB | Poisson or NB variance → MVN FIM | Same |
| Ordinal | Moments of category scores + **FD** mean derivative | Not multinomial ordinal information |
| TTE | Hazard × interval width, Poisson variance | Crude counting-process FO; last \(\Delta t\) = median gap |
| Recurrent | Same else-branch as TTE for FIM | OK-ish for Poisson process; not distinct |
| Weibull | Accepted in API (`design.R:107`, `dispersion` as “Weibull shape”) | **Never used in FIM** — only NB uses `dispersion` |

Multi-endpoint: each endpoint’s FIM is computed separately and summed (`information.R:319–327`); diagnostics admit `"endpoint_blocks = block diagonal..."`. Shared random-effects cross-endpoint covariance is ignored.

### 2.3 TTE FIM vs simulation inconsistency (bug-level)

FIM uses `hazard * delta` (`information.R:140`). Simulation draws `rpois(..., hazard)` **without** \(\Delta t\):

```27:29:C:\Users\svdijkman.DESKTOP-4OG10M4\Documents\LibeR\LibeRality\R\simulation.R
 } else {
 hazard <- pmax(response, 1e-12)
 data$DV[rows] <- stats::rpois(sum(rows), hazard)
```

Operating characteristics from simulation will not match TTE FIM scale.

### 2.4 Criteria — implemented, but several are aliases / simplifications

Classical D/A/E/Ds/c/L/RSE/power have analytic tests and look correct. Notable issues:

1. **`bayesian` ≡ `robust`** — identical aggregation (`criteria.R:529`).
2. **`model_average` does not average models.** It averages **scenario FIMs**, then evaluates the base criterion:

```479:484:C:\Users\svdijkman.DESKTOP-4OG10M4\Documents\LibeR\LibeRality\R\criteria.R
 if (criterion$type == "model_average") {
 matrices <- lapply(information, `[[`, "matrix")
 averaged <- Reduce(`+`, Map(function(matrix, weight) matrix * weight, matrices, weights))
 value <- .lity_direct_value(criterion$base, .lity_information_for_matrix(averaged, values), ...)
```

 Guidance claims competing structural models (`criterion-guidance.R:139–146`). `alternative_models` is only used in discrimination (`criteria.R:295`).

3. **ED** is classical \(\log E[\det F]\), not \(E[\log\det F]\) (Bayesian D). Documented honestly in NEWS/guidance; still easy to confuse with `bayesian(D)`.

4. **Local D uses only scenario 1** (`criteria.R:530`); other scenarios’ FIMs are computed then discarded unless wrapped.

5. **Ds** via \(-\log\det(\mathrm{Cov}_{ss})\) is the Schur form — correct (`criteria.R:241`).

6. **Discrimination / clinical criteria** are lightweight: residual-level KL/T on IPRED, IPRED target attainment, “correct dose” = pick arm with lowest target loss — far thinner than the prose.

### 2.5 Optimiser — mixed-variable OK; allocation ignores criterion

- Continuous: L-BFGS-B; discrete/integer: coordinate exchange / PSO; hybrid: PSO + local L-BFGS-B (`optimise.R:207–259`).
- Constraints: quadratic penalty (`optimise.R:69`) — soft, not exact feasible-set optimisation.
- **Allocation (`multiplicative` / `fedorov_wynn`) always uses D-optimal sensitivity** \(\mathrm{tr}(F^{-1} M_i)\):

```167:172:C:\Users\svdijkman.DESKTOP-4OG10M4\Documents\LibeR\LibeRality\R\optimise.R
 directional <- vapply(per_subject, function(matrix) sum(diag(inverse %*% matrix)), numeric(1))
 ...
 if (method == "multiplicative") weight <- .lity_normalize_weights(weight * pmax(directional, 1e-12))
```

 Criterion is only evaluated for tracing; updates ignore A/c/power/etc. **High correctness risk** if used with non-D objectives.

### 2.6 Pareto

Random Latin-ish sampling + non-domination (`optimise.R:310–336`). No NSGA-II / weighted Tchebycheff search. Fine as exploration; not a production multi-objective optimiser.

### 2.7 Simulation / OC

Complete-trial simulation via LibeRation + operational dropout/adherence/missed samples is real. `lity_operating_characteristics` returns bias/RMSE/convergence when `fit=TRUE`, but **no coverage** despite vignette claim (`optimal-design.Rmd:98`; `simulation.R:294–313` returns empty `coverage`).

---

## 3. ARCHITECTURE & DESIGN

**Design data model.** Typed S3 contracts (`liberality.design`, arms, endpoints, scenarios, variables, constraints, prior_fim) with hash/provenance — strong for serialisation and LibeRties handoff (`integration.R:117–148`).

**Reuse.**
- Predictions/derivatives: LibeRation
- Linear algebra: LibeRtAD Eigen bridge in C++
- Estimation/NCA/simulation: LibeRation
- Jobs: LibeRties `optimal_design`

**C++ boundary.** Thin and appropriate: only FIM assembly + matrix metrics. Almost all design logic stays in R.

**Concerns.**
- GUI/templates LOC ≫ math LOC → review/maintenance risk on the science path.
- FIM approximation mode is a silent default (`full_gaussian`); external engines need `fo_block`.
- Custom constraint/utility functions break queue serialisation (partially acknowledged for utility).

---

## 4. CODE QUALITY

**Hotspots.** `criteria.R` (~578), `external-validation.R` (~558), `gui.R` (~598), `design-templates.R` (~673), `information.R` (~386).

**Duplication.** Bayesian/robust; model_discrimination ≈ KL; exponential-error temporary-model blocks repeated four times in `information.R`.

**Error handling.** Generally fails loud via `.lity_stop`; optimiser swallows evaluation errors into huge penalties (`optimise.R:61–65`) — can hide model bugs as “bad designs”.

**Fragile spots.**
- ETA column name heuristics (`information.R:162–167`).
- TTE last-interval = median gap.
- PFIM combined-error Jacobian scaling is careful but convention-specific (`external-validation.R:278–282`).
- Soft constraint penalties dominate hard feasibility.

---

## 5. CORRECTNESS RISKS / BUGS

| Severity | Issue | Evidence |
|---|---|---|
| **High** | Allocation opt always D-sensitive | `optimise.R:167–172` |
| **High** | TTE FIM uses \(\lambda\Delta t\); sim uses \(\lambda\) | `information.R:140` vs `simulation.R:29` |
| **High** | Weibull accepted, ignored in FIM | `design.R:107–129` vs no `weibull` in `information.R` |
| **High** | `model_average` ≠ structural model averaging | `criteria.R:479–484` vs guidance |
| **Medium** | Non-continuous = working MVN / moments, not distributional FIM | `information.R:106–144,200` |
| **Medium** | Ordinal mean Jacobian = FD | `information.R:117–120` |
| **Medium** | Residual/\(\sigma\)/\(\theta\)-\(V\) derivatives = FD | `information.R:147–153,207–248` |
| **Medium** | Multi-endpoint independence | `information.R:370–371` |
| **Medium** | Coverage OC undocumented missing | vignette vs `simulation.R:297` |
| **Low** | `bayesian`/`robust` aliases | `criteria.R:529` |
| **Low** | Local criteria ignore non-first scenarios | `criteria.R:530` |

**TODO/FIXME/HACK/XXX/BUG/WIP:** essentially **none** in source. Risk is unfinished semantics without markers, not littered TODOs.

**Skipped tests.**
- External engines: `skip_if(Sys.getenv("_LIBERALITY_RUN_EXTERNAL_VALIDATION_") != "true")` (`test-external-validation.R:37`).
- Browser e2e: `LIBER_RUN_BROWSER_TESTS` + shinytest2 (`test-browser-e2e.R:2–3`).

---

## 6. VALIDATION vs PopED/PFIM

**Real comparison code: yes.** `R/external-validation.R` builds matched fixtures, runs LibeRality (`fo_block`), PopED, PFIM, reorders/scales parameters, compares full FIM + RSE + log-det + optional D-grid search.

**Closeness (checked-in baseline).** From `inst/extdata/external-validation-baseline.json`:

| Fixture | Engines | max \|ΔFIM\| | max \|ΔRSE\| (pp) |
|---|---|---|---|
| oral_proportional | vs PopED / PFIM | ~2.7e-6 / ~8.9e-7 | ~2e-9 |
| bolus_additive | vs PopED / PFIM | ~1e-7 / ~5e-9 | ~2e-10 |
| oral_combined | vs PopED only | ~2.8e-6 | ~4e-9 |

That is **publication-grade agreement** for continuous FO population FIM on these 1-cmt designs.

**Gaps.**
- Only ADVAN1/2 linear PK; proportional / additive / (combined vs PopED).
- No random effects beyond diagonal OMEGA; no covariates; no multi-arm; no non-continuous; no FOCE/Laplace.
- PFIM combined error explicitly unsupported (`external-validation.R:58–62`).
- Default `full_gaussian` is **not** what is validated.
- CI test for engines is opt-in via env var — default `testthat` never exercises PopED/PFIM.

---

## 7. TESTS

**Breadth.**
- Information: symmetry/rank, tiny C++ Gaussian check, finite matrices for all endpoint types (`test-information.R`) — **finite ≠ correct**.
- Criteria: smoke “all finite” for ~25 types (`test-criteria.R`); closed-form D/A/E/Ds/c/L/RSE/power/ED (`test-criteria-analytic.R`) — strong for classical scalar criteria.
- Optimiser: short coordinate-exchange + allocation size preservation — no improvement/guarantee tests.
- External: fo_block structure + transform unit test; full engine compare gated.
- Much of the suite is GUI/branding/history/browser.

**Gaps.** No analytic FIM for proportional-error PK; no non-continuous truth; no TTE counting-process reference; no allocation-with-A-opt; no Weibull; no multi-endpoint correlation; no Pareto dominance math; no fit=`TRUE` OC coverage.

---

## 8. DOCUMENTATION

| Claim | Reality |
|---|---|
| Exact CppAD sensitivities | Exact for predictions; FD for much of \(V\) |
| Continuous/binary/ordinal/count/TTE/recurrent | All runnable; ordinal/TTE/Weibull simplified or stubbed |
| 29 criteria | Runnable; several aliases/simplifications |
| PopED/PFIM validation | True for continuous FO `fo_block` fixtures |
| Coverage from simulation | **Over-claim** |
| Model-averaged criterion | **Over-claim** (scenario-FIM average) |
| Weibull TTE | **API over-claim** |
| Amber workbench | NEWS says palette replaced (0.2.7); README still mentions amber historically |

Package DESCRIPTION / README are relatively careful (“research beta”, support matrix), but vignette + criterion guidance oversell structural model averaging and simulation coverage.

---

## 9. TOP STRENGTHS

1. **Executable PopED/PFIM FIM parity** with Jacobian harmonisation, baselines, report, and frobenius/RSE tolerances at ~1e-6–1e-11.
2. Explicit **`fo_block` vs `full_gaussian`** split — rare honesty about FO conventions.
3. **Serialisable design contract** + LibeRation/LibeRties handoff is architecturally coherent.
4. Classical criterion algebra (D/A/E/Ds/c/L/ED/power) is clean and analytically tested.
5. Teaching example + wizard templates make the package usable beyond a math library.

---

## 10. PRIORITIZED RECOMMENDATIONS

### High
1. **Fix allocation methods** to use criterion-specific directional derivatives (or refuse non-D criteria with a hard error).
2. **Align TTE simulation with FIM** (`hazard * delta` both places), or document/simulate true waiting times.
3. **Implement or reject Weibull** — either use shape in hazard/FIM or remove from allowed distributions.
4. **Rename or rewrite `model_average`** to average over `alternative_models` (or call it scenario-averaged FIM).
5. **Gate marketing claims** in README/vignette/guidance to “internally verified working approximations” for non-continuous/TTE until reference tests exist.

### Medium
6. Add **analytic continuous FIM regression** (known 1-cmt formulas) in default CI, not only PopED opt-in.
7. Replace ordinal FD and residual FD with analytic derivatives where the error model allows.
8. Implement real **coverage** in `lity_operating_characteristics`, or delete the vignette claim.
9. Make `lity_evaluate`/`lity_information` default approximation configurable; warn when comparing to PopED without `fo_block`.
10. Add tests that non-D allocation either errors or improves the stated criterion.

### Low
11. Collapse or clearly document `bayesian` vs `robust` aliasing.
12. Distinguish `model_discrimination` from KL in code, or drop the third type.
13. Reduce repeated exponential-error temporary-model blocks in `information.R`.
14. Expand external fixtures (combined PFIM convention note already good) toward 2-cmt / IOV only after FO continuous path is locked.

---

**Bottom line:** Trust LibeRality for **continuous population-FO information and D-family design work** that has been matched to PopED/PFIM under `fo_block`. Treat non-continuous/TTE FIM, allocation-for-arbitrary-criteria, model averaging, Weibull, and simulation “coverage” as **not yet at the same scientific bar** as the continuous FO validation story.

---

## Appendix A. Cross-cutting findings from the lead reviewer

These are ecosystem-level observations from the coordinating review (outside any single package tree). They complement the per-package reports.

- **Size (excluding vendored CppAD/Eigen headers):** ~54k R lines + ~13k C++ lines across ~114 test files. LibeRation dominates (23.8k R / 11k C++). LibeRtAD's owned C++ is small but dense; LibeRality's C++ is only ~164 lines (the "native Eigen expected-information assembly" described in `ARCHITECTURE.md` is mostly R reusing LibeRation sensitivities — confirmed in §3.6).
- **Dependency graph:** LibeRtAD (foundation) ← LibeRation (`Imports`+`LinkingTo`) ← LibeRator/LibeRality/LibeRary(Suggests); LibeRality also `LinkingTo` LibeRtAD. LibeRties is standalone and only `Suggests` the others. Clean, acyclic; the "canonical generated contracts" mechanism (`tools/sync-*.R` copying `tools/shared/*` into packages with drift-checking in CI) is a sound way to share code without creating dependency cycles.
- **Model-contract version drift (P1):** `docs/ARCHITECTURE.md` says "model contract v3" / `liberation.model/3`, but `ecosystem.json` declares `model: 4` and `ALGORITHM-REVIEW-1.0.md` says "model-contract v4". Reconcile.
- **CI does not gate on NOTEs (P1):** `tools/ci-check.R` collects `errors` + `warnings` only, but `ROADMAP-1.0` §6.1 requires "no errors, warnings, or unexplained notes." CI does otherwise enforce a strong set of gates (repository hygiene, installer validation, shared-runtime/GUI/contract sync-drift, a security check that the hosted app disables Ollama, `--as-cran`), and is a 3-OS matrix (`ci.yml`) plus `deployment-validation.yml`, `external-validation.yml`, `nightly-hardening.yml`.
- **Windows at-rest permission gap (P1/security):** `tools/shared/liber-durability.R:19–21` only applies `chmod 0600` on non-Windows. On Windows, durable files (including anything the ecosystem writes with a "0600" intent) are not permission-restricted. Relevant to LibeRties/LibeRator at-rest claims on Windows hosts.
- **Validation infrastructure is real, not aspirational:** the `validation/*/run-validation.R` campaigns are runnable scripts with checked-in baselines (e.g. `validation/liberality/external/baseline/matrices/*.csv`, `methods.csv`, `comparators.csv`), and `docs/VALIDATION.md` records concrete numerical deltas vs NONMEM/PsN, nlmixr2, KFAS/glmmTMB/hmmTMB/pomp/bssm/deSolve, and PopED/PFIM. The layered philosophy (a defect cannot hide behind two paths sharing an implementation; missing comparators are recorded `not-run`, never a pass; performance is correctness-gated via `nm_validation_gate()`) is a genuine strength. Caveat: several campaigns are opt-in (env-gated), so *default* CI proves less than the docs describe — align this with the truth-in-labeling pass.
- **Shared durability primitives are solid:** atomic temp+rename publish with `.previous` rollback, recovery-on-read, `mkdir`-based locking with stale detection, and strict path-component validation (`^[A-Za-z0-9][A-Za-z0-9_.-]*$`, rejecting `.`/`..`). This backbone underpins every package's persistence and is well-written.
- **`LibeR-LLM-Distillation`** is a standalone Python QLoRA pipeline for the assistant model with data-governance/rights auditing and evaluation gates; it is explicitly not runtime-linked to the R packages. Out of scope for R fixes, but note its `merge --allow-unvalidated` escape hatch and that export is gated on evaluation — keep those gates hard.
- **Strategic note for the implementer:** the ecosystem's own `ALGORITHM-REVIEW-1.0.md` and `TODO.md` are candid and largely accurate; treat them as trustworthy companions to this review. Where this review and those documents disagree, prefer verifying against current code.
