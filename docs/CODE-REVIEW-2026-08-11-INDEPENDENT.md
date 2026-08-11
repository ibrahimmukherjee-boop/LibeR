# Independent review — 2026-08-11

An independent scientific, software, and interface review of the LibeR
ecosystem, performed on commit `f2da7a7`. Findings are ordered by severity;
none are fundamental defects.

## Scope and method

Targeted inspection of the numerical/statistical core (`LibeRation/src/`,
`LibeRation/R/estimation*.R`, `LibeRtAD/src/`), the validation and benchmark
infrastructure (`validation/`, `benchmarks/`, `docs/VALIDATION.md`), CI and
test suites, and the browser interfaces (live shinyapps deployments and the
shared design system).

## Scientific findings

### Verified correct

- **M3/M4 BLQ likelihoods** (`LibeRation/src/pk_engine_likelihood.h:1954-1978`):
  M3 contributes −2·log Φ((LLOQ−f)/sd); M4 correctly conditions on DV>0 via
  (Φ(z)−Φ(−f/sd))/(1−Φ(−f/sd)); exponential-error censoring is handled on the
  log scale, and M4 truncation is correctly skipped there.
- **OMEGA parameterisation** (`LibeRation/R/estimation.R:1262-1289`,
  `:1336-1344`): log-Cholesky with the correct Lebesgue prior Jacobian
  `n_eta·log(2) + Σ(n+2−i)·log(L_ii)` — a detail many implementations get
  wrong.
- **Importance sampling** (`LibeRation/R/estimation-stochastic.R:1061-1099`):
  signed log-sum-exp supporting negative Smolyak quadrature weights, finite
  masking, effective-sample-size and cancellation diagnostics; invalid states
  are explicit failures, not silent zeros.
- **NONMEM OFV convention**: the Gaussian NLL omits log(2π)
  (`pk_engine_likelihood.h:2002-2003`) to match NONMEM, and
  `bayesian-diagnostics.R:103-108` re-adds it for WAIC/PSIS-LOO where a true
  density is required, with an explanatory comment.
- **SAEM schedule** (`estimation-stochastic.R:3282,3590`): γ=1 during burn-in
  then (k−burn)^−0.7, correct single application of γ in the sufficient
  statistic update.
- **Reproducible parallelism**: replicate seeds drawn once from the master
  seed before dispatch (`simulate.R:111`, `diagnostics.R:1978`), so results
  do not depend on worker count.
- **VPC construction** (`diagnostics.R:1216-1262`): per-replicate quantiles
  with simulation intervals of those quantiles — the standard, correct
  construction.

Classic errors that were looked for and **not found**: quantile-of-pooled-data
VPCs, naive `log(sum(exp(...)))`, missing SAEM burn-in handling,
unparameterised OMEGA optimisation.

### Findings

1. **Moderate — normal CDF tail precision and vanishing AD gradients**
   (`pk_engine_likelihood.h:346-351`). Φ(z) computed as 0.5·(1+erf(z/√2))
   suffers catastrophic cancellation for z ≲ −5 and hits the 1e-300 floor near
   z ≈ −38. The floor is a conditional, so the AD derivative there is exactly
   zero: a far-censored BLQ record contributes a large penalty with **no
   gradient**, which can stall FOCEI/Laplace from poor starting values.
   Recommended fix: erfc-based or log-CDF evaluation with a smooth tail
   approximation.
2. **Minor — unguarded log-sum-exp**
   (`estimation-stochastic.R:6-9`). `.nm_log_sum_exp` returns NaN when all
   inputs are −Inf. The quadrature path masks non-finite values
   (`:1064-1085`) but the SAEM/IMP weight normalisation (`:1616-1622`) calls
   the helper directly. Hard to trigger through the existing guards; a
   robustness inconsistency rather than a demonstrated bug.
3. **Minor — RNG stream independence is probable, not provable.** HMC chains
   use `set.seed(seed + chain_id − 1)` (`estimation-hmc.R:1085`) and replicate
   seeds derive from `sample.int`. L'Ecuyer-CMRG streams
   (`parallel::nextRNGStream`) would make independence formal.
4. **Speculative — variance/prediction floors**
   (`pk_engine_likelihood.h:388`): 1e-16 variance and 1e-12 prediction floors
   flatten gradients at the boundary; values are conservative.

## Software engineering

- **Strong**: 118 test files / ~714 `test_that` blocks; three-OS
  `R CMD check` CI in dependency order plus integration, browser, nightly
  hardening, and external-validation workflows; pinned dependency versions.
- **Large units**: `pk_engine_saem.h` (5,299 lines),
  `estimation-stochastic.R` (5,078), `zzz-gui-app.R` (3,004).
- **Duplication**: the prior log-density block is triplicated nearly verbatim
  in `pk_engine_saem.h:251`, `pk_engine_population.h:1000`, and
  `hmc_sampler.h:485`; a new prior family added to one copy will silently
  diverge. Extraction into a shared header is recommended.
- **Dependency footprint**: LibeRation hard-Imports `shiny`, `htmlwidgets`,
  `reactR`, `promises`, `coro`, and `ellmer` (an LLM client). Moving the GUI
  and LLM stack to Suggests or a companion package would give headless/server
  estimation a minimal, auditable dependency tree.

## Validation claims

Substantiated in-repo to the extent verifiable without licensed software:
`validation/nonmem/` holds real ADVAN1-18 `.mod`/`.dat` fixtures and a runner;
`validation/estimation-methods/` has per-method acceptance criteria;
`validation/liberality/external/baseline/` retains PopED/PFIM comparison
artifacts; `validation/external-comparators/` has executable
nlmixr2/posologyr/SciML scripts. Missing comparators are recorded `not-run`
and never converted to passes — exemplary honesty.

## Interface

The applications are professional and internally consistent, but optimised
for expert density: 10-12 px body text with 9-10 px labels, and empty states
that name the absence ("No projects") without offering a first action. The
hosted demos cold-start to an unbranded "Please Wait" page. Recommendations:
raise the base type scale toward 13-14 px, platform-native font stacks
(`-apple-system` before `Segoe UI`), branded loading state, and
example-loading calls to action in empty states. An opt-in monochrome theme
(`tools/shared/gui/liber-theme-mono.css`) accompanies this review: it
collapses product accents to a greyscale ramp, reserves colour exclusively
for destructive actions, and adds soft-extruded depth cues, reducing
colour-based cognitive load without altering shell geometry or the
light/dark contract.

## Suggested improvements (priority order)

1. erfc/log-CDF evaluation for `normal_cdf_t` so BLQ gradients survive deep
   censoring.
2. All-non-finite guard in `.nm_log_sum_exp`/`.nm_log_mean_exp`.
3. Extract the triplicated prior log-density into one shared header.
4. Move the GUI/LLM stack out of LibeRation's hard Imports.
5. L'Ecuyer-CMRG streams for chains and bootstrap replicates.

**Bottom line**: unusually rigorous work for a research codebase. The
correctness-gated benchmark policy and the refusal to convert missing
comparators into passes are exemplary. The findings above are refinements,
not fundamental defects.
