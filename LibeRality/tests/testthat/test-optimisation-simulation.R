test_that("coordinate exchange returns a valid improved design record", {
  design <- lity_example()$design
  design$variables <- design$variables["sparse_t1"]
  result <- lity_optimise(
    design, lity_criterion_D(), method = "coordinate_exchange",
    control = list(maxit = 2, grid_points = 4)
  )
  expect_s3_class(result, "lity_optimisation")
  expect_true(lity_validate(result$design)$valid)
  expect_gt(result$evaluations, 0)
  expect_true(is.finite(result$evaluation$criteria$value))
})

test_that("allocation optimisation preserves the subject total", {
  design <- lity_example()$design
  original <- sum(vapply(design$arms, `[[`, numeric(1), "size"))
  result <- lity_optimise(
    design, lity_criterion_D(), method = "multiplicative",
    control = list(maxit = 3)
  )
  final <- sum(vapply(result$design$arms, `[[`, numeric(1), "size"))
  expect_equal(final, original)
})

test_that("complete trial simulation is reproducible", {
  design <- lity_example()$design
  first <- lity_simulate_trials(design, n = 2, seed = 91, retain_data = TRUE)
  second <- lity_simulate_trials(design, n = 2, seed = 91, retain_data = TRUE)
  expect_s3_class(first, "lity_simulation")
  expect_equal(first$scenario_draws, second$scenario_draws)
  expect_equal(first$data, second$data)
  expect_equal(nrow(first$summary), 2)
  expect_gt(nrow(first$endpoint_summary), 0)
  expect_gt(nrow(first$nca$summary), 0)
  expect_identical(first$nca$backend, "LibeRation native C++ NCA")

  payload <- LibeRality:::.lity_gui_payload(
    design, lity_criterion_D(), simulation = first
  )
  expect_gt(length(payload$simulation$endpointCurves), 0)
  expect_gt(length(payload$simulation$nca$summary), 0)
})

test_that("robustness and constraint details are explicit in the workbench", {
  design <- lity_example()$design
  evaluation <- lity_evaluate(design, lity_criterion_D())
  payload <- LibeRality:::.lity_gui_payload(
    design, lity_criterion_D(), evaluation = evaluation
  )
  expect_true(payload$workflow$robustnessEvaluated)
  expect_equal(length(payload$evaluation$robustness), length(design$scenarios))
  expect_true(all(c("rule", "detail", "id") %in% names(payload$constraints[[1L]])))
})

test_that("LibeRation hand-off and reports are materialised", {
  design <- lity_example()$design
  data <- lity_to_liberation(design)
  expect_s3_class(data, "data.frame")
  expect_true(all(c("ID", "TIME", "EVID", "AMT", "ARM") %in% names(data)))

  file <- tempfile(fileext = ".html")
  expect_equal(lity_report(lity_evaluate(design), file), normalizePath(file, winslash = "/"))
  expect_true(file.exists(file))
})

test_that("the workbench produces an htmlwidget", {
  widget <- liberality_workbench(lity_example()$design)
  expect_s3_class(widget, "htmlwidget")
  expect_match(jsonlite::toJSON(widget$x, auto_unbox = TRUE), "Oral PK population design")
})
