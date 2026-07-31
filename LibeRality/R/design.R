#' Create a NONMEM-style trial schedule
#'
#' @param sampling_times Observation times, or a data frame containing `TIME`
#'   and optional `DVID` and `CMT` columns.
#' @param dose Dose amount(s).
#' @param dose_times Dose administration times.
#' @param dose_cmt,observation_cmt Dose and observation compartments.
#' @param rate Infusion rate. Zero represents a bolus or extravascular dose.
#' @param duration Optional infusion duration; converted to `rate`.
#' @param ii,addl NONMEM repeat-dose interval and additional-dose count.
#' @param ss NONMEM steady-state flag.
#' @param route Descriptive administration route.
#' @param dvid Outcome identifier for vector `sampling_times`.
#' @param covariates Named constant covariates copied to every record.
#' @param id Subject identifier used by the elementary design.
#' @return A NONMEM-style event data frame with design metadata.
#' @export
lity_schedule <- function(sampling_times, dose = 0, dose_times = 0,
                          dose_cmt = 1L, observation_cmt = 1L, rate = 0,
                          duration = NULL, ii = 0, addl = 0L, ss = 0L,
                          route = "extravascular", dvid = 1L,
                          covariates = list(), id = 1L) {
  if (is.data.frame(sampling_times)) {
    observations <- as.data.frame(sampling_times, stringsAsFactors = FALSE)
    if (!"TIME" %in% names(observations)) .lity_stop("Sampling data require a `TIME` column.")
    if (!"DVID" %in% names(observations)) observations$DVID <- as.integer(dvid)[[1L]]
    if (!"CMT" %in% names(observations)) observations$CMT <- as.integer(observation_cmt)[[1L]]
  } else {
    observations <- data.frame(
      TIME = as.numeric(sampling_times), DVID = rep(as.integer(dvid), length.out = length(sampling_times)),
      CMT = rep(as.integer(observation_cmt), length.out = length(sampling_times)),
      stringsAsFactors = FALSE
    )
  }
  if (!nrow(observations) || any(!is.finite(observations$TIME))) {
    .lity_stop("At least one finite sampling time is required.")
  }
  observations$ID <- as.integer(id)
  observations$EVID <- 0L
  observations$AMT <- 0
  observations$RATE <- 0
  observations$II <- 0
  observations$ADDL <- 0L
  observations$SS <- 0L
  observations$DV <- 0
  observations$MDV <- 0L
  observations$.LITY_OBS <- seq_len(nrow(observations))
  observations$.LITY_DOSE <- NA_integer_

  dose_times <- as.numeric(dose_times)
  dose <- rep(as.numeric(dose), length.out = length(dose_times))
  if (any(!is.finite(dose_times)) || any(!is.finite(dose)) || any(dose < 0)) {
    .lity_stop("Dose times and amounts must be finite, and amounts cannot be negative.")
  }
  rate <- rep(as.numeric(rate), length.out = length(dose_times))
  if (!is.null(duration)) {
    duration <- rep(as.numeric(duration), length.out = length(dose_times))
    if (any(!is.finite(duration)) || any(duration <= 0)) .lity_stop("Infusion duration must be positive.")
    rate <- ifelse(dose > 0, dose / duration, 0)
  }
  doses <- data.frame(
    ID = as.integer(id), TIME = dose_times, EVID = 1L, AMT = dose,
    RATE = rate, II = rep(as.numeric(ii), length.out = length(dose_times)),
    ADDL = rep(as.integer(addl), length.out = length(dose_times)),
    SS = rep(as.integer(ss), length.out = length(dose_times)),
    CMT = rep(as.integer(dose_cmt), length.out = length(dose_times)),
    DVID = 1L, DV = NA_real_, MDV = 1L, .LITY_OBS = NA_integer_,
    .LITY_DOSE = seq_along(dose_times), stringsAsFactors = FALSE
  )
  columns <- union(names(doses), names(observations))
  fill <- function(data) {
    for (column in setdiff(columns, names(data))) data[[column]] <- NA
    data[columns]
  }
  events <- rbind(fill(doses), fill(observations))
  for (name in names(covariates)) {
    value <- covariates[[name]]
    if (length(value) != 1L) .lity_stop("Schedule covariate `", name, "` must be scalar.")
    events[[name]] <- value
  }
  events <- events[order(events$TIME, -events$EVID, events$.LITY_OBS, na.last = TRUE), , drop = FALSE]
  rownames(events) <- NULL
  attr(events, "lity_schedule") <- list(route = as.character(route)[[1L]])
  events
}

.lity_endpoint_options <- function(type = NULL) {
  options <- list(
    continuous = list(
      links = "identity",
      distributions = "normal"
    ),
    binary = list(
      links = c("logit", "probit", "cloglog"),
      distributions = "bernoulli"
    ),
    ordinal = list(
      links = c("logit", "probit"),
      distributions = "categorical"
    ),
    count = list(
      links = c("log", "identity"),
      distributions = c("poisson", "negative_binomial")
    ),
    time_to_event = list(
      links = c("log", "identity"),
      distributions = c("exponential", "weibull")
    ),
    recurrent_event = list(
      links = c("log", "identity"),
      distributions = c("poisson", "negative_binomial")
    )
  )
  if (is.null(type)) return(options)
  options[[match.arg(type, names(options))]]
}

#' Define an outcome used by an optimal design
#'
#' @param name Outcome name.
#' @param type Continuous, binary, ordinal, count, time-to-event, or recurrent-event.
#' @param dvid Dataset outcome identifier.
#' @param link Link applied to model predictions for non-continuous outcomes.
#' @param scale Whether model predictions are a linear predictor or already on
#'   the response scale.
#' @param thresholds Ordered cut points for an ordinal outcome.
#' @param distribution Distribution detail, such as `poisson`, `negative_binomial`,
#'   `exponential`, or `weibull`.
#' @param dispersion Optional count dispersion or Weibull shape.
#' @param target Optional clinical target definition.
#' @param metadata Additional serializable metadata.
#' @export
lity_endpoint <- function(name, type = c("continuous", "binary", "ordinal", "count",
                                         "time_to_event", "recurrent_event"),
                          dvid = 1L, link = NULL,
                          scale = c("linear_predictor", "response"), thresholds = NULL,
                          distribution = NULL, dispersion = NULL, target = NULL,
                          metadata = list()) {
  type <- match.arg(type)
  scale <- match.arg(scale)
  default_link <- switch(type, continuous = "identity", binary = "logit",
                         ordinal = "logit", count = "log",
                         time_to_event = "log", recurrent_event = "log")
  default_distribution <- switch(type, continuous = "normal", binary = "bernoulli",
                                 ordinal = "categorical", count = "poisson",
                                 time_to_event = "exponential", recurrent_event = "poisson")
  options <- .lity_endpoint_options(type)
  link <- tolower(as.character(link %||% default_link)[[1L]])
  distribution <- tolower(as.character(
    distribution %||% default_distribution
  )[[1L]])
  if (identical(distribution, "negbin")) {
    distribution <- "negative_binomial"
  }
  if (!link %in% options$links) {
    .lity_stop(
      "Unsupported ", type, " endpoint link `", link,
      "`. Choose one of: ", paste(options$links, collapse = ", "), "."
    )
  }
  if (!distribution %in% options$distributions) {
    .lity_stop(
      "Unsupported ", type, " endpoint distribution `", distribution,
      "`. Choose one of: ",
      paste(options$distributions, collapse = ", "), "."
    )
  }
  if (type == "ordinal") {
    thresholds <- as.numeric(thresholds)
    if (!length(thresholds) || any(!is.finite(thresholds)) || is.unsorted(thresholds, strictly = TRUE)) {
      .lity_stop("Ordinal endpoints require strictly increasing finite `thresholds`.")
    }
  }
  if (!is.null(dispersion)) dispersion <- .lity_number(dispersion, "dispersion", lower = .Machine$double.eps)
  structure(list(
    schema = "liberality.endpoint", version = 1L,
    name = .lity_scalar(name, "name"), type = type, dvid = as.integer(dvid)[[1L]],
    link = link, scale = scale,
    thresholds = thresholds, distribution = distribution,
    dispersion = dispersion, target = target, metadata = metadata
  ), class = "lity_endpoint")
}

#' Convert a LibeRator endpoint into a LibeRality design endpoint
#' @param endpoint A `lator_endpoint`.
#' @param dvid Outcome identifier.
#' @param type Statistical response type used by the design model.
#' @export
lity_endpoint_from_liberator <- function(endpoint, dvid = 1L, type = "continuous") {
  if (!inherits(endpoint, "lator_endpoint")) .lity_stop("`endpoint` must be a LibeRator endpoint.")
  result <- lity_endpoint(endpoint$name, type = type, dvid = dvid, target = list(
    kind = endpoint$kind, metric = endpoint$metric, rules = endpoint$rules,
    unit = endpoint$unit, source = endpoint$source, liberator_id = endpoint$id,
    liberator_version = endpoint$version
  ), metadata = list(source = "LibeRator", status = endpoint$status, drug = endpoint$drug))
  attr(result, "lator_endpoint") <- endpoint
  result
}

#' Define a trial arm or elementary design
#' @param name Arm name.
#' @param events Event records, commonly from [lity_schedule()].
#' @param size Exact number of subjects assigned to the arm.
#' @param allocation Approximate allocation weight.
#' @param population Population/stratum name.
#' @param costs Named fixed, per-subject, per-visit, per-sample, and assay costs.
#' @param sample_volume Blood/sample volume per observation.
#' @param metadata Additional metadata.
#' @export
lity_arm <- function(name, events, size = 1L, allocation = 1,
                     population = "default", costs = list(), sample_volume = 0,
                     metadata = list()) {
  events <- as.data.frame(events, stringsAsFactors = FALSE)
  required <- c("ID", "TIME", "EVID", "AMT", "CMT")
  if (!all(required %in% names(events))) .lity_stop("Arm events require: ", paste(required, collapse = ", "), ".")
  if (!"DV" %in% names(events)) events$DV <- ifelse(events$EVID == 0, 0, NA_real_)
  if (!"MDV" %in% names(events)) events$MDV <- as.integer(events$EVID != 0)
  if (!"DVID" %in% names(events)) events$DVID <- 1L
  if (!"RATE" %in% names(events)) events$RATE <- 0
  if (!"II" %in% names(events)) events$II <- 0
  if (!"ADDL" %in% names(events)) events$ADDL <- 0L
  if (!"SS" %in% names(events)) events$SS <- 0L
  if (!".LITY_OBS" %in% names(events)) {
    events$.LITY_OBS <- NA_integer_
    observed <- which(events$EVID == 0 & events$MDV == 0)
    events$.LITY_OBS[observed] <- seq_along(observed)
  }
  if (!".LITY_DOSE" %in% names(events)) {
    events$.LITY_DOSE <- NA_integer_
    doses <- which(events$EVID != 0)
    events$.LITY_DOSE[doses] <- seq_along(doses)
  }
  size <- as.integer(size)
  if (length(size) != 1L || is.na(size) || size < 0L) .lity_stop("Arm `size` must be a non-negative integer.")
  allocation <- .lity_number(allocation, "allocation", lower = 0)
  sample_volume <- .lity_number(sample_volume, "sample_volume", lower = 0)
  defaults <- list(fixed = 0, per_subject = 0, per_visit = 0, per_sample = 0, assay = 0)
  costs <- utils::modifyList(defaults, costs)
  if (any(!is.finite(unlist(costs))) || any(unlist(costs) < 0)) .lity_stop("Arm costs must be non-negative and finite.")
  structure(list(
    schema = "liberality.arm", version = 1L, name = .lity_scalar(name, "name"),
    events = events, size = size, allocation = allocation,
    population = .lity_scalar(population, "population"), costs = costs,
    sample_volume = sample_volume, metadata = metadata
  ), class = "lity_arm")
}

#' @export
print.lity_arm <- function(x, ...) {
  observations <- sum(x$events$EVID == 0 & x$events$MDV == 0)
  cat("LibeRality arm:", x$name, "\n")
  cat("  subjects:", x$size, " observations/subject:", observations,
      " population:", x$population, "\n")
  invisible(x)
}

#' Define populations and covariate strata
#' @param strata Data frame with a stratum `name`, `weight`, and optional model covariates.
#' @param name Population set name.
#' @param metadata Additional metadata.
#' @export
lity_population <- function(strata = data.frame(name = "default", weight = 1),
                            name = "Population", metadata = list()) {
  strata <- as.data.frame(strata, stringsAsFactors = FALSE)
  if (!nrow(strata)) .lity_stop("At least one population stratum is required.")
  if (!"name" %in% names(strata)) strata$name <- paste0("stratum-", seq_len(nrow(strata)))
  if (!"weight" %in% names(strata)) strata$weight <- 1
  if (any(!nzchar(as.character(strata$name))) || anyDuplicated(strata$name)) .lity_stop("Stratum names must be unique and non-empty.")
  strata$weight <- .lity_normalize_weights(strata$weight, "strata$weight")
  structure(list(schema = "liberality.population", version = 1L,
                 name = .lity_scalar(name, "name"), strata = strata,
                 metadata = metadata), class = "lity_population")
}

#' @export
print.lity_population <- function(x, ...) {
  cat("LibeRality population:", x$name, "\n")
  cat("  strata:", nrow(x$strata), "\n")
  invisible(x)
}

#' Define a parameter, model, or operational scenario
#' @param name Scenario name.
#' @param theta,omega,sigma Optional model parameter values.
#' @param model Optional alternative LibeRation model.
#' @param probability Scenario probability.
#' @param covariates Named covariate overrides.
#' @param dropout,adherence,missed_sample Operational probabilities.
#' @param metadata Additional metadata.
#' @export
lity_scenario <- function(name, theta = NULL, omega = NULL, sigma = NULL,
                          model = NULL, probability = 1, covariates = list(),
                          dropout = 0, adherence = 1, missed_sample = 0,
                          metadata = list()) {
  if (!is.null(model) && !inherits(model, "nm_model")) .lity_stop("Scenario `model` must be a LibeRation nm_model.")
  structure(list(
    schema = "liberality.scenario", version = 1L,
    name = .lity_scalar(name, "name"), theta = if (is.null(theta)) NULL else as.numeric(theta),
    omega = if (is.null(omega)) NULL else as.numeric(omega),
    sigma = if (is.null(sigma)) NULL else as.numeric(sigma), model = model,
    probability = .lity_probability(probability), covariates = covariates,
    dropout = .lity_probability(dropout, "dropout"),
    adherence = .lity_probability(adherence, "adherence"),
    missed_sample = .lity_probability(missed_sample, "missed_sample"), metadata = metadata
  ), class = "lity_scenario")
}

#' Define a complete optimal-design problem
#' @param model Primary LibeRation `nm_model`.
#' @param arms Named list of [lity_arm()] objects.
#' @param endpoints Named list of [lity_endpoint()] objects.
#' @param population Population strata.
#' @param scenarios Parameter/model/operational scenarios.
#' @param alternative_models Competing LibeRation models for discrimination.
#' @param variables Optimisable variables.
#' @param constraints Design constraints.
#' @param prior_fim Optional prior Fisher information matrix.
#' @param name,description Human-readable identity.
#' @param metadata Additional serializable metadata.
#' @export
lity_design <- function(model, arms, endpoints = NULL,
                        population = lity_population(), scenarios = NULL,
                        alternative_models = NULL, variables = list(),
                        constraints = list(), prior_fim = NULL,
                        name = "Optimal design", description = "", metadata = list()) {
  if (!inherits(model, "nm_model")) .lity_stop("`model` must be a LibeRation nm_model.")
  arms <- .lity_named_list(arms, "arms", "lity_arm")
  if (!length(arms)) .lity_stop("At least one design arm is required.")
  if (is.null(endpoints)) {
    dvids <- sort(unique(unlist(lapply(arms, function(arm) arm$events$DVID[arm$events$EVID == 0]))))
    endpoints <- lapply(dvids, function(id) lity_endpoint(paste("Continuous outcome", id), dvid = id))
    names(endpoints) <- paste0("DVID", dvids)
  }
  endpoints <- .lity_named_list(endpoints, "endpoints", "lity_endpoint")
  if (!inherits(population, "lity_population")) .lity_stop("`population` must be created by lity_population().")
  scenarios <- .lity_named_list(scenarios %||% list(lity_scenario("Nominal")), "scenarios", "lity_scenario")
  probabilities <- .lity_normalize_weights(vapply(scenarios, `[[`, numeric(1), "probability"), "scenario probabilities")
  for (i in seq_along(scenarios)) scenarios[[i]]$probability <- probabilities[[i]]
  alternative_models <- .lity_named_list(alternative_models, "alternative_models", "nm_model")
  variables <- .lity_named_list(variables, "variables", "lity_variable")
  constraints <- .lity_named_list(constraints, "constraints", "lity_constraint")
  if (!is.null(prior_fim)) {
    prior_fim <- as.matrix(prior_fim)
    if (nrow(prior_fim) != ncol(prior_fim) || any(!is.finite(prior_fim))) .lity_stop("`prior_fim` must be a finite square matrix.")
  }
  structure(list(
    schema = "liberality.design", version = 1L, id = .lity_id("design"),
    name = .lity_scalar(name, "name"), description = .lity_scalar(description, "description", TRUE),
    model = model, arms = arms, endpoints = endpoints, population = population,
    scenarios = scenarios, alternative_models = alternative_models,
    variables = variables, constraints = constraints, prior_fim = prior_fim,
    metadata = metadata, created_at = .lity_now()
  ), class = "lity_design")
}

#' @export
print.lity_design <- function(x, ...) {
  cat("LibeRality design:", x$name, "\n")
  cat("  arms:", length(x$arms), " subjects:", sum(vapply(x$arms, `[[`, numeric(1), "size")),
      " endpoints:", length(x$endpoints), " scenarios:", length(x$scenarios), "\n")
  cat("  variables:", length(x$variables), " constraints:", length(x$constraints), "\n")
  invisible(x)
}

#' Validate a LibeRality design
#' @param design Design object.
#' @param strict Whether warnings should be returned as validation failures.
#' @return Validation report.
#' @export
lity_validate <- function(design, strict = FALSE) {
  errors <- warnings <- character()
  if (!inherits(design, "lity_design") || !identical(design$schema, "liberality.design")) {
    errors <- c(errors, "Object is not a LibeRality design.")
  } else {
    observed_dvid <- unique(unlist(lapply(design$arms, function(arm) arm$events$DVID[arm$events$EVID == 0 & arm$events$MDV == 0])))
    endpoint_dvid <- vapply(design$endpoints, `[[`, integer(1), "dvid")
    missing <- setdiff(observed_dvid, endpoint_dvid)
    if (length(missing)) errors <- c(errors, paste("No endpoint definition for DVID", paste(missing, collapse = ", ")))
    unused <- setdiff(endpoint_dvid, observed_dvid)
    if (length(unused)) warnings <- c(warnings, paste("Endpoint DVID has no observations:", paste(unused, collapse = ", ")))
    if (!length(design$model$SIGMAS$Value) && any(vapply(design$endpoints, `[[`, character(1), "type") == "continuous")) {
      warnings <- c(warnings, "Continuous endpoint has no residual SIGMA; a small numerical variance floor will be used.")
    }
    if (!sum(vapply(design$arms, `[[`, numeric(1), "size"))) errors <- c(errors, "The design has no subjects.")
    # Information-dependent constraints are evaluated by lity_evaluate().  Do
    # not recurse through lity_information() while checking the design's
    # structural validity.
    structural <- design
    structural$constraints <- Filter(function(x) {
      !x$type %in% c("max_rse", "minimum_power", "exposure")
    }, design$constraints)
    constraint_report <- tryCatch(lity_constraint_check(structural), error = identity)
    if (inherits(constraint_report, "error")) errors <- c(errors, conditionMessage(constraint_report))
  }
  list(valid = !length(errors) && (!strict || !length(warnings)), errors = errors,
       warnings = warnings, hash = if (inherits(design, "lity_design")) .lity_hash(design) else NA_character_)
}
