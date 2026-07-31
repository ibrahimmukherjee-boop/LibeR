.lity_expand_arm <- function(arm) {
  pieces <- lapply(seq_len(arm$size), function(id) {
    data <- arm$events; data$ID <- id; data
  })
  if (!length(pieces)) return(arm$events[0, , drop = FALSE])
  do.call(rbind, pieces)
}

.lity_simulate_noncontinuous <- function(data, endpoints) {
  for (endpoint in endpoints) {
    rows <- data$EVID == 0 & data$MDV == 0 & data$DVID == endpoint$dvid
    if (!any(rows) || endpoint$type == "continuous") next
    mu <- data$IPRED[rows]
    response <- if (endpoint$scale == "response") mu else .lity_link(mu, endpoint$link)
    if (endpoint$type == "binary") data$DV[rows] <- stats::rbinom(sum(rows), 1L, pmin(1, pmax(0, response)))
    else if (endpoint$type == "count" || endpoint$type == "recurrent_event") {
      response <- pmax(response, 1e-10)
      data$DV[rows] <- if (endpoint$distribution %in% c("negative_binomial", "negbin")) {
        stats::rnbinom(sum(rows), mu = response, size = endpoint$dispersion %||% 1)
      } else stats::rpois(sum(rows), response)
    } else if (endpoint$type == "ordinal") {
      thresholds <- endpoint$thresholds
      data$DV[rows] <- vapply(mu, function(eta) {
        cumulative <- if (endpoint$link == "probit") stats::pnorm(thresholds - eta) else stats::plogis(thresholds - eta)
        sample.int(length(thresholds) + 1L, 1L, prob = diff(c(0, cumulative, 1))) - 1L
      }, integer(1))
    } else {
      hazard <- pmax(response, 1e-12)
      data$DV[rows] <- stats::rpois(sum(rows), hazard)
    }
  }
  data
}

.lity_apply_operational_scenario <- function(data, scenario) {
  dose <- data$EVID != 0
  if (scenario$adherence < 1 && any(dose)) {
    omit <- dose & stats::runif(nrow(data)) > scenario$adherence
    data$AMT[omit] <- 0; data$RATE[omit] <- 0
  }
  observation <- data$EVID == 0 & data$MDV == 0
  if (scenario$missed_sample > 0 && any(observation)) {
    missed <- observation & stats::runif(nrow(data)) < scenario$missed_sample
    data$MDV[missed] <- 1L; data$DV[missed] <- NA_real_
  }
  if (scenario$dropout > 0) {
    for (id in unique(data$ID)) {
      if (stats::runif(1) < scenario$dropout) {
        times <- sort(unique(data$TIME[data$ID == id & observation]))
        if (length(times)) {
          dropout_time <- sample(times, 1L)
          dropped <- data$ID == id & data$TIME > dropout_time & data$EVID == 0
          data$MDV[dropped] <- 1L; data$DV[dropped] <- NA_real_
        }
      }
    }
  }
  data
}

.lity_simulation_endpoint_rows <- function(dataset, endpoints, trial, scenario) {
  observed <- dataset$EVID == 0 & dataset$MDV == 0 &
    is.finite(dataset$TIME) & is.finite(dataset$DV)
  if (!any(observed)) return(data.frame())
  data <- dataset[observed, , drop = FALSE]
  endpoint_names <- stats::setNames(
    vapply(endpoints, `[[`, character(1), "name"),
    as.character(vapply(endpoints, `[[`, numeric(1), "dvid"))
  )
  data.frame(
    trial = trial, scenario = scenario, arm = as.character(data$ARM),
    endpoint = unname(endpoint_names[as.character(data$DVID)]),
    dvid = as.numeric(data$DVID), id = as.character(data$ID),
    time = as.numeric(data$TIME), value = as.numeric(data$DV),
    prediction = as.numeric(data$IPRED), stringsAsFactors = FALSE
  )
}

.lity_simulation_bind <- function(items) {
  items <- Filter(function(x) is.data.frame(x) && nrow(x), items)
  if (!length(items)) data.frame() else do.call(rbind, items)
}

.lity_simulation_endpoint_summary <- function(rows) {
  if (!nrow(rows)) return(data.frame())
  groups <- split(rows, interaction(rows[c("arm", "endpoint", "dvid", "time")],
                                    drop = TRUE, lex.order = TRUE))
  do.call(rbind, lapply(groups, function(data) {
    values <- data$value[is.finite(data$value)]
    predictions <- data$prediction[is.finite(data$prediction)]
    quantiles <- if (length(values)) stats::quantile(
      values, c(0.05, 0.5, 0.95), names = FALSE, type = 8
    ) else rep(NA_real_, 3L)
    data.frame(
      arm = data$arm[[1L]], endpoint = data$endpoint[[1L]],
      dvid = data$dvid[[1L]], time = data$time[[1L]], n = length(values),
      mean = if (length(values)) mean(values) else NA_real_,
      sd = if (length(values) > 1L) stats::sd(values) else NA_real_,
      lower = quantiles[[1L]], median = quantiles[[2L]], upper = quantiles[[3L]],
      prediction = if (length(predictions)) mean(predictions) else NA_real_,
      stringsAsFactors = FALSE
    )
  }))
}

.lity_simulation_nca <- function(rows, design, trial, scenario) {
  if (!nrow(rows)) return(list(results = data.frame(), applicability = data.frame()))
  results <- list(); applicability <- list(); cursor <- 0L
  for (endpoint in design$endpoints) {
    endpoint_rows <- rows[rows$dvid == endpoint$dvid, , drop = FALSE]
    for (arm_name in names(design$arms)) {
      cursor <- cursor + 1L
      data <- endpoint_rows[endpoint_rows$arm == arm_name, , drop = FALSE]
      key <- paste(arm_name, endpoint$name, sep = " | ")
      if (!identical(endpoint$type, "continuous")) {
        applicability[[cursor]] <- data.frame(
          arm = arm_name, endpoint = endpoint$name, applicable = FALSE,
          reason = "NCA is defined for continuous concentration-like endpoints.",
          stringsAsFactors = FALSE
        )
        next
      }
      counts <- if (nrow(data)) tapply(data$time, data$id, function(x) length(unique(x))) else numeric()
      eligible <- names(counts)[counts >= 2L]
      data <- data[data$id %in% eligible, , drop = FALSE]
      if (!nrow(data)) {
        applicability[[cursor]] <- data.frame(
          arm = arm_name, endpoint = endpoint$name, applicable = FALSE,
          reason = "At least two distinct concentration times per subject are required.",
          stringsAsFactors = FALSE
        )
        next
      }
      arm <- design$arms[[arm_name]]
      doses <- arm$events[arm$events$EVID != 0 & arm$events$AMT > 0, , drop = FALSE]
      dose <- if (nrow(doses)) doses$AMT[[1L]] else NULL
      tau <- if (nrow(doses) && is.finite(doses$II[[1L]]) && doses$II[[1L]] > 0) doses$II[[1L]] else NULL
      route <- tolower(arm$metadata$route %||% "extravascular")
      if (!route %in% c("extravascular", "oral", "bolus", "infusion")) route <- "extravascular"
      nca <- tryCatch(
        LibeRation::nm_nca(
          data.frame(ID = data$id, TIME = data$time, DV = data$value),
          time = "TIME", concentration = "DV", id = "ID", dose = dose,
          tau = tau, route = route, method = "lin_up_log_down",
          engine = "native", duplicate = "mean", blq = "zero"
        ),
        error = identity
      )
      if (inherits(nca, "error")) {
        applicability[[cursor]] <- data.frame(
          arm = arm_name, endpoint = endpoint$name, applicable = FALSE,
          reason = conditionMessage(nca), stringsAsFactors = FALSE
        )
        next
      }
      table <- nca$results
      table$trial <- trial; table$scenario <- scenario
      table$arm <- arm_name; table$endpoint <- endpoint$name
      results[[key]] <- table
      applicability[[cursor]] <- data.frame(
        arm = arm_name, endpoint = endpoint$name, applicable = TRUE,
        reason = paste(nrow(table), "profile(s) evaluated with native NCA."),
        stringsAsFactors = FALSE
      )
    }
  }
  list(
    results = if (length(results)) do.call(rbind, results) else data.frame(),
    applicability = if (length(applicability)) do.call(rbind, applicability) else data.frame()
  )
}

.lity_simulation_nca_summary <- function(results) {
  if (!nrow(results)) return(data.frame())
  metrics <- intersect(
    c("AUCLAST", "AUCINF_OBS", "AUC_TAU", "CAVG", "CMAX", "TMAX",
      "CLAST", "HALF_LIFE", "CL", "CL_F", "VZ", "VZ_F"),
    names(results)
  )
  long <- do.call(rbind, lapply(metrics, function(metric) data.frame(
    arm = results$arm, endpoint = results$endpoint, metric = metric,
    value = suppressWarnings(as.numeric(results[[metric]])),
    stringsAsFactors = FALSE
  )))
  long <- long[is.finite(long$value), , drop = FALSE]
  if (!nrow(long)) return(data.frame())
  groups <- split(long, interaction(long[c("arm", "endpoint", "metric")],
                                    drop = TRUE, lex.order = TRUE))
  do.call(rbind, lapply(groups, function(data) {
    q <- stats::quantile(data$value, c(0.05, 0.5, 0.95), names = FALSE, type = 8)
    data.frame(
      arm = data$arm[[1L]], endpoint = data$endpoint[[1L]],
      metric = data$metric[[1L]], n = nrow(data), mean = mean(data$value),
      sd = if (nrow(data) > 1L) stats::sd(data$value) else NA_real_,
      lower = q[[1L]], median = q[[2L]], upper = q[[3L]],
      stringsAsFactors = FALSE
    )
  }))
}

#' Simulate complete trials under a LibeRality design
#'
#' @param design Design object.
#' @param n Number of replicated trials.
#' @param scenarios Scenario sampling probabilities; defaults to the design.
#' @param fit Whether to re-estimate each simulated trial with LibeRation.
#' @param method Estimation method when `fit = TRUE`.
#' @param seed Reproducible seed.
#' @param n_cores Simulation cores passed to LibeRation.
#' @param retain_data Retain simulated datasets.
#' @param progress Optional callback.
#' @return A `lity_simulation` result.
#' @export
lity_simulate_trials <- function(design, n = 100L, scenarios = design$scenarios,
                                 fit = FALSE, method = "FOCEI", seed = 7301L,
                                 n_cores = 1L, retain_data = TRUE, progress = NULL) {
  started <- proc.time()[[3L]]; n <- as.integer(n); .lity_seed(seed)
  if (length(n) != 1L || is.na(n) || n < 1L) .lity_stop("`n` must be positive.")
  scenarios <- .lity_named_list(scenarios, "scenarios", "lity_scenario")
  probability <- .lity_normalize_weights(vapply(scenarios, `[[`, numeric(1), "probability"))
  chosen <- sample(seq_along(scenarios), n, replace = TRUE, prob = probability)
  data_sets <- if (retain_data) vector("list", n) else NULL
  fits <- if (fit) vector("list", n) else NULL
  summaries <- vector("list", n)
  endpoint_rows <- vector("list", n)
  nca_results <- vector("list", n)
  nca_applicability <- vector("list", n)
  for (trial in seq_len(n)) {
    scenario <- scenarios[[chosen[[trial]]]]; model <- scenario$model %||% design$model
    arm_data <- lapply(names(design$arms), function(arm_name) {
      arm <- design$arms[[arm_name]]; events <- .lity_expand_arm(arm)
      for (name in names(scenario$covariates)) events[[name]] <- scenario$covariates[[name]]
      events <- .lity_apply_operational_scenario(events, scenario)
      simulated <- LibeRation::nm_simulate(
        model, events, theta = scenario$theta %||% model$THETAS$Value,
        omega = scenario$omega %||% model$OMEGAS$Value,
        sigma = scenario$sigma %||% model$SIGMAS$Value,
        random_effects = model$n_eta > 0L, residual = nrow(model$SIGMAS) > 0L,
        seed = seed + trial * 1009L + match(arm_name, names(design$arms)), n_cores = n_cores
      )
      simulated <- .lity_simulate_noncontinuous(simulated, design$endpoints)
      simulated$ARM <- arm_name
      simulated
    })
    offsets <- cumsum(c(0L, utils::head(vapply(arm_data, function(data) length(unique(data$ID)), integer(1)), -1L)))
    for (i in seq_along(arm_data)) arm_data[[i]]$ID <- arm_data[[i]]$ID + offsets[[i]]
    dataset <- do.call(rbind, arm_data); dataset$TRIAL <- trial; rownames(dataset) <- NULL
    endpoint_rows[[trial]] <- .lity_simulation_endpoint_rows(
      dataset, design$endpoints, trial, scenario$name
    )
    nca <- .lity_simulation_nca(
      endpoint_rows[[trial]], design, trial, scenario$name
    )
    nca_results[[trial]] <- nca$results
    nca_applicability[[trial]] <- nca$applicability
    if (retain_data) data_sets[[trial]] <- dataset
    fit_result <- if (fit) tryCatch(LibeRation::nm_est(model, dataset, method = method), error = identity) else NULL
    if (fit) fits[[trial]] <- fit_result
    summaries[[trial]] <- data.frame(
      trial = trial, scenario = scenario$name, observations = sum(dataset$EVID == 0 & dataset$MDV == 0),
      converged = if (!fit) NA else !inherits(fit_result, "error") && identical(fit_result$convergence, 0L),
      error = if (inherits(fit_result, "error")) conditionMessage(fit_result) else "",
      stringsAsFactors = FALSE
    )
    if (is.function(progress)) progress(as.list(summaries[[trial]][1L, ]))
  }
  combined_endpoint_rows <- .lity_simulation_bind(endpoint_rows)
  combined_nca <- .lity_simulation_bind(nca_results)
  combined_applicability <- unique(.lity_simulation_bind(nca_applicability))
  result <- structure(list(
    schema = "liberality.simulation", version = 1L, id = .lity_id("simulation"),
    design_id = design$id, design = design, n = n,
    method = if (fit) method else "simulation only",
    scenario_draws = chosen, summary = do.call(rbind, summaries), data = data_sets,
    fits = fits, truth = lapply(scenarios, function(x) x$theta %||% design$model$THETAS$Value),
    endpoint_summary = .lity_simulation_endpoint_summary(combined_endpoint_rows),
    nca = list(
      backend = "LibeRation native C++ NCA",
      summary = .lity_simulation_nca_summary(combined_nca),
      applicability = combined_applicability,
      results = combined_nca
    ),
    seed = as.integer(seed), elapsed_seconds = proc.time()[[3L]] - started,
    created_at = .lity_now()
  ), class = "lity_simulation")
  result$operating_characteristics <- lity_operating_characteristics(result)
  result
}

#' Summarise empirical operating characteristics
#' @param simulation A result from [lity_simulate_trials()].
#' @param alpha Confidence interval alpha.
#' @export
lity_operating_characteristics <- function(simulation, alpha = 0.05) {
  if (!inherits(simulation, "lity_simulation")) .lity_stop("`simulation` must be a LibeRality trial simulation.")
  convergence <- if (is.null(simulation$fits)) NA_real_ else mean(simulation$summary$converged, na.rm = TRUE)
  if (is.null(simulation$fits)) return(list(convergence = convergence, estimates = data.frame(), coverage = data.frame()))
  successful <- which(vapply(simulation$fits, inherits, logical(1), "nm_fit"))
  if (!length(successful)) return(list(convergence = convergence, estimates = data.frame(), coverage = data.frame()))
  estimates <- do.call(rbind, lapply(successful, function(i) {
    fit <- simulation$fits[[i]]
    value <- fit$theta %||% fit$par[seq_len(length(simulation$truth[[simulation$scenario_draws[[i]]]]))]
    data.frame(trial = i, parameter = paste0("THETA", seq_along(value)), estimate = value,
               truth = simulation$truth[[simulation$scenario_draws[[i]]]], stringsAsFactors = FALSE)
  }))
  split_estimate <- split(estimates, estimates$parameter)
  summary <- do.call(rbind, lapply(split_estimate, function(data) data.frame(
    parameter = data$parameter[[1L]], mean = mean(data$estimate), bias = mean(data$estimate - data$truth),
    relative_bias = mean((data$estimate - data$truth) / data$truth),
    rmse = sqrt(mean((data$estimate - data$truth)^2)), n = nrow(data), stringsAsFactors = FALSE
  )))
  list(convergence = convergence, estimates = summary, raw_estimates = estimates,
       alpha = alpha, theoretical_information = "Use lity_information() for expected precision comparison.")
}

#' @export
print.lity_simulation <- function(x, ...) {
  cat("LibeRality trial simulation\n")
  cat("  trials:", x$n, " method:", x$method, " elapsed:", format(x$elapsed_seconds, digits = 5), "seconds\n")
  if (!is.na(x$operating_characteristics$convergence)) cat("  convergence:", x$operating_characteristics$convergence, "\n")
  invisible(x)
}
