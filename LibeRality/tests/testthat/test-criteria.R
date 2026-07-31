test_that("all scalar criterion families evaluate", {
  design <- lity_example()$design
  alternative <- design$model
  alternative$THETAS$Value[[2L]] <- alternative$THETAS$Value[[2L]] * 1.25
  design$alternative_models <- list(alternative = alternative)
  p <- nrow(lity_information(design)$matrix)
  contrast <- c(0, 1, rep(0, p - 2L))
  target <- list(metric = "trough", lower = 0, upper = 1000)

  criteria <- list(
    D = lity_criterion_D(), ED = lity_criterion_ED(),
    A = lity_criterion_A(), E = lity_criterion_E(),
    Ds = lity_criterion_Ds(c("THETA1", "THETA2")),
    c = lity_criterion_c(contrast), L = lity_criterion_L(matrix(contrast, 1)),
    rse = lity_criterion_rse(), max_rse = lity_criterion_rse(summary = "max"),
    prediction = lity_criterion_prediction(contrast),
    bayesian = lity_criterion_bayesian(), robust = lity_criterion_robust(),
    minimax = lity_criterion_minimax(), maximin = lity_criterion_maximin(),
    model_average = lity_criterion_model_average(),
    precision_probability = lity_criterion_precision_probability(threshold = 1e6),
    T = lity_criterion_discrimination("T"), KL = lity_criterion_discrimination("KL"),
    power = lity_criterion_power(contrast, effect = 1),
    superiority = lity_criterion_power(contrast, effect = 1, kind = "superiority"),
    noninferiority = lity_criterion_power(contrast, effect = 1, kind = "noninferiority"),
    target = lity_criterion_target(target, nsim = 4),
    correct_dose = lity_criterion_correct_dose(target, nsim = 4),
    utility = lity_criterion_expected_utility(target, nsim = 4),
    cost = lity_criterion_cost(), burden = lity_criterion_burden()
  )
  evaluation <- lity_evaluate(design, criteria)
  expect_equal(nrow(evaluation$criteria), length(criteria))
  expect_true(all(is.finite(evaluation$criteria$value)))
})

test_that("compound and Pareto criteria preserve components", {
  design <- lity_example()$design
  components <- list(information = lity_criterion_D(), cost = lity_criterion_cost())
  compound <- lity_criterion_compound(
    components, weights = c(0.8, 0.2), reference = c(1, 100000)
  )
  result <- lity_evaluate(design, compound)
  expect_true(is.finite(result$criteria$value))
  expect_named(result$criterion_details[[1L]]$details[[1L]]$components, names(components))

  pareto <- lity_criterion_pareto(components)
  result <- lity_evaluate(design, pareto)
  expect_true(is.na(result$criteria$value))
  expect_named(result$criterion_details[[1L]]$details$components, names(components))
})
