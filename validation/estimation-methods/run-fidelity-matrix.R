args <- commandArgs(trailingOnly = TRUE)
script_arg <- grep("^--file=", commandArgs(), value = TRUE)
script <- if (length(script_arg)) {
  sub("^--file=", "", script_arg[[1L]])
} else file.path("validation", "estimation-methods", "run-fidelity-matrix.R")
campaign_dir <- normalizePath(dirname(script), winslash = "/", mustWork = TRUE)
root <- normalizePath(file.path(campaign_dir, "..", ".."), winslash = "/")
source(file.path(root, "tools", "validation-runtime.R"), local = TRUE)

option_value <- function(name, default = NULL) {
  liber_validation_option(name, default, args = args)
}
validation_runtime <- liber_validation_library(
  root, c("LibeRtAD", "LibeRation"),
  library = option_value("library", Sys.getenv("LIBER_VALIDATION_LIBRARY", ""))
)
if (!requireNamespace("testthat", quietly = TRUE)) {
  stop("The broad estimator fidelity gate requires testthat.", call. = FALSE)
}

manifest_path <- file.path(campaign_dir, "fidelity-scenarios.csv")
manifest <- utils::read.csv(
  manifest_path, stringsAsFactors = FALSE, check.names = FALSE
)
required_columns <- c(
  "scenario", "feature", "methods", "policies", "reference",
  "release_requirement"
)
if (!all(required_columns %in% names(manifest)) || anyDuplicated(manifest$scenario)) {
  stop("The estimator fidelity scenario manifest is invalid.", call. = FALSE)
}
allowed_methods <- c(
  "FO", "FOCE", "FOCEI", "LAPLACE", "ITS", "GQ", "IMP", "SAEM",
  "BAYES", "HMC", "NUTS", "NPML", "NPAG"
)
declared_methods <- unique(unlist(strsplit(manifest$methods, "|", fixed = TRUE)))
if (!all(declared_methods %in% allowed_methods)) {
  stop("The estimator fidelity manifest contains an unknown method.", call. = FALSE)
}
if (length(setdiff(allowed_methods, declared_methods))) {
  stop(
    "The estimator fidelity manifest omits: ",
    paste(setdiff(allowed_methods, declared_methods), collapse = ", "), ".",
    call. = FALSE
  )
}

stamp <- format(Sys.time(), "%Y%m%dT%H%M%S", tz = "UTC")
output <- option_value(
  "output", file.path(campaign_dir, "results", paste0(stamp, "-fidelity-matrix"))
)
if (!grepl("^(?:[A-Za-z]:[/\\\\]|/)", output, perl = TRUE)) {
  output <- file.path(root, output)
}
dir.create(output, recursive = TRUE, showWarnings = FALSE)

cat("Running the eight-scenario estimator fidelity suite...\n")
failure <- tryCatch({
  testthat::test_local(
    file.path(root, "LibeRation"), filter = "estimator-fidelity-matrix",
    reporter = "silent", stop_on_failure = TRUE, stop_on_warning = FALSE
  )
  NULL
}, error = identity)
rows <- lapply(seq_len(nrow(manifest)), function(index) {
  scenario <- manifest$scenario[[index]]
  data.frame(
    scenario = scenario,
    status = if (is.null(failure)) "passed" else "failed",
    detail = if (is.null(failure)) "" else conditionMessage(failure),
    stringsAsFactors = FALSE
  )
})
results <- merge(manifest, do.call(rbind, rows), by = "scenario", sort = FALSE)
passed <- all(results$status == "passed")
utils::write.csv(results, file.path(output, "fidelity-matrix.csv"), row.names = FALSE)
provenance <- liber_validation_provenance(
  root = root, packages = c("LibeRtAD", "LibeRation"),
  library = validation_runtime$path,
  inputs = c(script, manifest_path),
  dependencies = c("Rcpp", "testthat"),
  metadata = list(
    passed = passed, scenarios = nrow(results),
    policies = c("nonmem_compatibility", "liber_optimized")
  )
)
report <- c(
  "# Broad estimator fidelity matrix", "",
  paste0("- Overall passed: ", toupper(passed), "."),
  paste0("- Scenarios: ", nrow(results), "."),
  "- Both numerical policies are exercised where the estimator has two paths.",
  "- Detailed scenario status is in `fidelity-matrix.csv`."
)
liber_validation_write_evidence(
  output, provenance = provenance, report = report
)
if (!passed) quit(save = "no", status = 1L)
