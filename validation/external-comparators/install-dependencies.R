#!/usr/bin/env Rscript

arguments <- commandArgs(trailingOnly = TRUE)
script_argument <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script <- if (length(script_argument)) {
  sub("^--file=", "", script_argument[[1L]])
} else {
  "validation/external-comparators/install-dependencies.R"
}
root <- normalizePath(
  file.path(dirname(script), "..", ".."), winslash = "/", mustWork = TRUE
)
source(file.path(root, "tools", "validation-runtime.R"), local = TRUE)
value_after <- function(name, default = NULL) {
  liber_validation_option(name, default, args = arguments)
}
library_path <- value_after(
  "library", liber_validation_dev_cache(
    root, "r-libraries", "external-comparators", create = TRUE
  )
)
dir.create(library_path, recursive = TRUE, showWarnings = FALSE)
library_path <- normalizePath(library_path, winslash = "/", mustWork = TRUE)

packages <- c("KFAS", "glmmTMB", "deSolve", "mapbayr")
if ("--extended" %in% arguments) {
  packages <- c(
    packages, "hmmTMB", "pomp", "bssm", "posologyr", "nlmixr2"
  )
}
repositories <- c(CRAN = value_after("cran", "https://cloud.r-project.org"))
install.packages(
  packages, lib = library_path, repos = repositories,
  dependencies = c("Depends", "Imports", "LinkingTo")
)

.libPaths(c(library_path, .libPaths()))
installed <- vapply(packages, function(package) {
  if (!requireNamespace(package, quietly = TRUE)) return(NA_character_)
  as.character(utils::packageVersion(package))
}, character(1))
table <- data.frame(
  package = packages,
  version = unname(installed),
  installed_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  repository = unname(repositories[[1L]]),
  status = ifelse(is.na(installed), "failed", "installed"),
  stringsAsFactors = FALSE
)
utils::write.csv(
  table, file.path(library_path, "external-comparator-lock.csv"),
  row.names = FALSE
)
print(table, row.names = FALSE)
if (anyNA(installed)) quit(status = 1L)
