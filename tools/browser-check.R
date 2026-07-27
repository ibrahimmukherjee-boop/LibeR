root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
source(file.path(root, "tools", "validation-runtime.R"), local = TRUE)
local_library <- Sys.getenv(
  "LIBER_INSTALL_LIBRARY",
  liber_validation_dev_cache(root, "r-libraries", "browser", create = TRUE)
)
dir.create(local_library, recursive = TRUE, showWarnings = FALSE)
.libPaths(unique(c(local_library, .libPaths())))
Sys.setenv(
  LIBER_INSTALL_LIBRARY = local_library,
  R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep)
)
packages <- c("LibeRtAD", "LibeRation", "LibeRary", "LibeRator", "LibeRality", "LibeRties")
if (!identical(tolower(Sys.getenv("LIBER_SKIP_INSTALL")), "true")) {
  status <- system2(
    file.path(R.home("bin"), "Rscript"),
    file.path(root, "tools", "install-local-stack.R")
  )
  if (!identical(status, 0L)) stop("Unable to install local package stack.")
}
required <- c("testthat", "shinytest2", "DT")
missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) {
  stop(
    "Browser validation requires: ", paste(missing, collapse = ", "),
    ". The CI dependency step must install these packages explicitly.",
    call. = FALSE
  )
}
Sys.setenv(LIBER_RUN_BROWSER_TESTS = "true", NOT_CRAN = "true")
for (package in packages) {
  path <- file.path(root, package, "tests", "testthat", "test-browser-e2e.R")
  if (file.exists(path)) {
    testthat::test_file(path, reporter = "summary", stop_on_failure = TRUE)
  }
}
