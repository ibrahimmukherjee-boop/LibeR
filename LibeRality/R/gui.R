.lity_gui_criterion <- function(type, design) {
  parameter_names <- .lity_parameter_spec(design$model)$name
  # `E` partially matches switch()'s formal `EXPR`; handle it explicitly so
  # strict partial-match checks remain quiet.
  if (identical(type, "E")) return(lity_criterion_E())
  switch(type,
    D = lity_criterion_D(), A = lity_criterion_A(),
    Ds = lity_criterion_Ds(parameter_names[grepl("^THETA", parameter_names)]),
    c = lity_criterion_c(c(1, rep(0, max(0, length(parameter_names) - 1L)))),
    L = lity_criterion_L(diag(length(parameter_names))),
    rse = lity_criterion_rse(), max_rse = lity_criterion_rse(summary = "max"),
    prediction_variance = lity_criterion_prediction(c(1, rep(0, max(0, length(parameter_names) - 1L)))),
    bayesian = lity_criterion_bayesian(), robust = lity_criterion_robust(),
    minimax = lity_criterion_minimax(), maximin = lity_criterion_maximin(),
    model_average = lity_criterion_model_average(),
    precision_probability = lity_criterion_precision_probability(),
    T = lity_criterion_discrimination("T"), KL = lity_criterion_discrimination("KL"),
    model_discrimination = lity_criterion_discrimination("model_discrimination"),
    power = lity_criterion_power(c(1, rep(0, max(0, length(parameter_names) - 1L)))),
    superiority = lity_criterion_power(c(1, rep(0, max(0, length(parameter_names) - 1L))), kind = "superiority"),
    noninferiority = lity_criterion_power(c(1, rep(0, max(0, length(parameter_names) - 1L))), kind = "noninferiority"),
    correct_dose = lity_criterion_correct_dose(
      design$endpoints[[1L]]$target %||% list(lower = 0, upper = Inf)
    ),
    target_attainment = lity_criterion_target(design$endpoints[[1L]]$target %||% list(lower = 0, upper = Inf)),
    expected_utility = lity_criterion_expected_utility(design$endpoints[[1L]]$target %||% list(lower = 0, upper = Inf)),
    cost = lity_criterion_cost(), burden = lity_criterion_burden(),
    compound = lity_criterion_compound(list(information = lity_criterion_D(), cost = lity_criterion_cost()),
                                       weights = c(0.8, 0.2), reference = c(1, max(.lity_design_cost(design), 1))),
    pareto = lity_criterion_pareto(list(information = lity_criterion_D(), cost = lity_criterion_cost())),
    lity_criterion_D()
  )
}

#' Launch the LibeRality optimal-design workbench
#'
#' @param design Initial design; the teaching example is used when omitted.
#' @param criterion Initial criterion.
#' @param queue Optional LibeRties local or remote queue.
#' @param host,port,launch.browser Passed to [shiny::runApp()]. Set
#'   `launch.browser = NULL` to return the Shiny application object for hosted
#'   deployment.
#' @return Invisibly, the Shiny app.
#' @export
liberality_gui <- function(design = NULL, criterion = lity_criterion_D(), queue = NULL,
                           host = "127.0.0.1", port = NULL, launch.browser = TRUE) {
  if (is.null(design)) design <- lity_example()$design
  validation <- lity_validate(design)
  if (!validation$valid) .lity_stop("Cannot launch an invalid design: ", paste(validation$errors, collapse = "; "))
  favicon <- system.file("assets", "favicon.svg", package = "LibeRality")
  if (!nzchar(favicon)) favicon <- file.path(getwd(), "LibeRality", "inst", "assets", "favicon.svg")
  prefix <- paste0("liberality-assets-", substr(.lity_id("gui"), 5, 16))
  if (file.exists(favicon)) shiny::addResourcePath(prefix, dirname(favicon))
  favicon_href <- if (file.exists(favicon)) paste0(prefix, "/favicon.svg") else ""
  ui <- htmltools::tags$html(
    htmltools::tags$head(
      htmltools::tags$title("LibeRality"),
      if (nzchar(favicon_href)) htmltools::tags$link(rel = "icon", type = "image/svg+xml", href = favicon_href),
      htmltools::tags$script(htmltools::HTML(
        "(function(){try{var t=localStorage.getItem('liber.theme');if(t!=='dark'&&t!=='light'){var l=localStorage.getItem('LibeRality.theme');t=l==='dark'?'dark':l==='light'?'light':(matchMedia('(prefers-color-scheme: dark)').matches?'dark':'light');}document.documentElement.setAttribute('data-liber-theme',t);}catch(e){}})();"
      )),
      htmltools::tags$style("html,body{margin:0;min-height:100%;background:#f8f5ef;font-family:'Segoe UI',Arial,sans-serif}html[data-liber-theme='dark'] body{background:#20201e}")
    ),
    htmltools::tags$body(liberalityWorkbenchOutput("liberality_workbench"))
  )
  server <- function(input, output, session) {
    tasks <- .liber_shared_task_registry(session)
    task_signal <- shiny::reactiveVal(0L)
    state <- shiny::reactiveValues(
      design = design, criterion = criterion, evaluation = NULL,
      optimisation = NULL, simulation = NULL,
      revision = 0L,
      status = list(level = "info", text = "Design workbench ready")
    )
    output$liberality_workbench <- renderLiberalityWorkbench({
      liberality_workbench(.lity_gui_payload(
        state$design, state$criterion, state$evaluation, state$optimisation,
        state$simulation, state$status, favicon_href, !is.null(queue),
        .liber_shared_task_snapshot(tasks)
      ))
    })
    shiny::observeEvent(input$liberality_workbench_event, {
      event <- input$liberality_workbench_event
      action <- as.character(event$action %||% "")
      tryCatch({
        if (action == "set_criterion") {
          state$criterion <- .lity_gui_criterion(as.character(event$type), state$design)
          state$revision <- state$revision + 1L
          state$status <- list(level = "info", text = paste("Selected", state$criterion$name))
        } else if (action == "evaluate") {
          .liber_shared_task_start(
            tasks, "LibeRality", ".lity_gui_background_task",
            args = list(
              operation = "evaluate",
              arguments = list(
                design = state$design, criterion = state$criterion
              )
            ),
            label = "Design evaluation",
            metadata = list(
              operation = "evaluate", revision = state$revision
            )
          )
          task_signal(task_signal() + 1L)
          .liber_shared_task_notify(
            session, "liberality_workbench", tasks
          )
        } else if (action == "edit_arm") {
          arm_id <- as.character(event$id); arm <- state$design$arms[[arm_id]]
          if (is.null(arm)) .lity_stop("Unknown arm.")
          size <- as.integer(event$size); if (!is.na(size) && size >= 0) arm$size <- size
          times <- suppressWarnings(as.numeric(strsplit(gsub("[[:space:]]", "", event$times %||% ""), ",", fixed = TRUE)[[1L]]))
          rows <- which(arm$events$EVID == 0 & arm$events$MDV == 0)
          if (length(times) == length(rows) && all(is.finite(times))) arm$events$TIME[rows] <- times
          dose <- as.numeric(event$dose); dose_rows <- which(arm$events$EVID != 0)
          if (length(dose_rows) && is.finite(dose) && dose >= 0) arm$events$AMT[dose_rows[[1L]]] <- dose
          arm$events <- arm$events[order(arm$events$TIME, -arm$events$EVID), , drop = FALSE]
          state$design$arms[[arm_id]] <- arm
          state$evaluation <- state$optimisation <- state$simulation <- NULL
          state$revision <- state$revision + 1L
          state$status <- list(level = "success", text = paste("Updated", arm$name))
        } else if (action == "optimise") {
          method <- as.character(event$method %||% "auto")
          maxit <- as.integer(event$maxit %||% 40L)
          .liber_shared_task_start(
            tasks, "LibeRality", ".lity_gui_background_task",
            args = list(
              operation = "optimise",
              arguments = list(
                design = state$design, criterion = state$criterion,
                method = method,
                control = list(
                  maxit = maxit,
                  particles = min(
                    30L, max(12L, 3L * length(state$design$variables))
                  )
                )
              )
            ),
            label = paste(method, "design optimisation"),
            metadata = list(
              operation = "optimise", revision = state$revision
            )
          )
          task_signal(task_signal() + 1L)
          .liber_shared_task_notify(
            session, "liberality_workbench", tasks
          )
        } else if (action == "simulate") {
          n <- as.integer(event$n %||% 20L); fit <- isTRUE(event$fit)
          .liber_shared_task_start(
            tasks, "LibeRality", ".lity_gui_background_task",
            args = list(
              operation = "simulate",
              arguments = list(
                design = state$design, n = n, fit = fit,
                method = as.character(event$method %||% "FOCEI")
              )
            ),
            label = paste(n, "trial simulations"),
            metadata = list(
              operation = "simulate", revision = state$revision, n = n
            )
          )
          task_signal(task_signal() + 1L)
          .liber_shared_task_notify(
            session, "liberality_workbench", tasks
          )
        } else if (action == "queue") {
          if (is.null(queue)) .lity_stop("No queue was supplied to liberality_gui().")
          job <- lity_job(state$design, state$criterion,
                          operation = as.character(event$operation %||% "optimise"),
                          arguments = list(method = as.character(event$method %||% "auto")))
          id <- queue$submit(job)
          state$status <- list(level = "success", text = paste("Submitted optimal-design job", id))
        } else if (action == "save") {
          path <- normalizePath(as.character(event$path), winslash = "/", mustWork = FALSE)
          saveRDS(state$design, path, version = 3)
          state$status <- list(level = "success", text = paste("Saved design to", path))
        } else if (action == "load") {
          loaded <- readRDS(as.character(event$path)); validation <- lity_validate(loaded)
          if (!validation$valid) .lity_stop("Saved design is invalid.")
          state$design <- loaded; state$evaluation <- state$optimisation <- state$simulation <- NULL
          state$revision <- state$revision + 1L
          state$status <- list(level = "success", text = paste("Loaded", loaded$name))
        } else if (action == "report") {
          path <- as.character(event$path %||% tempfile("LibeRality-report-", fileext = ".html"))
          source <- state$optimisation %||% state$evaluation %||% state$design
          .liber_shared_task_start(
            tasks, "LibeRality", ".lity_gui_background_task",
            args = list(
              operation = "report",
              arguments = list(source = source, path = path)
            ),
            label = "Design report",
            metadata = list(
              operation = "report", revision = state$revision, path = path
            )
          )
          task_signal(task_signal() + 1L)
          .liber_shared_task_notify(
            session, "liberality_workbench", tasks
          )
        } else if (action == "reset") {
          state$design <- lity_example()$design; state$criterion <- lity_criterion_D()
          state$evaluation <- state$optimisation <- state$simulation <- NULL
          state$revision <- state$revision + 1L
          state$status <- list(level = "info", text = "Teaching example restored")
        } else if (action == "cancel_task") {
          if (.liber_shared_task_cancel_all(tasks)) {
            state$status <- list(
              level = "warning", text = "Background calculation cancelled"
            )
            .liber_shared_task_notify(
              session, "liberality_workbench", tasks
            )
          }
        }
      }, error = function(error) {
        state$status <- list(level = "error", text = conditionMessage(error))
        shiny::showNotification(conditionMessage(error), type = "error", duration = 9)
      })
    }, ignoreInit = TRUE)
    shiny::observe({
      task_signal()
      if (!.liber_shared_task_active(tasks)) return()
      shiny::invalidateLater(100, session)
      .liber_shared_task_poll(tasks)
      completed <- .liber_shared_task_take_completed(tasks)
      if (!length(completed)) return()
      for (job in completed) {
        if (identical(job$status, "failed")) {
          state$status <- list(level = "error", text = job$error)
          shiny::showNotification(job$error, type = "error", duration = 9)
          next
        }
        if (!identical(job$status, "completed")) next
        operation <- job$metadata$operation
        if (!identical(operation, "report") &&
            !identical(job$metadata$revision, state$revision)) {
          state$status <- list(
            level = "warning",
            text = "The design changed; the stale background result was discarded"
          )
          next
        }
        if (identical(operation, "evaluate")) {
          state$evaluation <- job$result
          state$optimisation <- NULL
          state$status <- list(
            level = "success",
            text = paste(
              "Evaluation completed in",
              round(state$evaluation$elapsed_seconds, 2), "seconds"
            )
          )
        } else if (identical(operation, "optimise")) {
          state$optimisation <- job$result
          state$design <- state$optimisation$design
          state$evaluation <- state$optimisation$evaluation
          state$revision <- state$revision + 1L
          state$status <- list(
            level = "success",
            text = paste(
              "Optimisation completed after",
              state$optimisation$evaluations, "evaluations"
            )
          )
        } else if (identical(operation, "simulate")) {
          state$simulation <- job$result
          state$status <- list(
            level = "success",
            text = paste(job$metadata$n, "trial simulations completed")
          )
        } else if (identical(operation, "report")) {
          state$status <- list(
            level = "success",
            text = paste("Report written to", job$result)
          )
        }
      }
      .liber_shared_task_notify(session, "liberality_workbench", tasks)
    })
  }
  app <- shiny::shinyApp(ui, server)
  if (is.null(launch.browser)) return(app)
  shiny::runApp(app, host = host, port = port, launch.browser = launch.browser)
  invisible(app)
}
