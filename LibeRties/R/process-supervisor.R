#' Normalize a background process for LibeR GUI consumers
#'
#' The returned object exposes one lifecycle surface for `processx` and `callr`
#' processes: polling, incremental logs, cancellation, exit status, and a
#' serializable status snapshot. It does not broaden the worker's authority.
#'
#' @param process A live `processx::process` or `callr::r_process`.
#' @param label Optional human-readable label.
#' @return An R6 process supervisor.
#' @export
ls_supervise_process <- function(process, label = NULL) {
  required <- c("is_alive", "poll_io", "wait", "kill", "get_exit_status")
  missing <- required[!vapply(required, function(name) {
    is.function(tryCatch(process[[name]], error = function(error) NULL))
  }, logical(1))]
  if (length(missing)) {
    .ls_stop(
      "`process` does not implement the required process lifecycle: ",
      paste(missing, collapse = ", "), "."
    )
  }
  LibeRProcessSupervisor$new(process, label = label)
}

#' Start and supervise an external command
#'
#' @param command Executable path or command.
#' @param args Command arguments.
#' @param wd Working directory.
#' @param stdout,stderr Process stream configuration passed to `processx`.
#' @param cleanup Terminate the child if the supervising R session exits.
#' @param windows_hide_window Hide the process window on Windows.
#' @param label Optional human-readable label.
#' @return An R6 process supervisor.
#' @export
ls_process_supervisor <- function(
    command, args = character(), wd = NULL, stdout = "|", stderr = "2>&1",
    cleanup = TRUE, windows_hide_window = TRUE, label = NULL) {
  process <- processx::process$new(
    command, args = args, wd = wd, stdout = stdout, stderr = stderr,
    cleanup = cleanup, windows_hide_window = windows_hide_window
  )
  ls_supervise_process(process, label = label)
}

LibeRProcessSupervisor <- R6::R6Class(
  "LibeRProcessSupervisor",
  public = list(
    process = NULL,
    label = "",
    created = NULL,
    initialize = function(process, label = NULL) {
      self$process <- process
      self$label <- as.character(label %||% "")[[1L]]
      self$created <- .ls_now()
    },
    is_alive = function() {
      isTRUE(tryCatch(self$process$is_alive(), error = function(error) FALSE))
    },
    poll = function(timeout = 0L) {
      self$process$poll_io(as.integer(timeout))
    },
    wait = function(timeout = -1L) {
      self$process$wait(timeout = as.integer(timeout))
    },
    read_output_lines = function() {
      tryCatch(self$process$read_output_lines(), error = function(error) character())
    },
    read_error_lines = function() {
      method <- tryCatch(self$process$read_error_lines, error = function(error) NULL)
      if (!is.function(method)) return(character())
      tryCatch(method(), error = function(error) character())
    },
    read_all_output_lines = function() {
      method <- tryCatch(self$process$read_all_output_lines, error = function(error) NULL)
      if (!is.function(method)) return(self$read_output_lines())
      tryCatch(method(), error = function(error) character())
    },
    read_all_error_lines = function() {
      method <- tryCatch(self$process$read_all_error_lines, error = function(error) NULL)
      if (!is.function(method)) return(self$read_error_lines())
      tryCatch(method(), error = function(error) character())
    },
    get_result = function() {
      method <- tryCatch(self$process$get_result, error = function(error) NULL)
      if (!is.function(method)) {
        .ls_stop("This supervised process does not expose an R result.")
      }
      method()
    },
    get_exit_status = function() {
      tryCatch(self$process$get_exit_status(), error = function(error) NA_integer_)
    },
    kill_tree = function() {
      method <- tryCatch(self$process$kill_tree, error = function(error) NULL)
      if (is.function(method)) return(method())
      self$process$kill()
    },
    kill = function() {
      self$process$kill()
    },
    cancel = function(timeout = 2000L) {
      if (!self$is_alive()) return(FALSE)
      try(self$kill_tree(), silent = TRUE)
      try(self$wait(timeout = timeout), silent = TRUE)
      !self$is_alive()
    },
    snapshot = function() {
      status <- if (self$is_alive()) {
        "running"
      } else {
        exit <- self$get_exit_status()
        if (isTRUE(!is.na(exit) && exit == 0L)) "completed" else "failed"
      }
      list(
        schema = "liber.process-supervisor/1",
        label = self$label,
        status = status,
        alive = self$is_alive(),
        exit_status = self$get_exit_status(),
        created = self$created
      )
    }
  )
)
