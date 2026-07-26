#!/usr/bin/env Rscript

arguments <- commandArgs(trailingOnly = TRUE)
script_argument <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script <- if (length(script_argument)) {
  sub("^--file=", "", script_argument[[1L]])
} else {
  "validation/liberties/deployment/create-job-fixture.R"
}
root <- normalizePath(
  file.path(dirname(script), "..", "..", ".."),
  winslash = "/", mustWork = TRUE
)
source(file.path(root, "tools", "validation-runtime.R"), local = TRUE)
value_after <- function(name, default = NULL) {
  liber_validation_option(name, default, args = arguments)
}
runtime <- liber_validation_library(
  root, c("LibeRtAD", "LibeRation", "LibeRties"),
  library = value_after("library", Sys.getenv("LIBER_VALIDATION_LIBRARY", ""))
)
.libPaths(unique(c(runtime$path, .libPaths())))
output <- value_after("output", "validation-job.json")

data <- data.frame(
  ID = 1L, TIME = c(0, 1, 2), EVID = c(1L, 0L, 0L),
  AMT = c(100, 0, 0), CMT = 1L, DV = NA_real_, MDV = c(1L, 0L, 0L)
)
model <- LibeRation::nm_model(
  INPUT = names(data), ADVAN = 1, TRANS = 2,
  PRED = "CL=THETA(1);V=THETA(2);S1=V",
  THETAS = data.frame(THETA = 1:2, Value = c(5, 50), FIX = TRUE)
)
job <- LibeRties::ls_job(
  "simulate", model, data,
  arguments = list(residual = FALSE, seed = 20260724L),
  label = "Synthetic deployment validation"
)
payload <- jsonlite::toJSON(
  LibeRties::ls_job_to_wire(job),
  auto_unbox = TRUE, null = "null", digits = 17
)
writeLines(payload, output, useBytes = TRUE)
cat(normalizePath(output, winslash = "/", mustWork = TRUE), "\n")
