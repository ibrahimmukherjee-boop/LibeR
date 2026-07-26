test_that("GUI background registry returns a native benchmark", {
  registry <- .liber_shared_task_registry()
  id <- .liber_shared_task_start(
    registry, "LibeRtAD", ".ad_gui_background_task",
    args = list(
      case = "rosenbrock", iterations = 2L, warmups = 0L,
      optimize = TRUE, finite_difference = FALSE
    ),
    label = "test benchmark",
    metadata = list(operation = "native")
  )
  expect_true(nzchar(id))
  expect_true(.liber_shared_task_snapshot(registry)$running)
  deadline <- Sys.time() + 30
  while (.liber_shared_task_active(registry) && Sys.time() < deadline) {
    Sys.sleep(0.05)
    .liber_shared_task_poll(registry)
  }
  completed <- .liber_shared_task_take_completed(registry)
  expect_length(completed, 1L)
  expect_identical(completed[[1L]]$status, "completed")
  expect_s3_class(completed[[1L]]$result, "ad_benchmark_result")
})

test_that("GUI background tasks can be cancelled", {
  registry <- .liber_shared_task_registry()
  .liber_shared_task_start(
    registry, "LibeRtAD", ".ad_gui_background_task",
    args = list(
      case = "rosenbrock", iterations = 100000L, warmups = 0L,
      optimize = TRUE, finite_difference = FALSE
    )
  )
  expect_true(.liber_shared_task_cancel_all(registry))
  expect_false(.liber_shared_task_active(registry))
  completed <- .liber_shared_task_take_completed(registry)
  expect_identical(completed[[1L]]$status, "cancelled")
})
