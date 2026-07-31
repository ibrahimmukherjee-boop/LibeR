test_that("design evaluation background entry point returns a full result", {
  example <- lity_example()
  result <- .lity_gui_background_task(
    "evaluate",
    list(design = example$design, criterion = lity_criterion_D())
  )
  expect_s3_class(result, "lity_evaluation")
  expect_true(is.finite(result$elapsed_seconds))
})

test_that("source-loaded background dependencies are ordered before callers", {
  root <- tempfile("liberality-source-chain-")
  dir.create(root, recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)
  definitions <- list(
    LibeRtAD = character(),
    LibeRation = "Imports: LibeRtAD (>= 0.7.10)",
    LibeRality = c(
      "Imports: LibeRation (>= 0.9.7)",
      "LinkingTo: LibeRtAD (>= 0.7.10)"
    )
  )
  records <- lapply(names(definitions), function(package) {
    path <- file.path(root, package)
    dir.create(path)
    writeLines(
      c(
        paste("Package:", package),
        "Version: 1.0.0",
        definitions[[package]]
      ),
      file.path(path, "DESCRIPTION")
    )
    list(package = package, path = path, version = "1.0.0")
  })
  names(records) <- names(definitions)
  testthat::local_mocked_bindings(
    .liber_shared_task_source_record = function(package) records[[package]],
    .package = "LibeRality"
  )
  ordered <- .liber_shared_task_source_packages("LibeRality")
  expect_identical(
    vapply(ordered, `[[`, character(1), "package"),
    c("LibeRtAD", "LibeRation", "LibeRality")
  )
})
