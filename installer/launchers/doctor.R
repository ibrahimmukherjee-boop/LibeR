script_argument <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script <- normalizePath(
  sub("^--file=", "", script_argument[[1L]]),
  winslash = "/", mustWork = TRUE
)
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
result <- LibeRation::liber_doctor(strict = TRUE, verbose = TRUE)
quit(save = "no", status = if (isTRUE(result$healthy)) 0L else 1L)
