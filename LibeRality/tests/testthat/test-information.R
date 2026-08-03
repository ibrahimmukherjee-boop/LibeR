test_that("the teaching design validates and has usable information", {
  example <- lity_example()
  validation <- lity_validate(example$design)
  expect_true(validation$valid)

  information <- lity_information(example$design)
  expect_s3_class(information, "lity_information")
  expect_equal(information$matrix, t(information$matrix), tolerance = 1e-10)
  expect_equal(information$rank, nrow(information$matrix))
  expect_true(all(is.finite(information$se)))
  expect_true(all(information$eigenvalues >= -1e-8))
  expect_equal(example$design$information_approximation, "fo_block")
  expect_equal(information$diagnostics$approximation, "fo_block")

  full <- example$design
  full$information_approximation <- "full_gaussian"
  expect_equal(
    lity_information(full)$diagnostics$approximation,
    "full_gaussian"
  )

  legacy <- example$design
  legacy$information_approximation <- NULL
  expect_match(lity_validate(legacy)$warnings, "Legacy design")
  expect_equal(lity_information(legacy)$diagnostics$approximation, "fo_block")
})

test_that("the native assembler matches a simple Gaussian result", {
  result <- LibeRality:::lity_fim_cpp(
    matrix(c(1, 2), ncol = 1), diag(2),
    list(matrix(0, 2, 2))
  )
  expect_equal(drop(result$information), 5, tolerance = 1e-12)
  expect_equal(result$observation_covariance_rank, 2)
})

test_that("one-compartment IV information matches the analytic regression", {
  model <- LibeRation::nm_model(
    INPUT = c("ID", "TIME", "EVID", "AMT", "RATE", "CMT", "DV", "MDV", "DVID"),
    ADVAN = 1L, TRANS = 1L, DOSECMP = 1L, OBSCMP = 1L,
    PRED = "CL=THETA(1); V=THETA(2); S1=V",
    ERROR = "Y=F+ERR(1)",
    THETAS = data.frame(THETA = 1:2, Value = c(2, 20)),
    SIGMAS = data.frame(SIGMA = 1, Value = 0.25, FIX = TRUE)
  )
  times <- c(0.5, 1, 2, 4)
  arm <- lity_arm(
    "Analytic IV", lity_schedule(times, dose = 100, dose_cmt = 1,
                                  observation_cmt = 1), size = 3
  )
  design <- lity_design(
    model, list(iv = arm),
    endpoints = list(pk = lity_endpoint("Concentration", "continuous"))
  )
  information <- lity_information(design)
  concentration <- 100 / 20 * exp(-(2 / 20) * times)
  derivative <- cbind(
    CL = -times / 20 * concentration,
    V = concentration * (-1 / 20 + 2 * times / 20^2)
  )
  # The default residual parameterization stores a standard deviation.
  expected <- 3 * crossprod(derivative) / 0.25^2
  dimnames(expected) <- dimnames(information$matrix)
  expect_equal(information$matrix, expected, tolerance = 2e-8)
})

test_that("information-dependent precision constraints do not recurse", {
  design <- lity_example()$design
  design$constraints <- list(
    precision = lity_constraint("RSE below 100%", "max_rse", 100)
  )
  expect_true(lity_validate(design)$valid)
  evaluation <- lity_evaluate(design, lity_criterion_D())
  expect_true(evaluation$constraints$feasible)
  expect_true(evaluation$constraints$value < 100)
})

test_that("non-continuous endpoint families produce finite information", {
  design <- lity_example()$design
  designs <- list(
    binary = lity_endpoint("Response", "binary"),
    ordinal = lity_endpoint("Grade", "ordinal", thresholds = c(-1, 0, 1)),
    count = lity_endpoint("Count", "count"),
    event = lity_endpoint("Event", "time_to_event"),
    recurrent = lity_endpoint("Recurrent event", "recurrent_event")
  )
  for (endpoint in designs) {
    design$endpoints <- list(outcome = endpoint)
    information <- lity_information(design)
    expect_true(all(is.finite(information$matrix)))
    expect_true(information$rank > 0)
  }
})

test_that("ordinal and residual working-moment derivatives are analytic", {
  endpoint <- lity_endpoint(
    "Grade", "ordinal", link = "logit", thresholds = c(-1, 0.4, 1.7)
  )
  eta <- c(-0.7, 0.2, 1.1)
  moments <- LibeRality:::.lity_response_moments(
    eta, matrix(1, 3, 1), matrix(1, 3, 1), endpoint, 1:3
  )
  step <- 1e-6
  numerical <- vapply(seq_along(eta), function(i) {
    plus <- minus <- eta
    plus[[i]] <- plus[[i]] + step
    minus[[i]] <- minus[[i]] - step
    plus_value <- LibeRality:::.lity_response_moments(
      plus, matrix(1, 3, 1), matrix(1, 3, 1), endpoint, 1:3
    )$variance[[i]]
    minus_value <- LibeRality:::.lity_response_moments(
      minus, matrix(1, 3, 1), matrix(1, 3, 1), endpoint, 1:3
    )$variance[[i]]
    (plus_value - minus_value) / (2 * step)
  }, numeric(1))
  expect_equal(moments$variance_derivative, numerical, tolerance = 2e-8)

  model <- lity_example()$model
  model$LIK_CONFIG$error <- "combined"
  model$LIK_CONFIG$sigma_parameterization <- "sd"
  prediction <- c(0.8, 2.3)
  sigma <- c(0.2, 0.4)
  derivatives <- LibeRality:::.lity_residual_variance_derivatives(
    model, prediction, sigma, c(1L, 1L)
  )
  variance <- function(mu, sig) LibeRality:::.lity_residual_variance(
    model, mu, sig, c(1L, 1L)
  )
  expect_equal(
    derivatives$mu,
    (variance(prediction + step, sigma) - variance(prediction - step, sigma)) /
      (2 * step),
    tolerance = 2e-8
  )
  for (index in seq_along(sigma)) {
    plus <- minus <- sigma
    plus[[index]] <- plus[[index]] + step
    minus[[index]] <- minus[[index]] - step
    expect_equal(
      derivatives$sigma[, index],
      (variance(prediction, plus) - variance(prediction, minus)) / (2 * step),
      tolerance = 2e-8
    )
  }
})
