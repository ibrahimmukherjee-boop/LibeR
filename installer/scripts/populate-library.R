arguments <- commandArgs(trailingOnly = TRUE)
value_after <- function(name, default = "") {
  hit <- grep(paste0("^--", name, "="), arguments, value = TRUE)
  if (length(hit)) sub(paste0("^--", name, "="), "", hit[[length(hit)]])
  else default
}

root <- normalizePath(value_after("root", getwd()), winslash = "/",
                      mustWork = TRUE)
source(file.path(root, "tools", "validation-runtime.R"), local = TRUE)
library_path <- normalizePath(
  value_after("library"), winslash = "/", mustWork = FALSE
)
profile <- tolower(value_after("profile", "research"))
if (!profile %in% c("research", "runtime")) {
  stop("profile must be research or runtime.", call. = FALSE)
}
dir.create(library_path, recursive = TRUE, showWarnings = FALSE)

# Read the ecosystem contract before isolating the library search path. jsonlite
# is available in the build environment, but must not silently become a runtime
# dependency of the staged applications.
manifest <- jsonlite::fromJSON(
  file.path(root, "ecosystem.json"), simplifyVector = FALSE
)
packages <- names(manifest$packages)
expected <- vapply(manifest$packages, `[[`, character(1), "version")

# Isolate resolution from the interactive user library. The staged runtime must
# be complete on its own.
base_library <- file.path(R.home(), "library")
.libPaths(unique(c(library_path, base_library)))
Sys.setenv(
  R_LIBS_USER = library_path,
  R_LIBS_SITE = "",
  R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep)
)
options(repos = c(
  CRAN = Sys.getenv("LIBER_CRAN_MIRROR", "https://cloud.r-project.org")
))

description_dependencies <- function(path, fields) {
  description <- read.dcf(path)
  selected <- intersect(fields, colnames(description))
  if (!length(selected)) return(character())
  entries <- unlist(strsplit(
    paste(description[1L, selected], collapse = ","), ",", fixed = TRUE
  ), use.names = FALSE)
  trimws(sub("\\s*\\([^)]*\\)\\s*$", "", entries))
}

required_fields <- c("Depends", "Imports", "LinkingTo")
direct <- unique(unlist(lapply(packages, function(package) {
  description_dependencies(
    file.path(root, package, "DESCRIPTION"), required_fields
  )
}), use.names = FALSE))
base_packages <- rownames(utils::installed.packages(
  lib.loc = base_library, priority = "base"
))
external <- setdiff(direct[nzchar(direct)], c("R", packages, base_packages))

# Optional application features are deliberately selected. Installing every
# Suggests entry would pull external comparator stacks such as PopED and PFIM
# into the end-user runtime, even though they are only used by validation jobs.
runtime_optional <- c(
  "callr", "chromote", "DT", "knitr", "loo", "pdftools", "rmarkdown",
  "shiny", "yaml"
)
research_optional <- c(
  runtime_optional, "covr", "devtools", "rcmdcheck", "roxygen2",
  "shinytest2", "testthat"
)
optional <- if (identical(profile, "research")) {
  research_optional
} else {
  runtime_optional
}
external <- unique(c(external, optional))
if (length(external)) {
  install.packages(
    external, lib = library_path,
    dependencies = c("Depends", "Imports", "LinkingTo")
  )
}

missing <- external[!vapply(
  external, requireNamespace, logical(1), quietly = TRUE
)]
if (length(missing)) {
  stop("Unresolved bundled dependencies: ", paste(missing, collapse = ", "))
}

for (package in packages) {
  message("Installing staged LibeR package: ", package)
  status <- system2(
    file.path(R.home("bin"), "R"),
    c("CMD", "INSTALL", "--preclean", "--clean",
      "-l", shQuote(library_path),
      shQuote(file.path(root, package)))
  )
  if (!identical(status, 0L)) {
    stop("Unable to install staged package ", package, ".", call. = FALSE)
  }
  liber_validation_clean_native_source(file.path(root, package))
}

installed <- vapply(packages, function(package) {
  as.character(utils::packageVersion(package, lib.loc = library_path))
}, character(1))
if (!identical(unname(installed), unname(expected))) {
  stop("The staged LibeR versions do not match ecosystem.json.")
}

records <- as.data.frame(utils::installed.packages(
  lib.loc = library_path,
  fields = c("License", "Repository", "RemoteType", "RemoteRepo", "RemoteSha")
), stringsAsFactors = FALSE)
records$Package <- rownames(records)
manifest_fields <- c(
  "Package", "Version", "License", "Repository",
  "RemoteType", "RemoteRepo", "RemoteSha", "Built"
)
for (field in setdiff(manifest_fields, names(records))) {
  records[[field]] <- ""
}
records <- records[, manifest_fields, drop = FALSE]
utils::write.csv(
  records, file.path(dirname(library_path), "package-manifest.csv"),
  row.names = FALSE, na = ""
)
