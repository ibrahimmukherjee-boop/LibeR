arguments <- commandArgs(trailingOnly = TRUE)
root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
source(file.path(root, "tools", "validation-runtime.R"), local = TRUE)
library_argument <- grep("^--library=", arguments, value = TRUE)
library_path <- if (length(library_argument)) {
  sub("^--library=", "", library_argument[[1L]])
} else liber_validation_dev_cache(
  root, "r-libraries", "liberality-external", create = TRUE
)
library_path <- normalizePath(library_path, winslash = "/", mustWork = FALSE)
dir.create(library_path, recursive = TRUE, showWarnings = FALSE)

repositories <- c(CRAN = "https://cloud.r-project.org")
packages <- c("PopED", "PFIM")
install.packages(
  packages, lib = library_path, repos = repositories,
  dependencies = c("Depends", "Imports", "LinkingTo")
)
.libPaths(c(library_path, .libPaths()))
versions <- data.frame(
  package = packages,
  version = vapply(packages, function(package) {
    as.character(utils::packageVersion(package, lib.loc = library_path))
  }, character(1)),
  installed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  repository = unname(repositories[[1L]]), stringsAsFactors = FALSE
)
utils::write.csv(versions, file.path(library_path, "external-validation-lock.csv"), row.names = FALSE)
print(versions)
