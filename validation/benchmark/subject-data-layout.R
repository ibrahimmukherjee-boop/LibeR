args <- commandArgs(trailingOnly = TRUE)
option_value <- function(name, default) {
  prefix <- paste0("--", name, "=")
  value <- args[startsWith(args, prefix)]
  if (length(value)) sub(prefix, "", tail(value, 1L), fixed = TRUE) else default
}

n_subjects <- as.integer(option_value("subjects", "2000"))
n_context_subjects <- as.integer(option_value("context-subjects", "500"))
n_records <- as.integer(option_value("records", "8"))
output <- option_value(
  "output",
  file.path("validation", "benchmark", "results", "subject-data-layout.csv")
)
if (anyNA(c(n_subjects, n_context_subjects, n_records)) ||
    n_subjects < 1L || n_context_subjects < 1L || n_records < 2L) {
  stop("Subject and record counts must be positive integers.", call. = FALSE)
}
n_context_subjects <- min(n_context_subjects, n_subjects)

library(LibeRation)
times <- seq(0, 24, length.out = n_records)
id <- rep(seq_len(n_subjects), each = n_records)
data <- data.frame(
  ID = id,
  TIME = rep(times, n_subjects),
  EVID = rep(c(1L, rep.int(0L, n_records - 1L)), n_subjects),
  AMT = rep(c(100, rep.int(0, n_records - 1L)), n_subjects),
  MDV = rep(c(1L, rep.int(0L, n_records - 1L)), n_subjects),
  DV = rep(c(NA_real_, exp(-0.1 * times[-1L]) * 5), n_subjects),
  WT = rep(50 + (seq_len(n_subjects) %% 51L), each = n_records),
  stringsAsFactors = FALSE
)
for (column in seq_len(9L)) {
  data[[paste0("COV", column)]] <- (id %% (column + 3L)) / (column + 3L)
}
model <- nm_model(
  INPUT = names(data), ADVAN = 1L, DOSECMP = 1L, OBSCMP = 1L,
  PRED = paste(
    "CL=THETA(1)*(WT/70)^THETA(3)*exp(ETA(1));",
    "V=THETA(2); S1=V"
  ),
  ERROR = "Y=F+ERR(1)",
  THETAS = data.frame(THETA = 1:3, Value = c(2, 20, 0.75), FIX = TRUE),
  OMEGAS = data.frame(OMEGA = 1L, Value = 0.09, FIX = TRUE),
  SIGMAS = data.frame(SIGMA = 1L, Value = 0.2, FIX = TRUE)
)
normalized <- LibeRation:::.nm_engine_data(model, data)

copied_elapsed <- system.time({
  copied <- lapply(
    seq_len(n_subjects),
    function(subject) LibeRation:::.nm_subject_data(normalized, subject)
  )
})[["elapsed"]]
copied_bytes <- as.numeric(object.size(copied))
rm(copied)
invisible(gc())

view_elapsed <- system.time({
  store <- LibeRation:::.nm_subject_store(normalized)
})[["elapsed"]]
descriptor_bytes <- as.numeric(object.size(list(
  subject_ids = store$subject_ids,
  starts = store$starts,
  lengths = store$lengths,
  pointer = store$pointer,
  metadata = store$metadata
)))
dataset_bytes <- as.numeric(object.size(normalized))

context_data <- normalized[normalized$.ID_INDEX <= n_context_subjects, , drop = FALSE]
old <- options(
  LibeRation.fo_context_cache = FALSE,
  LibeRation.fo_objective_tape_sharing = TRUE
)
on.exit(options(old), add = TRUE)
context_elapsed <- function(use_views) {
  options(LibeRation.subject_data_views = use_views)
  invisible(gc())
  elapsed <- system.time({
    context <- LibeRation:::.nm_estimation_context_build(
      model, context_data, method = "FO"
    )
  })[["elapsed"]]
  list(
    elapsed = elapsed,
    materializations = sum(vapply(
      context$subjects, function(evaluator) evaluator$data_materializations,
      integer(1)
    )),
    projections = sum(vapply(
      context$subjects, function(evaluator) evaluator$data_projections,
      integer(1)
    ))
  )
}
view_context_elapsed <- context_elapsed(TRUE)
copied_context_elapsed <- context_elapsed(FALSE)

result <- data.frame(
  subjects = n_subjects,
  records_per_subject = n_records,
  rows = nrow(normalized),
  input_dataset_bytes = dataset_bytes,
  copied_subject_payload_bytes = copied_bytes,
  native_view_descriptor_bytes = descriptor_bytes,
  incremental_memory_reduction_percent =
    100 * (1 - descriptor_bytes / copied_bytes),
  copied_split_seconds = copied_elapsed,
  shared_store_seconds = view_elapsed,
  context_subjects = n_context_subjects,
  copied_context_seconds = copied_context_elapsed$elapsed,
  native_view_context_seconds = view_context_elapsed$elapsed,
  context_speedup = copied_context_elapsed$elapsed / view_context_elapsed$elapsed,
  native_subject_frame_materializations = view_context_elapsed$materializations,
  native_minimal_projections = view_context_elapsed$projections,
  stringsAsFactors = FALSE
)
dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
utils::write.csv(result, output, row.names = FALSE)
print(result, row.names = FALSE)
cat("Written:", normalizePath(output, winslash = "/", mustWork = TRUE), "\n")
