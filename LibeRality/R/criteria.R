.lity_criterion_types <- c(
  "D", "ED", "A", "E", "Ds", "c", "L", "rse", "max_rse",
  "prediction_variance",
  "bayesian", "robust", "minimax", "maximin", "model_average", "precision_probability",
  "T", "KL", "model_discrimination", "power", "superiority", "noninferiority",
  "correct_dose", "target_attainment", "expected_utility", "cost", "burden",
  "compound", "pareto"
)

.lity_default_direction <- function(type) {
  if (type %in% c("A", "c", "L", "rse", "max_rse", "prediction_variance", "cost", "burden")) "minimise" else "maximise"
}

#' Define an optimal-design criterion
#'
#' @param type Criterion type.
#' @param name Display name.
#' @param parameters Parameter subset.
#' @param weights Parameter, scenario, component, or loss weights.
#' @param contrast Contrast/gradient vector.
#' @param matrix L-criterion matrix.
#' @param target Clinical, precision, or decision target.
#' @param threshold Criterion threshold.
#' @param alpha Type-I error for power criteria.
#' @param alternative One- or two-sided alternative.
#' @param margin Non-inferiority/superiority margin.
#' @param effect Assumed effect; defaults to the contrast applied to nominal parameters.
#' @param base Base criterion for Bayesian/robust aggregation.
#' @param components Criteria combined into a compound or Pareto objective.
#' @param direction Optimisation direction.
#' @param scale,reference Compound-objective scaling.
#' @param nsim,seed Simulation controls for decision criteria.
#' @param utility Optional custom utility function; built-in serializable utility
#'   definitions are preferred for queue execution.
#' @param metadata Additional metadata.
#' @param ... Additional arguments passed from a criterion-specific helper to
#'   [lity_criterion()].
#' @param summary RSE aggregation: weighted, maximum, or arithmetic mean.
#' @param gradient Parameter gradient for expected prediction variance.
#' @param method Model-discrimination distance: KL, T, or weighted general
#'   model discrimination.
#' @param kind Hypothesis criterion: power, superiority, or non-inferiority.
#' @export
lity_criterion <- function(type = .lity_criterion_types, name = NULL,
                           parameters = NULL, weights = NULL, contrast = NULL,
                           matrix = NULL, target = NULL, threshold = NULL,
                           alpha = 0.05, alternative = c("two.sided", "greater", "less"),
                           margin = 0, effect = NULL, base = NULL, components = NULL,
                           direction = NULL, scale = NULL, reference = NULL,
                           nsim = 250L, seed = 7301L, utility = NULL, metadata = list()) {
  type <- match.arg(type)
  alternative <- match.arg(alternative)
  if (type %in% c("bayesian", "robust", "minimax", "maximin", "model_average") && is.null(base)) {
    base <- lity_criterion_D()
  }
  if (!is.null(base) && !inherits(base, "lity_criterion")) .lity_stop("`base` must be a LibeRality criterion.")
  if (!is.null(components)) components <- .lity_named_list(components, "components", "lity_criterion")
  if (type %in% c("compound", "pareto") && !length(components)) .lity_stop(type, " criteria require `components`.")
  if (!is.null(contrast)) contrast <- as.numeric(contrast)
  if (!is.null(matrix)) matrix <- as.matrix(matrix)
  if (!is.null(threshold)) threshold <- as.numeric(threshold)
  alpha <- .lity_number(alpha, "alpha", lower = .Machine$double.eps, upper = 1 - .Machine$double.eps)
  nsim <- as.integer(nsim)
  if (length(nsim) != 1L || is.na(nsim) || nsim < 1L) .lity_stop("`nsim` must be positive.")
  direction <- direction %||% if (!is.null(base) && type %in% c("bayesian", "robust", "minimax", "maximin", "model_average")) base$direction else .lity_default_direction(type)
  direction <- match.arg(direction, c("maximise", "minimise"))
  structure(list(
    schema = "liberality.criterion", version = 1L,
    type = type, name = .lity_scalar(name %||% type, "name"), parameters = parameters,
    weights = weights, contrast = contrast, matrix = matrix, target = target,
    threshold = threshold, alpha = alpha, alternative = alternative,
    margin = as.numeric(margin)[[1L]], effect = effect, base = base,
    components = components, direction = direction, scale = scale,
    reference = reference, nsim = nsim, seed = as.integer(seed)[[1L]],
    utility = utility, metadata = metadata
  ), class = "lity_criterion")
}

#' @export
print.lity_criterion <- function(x, ...) {
  cat("LibeRality criterion:", x$name, "[", x$type, "]", x$direction, "\n")
  invisible(x)
}

#' @rdname lity_criterion
#' @export
lity_criterion_D <- function(parameters = NULL, ...) lity_criterion("D", parameters = parameters, ...)
#' @rdname lity_criterion
#' @export
lity_criterion_ED <- function(parameters = NULL, weights = NULL,
                              name = "ED-optimality", ...) {
  lity_criterion(
    "ED", parameters = parameters, weights = weights,
    name = name, ...
  )
}
#' @rdname lity_criterion
#' @export
lity_criterion_A <- function(parameters = NULL, weights = NULL, ...) lity_criterion("A", parameters = parameters, weights = weights, ...)
#' @rdname lity_criterion
#' @export
lity_criterion_E <- function(parameters = NULL, ...) lity_criterion("E", parameters = parameters, ...)
#' @rdname lity_criterion
#' @export
lity_criterion_Ds <- function(parameters, ...) lity_criterion("Ds", parameters = parameters, ...)
#' @rdname lity_criterion
#' @export
lity_criterion_c <- function(contrast, ...) lity_criterion("c", contrast = contrast, ...)
#' @rdname lity_criterion
#' @export
lity_criterion_L <- function(matrix, weights = NULL, ...) lity_criterion("L", matrix = matrix, weights = weights, ...)
#' @rdname lity_criterion
#' @export
lity_criterion_rse <- function(parameters = NULL, weights = NULL, summary = c("weighted", "max", "mean"), ...) {
  summary <- match.arg(summary)
  lity_criterion(if (summary == "max") "max_rse" else "rse", parameters = parameters,
                 weights = weights, metadata = list(summary = summary), ...)
}
#' @rdname lity_criterion
#' @export
lity_criterion_prediction <- function(gradient, ...) lity_criterion("prediction_variance", contrast = gradient, ...)
#' @rdname lity_criterion
#' @export
lity_criterion_bayesian <- function(base = lity_criterion_D(), weights = NULL, ...) lity_criterion("bayesian", base = base, weights = weights, ...)
#' @rdname lity_criterion
#' @export
lity_criterion_robust <- function(base = lity_criterion_D(), weights = NULL, ...) lity_criterion("robust", base = base, weights = weights, ...)
#' @rdname lity_criterion
#' @export
lity_criterion_minimax <- function(base = lity_criterion_A(), ...) lity_criterion("minimax", base = base, ...)
#' @rdname lity_criterion
#' @export
lity_criterion_maximin <- function(base = lity_criterion_D(), ...) lity_criterion("maximin", base = base, ...)
#' @rdname lity_criterion
#' @export
lity_criterion_model_average <- function(base = lity_criterion_D(), weights = NULL, ...) lity_criterion("model_average", base = base, weights = weights, ...)
#' @rdname lity_criterion
#' @export
lity_criterion_precision_probability <- function(parameters = NULL, threshold = 20, ...) lity_criterion("precision_probability", parameters = parameters, threshold = threshold, ...)
#' @rdname lity_criterion
#' @export
lity_criterion_discrimination <- function(method = c("KL", "T", "model_discrimination"), weights = NULL, ...) {
  lity_criterion(match.arg(method), weights = weights, ...)
}
#' @rdname lity_criterion
#' @export
lity_criterion_power <- function(contrast, effect = NULL, alpha = 0.05,
                                 alternative = c("two.sided", "greater", "less"),
                                 margin = 0, kind = c("power", "superiority", "noninferiority"), ...) {
  lity_criterion(match.arg(kind), contrast = contrast, effect = effect, alpha = alpha,
                 alternative = match.arg(alternative), margin = margin, ...)
}
#' @rdname lity_criterion
#' @export
lity_criterion_target <- function(target, nsim = 250L, seed = 7301L, ...) {
  lity_criterion("target_attainment", target = target, nsim = nsim, seed = seed, ...)
}
#' @rdname lity_criterion
#' @export
lity_criterion_correct_dose <- function(target, nsim = 250L, seed = 7301L, ...) {
  lity_criterion("correct_dose", target = target, nsim = nsim, seed = seed, ...)
}
#' @rdname lity_criterion
#' @export
lity_criterion_expected_utility <- function(target = NULL, utility = NULL, weights = NULL,
                                            nsim = 250L, seed = 7301L, ...) {
  lity_criterion("expected_utility", target = target, utility = utility,
                 weights = weights, nsim = nsim, seed = seed, ...)
}
#' @rdname lity_criterion
#' @export
lity_criterion_cost <- function(...) lity_criterion("cost", ...)
#' @rdname lity_criterion
#' @export
lity_criterion_burden <- function(weights = NULL, ...) lity_criterion("burden", weights = weights, ...)
#' @rdname lity_criterion
#' @export
lity_criterion_compound <- function(components, weights = NULL, scale = NULL, reference = NULL, ...) {
  lity_criterion("compound", components = components, weights = weights,
                 scale = scale, reference = reference, ...)
}
#' @rdname lity_criterion
#' @export
lity_criterion_pareto <- function(components, ...) lity_criterion("pareto", components = components, ...)

.lity_information_for_matrix <- function(matrix, parameter_values = NULL, tolerance = 1e-10) {
  metrics <- lity_matrix_metrics_cpp(matrix, tolerance)
  covariance <- metrics$covariance
  dimnames(covariance) <- dimnames(matrix)
  values <- parameter_values %||% rep(NA_real_, nrow(matrix))
  se <- sqrt(pmax(diag(covariance), 0)); names(se) <- rownames(matrix)
  rse <- ifelse(is.finite(values) & abs(values) > 1e-15, 100 * se / abs(values), NA_real_)
  names(rse) <- rownames(matrix)
  list(matrix = matrix, covariance = covariance, se = se, rse = rse,
       eigenvalues = metrics$eigenvalues, rank = metrics$rank,
       condition_number = metrics$condition_number,
       log_determinant = metrics$log_determinant,
       trace_covariance = metrics$trace_covariance,
       minimum_eigenvalue = metrics$minimum_eigenvalue,
       parameters = data.frame(name = rownames(matrix), value = values, stringsAsFactors = FALSE))
}

.lity_contrast <- function(criterion, information) {
  contrast <- criterion$contrast
  if (is.null(contrast)) .lity_stop("Criterion `", criterion$name, "` requires a contrast or gradient.")
  if (!is.null(names(contrast))) {
    aligned <- numeric(nrow(information$matrix)); names(aligned) <- rownames(information$matrix)
    normalized <- toupper(gsub("_", "", names(contrast)))
    match_index <- match(normalized, toupper(gsub("_", "", names(aligned))))
    if (anyNA(match_index)) .lity_stop("Contrast contains unknown parameter names.")
    aligned[match_index] <- contrast
    contrast <- aligned
  }
  if (length(contrast) != nrow(information$matrix)) .lity_stop("Contrast length does not match the information matrix.")
  as.numeric(contrast)
}

.lity_logdet <- function(matrix, tolerance = 1e-10) {
  values <- eigen((matrix + t(matrix)) / 2, symmetric = TRUE, only.values = TRUE)$values
  threshold <- max(abs(values), 1) * tolerance
  if (any(values <= threshold)) return(-Inf)
  sum(log(values))
}

.lity_power <- function(effect, se, alpha, alternative) {
  if (!is.finite(se) || se <= 0) return(if (is.finite(effect) && effect != 0) 1 else 0)
  ncp <- effect / se
  if (alternative == "two.sided") {
    critical <- stats::qnorm(1 - alpha / 2)
    stats::pnorm(-critical - ncp) + 1 - stats::pnorm(critical - ncp)
  } else if (alternative == "greater") {
    1 - stats::pnorm(stats::qnorm(1 - alpha) - ncp)
  } else stats::pnorm(stats::qnorm(alpha) - ncp)
}

.lity_direct_value <- function(criterion, information, design, scenario = NULL) {
  names <- rownames(information$matrix)
  subset <- .lity_match_parameters(criterion$parameters, names)
  covariance <- information$covariance
  if (criterion$type == "D") return(.lity_logdet(information$matrix[subset, subset, drop = FALSE]))
  if (criterion$type == "Ds") return(-.lity_logdet(covariance[subset, subset, drop = FALSE]))
  if (criterion$type == "A") {
    weights <- criterion$weights %||% rep(1, length(subset)); weights <- rep(as.numeric(weights), length.out = length(subset))
    return(sum(weights * diag(covariance)[subset]))
  }
  if (criterion$type == "E") {
    effective <- .lity_safe_inverse(covariance[subset, subset, drop = FALSE])
    return(min(eigen(effective, symmetric = TRUE, only.values = TRUE)$values))
  }
  if (criterion$type == "c" || criterion$type == "prediction_variance") {
    contrast <- .lity_contrast(criterion, information)
    return(drop(t(contrast) %*% covariance %*% contrast))
  }
  if (criterion$type == "L") {
    L <- criterion$matrix
    if (ncol(L) != nrow(covariance)) .lity_stop("L-criterion matrix has the wrong number of columns.")
    variances <- diag(L %*% covariance %*% t(L))
    weights <- rep(as.numeric(criterion$weights %||% 1), length.out = length(variances))
    return(sum(weights * variances))
  }
  if (criterion$type %in% c("rse", "max_rse")) {
    values <- information$rse[subset]
    if (all(!is.finite(values))) return(Inf)
    if (criterion$type == "max_rse" || identical(criterion$metadata$summary, "max")) return(max(values, na.rm = TRUE))
    weights <- rep(as.numeric(criterion$weights %||% 1), length.out = length(values))
    if (identical(criterion$metadata$summary, "mean")) weights <- rep(1, length(values))
    return(stats::weighted.mean(values, weights, na.rm = TRUE))
  }
  if (criterion$type %in% c("power", "superiority", "noninferiority")) {
    contrast <- .lity_contrast(criterion, information)
    se <- sqrt(max(0, drop(t(contrast) %*% covariance %*% contrast)))
    assumed <- criterion$effect
    if (is.null(assumed)) assumed <- sum(contrast * information$parameters$value)
    if (criterion$type == "noninferiority") assumed <- assumed - criterion$margin
    if (criterion$type == "superiority") assumed <- assumed - criterion$margin
    return(.lity_power(as.numeric(assumed)[[1L]], se, criterion$alpha, criterion$alternative))
  }
  if (criterion$type == "cost") return(.lity_design_cost(design))
  if (criterion$type == "burden") return(.lity_design_burden(design, criterion$weights %||% list()))
  .lity_stop("Criterion `", criterion$type, "` requires a specialized evaluator.")
}

.lity_model_predictions <- function(model, arm, scenario = NULL) {
  theta <- if (!is.null(scenario) && length(scenario$theta) == nrow(model$THETAS)) scenario$theta else model$THETAS$Value
  sigma <- if (!is.null(scenario) && length(scenario$sigma) == nrow(model$SIGMAS)) scenario$sigma else model$SIGMAS$Value
  output <- LibeRation::nm_simulate(model, arm$events, theta = theta, sigma = sigma)
  observed <- arm$events$EVID == 0 & arm$events$MDV == 0
  data <- arm$events[observed, , drop = FALSE]
  mu <- as.numeric(output$IPRED[observed])
  variance <- .lity_residual_variance(model, mu, sigma, data$DVID)
  list(mu = mu, variance = variance, data = data)
}

.lity_discrimination_value <- function(design, criterion, scenario) {
  models <- c(list(primary = scenario$model %||% design$model), design$alternative_models)
  if (length(models) < 2L) .lity_stop("Model-discrimination criteria require at least one alternative model.")
  pairs <- utils::combn(seq_along(models), 2L)
  pair_values <- numeric(ncol(pairs)); pair_names <- character(ncol(pairs))
  for (pair in seq_len(ncol(pairs))) {
    first <- pairs[1L, pair]; second <- pairs[2L, pair]
    pair_names[[pair]] <- paste(names(models)[first], names(models)[second], sep = " vs ")
    value <- 0
    for (arm in design$arms) {
      a <- .lity_model_predictions(models[[first]], arm, scenario)
      b <- .lity_model_predictions(models[[second]], arm, scenario)
      if (length(a$mu) != length(b$mu)) .lity_stop("Competing models return different observation dimensions.")
      endpoint_index <- match(
        as.integer(a$data$DVID[[1L]]),
        vapply(design$endpoints, `[[`, integer(1), "dvid")
      )
      endpoint <- if (is.na(endpoint_index)) design$endpoints[[1L]] else design$endpoints[[endpoint_index]]
      if (endpoint$type == "binary") {
        pa <- if (endpoint$scale == "response") a$mu else .lity_link(a$mu, endpoint$link)
        pb <- if (endpoint$scale == "response") b$mu else .lity_link(b$mu, endpoint$link)
        pa <- pmin(1 - 1e-10, pmax(1e-10, pa)); pb <- pmin(1 - 1e-10, pmax(1e-10, pb))
        kl_ab <- pa * log(pa / pb) + (1 - pa) * log((1 - pa) / (1 - pb))
        kl_ba <- pb * log(pb / pa) + (1 - pb) * log((1 - pb) / (1 - pa))
        contribution <- if (criterion$type == "T") (pa - pb)^2 / pmax(pa * (1 - pa), 1e-10) else (kl_ab + kl_ba) / 2
      } else if (criterion$type == "T") {
        contribution <- (a$mu - b$mu)^2 / pmax((a$variance + b$variance) / 2, 1e-12)
      } else {
        kl_ab <- 0.5 * (log(b$variance / a$variance) + (a$variance + (a$mu - b$mu)^2) / b$variance - 1)
        kl_ba <- 0.5 * (log(a$variance / b$variance) + (b$variance + (a$mu - b$mu)^2) / a$variance - 1)
        contribution <- (kl_ab + kl_ba) / 2
      }
      value <- value + arm$size * sum(contribution)
    }
    pair_values[[pair]] <- value
  }
  weights <- .lity_normalize_weights(rep(as.numeric(criterion$weights %||% 1), length.out = length(pair_values)))
  list(value = sum(weights * pair_values), pairs = stats::setNames(pair_values, pair_names))
}

.lity_trapz <- function(time, value) {
  ordering <- order(time); time <- time[ordering]; value <- value[ordering]
  if (length(time) < 2L) return(value[[1L]] %||% NA_real_)
  sum(diff(time) * (value[-length(value)] + value[-1L]) / 2)
}

.lity_target_score <- function(time, value, target) {
  target <- target %||% list(kind = "range", lower = -Inf, upper = Inf, metric = "mean")
  rules <- target$rules %||% target
  metric_name <- target$metric %||% rules$metric %||% "mean"
  metric <- switch(metric_name,
    auc = .lity_trapz(time, value), trough = min(value, na.rm = TRUE),
    peak = max(value, na.rm = TRUE), last = utils::tail(value[order(time)], 1L),
    time_above = {
      threshold <- rules$threshold %||% rules$lower
      if (length(time) < 2L) as.numeric(value[[1L]] > threshold) else {
        ordering <- order(time); tt <- time[ordering]; vv <- value[ordering]
        sum(diff(tt) * ((vv[-length(vv)] > threshold) + (vv[-1L] > threshold)) / 2) / diff(range(tt))
      }
    },
    mean(value, na.rm = TRUE)
  )
  lower <- rules$lower %||% if (!is.null(rules$target_fraction)) rules$target_fraction else -Inf
  upper <- rules$upper %||% Inf
  target_value <- rules$target %||% if (is.finite(lower) && is.finite(upper)) mean(c(lower, upper)) else if (is.finite(lower)) lower else upper
  attained <- is.finite(metric) && metric >= lower && metric <= upper
  scale <- if (is.finite(lower) && is.finite(upper) && upper > lower) upper - lower else max(abs(target_value), 1)
  list(metric = metric, attained = attained, loss = abs(metric - target_value) / scale)
}

.lity_target_attainment <- function(design, criterion, scenario) {
  .lity_seed(criterion$seed)
  arm_results <- list()
  for (arm_name in names(design$arms)) {
    arm <- design$arms[[arm_name]]
    model <- scenario$model %||% design$model
    simulated <- LibeRation::nm_simulate(
      model, arm$events, theta = scenario$theta %||% model$THETAS$Value,
      sigma = scenario$sigma %||% model$SIGMAS$Value,
      omega = scenario$omega %||% model$OMEGAS$Value, nsim = criterion$nsim,
      random_effects = model$n_eta > 0L, residual = isTRUE(criterion$metadata$residual %||% FALSE),
      seed = criterion$seed
    )
    if (!"SIM" %in% names(simulated)) simulated$SIM <- 1L
    observed <- simulated$EVID == 0 & simulated$MDV == 0
    groups <- split(simulated[observed, , drop = FALSE], simulated$SIM[observed])
    target <- criterion$target %||% design$endpoints[[1L]]$target
    score <- lapply(groups, function(data) .lity_target_score(data$TIME, data$IPRED, target))
    arm_results[[arm_name]] <- data.frame(
      SIM = as.integer(names(groups)), metric = vapply(score, `[[`, numeric(1), "metric"),
      attained = vapply(score, `[[`, logical(1), "attained"),
      loss = vapply(score, `[[`, numeric(1), "loss"), stringsAsFactors = FALSE
    )
  }
  probability <- vapply(arm_results, function(x) mean(x$attained), numeric(1))
  weights <- vapply(design$arms, `[[`, numeric(1), "size"); weights <- .lity_normalize_weights(weights)
  list(value = sum(weights * probability), by_arm = probability, simulations = arm_results,
       mc_error = sqrt(sum(weights^2 * probability * (1 - probability) / criterion$nsim)))
}

.lity_correct_dose <- function(design, criterion, scenario) {
  target <- criterion$target %||% design$endpoints[[1L]]$target
  if (is.null(target)) .lity_stop("Correct-dose criteria require a target.")
  deterministic_loss <- vapply(design$arms, function(arm) {
    prediction <- .lity_model_predictions(scenario$model %||% design$model, arm, scenario)
    .lity_target_score(prediction$data$TIME, prediction$mu, target)$loss
  }, numeric(1))
  oracle <- names(which.min(deterministic_loss))[[1L]]
  simulated <- .lity_target_attainment(design, criterion, scenario)$simulations
  common <- Reduce(intersect, lapply(simulated, `[[`, "SIM"))
  selected <- vapply(common, function(id) {
    losses <- vapply(simulated, function(data) data$loss[match(id, data$SIM)], numeric(1))
    names(which.min(losses))[[1L]]
  }, character(1))
  probability <- mean(selected == oracle)
  list(value = probability, oracle = oracle, selection = table(selected),
       mc_error = sqrt(probability * (1 - probability) / max(1, length(selected))))
}

.lity_compound_value <- function(criterion, information, design, scenario) {
  components <- lapply(criterion$components, function(component) {
    if (component$type %in% c("T", "KL", "model_discrimination")) {
      result <- .lity_discrimination_value(design, component, scenario); value <- result$value
    } else if (component$type == "target_attainment") {
      result <- .lity_target_attainment(design, component, scenario); value <- result$value
    } else if (component$type == "correct_dose") {
      result <- .lity_correct_dose(design, component, scenario); value <- result$value
    } else value <- .lity_direct_value(component, information, design, scenario)
    list(value = value, direction = component$direction, name = component$name)
  })
  values <- vapply(components, `[[`, numeric(1), "value")
  directions <- vapply(components, `[[`, character(1), "direction")
  names(values) <- names(criterion$components)
  if (criterion$type == "pareto") return(list(value = NA_real_, components = values, directions = directions))
  weights <- .lity_normalize_weights(rep(as.numeric(criterion$weights %||% 1), length.out = length(values)))
  reference <- rep(as.numeric(criterion$reference %||% 1), length.out = length(values))
  scale <- rep(as.numeric(criterion$scale %||% 1), length.out = length(values))
  normalized <- values / pmax(abs(reference), 1e-12) * scale
  normalized[directions == "minimise"] <- -normalized[directions == "minimise"]
  list(value = sum(weights * normalized), components = values, normalized = normalized,
       directions = directions)
}

.lity_scenario_weights <- function(design, criterion) {
  default <- vapply(design$scenarios, `[[`, numeric(1), "probability")
  supplied <- criterion$weights
  if (is.null(supplied)) return(.lity_normalize_weights(default))
  if (!is.null(names(supplied))) supplied <- supplied[names(design$scenarios)]
  .lity_normalize_weights(rep(as.numeric(supplied), length.out = length(default)))
}

.lity_evaluate_criterion <- function(criterion, design, information) {
  scenarios <- design$scenarios
  weights <- .lity_scenario_weights(design, criterion)
  if (criterion$type == "ED") {
    parameter_names <- rownames(information[[1L]]$matrix)
    subset <- .lity_match_parameters(criterion$parameters, parameter_names)
    log_determinants <- vapply(information, function(item) {
      .lity_logdet(item$matrix[subset, subset, drop = FALSE])
    }, numeric(1))
    finite <- is.finite(log_determinants) & weights > 0
    log_expected <- if (!any(finite)) {
      -Inf
    } else {
      anchor <- max(log_determinants[finite])
      anchor + log(sum(weights[finite] * exp(
        log_determinants[finite] - anchor
      )))
    }
    expected <- if (
      is.finite(log_expected) &&
        log_expected <= log(.Machine$double.xmax)
    ) exp(log_expected) else if (identical(log_expected, -Inf)) 0 else Inf
    names(log_determinants) <- names(scenarios)
    return(list(
      value = log_expected,
      by_scenario = log_determinants,
      details = list(
        value_scale = "log_expected_determinant",
        expected_determinant = expected,
        scenario_log_determinants = log_determinants,
        parameters = parameter_names[subset]
      )
    ))
  }
  if (criterion$type == "model_average") {
    matrices <- lapply(information, `[[`, "matrix")
    averaged <- Reduce(`+`, Map(function(matrix, weight) matrix * weight, matrices, weights))
    values <- information[[1L]]$parameters$value
    value <- .lity_direct_value(criterion$base, .lity_information_for_matrix(averaged, values), design, scenarios[[1L]])
    return(list(value = value, by_scenario = NA_real_, details = list(averaged_information = averaged)))
  }
  if (criterion$type == "precision_probability") {
    selection <- .lity_match_parameters(criterion$parameters, rownames(information[[1L]]$matrix))
    threshold <- rep(criterion$threshold %||% 20, length.out = length(selection))
    achieved <- vapply(information, function(info) all(info$rse[selection] <= threshold, na.rm = FALSE), logical(1))
    return(list(value = sum(weights * achieved), by_scenario = achieved,
                details = list(threshold = threshold, parameters = rownames(information[[1L]]$matrix)[selection])))
  }
  base <- if (criterion$type %in% c("bayesian", "robust", "minimax", "maximin")) criterion$base else criterion
  details <- vector("list", length(scenarios)); scenario_values <- numeric(length(scenarios))
  for (i in seq_along(scenarios)) {
    if (base$type %in% c("T", "KL", "model_discrimination")) {
      details[[i]] <- .lity_discrimination_value(design, base, scenarios[[i]])
      scenario_values[[i]] <- details[[i]]$value
    } else if (base$type == "target_attainment") {
      details[[i]] <- .lity_target_attainment(design, base, scenarios[[i]])
      scenario_values[[i]] <- details[[i]]$value
    } else if (base$type == "correct_dose") {
      details[[i]] <- .lity_correct_dose(design, base, scenarios[[i]])
      scenario_values[[i]] <- details[[i]]$value
    } else if (base$type == "expected_utility") {
      attainment <- .lity_target_attainment(design, base, scenarios[[i]])
      cost <- .lity_design_cost(design); burden <- .lity_design_burden(design)
      if (is.function(base$utility)) value <- base$utility(attainment, cost, burden, design)
      else {
        utility_weights <- utils::modifyList(list(attainment = 1, cost = 0, burden = 0), base$weights %||% list())
        value <- utility_weights$attainment * attainment$value - utility_weights$cost * cost - utility_weights$burden * burden
      }
      details[[i]] <- list(attainment = attainment, cost = cost, burden = burden)
      scenario_values[[i]] <- as.numeric(value)[[1L]]
    } else if (base$type %in% c("compound", "pareto")) {
      details[[i]] <- .lity_compound_value(base, information[[i]], design, scenarios[[i]])
      scenario_values[[i]] <- details[[i]]$value
    } else scenario_values[[i]] <- .lity_direct_value(base, information[[i]], design, scenarios[[i]])
  }
  names(scenario_values) <- names(scenarios)
  if (base$type == "pareto") {
    components <- Reduce(`+`, Map(function(detail, weight) detail$components * weight, details, weights))
    return(list(value = NA_real_, by_scenario = scenario_values,
                details = list(components = components, directions = details[[1L]]$directions, scenarios = details)))
  }
  if (criterion$type %in% c("minimax", "maximin")) {
    worst <- if (base$direction == "maximise") min(scenario_values) else max(scenario_values)
    value <- worst
  } else if (criterion$type %in% c("bayesian", "robust")) value <- sum(weights * scenario_values)
  else value <- scenario_values[[1L]]
  mc_error <- sqrt(sum(weights * (scenario_values - sum(weights * scenario_values))^2) / max(1, length(scenario_values)))
  list(value = value, by_scenario = scenario_values, details = details, mc_error = mc_error)
}

#' Evaluate one or more criteria for a design
#' @param design Design object.
#' @param criteria Criterion or named list of criteria.
#' @param tolerance Numerical rank tolerance.
#' @param check_constraints Evaluate constraints after criteria.
#' @return A `lity_evaluation`.
#' @export
lity_evaluate <- function(design, criteria = lity_criterion_D(), tolerance = 1e-10,
                          check_constraints = TRUE) {
  started <- proc.time()[[3L]]
  if (inherits(criteria, "lity_criterion")) criteria <- list(criteria)
  criteria <- .lity_named_list(criteria, "criteria", "lity_criterion")
  information <- lapply(seq_along(design$scenarios), function(i) lity_information(design, i, tolerance = tolerance))
  names(information) <- names(design$scenarios)
  evaluated <- lapply(criteria, .lity_evaluate_criterion, design = design, information = information)
  table <- data.frame(
    name = vapply(criteria, `[[`, character(1), "name"),
    type = vapply(criteria, `[[`, character(1), "type"),
    direction = vapply(criteria, `[[`, character(1), "direction"),
    value = vapply(evaluated, function(x) as.numeric(x$value %||% NA_real_)[[1L]], numeric(1)),
    mc_error = vapply(evaluated, function(x) as.numeric(x$mc_error %||% NA_real_)[[1L]], numeric(1)),
    stringsAsFactors = FALSE
  )
  result <- structure(list(
    schema = "liberality.evaluation", version = 1L, id = .lity_id("evaluation"),
    design_id = design$id, design_hash = .lity_hash(design), design = design,
    criteria = table,
    criterion_definitions = criteria, criterion_details = evaluated,
    information = information, constraints = data.frame(),
    elapsed_seconds = proc.time()[[3L]] - started, created_at = .lity_now()
  ), class = "lity_evaluation")
  if (isTRUE(check_constraints)) result$constraints <- lity_constraint_check(design, result)
  result
}

#' @export
print.lity_evaluation <- function(x, ...) {
  cat("LibeRality design evaluation\n")
  print(x$criteria, row.names = FALSE)
  if (nrow(x$constraints)) cat("  feasible:", all(x$constraints$feasible), " constraints:", nrow(x$constraints), "\n")
  cat("  elapsed:", format(x$elapsed_seconds, digits = 4), "seconds\n")
  invisible(x)
}
