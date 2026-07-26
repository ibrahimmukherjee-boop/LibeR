test_that("process supervisors expose a stable lifecycle contract", {
  process <- processx::process$new(
    file.path(R.home("bin"), "Rscript"),
    c("-e", "cat('supervised output\\n')"),
    stdout = "|", stderr = "|", cleanup = TRUE,
    windows_hide_window = TRUE
  )
  supervisor <- ls_supervise_process(process, "test process")
  expect_s3_class(supervisor, "LibeRProcessSupervisor")
  supervisor$wait(timeout = 10000L)
  expect_false(supervisor$is_alive())
  expect_equal(supervisor$get_exit_status(), 0L)
  expect_match(
    paste(supervisor$read_all_output_lines(), collapse = "\n"),
    "supervised output"
  )
  snapshot <- supervisor$snapshot()
  expect_identical(snapshot$schema, "liber.process-supervisor/1")
  expect_identical(snapshot$status, "completed")
})

test_that("process supervisors cancel live process trees", {
  process <- processx::process$new(
    file.path(R.home("bin"), "Rscript"),
    c("-e", "Sys.sleep(30)"),
    stdout = "|", stderr = "|", cleanup = TRUE,
    windows_hide_window = TRUE
  )
  supervisor <- ls_supervise_process(process, "cancel test")
  on.exit(if (supervisor$is_alive()) supervisor$kill_tree(), add = TRUE)
  expect_true(supervisor$is_alive())
  expect_true(supervisor$cancel(timeout = 5000L))
  expect_false(supervisor$is_alive())
})
