packages <- c("LibeRtAD", "LibeRation", "LibeRary", "LibeRator", "LibeRality", "LibeRties")
root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
source(file.path(root, "tools", "validation-runtime.R"), local = TRUE)
liber_validation_assert_repository_hygiene(root)
installer_status <- system2(
  file.path(R.home("bin"), "Rscript"),
  c(file.path(root, "tools", "installer-check.R"), root)
)
if (!identical(installer_status, 0L)) {
  stop("Installer validation failed.", call. = FALSE)
}
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
hosted_liberation_launcher <- file.path(
  root, "deploy", "shinyapps", "liberation", "app.R"
)
hosted_liberation_source <- paste(
  readLines(hosted_liberation_launcher, warn = FALSE),
  collapse = "\n"
)
if (!grepl("allow_ollama = FALSE", hosted_liberation_source, fixed = TRUE)) {
  stop(
    "The hosted LibeRation launcher must explicitly disable Ollama.",
    call. = FALSE
  )
}
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
local_library <- Sys.getenv(
  "LIBER_INSTALL_LIBRARY",
  liber_validation_dev_cache(root, "r-libraries", "ci", create = TRUE)
)
dir.create(local_library, recursive = TRUE, showWarnings = FALSE)
.libPaths(unique(c(local_library, .libPaths())))
Sys.setenv(
  LIBER_INSTALL_LIBRARY = local_library,
  R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep)
)

matrix_status <- system2(
  file.path(R.home("bin"), "Rscript"),
  c(file.path(root, "tools", "support-matrix-check.R"), root)
)
if (!identical(matrix_status, 0L)) stop("Support-matrix validation failed.", call. = FALSE)

if (!requireNamespace("rcmdcheck", quietly = TRUE)) install.packages("rcmdcheck")

if (!identical(tolower(Sys.getenv("LIBER_SKIP_LOCAL_INSTALL")), "true")) {
  install_status <- system2(
    file.path(R.home("bin"), "Rscript"),
    file.path(root, "tools", "install-local-stack.R")
  )
  if (!identical(install_status, 0L)) {
    stop("Unable to install the exact local package stack.", call. = FALSE)
  }
}

failures <- list()
note_failures <- list()
note_allowlist_path <- file.path(root, "tools", "ci-note-allowlist.txt")
note_allowlist <- if (file.exists(note_allowlist_path)) {
  values <- trimws(readLines(note_allowlist_path, warn = FALSE))
  values[nzchar(values) & !startsWith(values, "#")]
} else character()
for (package in packages) {
  message("\n===== R CMD check: ", package, " =====")
  result <- rcmdcheck::rcmdcheck(
    file.path(root, package),
    args = c("--no-manual", "--as-cran"),
    build_args = "--no-manual",
    env = c(
      `_R_CHECK_FORCE_SUGGESTS_` = "false",
      `_R_CHECK_CRAN_INCOMING_REMOTE_` = "false",
      `_LIBERALITY_RUN_EXTERNAL_VALIDATION_` = "false"
    ),
    error_on = "never",
    check_dir = file.path(tempdir(), paste0(package, "-check"))
  )
  if (length(result$errors) || length(result$warnings)) failures[[package]] <- result
  unexpected_notes <- Filter(function(note) {
    !length(note_allowlist) || !any(vapply(
      note_allowlist, grepl, logical(1), x = note, perl = TRUE
    ))
  }, result$notes)
  if (length(unexpected_notes)) note_failures[[package]] <- unexpected_notes
}

if (length(failures) || length(note_failures)) {
  details <- vapply(names(failures), function(package) {
    result <- failures[[package]]
    paste0(package, ": ", length(result$errors), " error(s), ",
           length(result$warnings), " warning(s)")
  }, character(1))
  note_details <- vapply(names(note_failures), function(package) {
    paste0(package, ": ", length(note_failures[[package]]),
           " unexplained NOTE(s): ",
           paste(note_failures[[package]], collapse = " | "))
  }, character(1))
  stop(
    "Package checks failed:\n",
    paste(c(details, note_details), collapse = "\n"), call. = FALSE
  )
}
