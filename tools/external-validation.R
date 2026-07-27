root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
source(file.path(root, "tools", "validation-runtime.R"), local = TRUE)
packages <- c("LibeRtAD", "LibeRation", "LibeRality")
runtime_path <- Sys.getenv("LIBER_VALIDATION_LIBRARY")
if (!nzchar(runtime_path)) {
  runtime_path <- liber_validation_dev_cache(
    root, "r-libraries", "validation", liber_validation_library_name(root)
  )
}
if (!dir.exists(runtime_path)) {
  status <- system2(
    file.path(R.home("bin"), "Rscript"),
    c(shQuote(file.path(root, "tools", "create-validation-library.R")), "--source")
  )
  if (!identical(status, 0L)) {
    stop("Unable to create the exact validation library.", call. = FALSE)
  }
}
runtime <- liber_validation_library(root, packages, library = runtime_path)
dependency_library <- liber_validation_dev_cache(
  root, "r-libraries", "validation",
  paste0("external-r-", R.version$major, ".", strsplit(R.version$minor, "\\.")[[1L]][1L])
)
dir.create(dependency_library, recursive = TRUE, showWarnings = FALSE)
.libPaths(c(runtime$path, dependency_library, .libPaths()))
external_versions <- c(PopED = "0.7.0", PFIM = "7.0.3")
installed_external <- vapply(names(external_versions), function(package) {
  liber_validation_package_version(package, dependency_library)
}, character(1))
if (any(is.na(installed_external) | installed_external != external_versions)) {
  if (!requireNamespace("remotes", quietly = TRUE)) {
    utils::install.packages("remotes", lib = dependency_library)
  }
  for (package in names(external_versions)) {
    if (!identical(installed_external[[package]], external_versions[[package]])) {
      remotes::install_version(
        package, version = external_versions[[package]],
        lib = dependency_library, dependencies = NA, upgrade = "never",
        quiet = TRUE
      )
    }
  }
}
installed_external <- vapply(names(external_versions), function(package) {
  liber_validation_package_version(package, dependency_library)
}, character(1))
if (!identical(unname(installed_external), unname(external_versions))) {
  stop(
    "External validation dependency mismatch: ",
    paste(
      names(external_versions), "expected", external_versions,
      "found", installed_external, collapse = "; "
    ),
    call. = FALSE
  )
}
Sys.setenv(`_LIBERALITY_RUN_EXTERNAL_VALIDATION_` = "true")
library("LibeRality", character.only = TRUE)
test_result <- testthat::test_dir(
  file.path(root, "LibeRality", "tests", "testthat"),
  filter = "external-validation", reporter = "summary", stop_on_failure = TRUE
)
stamp <- paste0(
  format(Sys.time(), "%Y%m%dT%H%M%S", tz = "UTC"), "-",
  substr(liber_validation_git(root)$commit, 1L, 12L)
)
output <- file.path(root, "validation", "liberality", "external", "results", stamp)
dir.create(output, recursive = TRUE, showWarnings = FALSE)
saveRDS(test_result, file.path(output, "test-results.rds"), version = 3L)
repetitions <- suppressWarnings(as.integer(Sys.getenv("LIBERALITY_EXTERNAL_REPETITIONS", "3")))
if (!is.finite(repetitions) || repetitions < 1L) repetitions <- 3L
validation <- LibeRality::lity_external_validate(
  fixtures = LibeRality::lity_external_validation_fixtures(),
  repetitions = repetitions, design_search = TRUE, output_dir = output
)
provenance <- liber_validation_provenance(
  root = root, packages = packages, library = runtime$path,
  inputs = c(
    file.path(root, "ecosystem.json"),
    file.path(root, "tools", "external-validation.R"),
    file.path(root, "LibeRality", "R", "external-validation.R")
  ),
  seeds = list(),
  tolerances = validation$tolerance,
  dependencies = c("PopED", "PFIM", "testthat", "jsonlite", "openssl"),
  metadata = list(
    fixtures = as.list(names(validation$fixtures)),
    comparisons = nrow(validation$comparisons),
    design_search = TRUE, repetitions = repetitions,
    passed = validation$passed
  ),
  output = file.path(output, "provenance.json")
)
if (!isTRUE(validation$passed)) stop("Full PopED/PFIM validation failed.", call. = FALSE)
cat("External validation evidence:", normalizePath(output, winslash = "/"), "\n")
