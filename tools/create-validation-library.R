args <- commandArgs(trailingOnly = TRUE)
script_arg <- grep("^--file=", commandArgs(), value = TRUE)
script <- if (length(script_arg)) sub("^--file=", "", script_arg[[1L]]) else
  file.path("tools", "create-validation-library.R")
root <- normalizePath(file.path(dirname(script), ".."), winslash = "/", mustWork = TRUE)
source(file.path(root, "tools", "validation-runtime.R"), local = TRUE)
liber_validation_configure_rtools(root)

manifest <- liber_validation_manifest(root)
packages <- names(manifest$packages)
# Generated native objects are not source inputs and can otherwise make the
# dirty-worktree provenance hash depend on whether a developer compiled just
# before creating the library. Normalize that state before naming/marking the
# immutable validation library.
invisible(lapply(packages, function(package) {
  liber_validation_clean_native_source(file.path(root, package))
}))
destination <- liber_validation_library_path(root)
force <- "--force" %in% args
git <- liber_validation_git(root)
use_source <- "--source" %in% args || !isTRUE(git$tracked_worktree_clean)
if (dir.exists(destination) && !force) {
  checked <- liber_validation_library(root, packages, library = destination)
  cat("Validation library already exists and is compatible:", checked$path, "\n")
  quit(save = "no", status = 0L)
}

parent <- dirname(destination)
dir.create(parent, recursive = TRUE, showWarnings = FALSE)
temporary <- chartr(
  "\\", "/", tempfile("validation-library-", tmpdir = parent)
)
dir.create(temporary, recursive = TRUE, showWarnings = FALSE)
temporary <- normalizePath(temporary, winslash = "/", mustWork = TRUE)
on.exit(unlink(temporary, recursive = TRUE, force = TRUE), add = TRUE)

release_dir <- file.path(root, "releases", manifest$release)
install_one <- function(package) {
  version <- manifest$packages[[package]]$version
  binary <- file.path(release_dir, paste0(package, "_", version, ".zip"))
  source_archive <- file.path(release_dir, paste0(package, "_", version, ".tar.gz"))
  if (!use_source && .Platform$OS.type == "windows" && file.exists(binary)) {
    utils::install.packages(binary, repos = NULL, type = "win.binary", lib = temporary,
                            dependencies = FALSE, quiet = TRUE)
  } else if (!use_source && file.exists(source_archive)) {
    utils::install.packages(source_archive, repos = NULL, type = "source", lib = temporary,
                            dependencies = FALSE, quiet = TRUE)
  } else {
    command <- file.path(R.home("bin"), "R")
    status <- system2(command, c(
      "CMD", "INSTALL", "--preclean", "--clean", "-l", shQuote(temporary),
      shQuote(file.path(root, package))
    ))
    if (!identical(status, 0L)) stop("Unable to install ", package, call. = FALSE)
    liber_validation_clean_native_source(file.path(root, package))
  }
  installed <- liber_validation_package_version(package, temporary)
  if (is.na(installed) || !identical(installed, version)) {
    stop("Installed validation package version mismatch for ", package, call. = FALSE)
  }
}

for (package in packages) {
  message("Installing validation package ", package, " ", manifest$packages[[package]]$version)
  install_one(package)
}

marker <- list(
  schema = "liber.validation-library/1",
  release = manifest$release,
  git_commit = git$commit,
  tracked_worktree_clean = git$tracked_worktree_clean,
  tracked_diff_sha256 = git$tracked_diff_sha256,
  installed_from = if (use_source) "working tree source" else "release archives",
  created_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC"),
  packages = lapply(manifest$packages, function(package) package$version),
  source_manifest_sha256 = liber_validation_sha256(file.path(root, "ecosystem.json"))
)
jsonlite::write_json(marker, file.path(temporary, "LIBER_VALIDATION_LIBRARY.json"),
                     auto_unbox = TRUE, pretty = TRUE, null = "null")

if (dir.exists(destination)) unlink(destination, recursive = TRUE, force = TRUE)
if (!file.rename(temporary, destination)) {
  stop("Unable to publish validation library: ", destination, call. = FALSE)
}
on.exit(NULL, add = FALSE)
checked <- liber_validation_library(root, packages, library = destination)
cat("Created immutable validation library:", checked$path, "\n")
