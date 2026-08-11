args <- commandArgs(trailingOnly = TRUE)
option_value <- function(name, default) {
  prefix <- paste0("--", name, "=")
  value <- args[startsWith(args, prefix)]
  if (length(value)) sub(prefix, "", tail(value, 1L), fixed = TRUE) else default
}

n_subjects <- as.integer(option_value("subjects", "500"))
n_records <- as.integer(option_value("records", "8"))
repetitions <- as.integer(option_value("repetitions", "20"))
output <- option_value(
  "output",
  file.path(
    "validation", "benchmark", "results",
    "subject-native-calculations.csv"
  )
)
if (anyNA(c(n_subjects, n_records, repetitions)) || n_subjects < 1L ||
    n_records < 2L || repetitions < 1L) {
  stop("Benchmark dimensions must be positive integers.", call. = FALSE)
}

library(LibeRation)
times <- seq(0, 24, length.out = n_records)
data <- data.frame(
  ID = rep(seq_len(n_subjects), each = n_records),
  TIME = rep(times, n_subjects),
  EVID = rep(c(1L, rep.int(0L, n_records - 1L)), n_subjects),
  AMT = rep(c(100, rep.int(0, n_records - 1L)), n_subjects),
  MDV = rep(c(1L, rep.int(0L, n_records - 1L)), n_subjects),
  DV = rep(c(NA_real_, exp(-0.1 * times[-1L]) * 5), n_subjects),
  WT = rep(50 + (seq_len(n_subjects) %% 51L), each = n_records)
)
model <- nm_model(
  INPUT = names(data), ADVAN = 1L, DOSECMP = 1L, OBSCMP = 1L,
  PRED = "V=THETA(2); S1=V",
  ERROR = "Y=F+ERR(1)",
  THETAS = data.frame(
    THETA = 1:3, Value = c(2, 20, 0.75),
    FIX = c(FALSE, TRUE, FALSE)
  ),
  OMEGAS = data.frame(OMEGA = 1L, Value = 0.09, FIX = TRUE),
  SIGMAS = data.frame(SIGMA = 1L, Value = 0.2, FIX = TRUE),
  COVARIATES = "WT",
  MU = nm_mu(
    1L, "log(THETA(1))+THETA(3)*log(WT/70)", "CL",
    covariates = "WT"
  )
)
context <- LibeRation:::.nm_estimation_context_build(
  model, LibeRation:::.nm_engine_data(model, data), method = "SAEM"
)
specialization <- LibeRation:::.nm_mu_specialization(
  context, LibeRation:::.nm_outer_map(model)
)
theta <- model$THETAS$Value

r_mu_values <- function() {
  subject_data <- lapply(context$subjects, function(evaluator) {
    evaluator$project("WT", first_only = TRUE)
  })
  result <- matrix(0, context$n_subjects, context$n_eta)
  for (subject in seq_len(context$n_subjects)) {
    for (row in seq_along(specialization$expressions)) {
      result[subject, specialization$eta[[row]]] <-
        LibeRation:::.nm_mu_eval_scalar(
          specialization$expressions[[row]], subject_data[[subject]], theta,
          label = paste0("MU_", specialization$eta[[row]])
        )
    }
  }
  result
}

native_mu <- LibeRation:::.nm_mu_values(specialization, theta)
native_projection_count <- sum(vapply(
  context$subjects, function(evaluator) evaluator$data_projections, integer(1)
))
r_mu <- r_mu_values()
mu_difference <- max(abs(native_mu - r_mu))
native_mu_seconds <- system.time(for (index in seq_len(repetitions)) {
  native_mu <- LibeRation:::.nm_mu_values(specialization, theta)
})[["elapsed"]]
r_mu_seconds <- system.time(for (index in seq_len(repetitions)) {
  r_mu <- r_mu_values()
})[["elapsed"]]

native_counts <- LibeRation:::.nm_context_observation_counts(context)
r_counts <- vapply(context$subjects, function(evaluator) {
  length(evaluator$observation_data()$DV)
}, integer(1))
native_count_seconds <- system.time(for (index in seq_len(repetitions)) {
  native_counts <- LibeRation:::.nm_context_observation_counts(context)
})[["elapsed"]]
r_count_seconds <- system.time(for (index in seq_len(repetitions)) {
  r_counts <- vapply(context$subjects, function(evaluator) {
    length(evaluator$observation_data()$DV)
  }, integer(1))
})[["elapsed"]]

result <- data.frame(
  subjects = n_subjects,
  records_per_subject = n_records,
  repetitions = repetitions,
  native_mu_seconds = native_mu_seconds,
  r_projected_mu_seconds = r_mu_seconds,
  mu_speedup = r_mu_seconds / native_mu_seconds,
  mu_max_absolute_difference = mu_difference,
  native_observation_count_seconds = native_count_seconds,
  r_projected_observation_count_seconds = r_count_seconds,
  observation_count_speedup = r_count_seconds / native_count_seconds,
  observation_count_identical = identical(native_counts, r_counts),
  native_subject_frame_materializations = sum(vapply(
    context$subjects, function(evaluator) evaluator$data_materializations,
    integer(1)
  )),
  native_mu_projections_before_reference = native_projection_count,
  stringsAsFactors = FALSE
)
dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
utils::write.csv(result, output, row.names = FALSE)
print(result, row.names = FALSE)
cat("Written:", normalizePath(output, winslash = "/", mustWork = TRUE), "\n")
