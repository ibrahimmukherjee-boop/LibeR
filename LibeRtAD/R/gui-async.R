.ad_gui_background_task <- function(
    case, iterations, warmups, optimize, finite_difference) {
  ad_benchmark(
    case = case,
    iterations = as.integer(iterations),
    warmups = as.integer(warmups),
    optimize = isTRUE(optimize),
    finite_difference = isTRUE(finite_difference)
  )
}
