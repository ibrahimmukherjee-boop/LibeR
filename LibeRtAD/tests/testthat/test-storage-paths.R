test_that("benchmark output supports an explicit data root", {
  root <- file.path(tempdir(), paste0("libertad-benchmarks-", Sys.getpid()))
  old <- Sys.getenv("LIBERTAD_BENCHMARK_HOME", unset = NA_character_)
  on.exit({
    if (is.na(old)) Sys.unsetenv("LIBERTAD_BENCHMARK_HOME")
    else Sys.setenv(LIBERTAD_BENCHMARK_HOME = old)
  }, add = TRUE)

  Sys.setenv(LIBERTAD_BENCHMARK_HOME = root)
  expect_equal(
    .ad_default_benchmark_output(),
    normalizePath(root, winslash = "/", mustWork = FALSE)
  )
})
