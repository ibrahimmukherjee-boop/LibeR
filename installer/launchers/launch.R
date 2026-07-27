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

toolchain <- file.path(install_root, "developer", "rtools")
if (dir.exists(toolchain)) {
  compiler <- file.path(
    toolchain, "x86_64-w64-mingw32.static.posix", "bin"
  )
  utilities <- file.path(toolchain, "usr", "bin")
  available <- c(compiler, utilities)[dir.exists(c(compiler, utilities))]
  if (length(available)) {
    Sys.setenv(PATH = paste(
      c(normalizePath(available, winslash = "/", mustWork = TRUE),
        Sys.getenv("PATH")),
      collapse = .Platform$path.sep
    ))
  }
}

launchers <- list(
  libertad = function() LibeRtAD::libertad_gui(),
  liberation = function() LibeRation::liber_gui(),
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
