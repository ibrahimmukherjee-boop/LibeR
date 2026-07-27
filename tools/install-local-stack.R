args <- commandArgs(trailingOnly = TRUE)
script_arg <- grep("^--file=", commandArgs(), value = TRUE)
script <- if (length(script_arg)) sub("^--file=", "", script_arg[[1L]]) else
  file.path("tools", "install-local-stack.R")
root <- normalizePath(file.path(dirname(script), ".."), winslash = "/",
                      mustWork = TRUE)
source(file.path(root, "tools", "validation-runtime.R"), local = TRUE)
installer_helpers <- new.env(parent = globalenv())
sys.source(
  file.path(root, "tools", "install-ecosystem.R"),
  envir = installer_helpers
)
installer_helpers$.liber_configure_repositories()
dependencies_only <- "--dependencies-only" %in% args
if (.Platform$OS.type == "windows") {
  rtools_roots <- unique(Filter(nzchar, c(
    Sys.getenv("RTOOLS45_HOME"), Sys.getenv("RTOOLS_HOME"), "C:/rtools45"
  )))
  rtools_root <- rtools_roots[vapply(rtools_roots, function(path) {
    file.exists(file.path(
      path, "x86_64-w64-mingw32.static.posix", "bin", "g++.exe"
    ))
  }, logical(1))][1L]
  if (!is.na(rtools_root)) {
    tool_paths <- normalizePath(c(
      file.path(rtools_root, "x86_64-w64-mingw32.static.posix", "bin"),
      file.path(rtools_root, "usr", "bin")
    ), winslash = "/", mustWork = TRUE)
    Sys.setenv(
      PATH = paste(c(tool_paths, Sys.getenv("PATH")),
                   collapse = .Platform$path.sep),
      R_MAKEVARS_USER = file.path(root, "tools", "Makevars.rtools45")
    )
  }
}
packages <- c(
  "LibeRtAD", "LibeRation", "LibeRary", "LibeRator", "LibeRality", "LibeRties"
)
library <- Sys.getenv("LIBER_INSTALL_LIBRARY", "")
if (!nzchar(library)) library <- .libPaths()[[1L]]
library <- path.expand(library)
if (!dir.exists(library)) {
  dir.create(library, recursive = TRUE, showWarnings = FALSE)
}
library <- normalizePath(library, winslash = "/", mustWork = TRUE)
.libPaths(unique(c(library, .libPaths())))
Sys.setenv(R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))

description_dependencies <- function(path) {
  description <- read.dcf(path)
  fields <- intersect(c("Depends", "Imports", "LinkingTo"), colnames(description))
  if (!length(fields)) return(character())
  entries <- unlist(strsplit(paste(description[1L, fields], collapse = ","), ",",
                             fixed = TRUE), use.names = FALSE)
  trimws(sub("\\s*\\([^)]*\\)\\s*$", "", entries))
}

direct <- unique(unlist(lapply(packages, function(package) {
  description_dependencies(file.path(root, package, "DESCRIPTION"))
}), use.names = FALSE))
base_packages <- rownames(utils::installed.packages(priority = "base"))
external <- setdiff(direct[nzchar(direct)], c("R", packages, base_packages))
missing <- external[!vapply(
  external, requireNamespace, logical(1), quietly = TRUE
)]
if (length(missing)) {
  message("Installing missing source dependencies: ", paste(missing, collapse = ", "))
  utils::install.packages(missing, lib = library, dependencies = NA)
}

still_missing <- external[!vapply(
  external, requireNamespace, logical(1), quietly = TRUE
)]
if (length(still_missing)) {
  stop("Unresolved package dependencies: ", paste(still_missing, collapse = ", "),
       call. = FALSE)
}
if (dependencies_only) quit(save = "no", status = 0L)

for (package in packages) {
  message("Installing local package ", package)
  status <- system2(
    file.path(R.home("bin"), "R"),
    c("CMD", "INSTALL", "--preclean", "--clean", "-l", shQuote(library),
      shQuote(file.path(root, package)))
  )
  if (!identical(status, 0L)) {
    stop("Unable to install local package ", package, ".", call. = FALSE)
  }
  liber_validation_clean_native_source(file.path(root, package))
}
