test_that("design evaluation background entry point returns a full result", {
  example <- lity_example()
  result <- .lity_gui_background_task(
    "evaluate",
    list(design = example$design, criterion = lity_criterion_D())
  )
  expect_s3_class(result, "lity_evaluation")
  expect_true(is.finite(result$elapsed_seconds))
})
