arguments <- commandArgs(trailingOnly = TRUE)
`%||%` <- function(left, right) {
  if (is.null(left) || !length(left)) right else left
}
root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
source(file.path(root, "deploy", "shinyapps", "runtime.R"), local = TRUE)
source(file.path(root, "tools", "validation-runtime.R"), local = TRUE)
liber_validation_configure_rtools(root)

library_path <- liber_shinyapps_library(root, create = TRUE)
.libPaths(unique(c(library_path, .libPaths())))
manifest <- jsonlite::fromJSON(
  file.path(root, "ecosystem.json"), simplifyVector = FALSE
)
packages <- names(manifest$packages)
expected <- vapply(manifest$packages, `[[`, character(1), "version")
force <- "--force" %in% arguments

if (!requireNamespace("remotes", quietly = TRUE)) {
  stop("Install the 'remotes' package before preparing hosted deployments.")
}

for (package in packages) {
  description <- tryCatch(
    utils::packageDescription(package, lib.loc = library_path),
    error = function(error) NULL
  )
  reusable <- !is.null(description) &&
    identical(description$Version, expected[[package]]) &&
    identical(description$RemoteRepo, package) &&
    nzchar(description$RemoteSha %||% "")
  if (isTRUE(reusable) && !force) {
    message("Reusing ", package, " ", description$Version,
            " @ ", substr(description$RemoteSha, 1L, 12L))
    next
  }
  message("Installing GitHub mirror: ", package, " ", expected[[package]])
  remotes::install_github(
    paste0("svdijkman/", package),
    ref = "main",
    lib = library_path,
    dependencies = FALSE,
    upgrade = "never",
    force = TRUE,
    quiet = FALSE
  )
}

liber_shinyapps_use_library(root, require_exact = TRUE)
source(file.path(root, "deploy", "shinyapps", "check-dependencies.R"),
       local = new.env(parent = globalenv()))
cat("Hosted deployment library ready:", library_path, "\n")
