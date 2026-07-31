.lity_gui_payload <- function(design, criterion, evaluation = NULL,
                              optimisation = NULL, simulation = NULL,
                              status = list(level = "info", text = "Design workbench ready"),
                              icon = NULL, queue = FALSE,
                              task = list(running = FALSE, id = "", label = "",
                                          cancellable = FALSE),
                              model_catalogue = list(records = list(), messages = list()),
                              revision = 0L, hosted = FALSE,
                              design_history = list(
                                records = list(), currentSeries = "",
                                currentVersion = "", dirty = TRUE
                              )) {
  arms <- lapply(names(design$arms), function(id) {
    arm <- design$arms[[id]]; observed <- arm$events$EVID == 0 & arm$events$MDV == 0
    doses <- arm$events[arm$events$EVID != 0, , drop = FALSE]
    list(id = id, name = arm$name, size = arm$size, allocation = arm$allocation,
         population = arm$population, samples = sum(observed),
         samplingTimes = as.numeric(arm$events$TIME[observed]),
         doses = .lity_rows(doses[
           intersect(c("TIME", "AMT", "RATE", "II", "ADDL", "SS", "CMT"), names(arm$events))]),
         sampleVolume = arm$sample_volume,
         route = arm$metadata$route %||% "extravascular",
         doseCmt = if (nrow(doses)) doses$CMT[[1L]] else 1L,
         observationCmt = if (any(observed)) arm$events$CMT[observed][[1L]] else 1L,
         dvid = if (any(observed)) arm$events$DVID[observed][[1L]] else 1L,
         ii = if (nrow(doses)) doses$II[[1L]] else 0,
         addl = if (nrow(doses)) doses$ADDL[[1L]] else 0L,
         ss = if (nrow(doses)) doses$SS[[1L]] else 0L,
         costs = arm$costs)
  })
  endpoints <- lapply(names(design$endpoints), function(id) {
    endpoint <- design$endpoints[[id]]
    list(id = id, name = endpoint$name, type = endpoint$type, dvid = endpoint$dvid,
         link = endpoint$link, distribution = endpoint$distribution,
         scale = endpoint$scale, thresholds = endpoint$thresholds,
         dispersion = endpoint$dispersion, target = endpoint$target)
  })
  scenarios <- lapply(names(design$scenarios), function(id) {
    scenario <- design$scenarios[[id]]
    list(id = id, name = scenario$name, probability = scenario$probability,
         dropout = scenario$dropout, adherence = scenario$adherence,
         missedSample = scenario$missed_sample, theta = scenario$theta,
         omega = scenario$omega, sigma = scenario$sigma,
         covariates = scenario$covariates)
  })
  variables <- lapply(names(design$variables), function(id) {
    variable <- design$variables[[id]]
    list(id = id, name = variable$name, target = variable$target, arm = variable$arm,
         type = variable$type, lower = variable$lower, upper = variable$upper,
         current = .lity_variable_current(design, variable), index = variable$index,
         values = variable$values, covariate = variable$covariate)
  })
  constraints <- if (is.null(evaluation)) tryCatch(lity_constraint_check(design), error = function(e) data.frame()) else evaluation$constraints
  constraint_definitions <- lapply(names(design$constraints), function(id) {
    item <- design$constraints[[id]]
    list(
      id = id, name = item$name, type = item$type, limit = item$limit,
      arm = item$arm, endpoint = item$endpoint, parameters = item$parameters,
      lower = item$lower, upper = item$upper,
      scripted = identical(item$type, "custom")
    )
  })
  constraint_type_explanation <- c(
    min_separation = "The shortest interval between two samples must be at least the configured limit.",
    max_samples = "The number of samples per subject must not exceed the configured limit.",
    total_subjects = "The total number of randomised subjects must not exceed the configured limit.",
    total_cost = "The calculated total study cost must remain at or below the configured budget.",
    max_blood_volume = "The sampled blood volume per subject must not exceed the configured safety limit.",
    max_duration = "The duration of each selected arm must not exceed the configured limit.",
    arm_size = "The selected arm size must not exceed the configured limit.",
    allocation = "The selected allocation value must not exceed the configured limit.",
    max_rse = "The largest selected parameter relative standard error must not exceed the configured precision limit.",
    minimum_power = "The lowest evaluated power must meet or exceed the configured minimum.",
    exposure = "The lowest evaluated target-attainment probability must meet or exceed the configured minimum.",
    custom = "A user-supplied deterministic constraint function defines feasibility."
  )
  if (nrow(constraints)) {
    constraints$id <- vapply(seq_len(nrow(constraints)), function(i) {
      match <- which(vapply(design$constraints, function(x) identical(x$name, constraints$name[[i]]), logical(1)))
      if (length(match)) names(design$constraints)[match[[1L]]] else paste0("constraint-", i)
    }, character(1))
    constraints$rule <- unname(constraint_type_explanation[constraints$type])
    constraints$detail <- vapply(seq_len(nrow(constraints)), function(i) {
      row <- constraints[i, , drop = FALSE]
      relation <- if (row$type %in% c("min_separation", "minimum_power", "exposure")) "at least" else "at most"
      status <- if (isTRUE(row$feasible)) "satisfies" else "violates"
      paste0(
        "The evaluated value is ", format(row$value, digits = 5), ", which ",
        status, " the requirement of ", relation, " ", format(row$limit, digits = 5),
        if (!isTRUE(row$feasible)) paste0(" (violation magnitude ", format(row$violation, digits = 5), ").") else "."
      )
    }, character(1))
  }
  precision <- criteria <- information <- list()
  if (!is.null(evaluation)) {
    criteria <- .lity_rows(evaluation$criteria)
    first <- evaluation$information[[1L]]
    precision <- unname(lapply(seq_along(first$se), function(i) list(
      parameter = names(first$se)[[i]], value = first$parameters$value[[i]],
      se = first$se[[i]], rse = first$rse[[i]]
    )))
    information <- list(rank = first$rank, dimension = nrow(first$matrix),
                        condition = first$condition_number, logDeterminant = first$log_determinant,
                        eigenvalues = as.numeric(first$eigenvalues), matrix = unname(split(first$matrix, row(first$matrix))),
                        scenario = first$scenario, diagnostics = first$diagnostics)
  }
  trace <- list()
  if (!is.null(optimisation) && length(optimisation$trace)) trace <- lapply(optimisation$trace, function(item) list(
    iteration = item$iteration, criterion = item$criterion, objective = if (length(item$objective) == 1L) item$objective else NA_real_,
    feasible = item$feasible
  ))
  simulation_payload <- if (is.null(simulation)) NULL else list(
    n = simulation$n, method = simulation$method, elapsed = simulation$elapsed_seconds,
    convergence = simulation$operating_characteristics$convergence,
    summary = .lity_rows(simulation$summary),
    estimates = .lity_rows(simulation$operating_characteristics$estimates %||% data.frame()),
    endpointCurves = .lity_rows(simulation$endpoint_summary %||% data.frame()),
    nca = list(
      backend = simulation$nca$backend %||% "LibeRation native C++ NCA",
      summary = .lity_rows(simulation$nca$summary %||% data.frame()),
      applicability = .lity_rows(simulation$nca$applicability %||% data.frame())
    )
  )
  robustness <- if (is.null(evaluation)) list() else unname(lapply(evaluation$information, function(item) list(
    scenario = item$scenario, rank = item$rank,
    condition = item$condition_number, logDeterminant = item$log_determinant,
    method = item$diagnostics$method %||% "",
    predictionDerivatives = item$diagnostics$prediction_derivatives %||% ""
  )))
  route <- .lity_model_route(design$model)
  list(
    design = list(id = design$id, name = design$name, description = design$description,
                  advan = design$model$ADVAN, trans = design$model$TRANS,
                  modelType = route$label, predMode = route$mode,
                  subjects = sum(vapply(design$arms, `[[`, numeric(1), "size")),
                  cost = .lity_design_cost(design), burden = .lity_design_burden(design),
                  alternatives = length(design$alternative_models)),
    model = .lity_model_detail(
      design$model, design$metadata$model_provenance %||% NULL
    ),
    modelBrowser = list(
      catalogue = model_catalogue, preview = NULL, selectedKey = "",
      busy = FALSE, applied = FALSE
    ),
    designTemplates = .lity_rows(lity_design_templates()),
    designHistory = design_history,
    arms = arms, endpoints = endpoints, scenarios = scenarios, variables = variables,
    endpointOptions = lapply(.lity_endpoint_options(), function(item) list(
      links = as.character(item$links),
      distributions = as.character(item$distributions)
    )),
    constraintDefinitions = constraint_definitions,
    constraints = .lity_rows(constraints), criterion = list(
      name = criterion$name, type = criterion$type, direction = criterion$direction,
      guidance = .lity_criterion_guidance()[[criterion$type]]
    ), evaluation = if (is.null(evaluation)) NULL else list(
      id = evaluation$id, elapsed = evaluation$elapsed_seconds, criteria = criteria,
      precision = precision, information = information,
      robustness = robustness
    ),
    optimisation = if (is.null(optimisation)) NULL else list(
      method = optimisation$method, convergence = optimisation$convergence,
      message = optimisation$message, evaluations = optimisation$evaluations,
      elapsed = optimisation$elapsed_seconds, trace = trace
    ),
    simulation = simulation_payload, status = status, icon = icon, task = task,
    queueAvailable = isTRUE(queue), packageVersion = tryCatch(
      as.character(utils::packageVersion("LibeRality")), error = function(e) "0.1.2"
    ), criterionTypes = .lity_criterion_types,
    criterionGuidance = unname(.lity_criterion_guidance()),
    workflow = list(
      revision = as.integer(revision),
      modelReady = inherits(design$model, "nm_model"),
      designReady = length(design$arms) > 0L && length(design$endpoints) > 0L,
      objectivesReady = inherits(criterion, "lity_criterion"),
      evaluated = !is.null(evaluation),
      robustnessEvaluated = !is.null(evaluation) &&
        length(evaluation$information) >= length(design$scenarios),
      optimised = !is.null(optimisation),
      simulated = !is.null(simulation),
      violatedConstraints = if (nrow(constraints)) sum(!constraints$feasible) else 0L
    ),
    hosted = isTRUE(hosted), researchOnly = TRUE
  )
}

#' LibeRality React workbench widget
#' @param payload Workbench payload.
#' @param input_id Shiny event prefix.
#' @param width,height Widget dimensions.
#' @param elementId Optional element id.
#' @export
liberality_workbench <- function(payload, input_id = "liberality_workbench",
                                 width = NULL, height = "100vh", elementId = NULL) {
  if (inherits(payload, "lity_design")) {
    payload <- .lity_gui_payload(payload, lity_criterion_D())
  }
  if (!is.list(payload)) .lity_stop("`payload` must be a workbench payload or LibeRality design.")
  content <- reactR::component("LibeRalityWorkbench", c(payload, list(inputId = input_id)))
  htmlwidgets::createWidget(
    name = "liberalityWorkbench", reactR::reactMarkup(content), width = width,
    height = height, package = "LibeRality", elementId = elementId
  )
}

#' @noRd
widget_html.liberalityWorkbench <- function(id, style, class, ...) {
  htmltools::attachDependencies(
    htmltools::tags$div(id = id, class = class, style = style),
    list(reactR::html_dependency_corejs(), reactR::html_dependency_react(), reactR::html_dependency_reacttools())
  )
}

#' Shiny output for the LibeRality workbench
#' @param outputId Output id.
#' @param width,height CSS dimensions.
#' @export
liberalityWorkbenchOutput <- function(outputId, width = "100%", height = "100vh") {
  htmlwidgets::shinyWidgetOutput(outputId, "liberalityWorkbench", width, height, package = "LibeRality")
}

#' Render a LibeRality workbench
#' @param expr Widget expression.
#' @param env Evaluation environment.
#' @param quoted Whether expression is quoted.
#' @export
renderLiberalityWorkbench <- function(expr, env = parent.frame(), quoted = FALSE) {
  if (!quoted) expr <- substitute(expr)
  htmlwidgets::shinyRenderWidget(expr, liberalityWorkbenchOutput, env, quoted = TRUE)
}
