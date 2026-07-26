.lity_gui_background_task <- function(operation, arguments) {
  operation <- match.arg(
    operation, c("evaluate", "optimise", "simulate", "report")
  )
  if (!is.list(arguments)) {
    .lity_stop("Background GUI task arguments must be a list.")
  }
  switch(
    operation,
    evaluate = lity_evaluate(arguments$design, arguments$criterion),
    optimise = lity_optimise(
      arguments$design, arguments$criterion,
      method = arguments$method,
      control = arguments$control
    ),
    simulate = lity_simulate_trials(
      arguments$design,
      n = arguments$n,
      fit = arguments$fit,
      method = arguments$method,
      retain_data = FALSE
    ),
    report = lity_report(arguments$source, arguments$path)
  )
}
