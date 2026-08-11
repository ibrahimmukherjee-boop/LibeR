# LibeR Engine Review - Algorithms, Performance, Robustness, Auditability

- **Date:** 2026-08-07
- **Reviewer:** single-pass whole-ecosystem read-only review (no delegation)
- **Repository state:** `0.9.0-research-beta.17`; LibeRation 0.10.6, LibeRtAD 0.8.1,
  LibeRties 0.8.3, LibeRary 0.8.1, LibeRator 0.4.0, LibeRality 0.3.0
- **Focus:** numerical algorithms, and further opportunities in speed, robustness,
  reliability, auditability, and maintainability
- **Context read:** `docs/ENGINE-OPTIMISATION-2026-08-07.md` and
  `docs/FO-SAEM-PERFORMANCE-INVESTIGATION-2026-08-07.md` were reviewed first so this
  report does not re-propose work already done or already identified.

---

## 1. Summary

The dual-policy design is sound and well-plumbed. `nonmem_compatibility` is the
default everywhere, `liber_optimized` is opt-in, and the distinction between
*arithmetic-neutral* improvements (shared by both) and *arithmetic-changing* ones
(opt-in only) is the right boundary to have drawn.

I verified the new Woodbury/determinant-lemma FO likelihood mathematically and it is
**correct**. The new native SAEM limited-memory optimiser is **textbook-correct**.
Both new caches are **collision-safe and correctly invalidated**.

I found **one genuine bug** (unguarded CppAD recordings, high value / cheap fix) and
**three algorithmic robustness weaknesses**, all clustered around the new low-rank FO
path. Everything else below is opportunity rather than defect.

---

## 2. Algorithm verification - what is correct

### 2.1 Woodbury / determinant-lemma FO likelihood (verified correct)

`pk_engine_likelihood.h:2224 fo_low_rank_gaussian_nll_t`. With `C = G Om G' + R`,
`R = diag(variance)`, `L = chol(Om)`, `U = G L`:

- `residual_logdet = sum log(variance_i)` = `log det R`
- `information = I + sum_i u_i u_i' / variance_i` = `I + U' R^-1 U`
- `information_logdet = 2 sum log(L_ii)` = `log det(I + U' R^-1 U)`

so `log det C = residual_logdet + information_logdet` by the determinant lemma. And

- `base_quadratic = sum r_i^2 / variance_i` = `r' R^-1 r`
- `right = U' R^-1 r`; `forward = L^-1 right`; `correction = ||forward||^2 = right' (I + U'R^-1U)^-1 right`

so `r' C^-1 r = base_quadratic - correction` by the Woodbury identity. The returned
value `residual_logdet + information_logdet + base_quadratic - correction` is exactly
`log det C + r' C^-1 r`. Cost is `O(n_obs * n_eta^2 + n_eta^3)` instead of
`O(n_obs^3)`. **Mathematically correct.**

The eligibility guard (`fo_low_rank_conditioned`, 2322) is thorough and, importantly,
uses **relative** eigenvalue conditioning on both `Om` and `I + U'R^-1U`
(`min > max(1e-14, tolerance * max)`), plus finiteness checks on variance, Jacobian
and `Om`, and an explicit Cholesky-success check.

### 2.2 Native SAEM limited-memory M-step (verified correct)

`pk_engine_saem.h`. Powell-damped curvature updates that dampen rather than discard
memory (491-501); rejection of non-finite/non-positive curvature; bounded FIFO memory
(5); projected gradient with active-set component zeroing (590-592); fallback to
projected steepest descent (597); Armijo sufficient decrease at `1e-4` (639);
safeguarded quadratic interpolation clamped to `[0.1, 0.5] * step` (648-657); prompt
restart from steepest descent when a history direction fails early (621-627); and
**strong-Wolfe-gated** memory updates (668-670). This is a correct bound-constrained
L-BFGS. Sensibly, it remains the explicit/experimental choice while automatic
optimized SAEM uses the mature persistent R L-BFGS-B.

### 2.3 Caches (verified safe)

- **SAEM same-point cache** (`pk_engine_saem.h:218`) uses `isApprox(point, 0.0)` -
  i.e. exact equality - so it is a true same-point memoisation and cannot return a
  value for a different point.
- **FO context cache** (`estimation.R:815-878`) hashes a signature but then
  **re-verifies the complete signature with `identical()`** before reusing
  (852-854), so a hash collision cannot cause a wrong hit. LRU-evicted, bounded
  (default 4), opt-out via option, restricted to FO and `n_cores == 1`, and the hit is
  recorded as `context_cache_hit` in `fit$timing`.

### 2.4 Policy plumbing (verified clean)

`support.R:1-44`. Generous alias normalisation, hard error on an unknown value,
default `nonmem_compatibility` at every entry, and the resolved mode stored on the
model as `NUMERICAL_MODE` - so the policy travels with the serialisable model
contract into workers and queues, which is what auditability requires.

---

## 3. Issues found

### A1. Unguarded CppAD recordings in LibeRation - **High, cheap fix**

`CppADRecordingGuard` is defined in `pk_engine_event_advan.h:2-15` and is applied at
only **2 of 8** recording sites:

| Site | Guarded |
|---|---|
| `pk_engine_population.h:879-880` | yes |
| `pk_engine_population.h:1053-1054` | yes |
| `pk_engine_population.h:1143-1144` | **no** |
| `pk_engine_likelihood.h:260-261` | **no** |
| `pk_engine_likelihood.h:2428-2429` (`record_fo_tape`) | **no** |
| `pk_engine_likelihood.h:2649` | **no** |
| `pk_engine_likelihood.h:2759` | **no** |
| `pk_engine_likelihood.h:2818-2819` | **no** |

This matters most at `record_fo_tape` (2428), because the code it calls
*deliberately throws*: `fo_low_rank_gaussian_nll_t` raises `std::domain_error` for a
non-positive-definite `Om` (2245), a non-positive residual variance (2263), and a
non-positive-definite information matrix (2295). A throw between `Independent()` and
`Dependent()` leaves CppAD's thread-local recorder active, so the **next** tape
creation on that thread fails with a confusing "previous recording" error and the R
session is effectively poisoned until restart.

This is exactly the defect class LibeRtAD 0.8.0 fixed ("adds recording guards that
always abort an interrupted CppAD recording before control returns to R"); the fix was
not propagated to LibeRation's own recorders even though the guard class is available
in the same translation unit.

**Fix:** insert `CppADRecordingGuard<double> recording;` immediately after each
`Independent(...)` and `recording.release();` immediately after the matching
`Dependent(...)`/`ADFun` construction, mirroring `pk_engine_population.h:879-880`. Add
a regression that forces a mid-record throw (a singular `Om`, or a zero residual
variance) and then successfully records a second tape - LibeRtAD's
`.libertad_recording_recovery_probe` is the template.

### A2. Low-rank FO eligibility is decided once and never re-validated - **Medium**

`fo_low_rank_conditioned()` evaluates conditioning using the **recording-point**
values. Once the tape is recorded, replay is fixed arithmetic: the `domain_error`
guards inside `fo_low_rank_gaussian_nll_t` cannot fire again, because they test
`scalar_value(...)` at record time only.

Consequently, if conditioning degrades as the optimiser moves - `Om` drifting toward a
boundary during FO estimation is routine - the recorded Cholesky takes `sqrt` of a
non-positive value and produces NaN silently. It will surface as a non-finite
objective or gradient, and thanks to `allow_fd_gradient = FALSE` it now fails loudly
rather than silently degrading, but **without attribution**: the user is not told that
the low-rank route was the cause or that `low_rank = FALSE` would recover.

**Recommendations:**
1. Re-run `fo_low_rank_conditioned()` at retape anchors and whenever the existing
   parameter-distance guard triggers, and demote to the dense route with telemetry.
2. When a low-rank FO tape yields a non-finite value or gradient, emit a specific
   diagnostic naming the low-rank path and the recommended fallback. The
   `fo_low_rank_reason` / `fo_low_rank_fallback` fields already exist
   (`pk_engine_likelihood.h:9-12`) and only need to be populated on this route.

### A3. Absolute, unscaled positive-definiteness thresholds inside the taped kernel - **Medium**

`fo_low_rank_gaussian_nll_t` uses a fixed `> 1e-14` for `Om` diagonals (2244),
residual variances (2262), and information diagonals (2294). These are **absolute**
and therefore units-dependent: the same model expressed in ng/mL rather than mg/L
shifts variance magnitudes by roughly `1e6`, so the same threshold is either
meaningless or spuriously triggered.

The eligibility guard does this correctly with relative criteria; the in-tape backstop
does not. The project already has the right pattern in R -
`covariance-repair.R:11-12` computes `scale <- max(abs(matrix), 1); delta <- tolerance * scale`.

**Recommendation:** scale each threshold by the relevant matrix magnitude (max
diagonal or trace) rather than using a bare constant, and share one AD-safe Cholesky
helper (see M4) so the criterion is defined once.

### A4. Cancellation exposure in the Woodbury quadratic form - **Low-Medium**

The quadratic form is returned as `base_quadratic - correction`, a difference of two
non-negative quantities. Because `C = R + UU' >= R`, we have `C^-1 <= R^-1`, so
`correction >= 0` and the subtraction loses relative precision as the random effects
absorb more of the residual - that is, in the **high-IIV / low-RUV** regime, which is
common in population PK. The dense route computes `r' C^-1 r` from a single Cholesky
solve of `C` and has no such subtraction.

In realistic parameter ranges the loss is modest (a digit or two), so this is a
monitored risk rather than a demonstrated defect. But the dense-equivalence
comparison is performed **once, at tape creation**, and the recorded
`fo_low_rank_relative_difference` therefore describes the initial point, not the
solution.

**Recommendation:** re-run the dense-versus-low-rank comparison once at the final
estimate and refresh `fo_low_rank_relative_difference` in fit provenance. This costs a
single extra objective evaluation and converts a point-in-time check into a statement
about the reported result.

---

## 4. Speed opportunities

Their own review already identifies the two largest projects; I agree with both and
add specifics, then four further items.

### S1. Structural tape sharing across subjects (their #1) - agreed, largest remaining

Already achieved for FO *conditional-objective* tapes with dynamic observations and
covariates. The remaining prize is the **prediction** tape across heterogeneous event
layouts. The blocker they name - separating dynamic event/observation data from
structural tape identity - is the correct framing. Concretely, the structural key
needs to admit *padded* event layouts (a common maximum record count with masked
rows), so subjects differing only in observation count can share one tape with a
dynamic mask rather than falling into separate pools.

### S2. Fuse prediction and ETA-sensitivity in specialized ADVAN kernels (their #2) - agreed

FO needs `G = df/deta` at `eta = 0`. For ADVAN1-4/11/12 the analytic sensitivity of the
affine propagation with respect to `eta` is closed-form, so `G` can be produced by the
same recursion that produces `f` instead of a separate sweep over the prediction tape.
This roughly halves propagation work on the flagship analytical path.

### S3. Extend Woodbury to AR(1) and residual-group covariance - **new, high value**

AR(1) and cross-endpoint/residual-group structures currently force the dense
`O(n_obs^3)` route - precisely the models with the most observations per subject.
Both retain the low-rank structure; only `R^-1` changes:

- **AR(1):** the precision matrix is tridiagonal in closed form, so `R^-1 x` costs
  `O(n_obs)` and `log det R` is a closed-form sum. Woodbury applies unchanged, with
  `U' R^-1 U` accumulated by a banded product; `R^-1` is never formed.
- **Residual groups / block diagonal:** decompose per block and sum the
  contributions to `U' R^-1 U`, `U' R^-1 r`, `r' R^-1 r`, and `log det R`.

This keeps the ETA-dimensional factorisation for exactly the cases currently excluded,
and the existing dense-equivalence gate provides the validation harness.

### S4. Reuse `U` structure across the inner loops - **new, medium**

`I + U' R^-1 U` is rebuilt per subject per evaluation. Within SAEM/IMP inner loops
where `Om` and `sigma` are fixed and only `eta`/THETA trial points move, and for
subjects the structural pool has already identified as sharing an event layout, parts
of `U = G chol(Om)` are invariant. Caching `chol(Om)` per M-step (already done for
OMEGA roots) and the `G` blocks for fixed-THETA trials would avoid recomputation.

### S5. Avoid the finite-difference Hessian for GQ/IMP/SAEM covariance - **new, medium**

The native CppAD Hessian covers FO/FOCE/FOCEI/Laplace, but
`marginal <- fit$method %in% c("GQ","IMP","SAEM")` (`diagnostics.R:904`) routes those
to `stats::optimHess`, which needs about `2 * n_par` gradient evaluations - expensive
precisely where each gradient is a Monte-Carlo or quadrature sweep. Two cheaper
routes, both already partly present:

1. Use the **OPG/S** information (already implemented as the sandwich "meat") as the
   default bread for these estimators rather than an FD Hessian.
2. Or reuse the optimiser's own **limited-memory secant** history as a low-rank
   Hessian approximation - free, since SAEM's M-step already maintains it.

Either removes the `2 * n_par` marginal-gradient cost from the covariance step.

### S6. Close the remaining FO core-time gap to NONMEM - **new, diagnostic**

Their own matched benchmark is the right place to look: LibeR dominates end-to-end
(FO 0.80 s vs 4.55 s) but NONMEM's **core** FO is still faster (0.266 s vs 0.45 s).
That is the flagship number and the one place NONMEM leads. At 100 subjects / 800
records the per-subject problem is small, so the likely cause is per-sweep tape
bookkeeping rather than arithmetic. Two concrete probes:

- Instrument `Forward(0)` / `Reverse(1)` call count and per-call fixed overhead versus
  arithmetic for a single subject, to establish whether sweep setup dominates.
- If it does, batching several subjects into one tape sweep amortises the setup - which
  is S1, and would convert the last NONMEM core advantage.

The per-phase timing split below (AU3) is a prerequisite for doing this cleanly.

---

## 5. Robustness and reliability

- **R1.** A1, A2 and A3 above are the substantive items.
- **R2.** The adaptive-ODE retape guard remains a heuristic parameter-distance radius
  (`LibeRation.tape_guard_radius`, default 0.5). With the low-rank FO route added, a
  retape should now also re-decide low-rank eligibility; today it does not (ties to A2).
- **R3.** The FO context cache is a **package-level environment** holding compiled
  engines, tapes and external pointers for the process lifetime (up to 4 entries).
  It is correctly keyed and bounded, but in a long-lived Shiny/LibeRties process it is
  shared across sessions. FO-only plus `n_cores == 1` limits exposure. Consider keying
  by workspace/session, and document
  `.nm_estimation_context_cache_clear()` (or export a supported equivalent) so
  operators can reclaim memory deterministically.
- **R4.** `record_fo_tape`'s low-rank flag, tolerance, and condition tolerance are
  plumbed as three separate scalars through the R/C++ boundary
  (`pk_engine.cpp:563-570`). Bundling them into one options struct would prevent a
  future argument-order mistake at the boundary.

---

## 6. Auditability

Already strong, and materially better than at the start of the month:
`bread_source`/`bread_exact`, `gradient_class`, `gradient_fallbacks`,
`fo_low_rank_*` telemetry fields, `context_cache_hit`,
`initialization_seconds` separated from core time, and `NUMERICAL_MODE` carried on
the serialisable model contract.

Remaining gaps:

- **AU1.** Surface the **numerical policy at the result level**, in the same
  `derivative_provenance` block that prints gradient and covariance provenance. It is
  currently a property of the model; an archived fit should self-declare which policy
  produced it without the reader having to inspect the model.
- **AU2.** Refresh `fo_low_rank_relative_difference` at convergence (A4) so the
  recorded equivalence statement describes the reported estimates.
- **AU3.** Implement the **per-phase timing split** still open in `TODO.md` section 8
  (prediction / ETA optimisation / curvature / population gradient / covariance). Now
  that core-time boundaries have been aligned with NONMEM, this is the natural next
  step and it is the prerequisite for diagnosing S6.
- **AU4.** Record, per fit, which subjects used the low-rank route versus dense. The
  focused measurement notes "all 100 subjects passing the low-rank guards", so the
  information exists at run time; persisting a count (and reasons for any fallback)
  makes the objective reproducible from provenance alone.

---

## 7. Code maintenance

- **M1. Dual-policy combinatorial surface.** Every numerically sensitive path now has
  two behaviours, and the equivalence gate is the right mitigation. Make the divergence
  set **explicit and enforced**: enumerate the `.nm_liber_optimized()` call sites into a
  machine-readable registry (file, function, what differs, which equivalence test
  covers it) and add a CI check that every divergent site is named by at least one
  equivalence test. Without this the matrix can grow untested branches silently.
- **M2. New hotspot file.** `pk_engine_likelihood.h` is 2,816 lines and now carries the
  dense FO likelihood, the low-rank kernel, the conditioning guard, and several tape
  recorders. The earlier split was a clear win; this file is the natural next seam -
  separating the FO marginal likelihood (dense + low-rank + guards) would isolate the
  most numerically sensitive code in the package.
- **M3. Include-file convention.** The former `.ipp` files are now `.h` but remain
  non-standalone textual includes into one translation unit. Either name them `*_impl.h`
  to signal that, or make them self-contained with include guards, so editors, linters
  and static analysis treat them correctly.
- **M4. Duplicated hand-rolled Cholesky.** There are now at least four factorisations:
  `positive_definite_*` (2139, 2182), the two inline factorisations inside
  `fo_low_rank_gaussian_nll_t`, and `.nm_modified_cholesky` in R. Consolidating the
  AD-safe variants into one template helper with a single scaled tolerance policy would
  fix A3 in one place and remove the risk of the thresholds drifting apart.

---

## 8. Suggested order of work

1. **A1** - add the six missing recording guards plus a mid-record-throw regression.
   Small, mechanical, removes a session-poisoning failure mode.
2. **A2 + A3** - re-validate low-rank eligibility at retape, attribute non-finite
   low-rank results, and scale the in-tape thresholds (with M4 as the vehicle).
3. **AU3** - per-phase timing split, since it gates the remaining performance work.
4. **S3** - Woodbury for AR(1) and residual groups: the best-defined large speed win,
   and it targets the models with the most observations per subject.
5. **S5** - remove the FD Hessian from GQ/IMP/SAEM covariance.
6. **S1 / S2 / S6** - the structural tape-sharing and kernel-fusion programme, which is
   where the remaining NONMEM core-time gap on FO will be closed.
7. **M1, M2** - policy-divergence registry and the FO likelihood split, to keep the
   dual-path design maintainable as it grows.

---

## 9. Assessment

The engine work this week is of high quality. The new low-rank FO likelihood is
mathematically correct and is exactly the right algorithmic move - trading an
observation-dimensional factorisation for an ETA-dimensional one is the standard
result and it has been implemented with genuine conservatism (relative conditioning
guards, dense-equivalence checking, automatic fallback with telemetry, and structures
that are not yet validated deliberately excluded). The native SAEM optimiser is
correct, and sensibly kept as an explicit choice while the mature R coordinator
remains automatic.

The dual-policy boundary is the right architecture for a tool whose central claim is
NONMEM comparability: it lets performance work proceed without eroding the reference
path, and the insistence that arithmetic-neutral gains be shared by both policies
means compatibility users are not penalised.

The one real defect - the unguarded recordings - is a propagation oversight rather
than a design error, and it is cheap to fix. The three low-rank robustness items all
share a single root cause worth stating plainly: **the low-rank route is validated at
the point where the tape is recorded, but used at every point the optimiser
subsequently visits.** Closing that gap, and extending Woodbury to the residual
structures currently excluded, are the highest-value next steps on both correctness
and speed.
