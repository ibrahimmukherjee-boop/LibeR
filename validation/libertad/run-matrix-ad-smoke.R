#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
root <- if (length(args)) normalizePath(args[[1L]], mustWork = TRUE) else
  normalizePath(file.path(getwd()), mustWork = TRUE)
library(LibeRtAD)
environment <- new.env(parent = asNamespace("LibeRtAD"))
sys.source(file.path(root, "LibeRtAD", "R", "ir-compiler.R"), environment)
sys.source(file.path(root, "LibeRtAD", "R", "ad-model.R"), environment)
sys.source(file.path(root, "LibeRtAD", "R", "matrix-ad.R"), environment)
evalq({
  ir <- ad_matrix_ir(
    inputs = list(A = c(2, 2), b = c(2, 1)),
    operations = list(
      ad_matrix_op("L", "cholesky", x = "A"),
      ad_matrix_op("x", "solve", a = "A", b = "b", method = "spd"),
      ad_matrix_op("ld", "logdet", x = "A"),
      ad_matrix_op("q", "quadratic_form", a = "A", x = "b")
    ), outputs = c("L", "x", "ld", "q")
  )
  at <- list(A = matrix(c(4, 1, 1, 3), 2), b = matrix(c(2, -1), 2, 1))
  model <- ad_matrix_compile(ir, at = at, wrt = c("A", "b"))
  value <- model$value(at)
  stopifnot(
    isTRUE(all.equal(value$L, t(chol(at$A)), tolerance = 1e-10)),
    isTRUE(all.equal(value$x, solve(at$A, at$b), tolerance = 1e-10)),
    isTRUE(all.equal(drop(value$ld), as.numeric(determinant(at$A, logarithm = TRUE)$modulus), tolerance = 1e-10)),
    isTRUE(all.equal(drop(value$q), drop(crossprod(at$b, at$A %*% at$b)), tolerance = 1e-10))
  )
  q_ir <- ad_matrix_ir(
    inputs = list(A = c(2, 2), b = c(2, 1)),
    operations = list(ad_matrix_op("q", "quadratic_form", a = "A", x = "b")),
    outputs = "q"
  )
  q_model <- ad_matrix_compile(q_ir, at = at, wrt = "b")
  stopifnot(
    isTRUE(all.equal(unname(q_model$gradient(at)), drop(2 * at$A %*% at$b), tolerance = 1e-10)),
    isTRUE(all.equal(unname(q_model$hessian(at)), 2 * at$A, tolerance = 1e-10))
  )
  exp_ir <- ad_matrix_ir(
    inputs = list(K = c(2, 2), raw = c(2, 2)),
    operations = list(
      ad_matrix_op("E", "matrix_exp", x = "K", order = 22L, scaling = 3L),
      ad_matrix_op("Omega", "covariance", x = "raw", log_diagonal = TRUE)
    ), outputs = c("E", "Omega")
  )
  exp_at <- list(
    K = diag(c(0.2, -0.4)),
    raw = matrix(c(log(2), 0.3, 99, log(1.5)), 2, 2)
  )
  exp_value <- ad_matrix_compile(exp_ir, at = exp_at)$value(exp_at)
  lower <- matrix(c(2, 0.3, 0, 1.5), 2, 2)
  stopifnot(
    isTRUE(all.equal(exp_value$E, diag(exp(c(0.2, -0.4))), tolerance = 1e-10)),
    isTRUE(all.equal(exp_value$Omega, lower %*% t(lower), tolerance = 1e-10))
  )
  cat("matrix-evaluation-ok\n")
  cache <- tempfile(fileext = ".rds")
  on.exit(unlink(cache), add = TRUE)
  q_model$save_tape(cache)
  cat("matrix-cache-saved\n")
  loaded <- ad_matrix_load_tape(cache)
  cat("matrix-cache-loaded\n")
  stopifnot(isTRUE(all.equal(loaded$value(at)$q, q_model$value(at)$q, tolerance = 1e-12)))
  cat("matrix-core-ok\n")
}, environment)
