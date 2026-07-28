.lity_gui_payload <- function(design, criterion, evaluation = NULL,
                              optimisation = NULL, simulation = NULL,
                              status = list(level = "info", text = "Design workbench ready"),
                              icon = NULL, queue = FALSE,
                              task = list(running = FALSE, id = "", label = "",
                                          cancellable = FALSE),
                              model_catalogue = list(records = list(), messages = list())) {
  arms <- lapply(names(design$arms), function(id) {
    arm <- design$arms[[id]]; observed <- arm$events$EVID == 0 & arm$events$MDV == 0
    list(id = id, name = arm$name, size = arm$size, allocation = arm$allocation,
         population = arm$population, samples = sum(observed),
         samplingTimes = as.numeric(arm$events$TIME[observed]),
         doses = .lity_rows(arm$events[arm$events$EVID != 0,
           intersect(c("TIME", "AMT", "RATE", "II", "ADDL", "SS", "CMT"), names(arm$events)), drop = FALSE]),
         sampleVolume = arm$sample_volume)
  })
  endpoints <- lapply(names(design$endpoints), function(id) {
    endpoint <- design$endpoints[[id]]
    list(id = id, name = endpoint$name, type = endpoint$type, dvid = endpoint$dvid,
         link = endpoint$link, distribution = endpoint$distribution,
         target = endpoint$target)
  })
  scenarios <- lapply(names(design$scenarios), function(id) {
    scenario <- design$scenarios[[id]]
    list(id = id, name = scenario$name, probability = scenario$probability,
         dropout = scenario$dropout, adherence = scenario$adherence,
         missedSample = scenario$missed_sample)
  })
  variables <- lapply(names(design$variables), function(id) {
    variable <- design$variables[[id]]
    list(id = id, name = variable$name, target = variable$target, arm = variable$arm,
         type = variable$type, lower = variable$lower, upper = variable$upper,
         current = .lity_variable_current(design, variable))
  })
  constraints <- if (is.null(evaluation)) tryCatch(lity_constraint_check(design), error = function(e) data.frame()) else evaluation$constraints
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
    estimates = .lity_rows(simulation$operating_characteristics$estimates %||% data.frame())
  )
  list(
    design = list(id = design$id, name = design$name, description = design$description,
                  advan = design$model$ADVAN, trans = design$model$TRANS,
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
    arms = arms, endpoints = endpoints, scenarios = scenarios, variables = variables,
    constraints = .lity_rows(constraints), criterion = list(
      name = criterion$name, type = criterion$type, direction = criterion$direction
    ), evaluation = if (is.null(evaluation)) NULL else list(
      id = evaluation$id, elapsed = evaluation$elapsed_seconds, criteria = criteria,
      precision = precision, information = information
    ),
    optimisation = if (is.null(optimisation)) NULL else list(
      method = optimisation$method, convergence = optimisation$convergence,
      message = optimisation$message, evaluations = optimisation$evaluations,
      elapsed = optimisation$elapsed_seconds, trace = trace
    ),
    simulation = simulation_payload, status = status, icon = icon, task = task,
    queueAvailable = isTRUE(queue), packageVersion = tryCatch(
      as.character(utils::packageVersion("LibeRality")), error = function(e) "0.1.2"
    ), criterionTypes = .lity_criterion_types, researchOnly = TRUE
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
