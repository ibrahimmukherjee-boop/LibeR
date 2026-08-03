#!/usr/bin/env Rscript

arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) != 2L) {
  stop("Usage: run-installed-package-tests.R <source-root> <package>", call. = FALSE)
}
root <- normalizePath(arguments[[1L]], mustWork = TRUE)
package <- arguments[[2L]]
if (!grepl("^[A-Za-z][A-Za-z0-9.]+$", package)) {
  stop("Invalid package name.", call. = FALSE)
}
testthat::test_local(
  file.path(root, package), reporter = "summary",
  load_package = "installed", stop_on_failure = TRUE
)
