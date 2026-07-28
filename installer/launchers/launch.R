arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) != 1L) {
  stop("Usage: launch.R <libertad|liberation|liberary|liberary-ingest|liberary-reference|liberator|liberality|liberties>")
}

application <- tolower(arguments[[1L]])
script_argument <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script <- if (length(script_argument)) {
  normalizePath(sub("^--file=", "", script_argument[[1L]]),
                winslash = "/", mustWork = TRUE)
} else {
  normalizePath("launch.R", winslash = "/", mustWork = TRUE)
}
install_root <- normalizePath(
  file.path(dirname(script), ".."), winslash = "/", mustWork = TRUE
)
private_library <- file.path(install_root, "library")
.libPaths(unique(c(private_library, file.path(R.home(), "library"))))
Sys.setenv(
  R_LIBS_USER = private_library,
  R_LIBS_SITE = "",
  LIBER_INSTALL_MODE = "bundled",
  LIBER_RUNTIME_ROOT = install_root
)

launchers <- list(
  libertad = function() LibeRtAD::libertad_gui(),
  # Rscript is non-interactive, so LibeRation's package-level default correctly
  # avoids opening a browser. A desktop launcher is an explicit interactive
  # request and must override that default.
  liberation = function() LibeRation::liber_gui(launch.browser = TRUE),
  liberary = function() LibeRary::library_shiny(),
  `liberary-ingest` = function() LibeRary::ingest_shiny(),
  `liberary-reference` = function() LibeRary::library_reference_shiny(),
  liberator = function() LibeRator::lator_gui(),
  liberality = function() LibeRality::liberality_gui(),
  liberties = function() LibeRties::ls_run_admin()
)
if (!application %in% names(launchers)) {
  stop("Unknown LibeR application: ", application, call. = FALSE)
}
launchers[[application]]()
