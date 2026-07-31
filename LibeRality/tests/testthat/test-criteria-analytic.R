test_that("classical information criteria match closed-form diagonal results", {
  matrix <- diag(c(4, 9))
  dimnames(matrix) <- list(c("P1", "P2"), c("P1", "P2"))
  information <- LibeRality:::.lity_information_for_matrix(
    matrix, parameter_values = c(P1 = 2, P2 = 3)
  )
  design <- lity_example()$design
  evaluate <- function(criterion) {
    LibeRality:::.lity_direct_value(criterion, information, design)
  }

  expect_equal(evaluate(lity_criterion_D()), log(36), tolerance = 1e-12)
  expect_equal(evaluate(lity_criterion_A()), 1 / 4 + 1 / 9, tolerance = 1e-12)
  expect_equal(evaluate(lity_criterion_E()), 4, tolerance = 1e-12)
  expect_equal(evaluate(lity_criterion_Ds("P1")), log(4), tolerance = 1e-12)
  expect_equal(
    evaluate(lity_criterion_c(c(P1 = 1, P2 = 2))),
    1 / 4 + 4 / 9, tolerance = 1e-12
  )
  expect_equal(
    evaluate(lity_criterion_L(matrix(c(1, 2), nrow = 1))),
    1 / 4 + 4 / 9, tolerance = 1e-12
  )
  expect_equal(
    evaluate(lity_criterion_rse(summary = "mean")),
    mean(c(25, 100 / 9)), tolerance = 1e-12
  )
  expect_equal(
    evaluate(lity_criterion_rse(summary = "max")),
    25, tolerance = 1e-12
  )
})

test_that("power, superiority, and noninferiority use their declared margins", {
  matrix <- diag(c(4, 9))
  dimnames(matrix) <- list(c("P1", "P2"), c("P1", "P2"))
  information <- LibeRality:::.lity_information_for_matrix(
    matrix, parameter_values = c(P1 = 2, P2 = 3)
  )
  design <- lity_example()$design
  contrast <- c(P1 = 1, P2 = 0)
  expected <- LibeRality:::.lity_power(1, 0.5, 0.05, "two.sided")
  direct <- function(criterion) {
    LibeRality:::.lity_direct_value(criterion, information, design)
  }

  expect_equal(direct(lity_criterion_power(contrast, effect = 1)), expected)
  expect_equal(
    direct(lity_criterion_power(
      contrast, effect = 1.2, margin = 0.2, kind = "superiority"
    )), expected
  )
  expect_equal(
    direct(lity_criterion_power(
      contrast, effect = 1.2, margin = 0.2, kind = "noninferiority"
    )), expected
  )
})

test_that("singular information is rejected by determinant criteria", {
  matrix <- diag(c(4, 0))
  dimnames(matrix) <- list(c("P1", "P2"), c("P1", "P2"))
  information <- LibeRality:::.lity_information_for_matrix(
    matrix, parameter_values = c(P1 = 2, P2 = 3)
  )
  design <- lity_example()$design
  expect_identical(
    LibeRality:::.lity_direct_value(lity_criterion_D(), information, design),
    -Inf
  )
})

test_that("ED-optimality maximises the expected determinant on a log scale", {
  matrices <- list(
    low = diag(c(2, 3)),
    high = diag(c(4, 5))
  )
  information <- lapply(matrices, function(matrix) {
    dimnames(matrix) <- list(c("P1", "P2"), c("P1", "P2"))
    LibeRality:::.lity_information_for_matrix(
      matrix, parameter_values = c(P1 = 1, P2 = 1)
    )
  })
  design <- lity_example()$design
  design$scenarios <- list(
    low = lity_scenario("Low", probability = 0.25),
    high = lity_scenario("High", probability = 0.75)
  )
  criterion <- lity_criterion_ED()
  result <- LibeRality:::.lity_evaluate_criterion(
    criterion, design, information
  )

  expect_identical(criterion$type, "ED")
  expect_identical(criterion$name, "ED-optimality")
  expect_equal(result$value, log(0.25 * 6 + 0.75 * 20), tolerance = 1e-12)
  expect_equal(result$details$expected_determinant, 16.5, tolerance = 1e-12)
  expect_identical(result$details$value_scale, "log_expected_determinant")
  expect_equal(unname(result$by_scenario), log(c(6, 20)))
})
