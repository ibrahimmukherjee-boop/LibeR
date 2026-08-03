# LibeRtAD

LibeRtAD is the automatic-differentiation engine for the LibeR population
PK/PD modelling system. It compiles a restricted R-like mathematical language
to a serializable intermediate representation and evaluates persistent CppAD
tapes using the bundled official CppAD 20260000.0 and Eigen 5.0.1 headers. R
owns only a light R6/external-pointer wrapper; values, gradients, Jacobians,
Hessians are evaluated in C++. The base expression IR is scalar-valued. A
public fixed-shape matrix IR now lowers guarded matrix operations onto that
same persistent C++ tape engine, including multiplication, triangular/SPD and
fixed-no-pivot solves, Cholesky/log-determinant, quadratic forms, symmetric
rank updates, covariance construction, and fixed-path matrix exponentials.

Portable graph caches use a versioned semantic probe: their domain/dynamic
partition, source IR, optimized CppAD graph values, and Jacobian must agree at
the recorded point before a worker may use the cache. Caches created before
this contract must be recorded again rather than being loaded dimension-only.

Derivative results are exact for the recorded smooth mathematical path, up to
floating-point error. At kinks (`abs`, `min`, `max`, conditional boundaries),
outside function domains, or after a structural branch/path change, users must
interpret derivatives as path-local; each tape instance is evaluated by only
one thread at a time.

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

Fixed-shape differentiable matrix algebra uses an explicit, serializable graph:

```r
matrix_ir <- ad_matrix_ir(
  inputs = list(A = c(2, 2), b = c(2, 1)),
  operations = list(
    ad_matrix_op("solution", "solve", a = "A", b = "b", method = "spd"),
    ad_matrix_op("logdet", "logdet", x = "A")
  ),
  outputs = c("solution", "logdet")
)

point <- list(A = matrix(c(4, 1, 1, 3), 2), b = matrix(c(2, -1), 2, 1))
matrix_model <- ad_matrix_compile(matrix_ir, at = point, wrt = c("A", "b"))
matrix_model$value(point)
```

Shapes and numerical paths are fixed at compile time. Cholesky-based methods
require positive-definite inputs, general solves deliberately record a
no-pivot path, and the matrix exponential differentiates a declared fixed
approximation. Dynamic shapes and arbitrary SVD/eigenvector derivatives are
rejected rather than assigned ambiguous derivatives.

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

LibeRtAD's numerical core requires R 4.1 or newer, a C++17 toolchain, Rcpp, and
R6. CppAD 20260000.0 and Eigen 5.0.1 are bundled and do not require separate
installation. Shiny, reactR, htmlwidgets, htmltools, processx, and callr are
optional dependencies used only by the benchmark workbench. From a source checkout:

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
