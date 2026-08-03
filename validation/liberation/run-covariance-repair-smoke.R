#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
root <- if (length(args)) normalizePath(args[[1L]], mustWork = TRUE) else
  normalizePath(getwd(), mustWork = TRUE)
library(LibeRation)
environment <- new.env(parent = asNamespace("LibeRation"))
sys.source(file.path(root, "LibeRation", "R", "covariance-repair.R"), environment)
evalq({
  covariance <- matrix(c(
    1.0, 1.4, -0.7,
    1.4, 0.9, 0.2,
    -0.7, 0.2, 0.3
  ), 3, 3)
  modified <- nm_covariance_repair(covariance, "modified_cholesky")
  stopifnot(
    min(modified$diagnostics$repaired_eigenvalues) > 0,
    is.finite(modified$diagnostics$condition_number),
    identical(sort(modified$diagnostics$permutation), 1:3)
  )
  sensitivity <- nm_covariance_repair_sensitivity(
    covariance,
    statistic = function(value) c(trace = sum(diag(value)), variance_sum = sum(value)),
    methods = c("none", "jitter", "higham", "modified_cholesky"),
    reference_method = "higham"
  )
  stopifnot(
    inherits(sensitivity, "nm_covariance_sensitivity"),
    any(sensitivity$comparison$status == "failed"),
    all(sensitivity$comparison$difference[
      sensitivity$comparison$method == "higham"
    ] == 0)
  )
  cat("covariance-repair-ok\n")
}, environment)
