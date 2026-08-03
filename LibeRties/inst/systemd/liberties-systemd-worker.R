#!/usr/bin/env Rscript

arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) != 1L || !nzchar(arguments[[1L]])) {
  stop("Expected one isolated LibeRties job directory.", call. = FALSE)
}
paths <- Sys.getenv("LIBERTIES_LIBRARY_PATHS", unset = "")
if (nzchar(paths)) {
  .libPaths(unique(c(
    strsplit(paths, .Platform$path.sep, fixed = TRUE)[[1L]], .libPaths()
  )))
}
suppressPackageStartupMessages(library(LibeRties))
LibeRties:::.ls_run_job(arguments[[1L]])
