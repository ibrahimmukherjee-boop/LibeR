.lity_prediction_plan_cache <- new.env(parent = emptyenv())
.lity_prediction_plan_cache$.order <- character()

.lity_prediction_plan_key <- function(model, events) {
  structural <- intersect(
    c("ID", "EVID", "MDV", "CMT", "DVID", "SS", "ADDL", "RATE"),
    names(events)
  )
  .lity_hash(list(
    model = model,
    rows = nrow(events),
    structure = events[structural]
  ))
}

.lity_prediction_plan_clear <- function() {
  keys <- setdiff(
    ls(.lity_prediction_plan_cache, all.names = TRUE), ".order"
  )
  if (length(keys)) {
    remove(list = keys, envir = .lity_prediction_plan_cache)
  }
  .lity_prediction_plan_cache$.order <- character()
  invisible(NULL)
}

.lity_prediction_plan <- function(model, events, theta, sigma) {
  key <- .lity_prediction_plan_key(model, events)
  hit <- exists(key, envir = .lity_prediction_plan_cache, inherits = FALSE)
  if (hit) {
    plan <- get(key, envir = .lity_prediction_plan_cache, inherits = FALSE)
  } else {
    plan <- LibeRation::nm_prediction_plan(
      model, events, theta = theta, sigma = sigma
    )
    assign(key, plan, envir = .lity_prediction_plan_cache)
    .lity_prediction_plan_cache$.order <- c(
      .lity_prediction_plan_cache$.order, key
    )
    limit <- max(1L, as.integer(getOption(
      "LibeRality.prediction_plan_cache_size", 64L
    )))
    while (length(.lity_prediction_plan_cache$.order) > limit) {
      discard <- .lity_prediction_plan_cache$.order[[1L]]
      .lity_prediction_plan_cache$.order <-
        .lity_prediction_plan_cache$.order[-1L]
      if (exists(discard, envir = .lity_prediction_plan_cache,
                 inherits = FALSE)) {
        remove(list = discard, envir = .lity_prediction_plan_cache)
      }
    }
  }
  list(plan = plan, hit = hit)
}

.lity_parameter_spec <- function(model) {
  theta <- model$THETAS
  omega <- model$OMEGAS
  sigma <- model$SIGMAS
  parts <- list()
  if (nrow(theta)) parts[[length(parts) + 1L]] <- data.frame(
    name = paste0("THETA", theta$THETA), type = "theta", index = seq_len(nrow(theta)),
    row = theta$THETA, col = theta$THETA, value = theta$Value,
    fixed = theta$FIX, stringsAsFactors = FALSE
  )
  if (nrow(omega)) parts[[length(parts) + 1L]] <- data.frame(
    name = paste0("OMEGA_", omega$ROW, "_", omega$COL), type = "omega",
    index = seq_len(nrow(omega)), row = omega$ROW, col = omega$COL,
    value = omega$Value, fixed = omega$FIX, stringsAsFactors = FALSE
  )
  if (nrow(sigma)) parts[[length(parts) + 1L]] <- data.frame(
    name = paste0("SIGMA", sigma$SIGMA), type = "sigma", index = seq_len(nrow(sigma)),
    row = sigma$SIGMA, col = sigma$SIGMA, value = sigma$Value,
    fixed = sigma$FIX, stringsAsFactors = FALSE
  )
  result <- if (length(parts)) do.call(rbind, parts) else data.frame(
    name = character(), type = character(), index = integer(), row = integer(),
    col = integer(), value = numeric(), fixed = logical(), stringsAsFactors = FALSE
  )
  result[!result$fixed, , drop = FALSE]
}

.lity_omega_matrix <- function(model, values = model$OMEGAS$Value) {
  n_eta <- as.integer(model$n_eta %||% 0L)
  result <- matrix(0, n_eta, n_eta)
  if (!n_eta || !nrow(model$OMEGAS)) return(result)
  for (i in seq_len(nrow(model$OMEGAS))) {
    row <- model$OMEGAS$ROW[[i]]; col <- model$OMEGAS$COL[[i]]
    result[row, col] <- result[col, row] <- values[[i]]
  }
  result
}

.lity_sigma_variance <- function(value, model) {
  if (identical(model$LIK_CONFIG$sigma_parameterization, "variance")) value else value^2
}

.lity_residual_variance <- function(model, prediction, sigma, dvid = 1L) {
  error <- model$LIK_CONFIG$error %||% model$ERROR_TYPE %||% "none"
  if (error == "auto") error <- model$ERROR_TYPE
  if (error == "none" || !length(sigma)) return(rep(1e-12, length(prediction)))
  per_response <- if (error %in% c("combined", "power")) 2L else 1L
  dvid <- pmax(1L, as.integer(dvid))
  result <- numeric(length(prediction))
  for (i in seq_along(prediction)) {
    offset <- (dvid[[i]] - 1L) * per_response + 1L
    if (offset + per_response - 1L > length(sigma)) offset <- 1L
    first <- .lity_sigma_variance(sigma[[offset]], model)
    mu <- prediction[[i]]
    result[[i]] <- switch(error,
      additive = first,
      exponential = first,
      proportional = first * mu^2,
      combined = first * mu^2 + .lity_sigma_variance(sigma[[offset + 1L]], model),
      power = first * max(abs(mu), 1e-12)^(2 * sigma[[offset + 1L]]),
      first
    )
  }
  pmax(result, 1e-16)
}

.lity_residual_covariance <- function(model, prediction, sigma, data) {
  variance <- .lity_residual_variance(model, prediction, sigma, data$DVID %||% rep(1L, length(prediction)))
  covariance <- diag(variance, length(variance))
  if (identical(model$LIK_CONFIG$sigma_corr, "ar1") && length(variance) > 1L) {
    rho <- model$LIK_CONFIG$ar1_rho
    time <- as.numeric(data$TIME)
    dvid <- as.integer(data$DVID %||% rep(1L, nrow(data)))
    correlation <- outer(time, time, function(a, b) rho^abs(a - b))
    correlation[outer(dvid, dvid, `!=`)] <- 0
    diag(correlation) <- 1
    covariance <- correlation * outer(sqrt(variance), sqrt(variance))
  }
  covariance
}

.lity_residual_variance_derivatives <- function(model, prediction, sigma, dvid = 1L) {
  error <- model$LIK_CONFIG$error %||% model$ERROR_TYPE %||% "none"
  if (error == "auto") error <- model$ERROR_TYPE
  n <- length(prediction)
  d_sigma <- matrix(0, n, length(sigma))
  d_mu <- numeric(n)
  if (error == "none" || !length(sigma)) {
    return(list(mu = d_mu, sigma = d_sigma))
  }
  sigma_derivative <- function(value) {
    if (identical(model$LIK_CONFIG$sigma_parameterization, "variance")) 1 else 2 * value
  }
  per_response <- if (error %in% c("combined", "power")) 2L else 1L
  dvid <- pmax(1L, as.integer(dvid))
  for (i in seq_along(prediction)) {
    offset <- (dvid[[i]] - 1L) * per_response + 1L
    if (offset + per_response - 1L > length(sigma)) offset <- 1L
    first <- .lity_sigma_variance(sigma[[offset]], model)
    first_derivative <- sigma_derivative(sigma[[offset]])
    mu <- prediction[[i]]
    if (error %in% c("additive", "exponential")) {
      d_sigma[i, offset] <- first_derivative
    } else if (error == "proportional") {
      d_mu[[i]] <- 2 * first * mu
      d_sigma[i, offset] <- first_derivative * mu^2
    } else if (error == "combined") {
      d_mu[[i]] <- 2 * first * mu
      d_sigma[i, offset] <- first_derivative * mu^2
      d_sigma[i, offset + 1L] <- sigma_derivative(sigma[[offset + 1L]])
    } else if (error == "power") {
      magnitude <- max(abs(mu), 1e-12)
      exponent <- sigma[[offset + 1L]]
      variance <- first * magnitude^(2 * exponent)
      d_mu[[i]] <- if (abs(mu) > 1e-12) {
        variance * 2 * exponent / mu
      } else 0
      d_sigma[i, offset] <- first_derivative * magnitude^(2 * exponent)
      d_sigma[i, offset + 1L] <- variance * 2 * log(magnitude)
    } else {
      d_sigma[i, offset] <- first_derivative
    }
  }
  list(mu = d_mu, sigma = d_sigma)
}

.lity_residual_covariance_direction <- function(model, covariance, variance,
                                                variance_direction, data) {
  if (!identical(model$LIK_CONFIG$sigma_corr, "ar1") || length(variance) <= 1L) {
    return(diag(variance_direction, length(variance_direction)))
  }
  relative <- variance_direction / pmax(variance, 1e-16)
  covariance * 0.5 * outer(relative, relative, `+`)
}

.lity_link <- function(value, link, inverse = TRUE) {
  if (!inverse) return(switch(link,
    logit = log(value / (1 - value)), probit = stats::qnorm(value),
    cloglog = log(-log(1 - value)), log = log(value), identity = value,
    .lity_stop("Unsupported link: ", link, ".")
  ))
  switch(link,
    logit = stats::plogis(value), probit = stats::pnorm(value),
    cloglog = 1 - exp(-exp(value)), log = exp(value), identity = value,
    .lity_stop("Unsupported link: ", link, ".")
  )
}

.lity_link_derivative <- function(value, link, scale) {
  if (scale == "response") return(rep(1, length(value)))
  switch(link,
    logit = { p <- stats::plogis(value); p * (1 - p) },
    probit = stats::dnorm(value),
    cloglog = exp(value - exp(value)),
    log = exp(value), identity = rep(1, length(value)),
    .lity_stop("Unsupported link: ", link, ".")
  )
}

.lity_interval_widths <- function(time) {
  time <- as.numeric(time)
  if (!length(time)) return(numeric())
  ordering <- order(time)
  sorted <- time[ordering]
  positive <- diff(sorted)
  positive <- positive[is.finite(positive) & positive > 0]
  terminal <- if (length(positive)) stats::median(positive) else 1
  delta <- numeric(length(time))
  delta[ordering] <- c(diff(sorted), terminal)
  pmax(delta, 1e-8)
}

.lity_tte_interval_exposure <- function(time, endpoint) {
  time <- as.numeric(time)
  delta <- .lity_interval_widths(time)
  if (!identical(endpoint$distribution, "weibull")) return(delta)
  if (any(!is.finite(time)) || any(time < 0)) {
    .lity_stop("Weibull time-to-event design times must be finite and non-negative.")
  }
  shape <- .lity_number(
    endpoint$dispersion, "Weibull shape", lower = .Machine$double.eps
  )
  # H(t) = lambda * t^shape, so each counting-process interval contributes
  # Delta H = lambda * ((t + delta)^shape - t^shape). This reduces exactly
  # to the exponential hazard-times-width convention when shape equals one.
  pmax((time + delta)^shape - time^shape, 1e-12)
}

.lity_response_moments <- function(mu, H, G, endpoint, time) {
  if (endpoint$type == "continuous") {
    return(list(mean = mu, H = H, G = G, variance = NULL,
                variance_derivative = NULL))
  }
  if (endpoint$type == "ordinal") {
    thresholds <- endpoint$thresholds
    category_moments <- function(eta) {
      shifted <- thresholds - eta
      cumulative <- if (endpoint$link == "probit") stats::pnorm(shifted) else stats::plogis(shifted)
      density <- if (endpoint$link == "probit") stats::dnorm(shifted) else cumulative * (1 - cumulative)
      probability <- diff(c(0, cumulative, 1))
      probability_derivative <- diff(c(0, -density, 0))
      categories <- seq_along(probability) - 1
      mean <- sum(categories * probability)
      mean_derivative <- sum(categories * probability_derivative)
      variance <- sum(categories^2 * probability) - mean^2
      variance_derivative <- sum(categories^2 * probability_derivative) -
        2 * mean * mean_derivative
      c(mean = mean, variance = variance, mean_derivative = mean_derivative,
        variance_derivative = variance_derivative)
    }
    moments <- t(vapply(mu, category_moments, numeric(4)))
    derivative <- moments[, "mean_derivative"]
    return(list(mean = moments[, "mean"], H = derivative * H, G = derivative * G,
                variance = pmax(moments[, "variance"], 1e-10),
                variance_derivative = moments[, "variance_derivative"]))
  }
  response <- if (endpoint$scale == "response") mu else .lity_link(mu, endpoint$link)
  derivative <- .lity_link_derivative(mu, endpoint$link, endpoint$scale)
  if (endpoint$type == "binary") {
    response <- pmin(1 - 1e-9, pmax(1e-9, response)); variance <- response * (1 - response)
    variance_derivative <- derivative * (1 - 2 * response)
  } else if (endpoint$type == "count") {
    response <- pmax(response, 1e-9)
    variance <- if (endpoint$distribution %in% c("negative_binomial", "negbin")) {
      response + response^2 / (endpoint$dispersion %||% 1)
    } else response
    variance_derivative <- if (endpoint$distribution %in% c("negative_binomial", "negbin")) {
      derivative * (1 + 2 * response / (endpoint$dispersion %||% 1))
    } else derivative
  } else {
    hazard <- pmax(response, 1e-12)
    exposure <- .lity_tte_interval_exposure(time, endpoint)
    response <- hazard * exposure
    derivative <- derivative * exposure
    variance <- response
    variance_derivative <- derivative
  }
  list(mean = response, H = derivative * H, G = derivative * G,
       variance = pmax(variance, 1e-12),
       variance_derivative = variance_derivative)
}

.lity_numerical_matrix_derivative <- function(fn, value, index, relative_step = 1e-5) {
  step <- max(1e-7, abs(value[[index]]) * relative_step)
  plus <- minus <- value
  plus[[index]] <- plus[[index]] + step
  minus[[index]] <- minus[[index]] - step
  (fn(plus) - fn(minus)) / (2 * step)
}

.lity_prediction_parts <- function(model, events, theta, sigma, endpoint) {
  cached <- .lity_prediction_plan(model, events, theta, sigma)
  derivative <- LibeRation::nm_prediction_plan_evaluate(
    cached$plan, events, theta = theta, sigma = sigma
  )
  observed <- which(events$EVID == 0 & events$MDV == 0 & as.integer(events$DVID) == endpoint$dvid)
  if (!length(observed)) return(NULL)
  jacobian <- derivative$jacobian
  theta_columns <- match(paste0("THETA_", seq_along(theta)), colnames(jacobian))
  H <- if (length(theta)) jacobian[observed, theta_columns, drop = FALSE] else matrix(0, length(observed), 0L)
  eta_pattern <- "^ETA_1_[0-9]+$"
  eta_columns <- grep(eta_pattern, colnames(jacobian))
  if (model$n_eta && length(eta_columns) != model$n_eta) {
    eta_columns <- grep("^ETA_[0-9]+$", colnames(jacobian))
  }
  G <- if (model$n_eta) jacobian[observed, eta_columns[seq_len(model$n_eta)], drop = FALSE] else matrix(0, length(observed), 0L)
  list(mu = as.numeric(derivative$value[observed]), H = H, G = G,
       data = events[observed, , drop = FALSE], diagnostics = list(
         propagation_kernel = derivative$propagation_kernel %||% "unknown",
         operation_count = derivative$operation_count %||% NA_integer_,
         prediction_plan_cache_hit = cached$hit,
         prediction_plan = derivative$plan_telemetry
       ))
}

.lity_endpoint_information <- function(model, events, endpoint, theta, omega, sigma,
                                       parameter_spec, tolerance,
                                       approximation = c("full_gaussian", "fo_block")) {
  approximation <- match.arg(approximation)
  prediction <- .lity_prediction_parts(model, events, theta, sigma, endpoint)
  if (is.null(prediction)) return(NULL)
  mu_original <- prediction$mu
  H_original <- prediction$H
  G_original <- prediction$G
  time <- as.numeric(prediction$data$TIME)
  exponential <- endpoint$type == "continuous" && identical(model$LIK_CONFIG$error, "exponential")
  if (exponential) {
    safe <- pmax(mu_original, 1e-12)
    mu <- log(safe); H <- H_original / safe; G <- G_original / safe
  } else {
    mu <- mu_original; H <- H_original; G <- G_original
  }
  moments <- .lity_response_moments(mu, H, G, endpoint, time)
  H <- moments$H; G <- moments$G
  omega_matrix <- .lity_omega_matrix(model, omega)
  if (endpoint$type == "continuous") {
    residual <- if (exponential) {
      temporary <- model; temporary$LIK_CONFIG$error <- "additive"
      .lity_residual_covariance(temporary, mu_original, sigma, prediction$data)
    } else .lity_residual_covariance(model, mu_original, sigma, prediction$data)
  } else residual <- diag(moments$variance, length(moments$variance))
  residual_variance <- diag(residual)
  residual_derivatives <- if (endpoint$type == "continuous") {
    residual_model <- if (exponential) {
      temporary <- model; temporary$LIK_CONFIG$error <- "additive"; temporary
    } else model
    .lity_residual_variance_derivatives(
      residual_model, mu_original, sigma,
      prediction$data$DVID %||% rep(1L, length(mu_original))
    )
  } else NULL
  V <- if (ncol(G)) G %*% omega_matrix %*% t(G) + residual else residual
  k <- nrow(parameter_spec)
  Dmu <- matrix(0, nrow(H), k)
  theta_rows <- which(parameter_spec$type == "theta")
  if (length(theta_rows)) Dmu[, theta_rows] <- H[, parameter_spec$index[theta_rows], drop = FALSE]
  dV <- replicate(k, matrix(0, nrow(V), ncol(V)), simplify = FALSE)
  for (position in theta_rows) {
    theta_index <- parameter_spec$index[[position]]
    direction <- H_original[, theta_index]
    if (endpoint$type == "continuous") {
      variance_direction <- residual_derivatives$mu * direction
      dV[[position]] <- .lity_residual_covariance_direction(
        if (exponential) temporary else model, residual, residual_variance,
        variance_direction, prediction$data
      )
    } else {
      dV[[position]] <- diag(
        moments$variance_derivative * direction,
        length(moments$variance_derivative)
      )
    }
  }
  omega_rows <- which(parameter_spec$type == "omega")
  for (position in omega_rows) {
    derivative_omega <- matrix(0, model$n_eta, model$n_eta)
    row <- parameter_spec$row[[position]]; col <- parameter_spec$col[[position]]
    derivative_omega[row, col] <- 1
    derivative_omega[col, row] <- 1
    dV[[position]] <- G %*% derivative_omega %*% t(G)
  }
  sigma_rows <- which(parameter_spec$type == "sigma")
  if (endpoint$type == "continuous" && length(sigma_rows)) {
    for (position in sigma_rows) {
      sigma_index <- parameter_spec$index[[position]]
      dV[[position]] <- .lity_residual_covariance_direction(
        if (exponential) temporary else model, residual, residual_variance,
        residual_derivatives$sigma[, sigma_index], prediction$data
      )
    }
  }
  # PopED and PFIM use the conventional block-diagonal population-FO FIM:
  # fixed effects contribute through the mean and variance parameters through
  # the observation covariance, with the cross block set to zero. The fuller
  # Gaussian covariance-derivative form remains an explicit advanced option.
  if (identical(approximation, "fo_block") && length(theta_rows)) {
    dV[theta_rows] <- replicate(length(theta_rows), matrix(0, nrow(V), ncol(V)), simplify = FALSE)
  }
  assembled <- lity_fim_cpp(Dmu, V, dV, tolerance)
  list(information = assembled$information, covariance = V,
       prediction = moments$mean, mean_jacobian = Dmu,
       observation_covariance_rank = assembled$observation_covariance_rank,
       diagnostics = prediction$diagnostics)
}

.lity_strata_for_arm <- function(population, arm) {
  strata <- population$strata
  if (arm$population %in% strata$name && !(arm$population == "default" && nrow(strata) > 1L)) {
    strata <- strata[strata$name == arm$population, , drop = FALSE]
    strata$weight <- 1
  }
  strata
}

#' Calculate expected information for a design
#'
#' Continuous outcomes use the multivariate-normal population FIM, including
#' mean/covariance cross-information and exact LibeRation prediction
#' sensitivities. Non-continuous outcomes use distribution-aware working
#' moments, allowing shared random effects and variance-component information.
#' Exponential and fixed-shape Weibull time-to-event endpoints use
#' counting-process interval increments. For Weibull endpoints the model
#' response is the coefficient in `H(t) = lambda * t^shape`.
#'
#' @param design LibeRality design.
#' @param scenario Scenario name, index, or object.
#' @param model Optional model override.
#' @param tolerance Numerical rank tolerance.
#' @param approximation Optional information approximation override.
#'   `"fo_block"` uses the conventional block-diagonal population-FO form used
#'   by PopED and PFIM; `"full_gaussian"` includes covariance derivatives for
#'   fixed effects. When omitted, the convention stored in `design` is used.
#' @return A `lity_information` object.
#' @export
lity_information <- function(design, scenario = 1L, model = NULL, tolerance = 1e-10,
                             approximation = NULL) {
  approximation <- approximation %||% design$information_approximation %||% "fo_block"
  approximation <- match.arg(approximation, c("fo_block", "full_gaussian"))
  validation <- lity_validate(design)
  if (!validation$valid) .lity_stop("Invalid design: ", paste(validation$errors, collapse = "; "))
  if (inherits(scenario, "lity_scenario")) selected <- scenario
  else if (is.character(scenario)) selected <- design$scenarios[[scenario]]
  else selected <- design$scenarios[[as.integer(scenario)]]
  if (is.null(selected)) .lity_stop("Unknown design scenario.")
  model <- model %||% selected$model %||% design$model
  theta <- selected$theta %||% model$THETAS$Value
  omega <- selected$omega %||% model$OMEGAS$Value
  sigma <- selected$sigma %||% model$SIGMAS$Value
  if (length(theta) != nrow(model$THETAS) || length(omega) != nrow(model$OMEGAS) || length(sigma) != nrow(model$SIGMAS)) {
    .lity_stop("Scenario parameter dimensions do not match the selected model.")
  }
  parameters <- .lity_parameter_spec(model)
  total <- matrix(0, nrow(parameters), nrow(parameters), dimnames = list(parameters$name, parameters$name))
  arm_contributions <- list(); kernels <- character(); operation_count <- 0
  prediction_cache_hits <- prediction_cache_misses <- prediction_retapes <- 0L
  for (arm_name in names(design$arms)) {
    arm <- design$arms[[arm_name]]
    arm_blocks <- list()
    arm_weights <- numeric()
    strata <- .lity_strata_for_arm(design$population, arm)
    for (stratum_index in seq_len(nrow(strata))) {
      events <- arm$events
      covariate_names <- setdiff(names(strata), c("name", "weight"))
      for (name in covariate_names) events[[name]] <- strata[[name]][[stratum_index]]
      for (name in names(selected$covariates)) events[[name]] <- selected$covariates[[name]]
      for (endpoint in design$endpoints) {
        contribution <- .lity_endpoint_information(
          model, events, endpoint, theta, omega, sigma, parameters, tolerance,
          approximation = approximation
        )
        if (is.null(contribution)) next
        effective <- arm$size * strata$weight[[stratum_index]] * selected$adherence *
          (1 - selected$dropout) * (1 - selected$missed_sample)
        arm_blocks[[length(arm_blocks) + 1L]] <- contribution$information
        arm_weights[[length(arm_weights) + 1L]] <- effective
        kernels <- c(kernels, contribution$diagnostics$propagation_kernel)
        operation_count <- operation_count + (contribution$diagnostics$operation_count %||% 0)
        prediction_cache_hits <- prediction_cache_hits +
          as.integer(isTRUE(contribution$diagnostics$prediction_plan_cache_hit))
        prediction_cache_misses <- prediction_cache_misses +
          as.integer(!isTRUE(contribution$diagnostics$prediction_plan_cache_hit))
        prediction_retapes <- prediction_retapes + as.integer(
          contribution$diagnostics$prediction_plan$retapes %||% 0L
        )
      }
    }
    arm_total <- if (length(arm_blocks)) {
      lity_weighted_information_cpp(
        arm_blocks, arm_weights,
        matrix(0, nrow(parameters), nrow(parameters)), tolerance
      )$information
    } else matrix(0, nrow(parameters), nrow(parameters))
    dimnames(arm_total) <- dimnames(total)
    arm_contributions[[arm_name]] <- arm_total
  }
  if (!is.null(design$prior_fim)) {
    prior <- design$prior_fim
    if (!is.null(rownames(prior))) {
      aligned <- matrix(0, nrow(total), ncol(total), dimnames = dimnames(total))
      common <- intersect(rownames(prior), rownames(total))
      aligned[common, common] <- prior[common, common, drop = FALSE]
      prior <- aligned
    }
    if (!all(dim(prior) == dim(total))) .lity_stop("Prior FIM dimension does not match estimated parameters.")
  } else {
    prior <- matrix(0, nrow(total), ncol(total))
  }
  metrics <- lity_weighted_information_cpp(
    unname(arm_contributions), rep(1, length(arm_contributions)),
    prior, tolerance
  )
  total <- metrics$information
  dimnames(total) <- list(parameters$name, parameters$name)
  covariance <- metrics$covariance
  dimnames(covariance) <- dimnames(total)
  values <- parameters$value
  se <- sqrt(pmax(diag(covariance), 0))
  rse <- ifelse(abs(values) > 1e-15, 100 * se / abs(values), NA_real_)
  names(se) <- names(rse) <- parameters$name
  structure(list(
    schema = "liberality.information", version = 1L,
    design_id = design$id, scenario = selected$name, model_hash = .lity_hash(model),
    matrix = total, covariance = covariance, parameters = parameters,
    se = se, rse = rse, eigenvalues = metrics$eigenvalues,
    rank = metrics$rank, condition_number = metrics$condition_number,
    log_determinant = metrics$log_determinant,
    trace_covariance = metrics$trace_covariance,
    minimum_eigenvalue = metrics$minimum_eigenvalue,
    arm_contributions = arm_contributions,
    diagnostics = list(
      method = if (identical(approximation, "fo_block")) {
        "block-diagonal population-FO expected information (PopED/PFIM convention)"
      } else "full Gaussian expected information",
      approximation = approximation,
      prediction_derivatives = "exact CppAD",
      covariance_derivatives = "analytic OMEGA, supported residual models, and non-continuous working moments",
      noncontinuous = "distribution-aware working-moment information",
      endpoint_blocks = "block diagonal conditional on shared parameter vector",
      propagation_kernels = sort(unique(kernels)), operation_count = operation_count,
      prediction_plan = list(
        backend = "persistent guarded CppAD dynamic-parameter tape",
        cache_hits = prediction_cache_hits,
        cache_misses = prediction_cache_misses,
        cumulative_retapes = prediction_retapes
      ),
      tolerance = tolerance, warnings = validation$warnings
    ), created_at = .lity_now()
  ), class = "lity_information")
}

#' @export
print.lity_information <- function(x, ...) {
  cat("LibeRality information\n")
  cat("  scenario:", x$scenario, " rank:", x$rank, "/", nrow(x$matrix),
      " condition:", format(x$condition_number, digits = 4), "\n")
  cat("  log determinant:", format(x$log_determinant, digits = 6), "\n")
  invisible(x)
}
