# MU-referenced estimator comparison

This campaign compares algebraically equivalent conventional and
MU-referenced ADVAN1/TRANS2 models in NONMEM and LibeRation. FOCEI is an
algebraic control; IMP and SAEM exercise the estimator families for which
LibeRation has explicit MU-aware specialization. Available scenarios are:

- `baseline-fixed`: one log-MU ETA with fixed OMEGA and SIGMA;
- `dual-estimated`: two log-MU ETAs with estimated diagonal OMEGA and SIGMA;
- `covariate-full`: two log-MU ETAs, a weight effect, and estimated correlated
  OMEGA and SIGMA.

The comparison records:

- population and individual estimates;
- objective values as descriptive evidence;
- fresh-process end-to-end and engine core runtime;
- conventional versus MU equivalence within each engine;
- specialized versus non-specialized LibeRation MU execution; and
- IMP mode-recentring and SAEM closed-form GLS telemetry.

FOCEI conventional-versus-MU equivalence and all cross-engine MU comparisons
are numerical qualification gates. IMP and SAEM conventional-versus-MU
comparisons are retained as descriptive evidence because a finite stochastic
path can depend on parameterization even when the underlying model is
equivalent. Their MU specialization telemetry is gated separately.

For active MU covariate designs, IMP uses the inexpensive importance-score
gradient as a warm start and then refines the result against the exact finite
common-random-number objective. This improves agreement with NONMEM, at the
expected cost of additional core runtime in that scenario.

Run a quick comparison with an isolated validation library:

```r
Rscript validation/mu-referencing/run-validation.R \
  --library=../LibeR-dev-cache/r-libraries/release-build --profile=quick --scenario=baseline-fixed
```

Use `--profile=standard --repeats=3` for a more stable runtime comparison.
`--scenario=baseline-fixed|dual-estimated|covariate-full`,
`--methods=FOCEI,IMP,SAEM`, `--subjects=N`, `--warmups=N`, `--seed=N`, and
`--output=PATH` can be overridden.

Raw NONMEM listings and PsN run directories are temporary and are deleted
after parsing. The published result directory contains only generated controls,
the synthetic fixture, and derived numerical evidence.
