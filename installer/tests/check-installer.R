liber_installer_layout_check <- function(root = getwd()) {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  required <- c(
    "installer/config/installer.json",
    "installer/launchers/doctor.R",
    "installer/launchers/launch.R",
    "installer/scripts/build-windows.ps1",
    "installer/scripts/build-icon.py",
    "installer/scripts/populate-library.R",
    "installer/scripts/stage-runtime.ps1",
    "installer/windows/liber.ico",
    "installer/windows/LibeR.iss"
  )
  missing <- required[!file.exists(file.path(root, required))]
  if (length(missing)) {
    stop("Missing installer files: ", paste(missing, collapse = ", "))
  }

  invisible(lapply(
    file.path(root, required[grepl("\\.R$", required)]),
    parse
  ))
  config <- jsonlite::fromJSON(file.path(
    root, "installer", "config", "installer.json"
  ))
  stopifnot(
    identical(config$schema, "liber.installer/1"),
    identical(config$runtime$r_version, "4.6.0"),
    identical(config$runtime$r_platform, "x86_64-w64-mingw32"),
    isTRUE(config$research_profile$include_cpp_toolchain),
    isTRUE(config$research_profile$include_package_sources),
    identical(config$runtime_profile$include_cpp_toolchain, FALSE),
    identical(config$runtime_profile$include_package_sources, FALSE)
  )

  launcher <- paste(readLines(
    file.path(root, "installer", "launchers", "launch.R"),
    warn = FALSE
  ), collapse = "\n")
  expected_launchers <- c(
    "LibeRtAD::libertad_gui", "LibeRation::liber_gui",
    "LibeRary::library_shiny", "LibeRary::ingest_shiny",
    "LibeRary::library_reference_shiny", "LibeRator::lator_gui",
    "LibeRality::liberality_gui", "LibeRties::ls_run_admin"
  )
  stopifnot(all(vapply(
    expected_launchers, grepl, logical(1), x = launcher, fixed = TRUE
  )))
  stopifnot(
    grepl('file.path(R.home(), "library")', launcher, fixed = TRUE),
    !grepl("c(private_library, .libPaths())", launcher, fixed = TRUE)
  )

  population <- paste(readLines(
    file.path(root, "installer", "scripts", "populate-library.R"),
    warn = FALSE
  ), collapse = "\n")
  stopifnot(
    grepl('"PFIM"', population, fixed = TRUE) == FALSE,
    grepl('"PopED"', population, fixed = TRUE) == FALSE,
    grepl("runtime_optional", population, fixed = TRUE),
    grepl("research_optional", population, fixed = TRUE)
  )

  inno <- paste(readLines(
    file.path(root, "installer", "windows", "LibeR.iss"),
    warn = FALSE
  ), collapse = "\n")
  stopifnot(
    grepl("PrivilegesRequired=lowest", inno, fixed = TRUE),
    grepl("SetupIconFile=liber.ico", inno, fixed = TRUE),
    grepl("Components: developer", inno, fixed = TRUE),
    grepl("LibeR-{#AppVersion}-{#InstallerProfile}", inno, fixed = TRUE),
    grepl('Parameters: "--vanilla', inno, fixed = TRUE)
  )

  message("Bundled installer layout checks passed.")
  invisible(TRUE)
}
