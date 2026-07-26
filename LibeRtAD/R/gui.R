.ad_find_ecosystem_benchmark <- function(root = NULL) {
  candidates <- character()
  if (!is.null(root) && length(root) == 1L && nzchar(root)) {
    root <- path.expand(root)
    candidates <- c(candidates, root, file.path(root, "benchmark.R"),
                    file.path(root, "validation", "benchmark", "benchmark.R"))
  }
  current <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  for (index in seq_len(8L)) {
    candidates <- c(candidates, file.path(current, "validation", "benchmark", "benchmark.R"))
    parent <- dirname(current)
    if (identical(parent, current)) break
    current <- parent
  }
  candidates <- unique(candidates)
  match <- candidates[file.exists(candidates) & !dir.exists(candidates)][1L]
  if (!length(match) || is.na(match)) return(NULL)
  normalizePath(match, winslash = "/", mustWork = TRUE)
}

.ad_default_benchmark_output <- function() {
  .liber_shared_user_root("benchmarks")
}

.ad_gui_ecosystem_result <- function(output, exit_status) {
  read_optional <- function(name) {
    path <- file.path(output, name)
    if (!file.exists(path) || is.na(file.info(path)$size) || file.info(path)$size <= 4L) return(list())
    tryCatch(
      .ad_gui_rows(utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)),
      error = function(error) list()
    )
  }
  list(
    output = normalizePath(output, winslash = "/", mustWork = FALSE),
    exitStatus = as.integer(exit_status),
    summary = read_optional("summary.csv"),
    paired = read_optional("paired-timing-comparison.csv"),
    report = if (file.exists(file.path(output, "REPORT.md"))) {
      readLines(file.path(output, "REPORT.md"), warn = FALSE, encoding = "UTF-8")
    } else character()
  )
}

.ad_gui_stop_process <- function(state) {
  process <- shiny::isolate(state$process)
  if (!is.null(process) && process$is_alive()) process$kill()
  invisible(NULL)
}

#' Launch the LibeRtAD benchmark laboratory
#'
#' The local-only workbench runs native tape microbenchmarks directly and can
#' launch the repository's paired LibeRation/NONMEM benchmark harness as a
#' cancellable background process. The latter requires a LibeR source checkout,
#' LibeRation, and (when selected) PsN `execute` plus NONMEM.
#'
#' @param benchmark_root Optional repository root or benchmark script path.
#' @param host,port,launch.browser Passed to [shiny::runApp()].
#' @param allow_remote Explicitly permit a non-loopback bind.
#' @return Invisibly, the Shiny app.
#' @export
libertad_gui <- function(benchmark_root = NULL, host = "127.0.0.1", port = NULL,
                         launch.browser = TRUE, allow_remote = FALSE) {
  if (!host %in% c("127.0.0.1", "localhost", "::1") && !isTRUE(allow_remote)) {
    .ad_stop("Non-loopback hosting is disabled unless `allow_remote = TRUE`.")
  }
  benchmark_script <- .ad_find_ecosystem_benchmark(benchmark_root)
  favicon <- system.file("assets", "favicon.svg", package = "LibeRtAD")
  if (!nzchar(favicon)) favicon <- file.path(getwd(), "LibeRtAD", "inst", "assets", "favicon.svg")
  prefix <- paste0("libertad-assets-", sprintf("%08x", sample.int(.Machine$integer.max, 1L)))
  if (file.exists(favicon)) shiny::addResourcePath(prefix, dirname(favicon))
  favicon_href <- if (file.exists(favicon)) paste0(prefix, "/favicon.svg") else ""

  ui <- htmltools::tags$html(
    htmltools::tags$head(
      htmltools::tags$title("LibeRtAD"),
      if (nzchar(favicon_href)) htmltools::tags$link(rel = "icon", type = "image/svg+xml", href = favicon_href),
      htmltools::tags$script(htmltools::HTML(
        "(function(){try{var t=localStorage.getItem('liber.theme');if(t!=='dark'&&t!=='light'){var l=localStorage.getItem('libertadTheme');t=l==='dark'?'dark':l==='light'?'light':(matchMedia('(prefers-color-scheme: dark)').matches?'dark':'light');}document.documentElement.setAttribute('data-liber-theme',t);}catch(e){}})();"
      )),
      htmltools::tags$style("html,body{margin:0;min-height:100%;background:#f5f3f8;font-family:'Segoe UI',Arial,sans-serif}html[data-liber-theme='dark'] body{background:#211c27}")
    ),
    htmltools::tags$body(libertadWorkbenchOutput("libertad_workbench"))
  )

  server <- function(input, output, session) {
    tasks <- .liber_shared_task_registry(session)
    task_signal <- shiny::reactiveVal(0L)
    state <- shiny::reactiveValues(
      native = NULL, process = NULL, ecosystem = NULL,
      ecosystem_log = character(), ecosystem_output = NULL,
      status = list(level = "info", text = "Benchmark laboratory ready")
    )
    append_ecosystem_log <- function(lines) {
      lines <- as.character(lines)
      lines <- lines[nzchar(lines)]
      if (!length(lines)) return(invisible(FALSE))
      state$ecosystem_log <- c(shiny::isolate(state$ecosystem_log), lines)
      session$sendCustomMessage(
        "libertad-workbench-patch",
        list(inputId = "libertad_workbench", ecosystemLogAppend = lines)
      )
      invisible(TRUE)
    }
    reset_ecosystem_log <- function(lines = character()) {
      lines <- as.character(lines)
      state$ecosystem_log <- lines
      session$sendCustomMessage(
        "libertad-workbench-patch",
        list(inputId = "libertad_workbench", ecosystemLog = lines)
      )
      invisible(TRUE)
    }
    output$libertad_workbench <- renderLibertadWorkbench({
      libertad_workbench(.ad_gui_payload(
        state$native, state$ecosystem, shiny::isolate(state$ecosystem_log),
        benchmark_script, !is.null(state$process), state$status, favicon_href,
        .liber_shared_task_snapshot(tasks)
      ))
    })

    shiny::observeEvent(input$libertad_workbench_event, {
      event <- input$libertad_workbench_event
      action <- as.character(event$action %||% "")
      tryCatch({
        if (action == "run_native") {
          if (!is.null(state$process) && state$process$is_alive()) {
            .ad_stop("Wait for the ecosystem benchmark to finish or cancel it first.")
          }
          .liber_shared_task_start(
            tasks, "LibeRtAD", ".ad_gui_background_task",
            args = list(
              case = as.character(event$case %||% "rosenbrock"),
              iterations = as.integer(event$iterations %||% 1000L),
              warmups = as.integer(event$warmups %||% 50L),
              optimize = isTRUE(event$optimize),
              finite_difference = isTRUE(event$finite_difference)
            ),
            label = "C++ tape benchmark",
            metadata = list(operation = "native")
          )
          task_signal(task_signal() + 1L)
          .liber_shared_task_notify(
            session, "libertad_workbench", tasks
          )
        } else if (action == "run_ecosystem") {
          if (is.null(benchmark_script)) .ad_stop("The repository benchmark harness is not available.")
          if (!is.null(state$process) && state$process$is_alive()) .ad_stop("A benchmark is already running.")
          if (.liber_shared_task_active(tasks)) .ad_stop("A native benchmark is already running.")
          profile <- match.arg(as.character(event$profile %||% "smoke"), c("smoke", "quick", "standard"))
          scenario <- match.arg(as.character(event$scenario %||% "iv-bolus"),
                                c("iv-bolus", "oral", "two-compartment", "three-compartment",
                                  "full-omega", "infusion-steady-state", "iov", "advan6", "advan13"))
          methods <- as.character(event$methods %||% "deterministic")
          engines <- as.character(event$engines %||% "LIBERATION")
          if (!methods %in% c("deterministic", "all", "FO", "FOCE", "FOCEI", "LAPLACE", "ITS", "IMP", "SAEM")) {
            .ad_stop("Unsupported method selection.")
          }
          if (!engines %in% c("LIBERATION", "NONMEM", "NONMEM,LIBERATION")) .ad_stop("Unsupported engine selection.")
          output_root <- path.expand(as.character(event$output %||% .ad_default_benchmark_output()))
          output_directory <- file.path(
            output_root,
            paste0(format(Sys.time(), "%Y%m%d-%H%M%S"), "-", profile, "-", scenario)
          )
          dir.create(output_directory, recursive = TRUE, showWarnings = FALSE)
          rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
          args <- c(
            benchmark_script, paste0("--profile=", profile), paste0("--scenario=", scenario),
            paste0("--methods=", methods), paste0("--engines=", engines),
            paste0("--repeats=", as.integer(event$repeats %||% 1L)),
            paste0("--warmups=", as.integer(event$process_warmups %||% 0L)),
            paste0("--output=", normalizePath(output_directory, winslash = "/", mustWork = FALSE)),
            "--population-objective=cpp"
          )
          if (!isTRUE(event$covariance)) args <- c(args, "--no-covariance")
          if (!isTRUE(event$simulation)) args <- c(args, "--no-simulation")
          reset_ecosystem_log(c(
            paste("Launching:", rscript, paste(args, collapse = " ")),
            paste("Output:", output_directory)
          ))
          state$ecosystem <- NULL
          state$ecosystem_output <- output_directory
          state$process <- if (requireNamespace("LibeRties", quietly = TRUE)) {
            LibeRties::ls_process_supervisor(
              rscript, args = args, wd = dirname(benchmark_script),
              stdout = "|", stderr = "2>&1", cleanup = TRUE,
              windows_hide_window = TRUE,
              label = paste(profile, scenario, "ecosystem benchmark")
            )
          } else {
            processx::process$new(
              rscript, args = args, wd = dirname(benchmark_script),
              stdout = "|", stderr = "2>&1", cleanup = TRUE,
              windows_hide_window = TRUE
            )
          }
          state$status <- list(level = "working", text = paste("Running", profile, scenario, "ecosystem benchmark..."))
        } else if (action == "stop_ecosystem") {
          if (!is.null(state$process) && state$process$is_alive()) {
            state$process$kill()
            state$status <- list(level = "warning", text = "Benchmark cancellation requested")
          }
        } else if (action == "cancel_task") {
          if (.liber_shared_task_cancel_all(tasks)) {
            state$status <- list(level = "warning", text = "Native benchmark cancelled")
            .liber_shared_task_notify(
              session, "libertad_workbench", tasks
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
        if (identical(job$status, "completed")) {
          state$native <- job$result
          state$status <- list(
            level = "success",
            text = paste("Completed", state$native$label)
          )
        } else if (identical(job$status, "failed")) {
          state$status <- list(level = "error", text = job$error)
          shiny::showNotification(job$error, type = "error", duration = 9)
        }
      }
      .liber_shared_task_notify(session, "libertad_workbench", tasks)
    })

    shiny::observe({
      process <- state$process
      if (is.null(process)) return()
      shiny::invalidateLater(500, session)
      tryCatch({
        lines <- tryCatch(process$read_output_lines(), error = function(error) character())
        append_ecosystem_log(lines)
        if (!process$is_alive()) {
          lines <- tryCatch(process$read_all_output_lines(), error = function(error) character())
          append_ecosystem_log(lines)
          status <- process$get_exit_status()
          state$ecosystem <- .ad_gui_ecosystem_result(state$ecosystem_output, status)
          state$process <- NULL
          state$status <- if (identical(status, 0L)) {
            list(level = "success", text = "Ecosystem benchmark completed")
          } else list(level = "error", text = paste("Ecosystem benchmark exited with status", status))
        }
      }, error = function(error) {
        append_ecosystem_log(paste("GUI polling error:", conditionMessage(error)))
        state$process <- NULL
        state$status <- list(level = "error", text = paste("Unable to collect benchmark results:", conditionMessage(error)))
      })
    })
    session$onSessionEnded(function() {
      .ad_gui_stop_process(state)
      .liber_shared_task_cancel_all(tasks)
    })
  }
  app <- shiny::shinyApp(ui, server)
  if (is.null(launch.browser)) return(app)
  shiny::runApp(app, host = host, port = port, launch.browser = launch.browser)
  invisible(app)
}
