# LibeRtAD

LibeRtAD is the automatic-differentiation engine for the LibeR population
PK/PD modelling system. It compiles a restricted R-like mathematical language
to a serializable intermediate representation and evaluates persistent CppAD
tapes using the bundled official CppAD 20260000.0 and Eigen 5.0.1 headers. R
owns only a light R6/external-pointer wrapper; values, gradients, Jacobians,
Hessians, and matrix operations are evaluated in C++.

LibeRtAD is distributed as part of the LibeR 0.9 research beta. Install a
complete compatibility set through the [ecosystem installer](../docs/INSTALL.md)
and consult `LibeRation::liber_support_matrix("LibeRtAD")` before relying on a
capability.

It also supplies normalized standard-normal Gauss--Hermite rules, guarded
tensor grids through `ad_gauss_hermite()`, and signed-weight Smolyak sparse
grids through `ad_smolyak_gauss_hermite()`. LibeRation uses both for its
deterministic adaptive quadrature estimator.

## Example

```r
library(LibeRtAD)

model <- ad_compile(
  "CL = THETA(1) * exp(ETA(1))\nPENALTY = log(CL)^2",
  at = c(THETA_1 = 2, ETA_1 = 0),
  wrt = c("THETA_1", "ETA_1"),
  outputs = "PENALTY"
)

model$value_gradient(c(THETA_1 = 2, ETA_1 = 0))
model$hessian(c(THETA_1 = 2, ETA_1 = 0))
```

## Benchmark laboratory

Run a reproducible native benchmark from R:

```r
result <- ad_benchmark("pk", iterations = 1000, warmups = 50)
result
```

Or open the purple React workbench:

```r
libertad_gui()
```

The GUI separates tape recording from repeated value, gradient/Jacobian, and
Hessian calls and reports agreement against independent R references. When it
is opened from the LibeR source checkout, it can also launch and cancel the
existing fresh-process LibeRation/NONMEM benchmark harness and stream its log.

## Installation

LibeRtAD requires R 4.1 or newer, a C++17 toolchain, Rcpp, R6, and its
Shiny/React GUI dependencies. CppAD 20260000.0 and Eigen 5.0.1 are bundled and
do not require separate installation. From a source checkout:

```text
R CMD INSTALL .
```

## AI-assisted development

GPT-5.6 was used as an AI engineering collaborator to help review and implement
the CppAD/Eigen integration, numerical kernels, benchmarks, tests, and documentation.

The benchmark GUI writes new result sets to `Documents/LibeR-data/benchmarks`
on Windows and `~/LibeR-data/benchmarks` elsewhere. Set
`LIBERTAD_BENCHMARK_HOME` to use another persistent result directory.
Scientific direction, architecture, validation criteria, and release decisions remain the responsibility of the project owner.

LibeRtAD is MIT licensed. The bundled CppAD headers retain their EPL-2.0 or
GPL-2.0-or-later dual licence. The bundled Eigen headers retain their MPL-2.0
or more permissive licences.
