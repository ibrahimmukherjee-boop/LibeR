root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
source(file.path(root, "tools", "validation-runtime.R"), local = TRUE)
manifest <- jsonlite::fromJSON(file.path(root, "ecosystem.json"), simplifyVector = FALSE)
packages <- names(manifest$packages)
versions <- vapply(manifest$packages, `[[`, character(1), "version")
liber_validation_assert_repository_hygiene(root)
shared_status <- system2(
  file.path(R.home("bin"), "Rscript"),
  c(file.path(root, "tools", "sync-shared-runtime.R"), "--check")
)
if (!identical(shared_status, 0L)) {
  stop("Generated shared runtime validation failed.", call. = FALSE)
}
gui_asset_status <- system2(
  file.path(R.home("bin"), "Rscript"),
  c(file.path(root, "tools", "sync-gui-assets.R"), "--check")
)
if (!identical(gui_asset_status, 0L)) {
  stop("Generated GUI design-system validation failed.", call. = FALSE)
}
contract_status <- system2(
  file.path(R.home("bin"), "Rscript"),
  c(file.path(root, "tools", "sync-packaged-contracts.R"), "--check")
)
if (!identical(contract_status, 0L)) {
  stop("Packaged contract synchronization failed.", call. = FALSE)
}
git_state <- liber_validation_git(root)
if (!isTRUE(git_state$tracked_worktree_clean) &&
    !identical(tolower(Sys.getenv("LIBER_RELEASE_ALLOW_DIRTY", "false")), "true")) {
  stop(
    "Release builds require a clean tracked worktree. Commit the intended source, or set ",
    "LIBER_RELEASE_ALLOW_DIRTY=true only for a non-publishable development build.",
    call. = FALSE
  )
}

# R CMD build may compile vignettes before R CMD INSTALL gets a chance to
# configure the toolchain.  Make clean Windows release shells reproducible by
# discovering Rtools explicitly instead of relying on an interactive PATH.
if (.Platform$OS.type == "windows") {
  rtools_roots <- unique(Filter(nzchar, c(
    Sys.getenv("RTOOLS45_HOME"), Sys.getenv("RTOOLS_HOME"), "C:/rtools45"
  )))
  rtools_root <- rtools_roots[vapply(rtools_roots, function(path) {
    file.exists(file.path(path, "x86_64-w64-mingw32.static.posix", "bin", "g++.exe"))
  }, logical(1))][1L]
  if (!is.na(rtools_root)) {
    tool_paths <- normalizePath(c(
      file.path(rtools_root, "x86_64-w64-mingw32.static.posix", "bin"),
      file.path(rtools_root, "usr", "bin")
    ), winslash = "/", mustWork = TRUE)
    Sys.setenv(
      PATH = paste(c(tool_paths, Sys.getenv("PATH")), collapse = .Platform$path.sep),
      R_MAKEVARS_USER = file.path(root, "tools", "Makevars.rtools45")
    )
  }
}

actual <- vapply(packages, function(package) {
  read.dcf(file.path(root, package, "DESCRIPTION"))[[1L, "Version"]]
}, character(1))
if (!identical(unname(actual), unname(versions))) {
  stop("DESCRIPTION versions do not match ecosystem.json:\n",
       paste(paste(packages, actual, versions, sep = ": "), collapse = "\n"), call. = FALSE)
}

release_root <- file.path(root, "releases")
dir.create(release_root, recursive = TRUE, showWarnings = FALSE)
release_root <- normalizePath(release_root, winslash = "/", mustWork = TRUE)
destination <- file.path(release_root, manifest$release)
if (dir.exists(destination)) {
  resolved_destination <- normalizePath(
    destination, winslash = "/", mustWork = TRUE
  )
  if (!identical(dirname(resolved_destination), release_root)) {
    stop("Refusing to clean a release directory outside releases/.", call. = FALSE)
  }
  unlink(resolved_destination, recursive = TRUE, force = TRUE)
}
dir.create(destination, recursive = TRUE, showWarnings = FALSE)
pandoc_candidates <- Filter(nzchar, c(
  Sys.getenv("LIBER_PANDOC_HOME", unset = ""),
  liber_validation_dev_cache(root, "tools", "pandoc", "3.10"),
  file.path(root, "tools", "pandoc-3.10")
))
bundled_pandoc <- pandoc_candidates[dir.exists(pandoc_candidates)][1L]
if (!is.na(bundled_pandoc) && !nzchar(Sys.getenv("RSTUDIO_PANDOC"))) {
  Sys.setenv(RSTUDIO_PANDOC = normalizePath(
    bundled_pandoc, winslash = "/", mustWork = TRUE
  ))
}

manual_status <- system2(file.path(R.home("bin"), "Rscript"),
                         c(shQuote(file.path(root, "tools", "build-reference-manuals.R")),
                           shQuote(root)))
if (!identical(manual_status, 0L)) stop("Reference-manual generation failed.", call. = FALSE)

release_library <- liber_validation_dev_cache(
  root, "r-libraries", "release-build", create = TRUE
)
if (dir.exists(release_library)) unlink(release_library, recursive = TRUE, force = TRUE)
dir.create(release_library, recursive = TRUE, showWarnings = FALSE)
release_libs <- paste(c(release_library, .libPaths()), collapse = .Platform$path.sep)
old_r_libs <- Sys.getenv("R_LIBS", unset = NA_character_)
Sys.setenv(R_LIBS = release_libs)
on.exit({
  if (is.na(old_r_libs)) Sys.unsetenv("R_LIBS") else Sys.setenv(R_LIBS = old_r_libs)
}, add = TRUE)
for (package in packages) {
  status <- system2(
    file.path(R.home("bin"), "R"),
    c("CMD", "INSTALL", "--preclean", "--clean",
      "-l", shQuote(release_library),
      shQuote(file.path(root, package))),
    stdout = TRUE, stderr = TRUE
  )
  if (!is.null(attr(status, "status")) && attr(status, "status") != 0L) {
    stop("Failed to install exact release dependency ", package, ":\n",
         paste(status, collapse = "\n"), call. = FALSE)
  }
  liber_validation_clean_native_source(file.path(root, package))
}

for (package in packages) {
  status <- system2(file.path(R.home("bin"), "R"),
                    c("CMD", "build", "--no-manual", shQuote(file.path(root, package))),
                    stdout = TRUE, stderr = TRUE)
  if (!is.null(attr(status, "status")) && attr(status, "status") != 0L) {
    stop("Failed to build ", package, ":\n", paste(status, collapse = "\n"), call. = FALSE)
  }
  archive <- file.path(root, paste0(package, "_", versions[[package]], ".tar.gz"))
  if (!file.exists(archive)) stop("Build did not create ", archive, call. = FALSE)
  file.copy(archive, destination, overwrite = TRUE)
}

if (.Platform$OS.type == "windows") {
  for (package in packages) {
    status <- system2(
      file.path(R.home("bin"), "R"),
      c("CMD", "INSTALL", "--build", "--preclean", "--clean",
        "-l", shQuote(release_library),
        shQuote(file.path(root, package))),
      stdout = TRUE, stderr = TRUE
    )
    if (!is.null(attr(status, "status")) && attr(status, "status") != 0L) {
      stop("Failed to build Windows binary for ", package, ":\n",
           paste(status, collapse = "\n"), call. = FALSE)
    }
    liber_validation_clean_native_source(file.path(root, package))
    archive <- file.path(root, paste0(package, "_", versions[[package]], ".zip"))
    if (!file.exists(archive)) stop("Binary build did not create ", archive, call. = FALSE)
    file.copy(archive, destination, overwrite = TRUE)
  }
}
if (!requireNamespace("openssl", quietly = TRUE)) install.packages("openssl")

evidence_dir <- file.path(destination, "evidence")
check_root <- file.path(evidence_dir, "checks")
dir.create(check_root, recursive = TRUE, showWarnings = FALSE)
api_inventory <- file.path(evidence_dir, "api-inventory.csv")
api_inventory_json <- file.path(evidence_dir, "api-inventory.json")
api_status <- system2(
  file.path(R.home("bin"), "Rscript"),
  c(shQuote(file.path(root, "tools", "api-inventory.R")),
    shQuote(paste0("--output=", api_inventory)),
    shQuote(paste0("--json=", api_inventory_json)))
)
if (!identical(api_status, 0L)) stop("API lifecycle inventory failed.", call. = FALSE)
Sys.setenv(
  `_R_CHECK_FORCE_SUGGESTS_` = "false",
  `_R_CHECK_CRAN_INCOMING_REMOTE_` = "false"
)
run_release_check <- function(package) {
  archive <- file.path(root, paste0(package, "_", versions[[package]], ".tar.gz"))
  package_check <- file.path(check_root, paste0(package, ".Rcheck"))
  if (dir.exists(package_check)) unlink(package_check, recursive = TRUE, force = TRUE)
  old <- setwd(check_root)
  on.exit(setwd(old), add = TRUE)
  output <- system2(
    file.path(R.home("bin"), "R"),
    c("CMD", "check", "--no-manual", "--no-build-vignettes", shQuote(archive)),
    stdout = TRUE, stderr = TRUE
  )
  writeLines(output, file.path(check_root, paste0(package, "-command.log")))
  command_status <- attr(output, "status")
  if (is.null(command_status)) command_status <- 0L
  log_path <- file.path(package_check, "00check.log")
  log <- if (file.exists(log_path)) readLines(log_path, warn = FALSE) else character()
  status_line <- tail(grep("^Status:", log, value = TRUE), 1L)
  passed <- identical(command_status, 0L) && identical(status_line, "Status: OK")
  list(
    package = package, version = versions[[package]], passed = passed,
    command_status = command_status,
    status = if (length(status_line)) status_line else "missing check status",
    log = if (file.exists(log_path)) file.path("evidence", "checks", paste0(package, ".Rcheck"),
                                                "00check.log") else NA_character_
  )
}

checks <- lapply(packages, run_release_check)
names(checks) <- packages
if (!all(vapply(checks, `[[`, logical(1), "passed"))) {
  failed <- names(checks)[!vapply(checks, `[[`, logical(1), "passed")]
  stop("Release checks failed: ", paste(failed, collapse = ", "), call. = FALSE)
}

artifacts <- list.files(destination, full.names = TRUE, pattern = "(\\.tar\\.gz|\\.zip|\\.pdf)$")
artifact_records <- lapply(artifacts, function(path) list(
  file = basename(path), bytes = unname(file.info(path)$size),
  sha256 = liber_validation_sha256(path)
))
names(artifact_records) <- basename(artifacts)
source_records <- lapply(packages, function(package) list(
  version = versions[[package]],
  description_sha256 = liber_validation_sha256(file.path(root, package, "DESCRIPTION")),
  namespace_sha256 = liber_validation_sha256(file.path(root, package, "NAMESPACE"))
))
names(source_records) <- packages
evidence_manifest <- list(
  schema = "liber.release-evidence/1",
  release = manifest$release,
  created_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC"),
  publishable = isTRUE(git_state$tracked_worktree_clean),
  git = git_state,
  ecosystem_manifest_sha256 = liber_validation_sha256(file.path(root, "ecosystem.json")),
  api_lifecycle_sha256 = liber_validation_sha256(file.path(root, "api-lifecycle.json")),
  api_inventory_sha256 = liber_validation_sha256(api_inventory_json),
  r = list(version = R.version.string, platform = R.version$platform),
  system = as.list(Sys.info()),
  sources = source_records,
  artifacts = artifact_records,
  checks = checks
)
evidence_path <- file.path(evidence_dir, "release-evidence.json")
jsonlite::write_json(evidence_manifest, evidence_path, auto_unbox = TRUE,
                     pretty = TRUE, null = "null", digits = 17)

deliverables <- list.files(destination, recursive = TRUE, full.names = TRUE)
deliverables <- deliverables[file.info(deliverables)$isdir %in% FALSE]
deliverables <- deliverables[basename(deliverables) != "SHA256SUMS"]
checksums <- vapply(deliverables, liber_validation_sha256, character(1))
relative <- substring(
  normalizePath(deliverables, winslash = "/", mustWork = TRUE),
  nchar(normalizePath(destination, winslash = "/", mustWork = TRUE)) + 2L
)
writeLines(paste(checksums, relative), file.path(destination, "SHA256SUMS"))
