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

test_that("information reuses guarded LibeRation prediction plans", {
  .lity_prediction_plan_clear()
  design <- lity_example()$design
  first <- lity_information(design)
  second <- lity_information(design)
  expect_gt(first$diagnostics$prediction_plan$cache_misses, 0L)
  expect_gt(second$diagnostics$prediction_plan$cache_hits, 0L)
  expect_equal(second$matrix, first$matrix, tolerance = 1e-12)
  expect_identical(
    second$diagnostics$prediction_plan$backend,
    "persistent guarded CppAD dynamic-parameter tape"
  )
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

test_that("allocation optimisation can activate an initially empty arm", {
  design <- lity_example()$design
  skip_if(length(design$arms) < 2L)
  total <- sum(vapply(design$arms, `[[`, numeric(1), "size"))
  design$arms[[1L]]$size <- total
  design$arms[[1L]]$allocation <- 1
  design$arms[[2L]]$size <- 0
  design$arms[[2L]]$allocation <- 0
  result <- lity_optimise(
    design, lity_criterion_D(), method = "fedorov_wynn",
    control = list(maxit = 2)
  )
  expect_s3_class(result, "lity_optimisation")
  expect_equal(
    sum(vapply(result$design$arms, `[[`, numeric(1), "size")),
    total
  )
})

test_that("allocation methods use criterion-specific sensitivities", {
  design <- lity_example()$design
  initial <- lity_evaluate(design, lity_criterion_A())$criteria$value[[1L]]
  result <- lity_optimise(
    design, lity_criterion_A(), method = "multiplicative",
    control = list(maxit = 8, reltol = 1e-8)
  )
  final <- lity_evaluate(result$design, lity_criterion_A())$criteria$value[[1L]]
  expect_lte(final, initial * (1 + 1e-8))
  expect_equal(
    sum(vapply(result$design$arms, `[[`, numeric(1), "size")),
    sum(vapply(design$arms, `[[`, numeric(1), "size"))
  )

  expect_error(
    lity_optimise(
      design, lity_criterion_rse(), method = "multiplicative",
      control = list(maxit = 1)
    ),
    "not implemented"
  )
})

test_that("event simulation uses the same hazard-time scale as information", {
  set.seed(17)
  ids <- rep(seq_len(2500L), each = 3L)
  data <- data.frame(
    ID = ids, TIME = rep(c(0, 2, 5), 2500L), EVID = 0L, MDV = 0L,
    DVID = 1L, IPRED = 0
  )
  endpoint <- lity_endpoint(
    "Event", "time_to_event", link = "identity", scale = "response"
  )
  data$IPRED <- 0.5
  simulated <- LibeRality:::.lity_simulate_noncontinuous(
    data, list(endpoint)
  )
  means <- tapply(simulated$DV, simulated$TIME, mean)
  expect_equal(as.numeric(means), 0.5 * c(2, 3, 2.5), tolerance = 0.08)
})

test_that("Weibull event simulation uses fixed-shape cumulative-hazard increments", {
  expect_error(
    lity_endpoint("Event", "time_to_event", distribution = "weibull"),
    "require a fixed positive"
  )
  endpoint <- lity_endpoint(
    "Event", "time_to_event", link = "identity", scale = "response",
    distribution = "weibull", dispersion = 2
  )
  expect_equal(
    LibeRality:::.lity_tte_interval_exposure(c(0, 2, 5), endpoint),
    c(4, 21, 31.25)
  )
  moments <- LibeRality:::.lity_response_moments(
    rep(0.01, 3), matrix(1, 3, 1), matrix(2, 3, 1), endpoint, c(0, 2, 5)
  )
  expect_equal(moments$mean, 0.01 * c(4, 21, 31.25))
  expect_equal(drop(moments$H), c(4, 21, 31.25))
  expect_equal(drop(moments$G), 2 * c(4, 21, 31.25))

  set.seed(18)
  ids <- rep(seq_len(4000L), each = 3L)
  data <- data.frame(
    ID = ids, TIME = rep(c(0, 2, 5), 4000L), EVID = 0L, MDV = 0L,
    DVID = 1L, IPRED = 0.01
  )
  simulated <- LibeRality:::.lity_simulate_noncontinuous(data, list(endpoint))
  means <- tapply(simulated$DV, simulated$TIME, mean)
  expect_equal(as.numeric(means), 0.01 * c(4, 21, 31.25), tolerance = 0.035)
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

test_that("operating characteristics calculate empirical interval coverage", {
  make_fit <- function(theta, se) structure(list(
    theta = theta, convergence = 0L,
    covariance = structure(list(
      status = "completed", type = "hessian",
      se = stats::setNames(se, c("THETA1", "THETA2"))
    ), class = "nm_covariance")
  ), class = "nm_fit")
  simulation <- structure(list(
    fits = list(make_fit(c(1.05, 2.1), c(0.1, 0.2)),
                make_fit(c(1.5, 2.8), c(0.1, 0.1))),
    summary = data.frame(converged = c(TRUE, TRUE)),
    truth = list(c(1, 2)), scenario_draws = c(1L, 1L)
  ), class = "lity_simulation")
  result <- lity_operating_characteristics(simulation)
  expect_true(result$coverage_available)
  expect_equal(result$coverage$coverage, c(0.5, 0.5))
  expect_equal(result$coverage$nominal, rep(0.95, 2))
  expect_equal(nrow(result$raw_coverage), 4L)
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
