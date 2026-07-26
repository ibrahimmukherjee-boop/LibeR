# External AD backend benchmark

This harness compares persistent value/gradient and Hessian evaluation for a
10-dimensional Rosenbrock objective and a deterministic 400-by-10 logistic
likelihood. It reports backend compilation separately from tape/model-method
initialisation and steady-state evaluation. LibeRtAD's
`tape_bytes_proxy` covers its CppAD operation sequence and live work vectors;
`object_bytes` is only R's serialized object estimate and is **not** a
cross-backend resident-memory comparison.

Run from the consolidated repository root:

```powershell
& "C:\Program Files\R\R-4.6.0\bin\x64\R.exe" --vanilla `
  validation/ad-backends/run-benchmark.R --iterations=200
```

The script always runs LibeRtAD. TMB and CmdStan are reported as `skipped`
unless their R packages and, for CmdStanR, a configured CmdStan installation
are already available. A backend compile or runtime error is retained as
`failed`; it never silently removes a competitor. Results are written to
`validation/ad-backends/results/benchmark.csv`, `.rds`, and `summary.json`.
Value, gradient, and Hessian tolerances are executable gates. Use
`--require-cmdstan` for an independent Stan Math gate; TMB remains useful
cross-frontend evidence but shares CppAD ancestry with LibeRtAD.

The runner requires the same immutable source-built validation library as the
other evidence campaigns. `--library=<path>` and `--output=<path>` are
available for CI and retained validation artifacts.

The adapters follow the official [TMB compile/`MakeADFun`
workflow](https://kaskr.github.io/adcomp/Introduction.html) and CmdStanR's
documented [`grad_log_prob()` and model-method
initialisation](https://mc-stan.org/cmdstanr/reference/fit-method-grad_log_prob.html).
External-backend timing is comparative engineering evidence, not validation of
pharmacometric estimates or a claim of universal performance.
