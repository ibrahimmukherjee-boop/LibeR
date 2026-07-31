.lity_gui_numbers <- function(value, name, allow_empty = FALSE, integer = FALSE) {
  text <- trimws(as.character(value %||% "")[[1L]])
  if (!nzchar(text)) {
    if (allow_empty) return(numeric())
    .lity_stop("`", name, "` cannot be empty.")
  }
  values <- suppressWarnings(as.numeric(strsplit(gsub("[[:space:]]", "", text), ",", fixed = TRUE)[[1L]]))
  if (!length(values) || any(!is.finite(values))) {
    .lity_stop("`", name, "` must contain comma-separated finite numbers.")
  }
  if (integer) values <- as.integer(round(values))
  values
}

.lity_gui_optional_number <- function(value, name) {
  text <- trimws(as.character(value %||% "")[[1L]])
  if (!nzchar(text)) return(NULL)
  .lity_number(suppressWarnings(as.numeric(text)), name)
}

.lity_gui_key <- function(items, prefix, label) {
  base <- tolower(gsub("[^a-zA-Z0-9]+", "-", trimws(label)))
  base <- gsub("(^-+|-+$)", "", base)
  if (!nzchar(base)) base <- prefix
  key <- paste0(prefix, "-", base)
  if (!key %in% names(items)) return(key)
  index <- 2L
  while (paste0(key, "-", index) %in% names(items)) index <- index + 1L
  paste0(key, "-", index)
}

.lity_gui_relevel_scenarios <- function(scenarios) {
  if (!length(scenarios)) return(scenarios)
  probability <- vapply(scenarios, `[[`, numeric(1), "probability")
  if (!all(is.finite(probability)) || sum(probability) <= 0) probability[] <- 1
  probability <- probability / sum(probability)
  for (index in seq_along(scenarios)) scenarios[[index]]$probability <- probability[[index]]
  scenarios
}

.lity_gui_upsert_arm <- function(design, event) {
  id <- as.character(event$id %||% "")[[1L]]
  existing <- if (nzchar(id)) design$arms[[id]] else NULL
  name <- trimws(as.character(event$name %||% existing$name %||% "New arm")[[1L]])
  sampling_times <- .lity_gui_numbers(event$samplingTimes, "Sampling times")
  dose_times <- .lity_gui_numbers(event$doseTimes %||% "0", "Dose times")
  dose_amounts <- .lity_gui_numbers(event$doseAmounts %||% "0", "Dose amounts")
  rates <- .lity_gui_numbers(event$rates %||% "0", "Rates")
  if (length(dose_amounts) != 1L && length(dose_amounts) != length(dose_times)) {
    .lity_stop("Dose amounts must have length one or match the number of dose times.")
  }
  if (length(rates) != 1L && length(rates) != length(dose_times)) {
    .lity_stop("Rates must have length one or match the number of dose times.")
  }
  events <- lity_schedule(
    sampling_times = sampling_times,
    dose = dose_amounts,
    dose_times = dose_times,
    dose_cmt = as.integer(event$doseCmt %||% 1L),
    observation_cmt = as.integer(event$observationCmt %||% 1L),
    rate = rates,
    ii = as.numeric(event$ii %||% 0),
    addl = as.integer(event$addl %||% 0L),
    ss = as.integer(event$ss %||% 0L),
    route = as.character(event$route %||% "extravascular")[[1L]],
    dvid = as.integer(event$dvid %||% 1L)
  )
  costs <- list(
    fixed = as.numeric(event$costFixed %||% 0),
    per_subject = as.numeric(event$costSubject %||% 0),
    per_visit = as.numeric(event$costVisit %||% 0),
    per_sample = as.numeric(event$costSample %||% 0),
    assay = as.numeric(event$costAssay %||% 0)
  )
  arm <- lity_arm(
    name, events,
    size = as.integer(event$size %||% 0L),
    allocation = as.numeric(event$allocation %||% 1),
    population = as.character(event$population %||% "default")[[1L]],
    costs = costs,
    sample_volume = as.numeric(event$sampleVolume %||% 0),
    metadata = utils::modifyList(
      existing$metadata %||% list(),
      list(route = as.character(event$route %||% "extravascular")[[1L]])
    )
  )
  if (!nzchar(id)) id <- .lity_gui_key(design$arms, "arm", name)
  old_name <- existing$name %||% NULL
  design$arms[[id]] <- arm
  if (!is.null(old_name) && !identical(old_name, name)) {
    for (key in names(design$variables)) {
      if (design$variables[[key]]$arm %in% c(id, old_name)) design$variables[[key]]$arm <- id
    }
    for (key in names(design$constraints)) {
      if (!is.null(design$constraints[[key]]$arm) &&
          design$constraints[[key]]$arm %in% c(id, old_name)) {
        design$constraints[[key]]$arm <- id
      }
    }
  }
  design
}

.lity_gui_remove_arm <- function(design, id) {
  if (!id %in% names(design$arms)) .lity_stop("Unknown design arm.")
  if (length(design$arms) <= 1L) .lity_stop("A design must retain at least one arm.")
  name <- design$arms[[id]]$name
  design$arms[[id]] <- NULL
  design$variables <- Filter(function(item) !item$arm %in% c(id, name), design$variables)
  design$constraints <- Filter(function(item) {
    is.null(item$arm) || !item$arm %in% c(id, name)
  }, design$constraints)
  design
}

.lity_gui_upsert_endpoint <- function(design, event) {
  id <- as.character(event$id %||% "")[[1L]]
  existing <- if (nzchar(id)) design$endpoints[[id]] else NULL
  name <- trimws(as.character(event$name %||% existing$name %||% "Endpoint")[[1L]])
  thresholds <- .lity_gui_numbers(
    event$thresholds %||% "", "Thresholds", allow_empty = TRUE
  )
  dispersion <- .lity_gui_optional_number(event$dispersion %||% "", "dispersion")
  optional_text <- function(value) {
    value <- trimws(as.character(value %||% "")[[1L]])
    if (nzchar(value)) value else NULL
  }
  endpoint <- lity_endpoint(
    name = name,
    type = as.character(event$type %||% "continuous")[[1L]],
    dvid = as.integer(event$dvid %||% 1L),
    link = optional_text(event$link),
    scale = as.character(event$scale %||% "linear_predictor")[[1L]],
    thresholds = if (length(thresholds)) thresholds else NULL,
    distribution = optional_text(event$distribution),
    dispersion = dispersion,
    target = existing$target %||% NULL,
    metadata = existing$metadata %||% list()
  )
  if (!nzchar(id)) id <- .lity_gui_key(design$endpoints, "endpoint", name)
  design$endpoints[[id]] <- endpoint
  design
}

.lity_gui_remove_endpoint <- function(design, id) {
  if (!id %in% names(design$endpoints)) .lity_stop("Unknown endpoint.")
  if (length(design$endpoints) <= 1L) .lity_stop("A design must retain at least one endpoint.")
  design$endpoints[[id]] <- NULL
  design$constraints <- Filter(function(item) {
    is.null(item$endpoint) || !identical(item$endpoint, id)
  }, design$constraints)
  design
}

.lity_gui_upsert_scenario <- function(design, event) {
  id <- as.character(event$id %||% "")[[1L]]
  existing <- if (nzchar(id)) design$scenarios[[id]] else NULL
  name <- trimws(as.character(event$name %||% existing$name %||% "Scenario")[[1L]])
  values <- function(field) {
    parsed <- .lity_gui_numbers(event[[field]] %||% "", field, allow_empty = TRUE)
    if (length(parsed)) parsed else NULL
  }
  scenario <- lity_scenario(
    name = name,
    theta = values("theta"),
    omega = values("omega"),
    sigma = values("sigma"),
    model = existing$model %||% NULL,
    probability = as.numeric(event$probability %||% 1),
    covariates = existing$covariates %||% list(),
    dropout = as.numeric(event$dropout %||% 0),
    adherence = as.numeric(event$adherence %||% 1),
    missed_sample = as.numeric(event$missedSample %||% 0),
    metadata = existing$metadata %||% list()
  )
  if (!nzchar(id)) id <- .lity_gui_key(design$scenarios, "scenario", name)
  design$scenarios[[id]] <- scenario
  design$scenarios <- .lity_gui_relevel_scenarios(design$scenarios)
  design
}

.lity_gui_remove_scenario <- function(design, id) {
  if (!id %in% names(design$scenarios)) .lity_stop("Unknown scenario.")
  if (length(design$scenarios) <= 1L) .lity_stop("A design must retain at least one scenario.")
  design$scenarios[[id]] <- NULL
  design$scenarios <- .lity_gui_relevel_scenarios(design$scenarios)
  design
}

.lity_gui_upsert_variable <- function(design, event) {
  id <- as.character(event$id %||% "")[[1L]]
  name <- trimws(as.character(event$name %||% "Design variable")[[1L]])
  type <- as.character(event$type %||% "continuous")[[1L]]
  value_text <- trimws(as.character(event$values %||% "")[[1L]])
  values <- if (identical(type, "categorical") && nzchar(value_text)) {
    result <- trimws(strsplit(value_text, ",", fixed = TRUE)[[1L]])
    result[nzchar(result)]
  } else {
    .lity_gui_numbers(value_text, "Candidate values", allow_empty = TRUE)
  }
  variable <- lity_variable(
    name = name,
    target = as.character(event$target %||% "sampling_time")[[1L]],
    arm = as.character(event$arm %||% "")[[1L]],
    index = as.integer(event$index %||% 1L),
    lower = as.numeric(event$lower %||% -Inf),
    upper = as.numeric(event$upper %||% Inf),
    values = if (length(values)) values else NULL,
    type = type,
    covariate = if (nzchar(trimws(as.character(event$covariate %||% "")[[1L]]))) {
      trimws(as.character(event$covariate)[[1L]])
    } else NULL
  )
  if (!nzchar(id)) id <- .lity_gui_key(design$variables, "variable", name)
  design$variables[[id]] <- variable
  design
}

.lity_gui_remove_variable <- function(design, id) {
  if (!id %in% names(design$variables)) .lity_stop("Unknown design variable.")
  design$variables[[id]] <- NULL
  design
}

.lity_gui_upsert_constraint <- function(design, event) {
  id <- as.character(event$id %||% "")[[1L]]
  name <- trimws(as.character(event$name %||% "Constraint")[[1L]])
  parameters <- trimws(as.character(event$parameters %||% "")[[1L]])
  parameters <- if (nzchar(parameters)) {
    trimws(strsplit(parameters, ",", fixed = TRUE)[[1L]])
  } else NULL
  optional_text <- function(field) {
    value <- trimws(as.character(event[[field]] %||% "")[[1L]])
    if (nzchar(value)) value else NULL
  }
  constraint <- lity_constraint(
    name = name,
    type = as.character(event$type %||% "total_subjects")[[1L]],
    limit = as.numeric(event$limit %||% 0),
    arm = optional_text("arm"),
    endpoint = optional_text("endpoint"),
    parameters = parameters,
    lower = .lity_gui_optional_number(event$lower %||% "", "lower"),
    upper = .lity_gui_optional_number(event$upper %||% "", "upper")
  )
  if (!nzchar(id)) id <- .lity_gui_key(design$constraints, "constraint", name)
  design$constraints[[id]] <- constraint
  design
}

.lity_gui_remove_constraint <- function(design, id) {
  if (!id %in% names(design$constraints)) .lity_stop("Unknown constraint.")
  design$constraints[[id]] <- NULL
  design
}
