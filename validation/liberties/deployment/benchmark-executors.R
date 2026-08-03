#!/usr/bin/env Rscript

# Compare LibeRties' trusted-local callr subprocess with the hardened systemd
# executor through the same queue, encrypted storage, job contract, package
# library, workload, and result-retrieval path.

if (!identical(Sys.info()[["sysname"]], "Linux")) {
  stop("This benchmark requires Linux with systemd (native or WSL 2).", call. = FALSE)
}
for (package in c("LibeRties", "LibeRation", "jsonlite")) {
  if (!requireNamespace(package, quietly = TRUE)) {
    stop(package, " must be installed before running the executor benchmark.", call. = FALSE)
  }
}

credential <- Sys.getenv("LIBERTIES_SYSTEMD_STORAGE_CREDENTIAL", unset = "")
if (!nzchar(credential) || !file.exists(credential)) {
  stop("Set LIBERTIES_SYSTEMD_STORAGE_CREDENTIAL to the protected storage-key file.", call. = FALSE)
}
storage_key <- trimws(readLines(credential, n = 1L, warn = FALSE))
if (!grepl("^[A-Fa-f0-9]{64}$", storage_key)) {
  stop("The storage credential is not a 256-bit hexadecimal key.", call. = FALSE)
}
old_key <- Sys.getenv("LIBERTIES_STORAGE_KEY", unset = NA_character_)
on.exit({
  if (is.na(old_key)) Sys.unsetenv("LIBERTIES_STORAGE_KEY") else
    Sys.setenv(LIBERTIES_STORAGE_KEY = old_key)
}, add = TRUE)
# The local callr worker inherits this value. The systemd launcher removes it
# from the unit environment and supplies the same key through LoadCredential.
Sys.setenv(LIBERTIES_STORAGE_KEY = storage_key)

profile <- match.arg(
  tolower(Sys.getenv("LIBERTIES_EXECUTOR_BENCHMARK_PROFILE", unset = "full")),
  c("quick", "full")
)
output_root <- Sys.getenv(
  "LIBERTIES_EXECUTOR_BENCHMARK_OUTPUT",
  unset = file.path(getwd(), "executor-benchmark-results")
)
dir.create(output_root, recursive = TRUE, showWarnings = FALSE)
output_root <- normalizePath(output_root, winslash = "/", mustWork = TRUE)

timestamp <- function(x) {
  suppressWarnings(as.POSIXct(
    as.character(x), format = "%Y-%m-%dT%H:%M:%OSZ", tz = "UTC"
  ))
}
elapsed <- function(start) unname(proc.time()[["elapsed"]] - start)
safe_numeric <- function(x) {
  value <- suppressWarnings(as.numeric(x))
  if (length(value) != 1L || !is.finite(value)) NA_real_ else value
}

model <- LibeRation::nm_model(
  INPUT = c("ID", "TIME", "EVID", "AMT", "DV", "MDV"),
  ADVAN = 2L, TRANS = 2L, DOSECMP = 1L, OBSCMP = 2L,
  PRED = paste(
    "CL=THETA(1)*exp(ETA(1))",
    "V=THETA(2)*exp(ETA(2))",
    "KA=THETA(3)",
    "S2=V", sep = ";"
  ),
  ERROR = "Y=F+ERR(1)",
  THETAS = data.frame(
    THETA = 1:3, Value = c(4, 40, 1.3),
    Lower = c(0.04, 0.4, 0.013), Upper = c(4000, 40000, 1300),
    FIX = c(FALSE, FALSE, TRUE)
  ),
  OMEGAS = data.frame(
    OMEGA = 1:2, Value = c(0.09, 0.04), FIX = c(TRUE, TRUE)
  ),
  SIGMAS = data.frame(SIGMA = 1L, Value = 0.04, FIX = TRUE)
)

oral_concentration <- function(time, dose, clearance, volume, ka = 1.3) {
  elimination <- clearance / volume
  dose / volume * ka / (ka - elimination) *
    (exp(-elimination * time) - exp(-ka * time))
}

simulation_data <- function(subjects, times) {
  do.call(rbind, lapply(seq_len(subjects), function(id) {
    data.frame(
      ID = id, TIME = c(0, times), EVID = c(1L, rep(0L, length(times))),
      AMT = c(100, rep(0, length(times))),
      DV = NA_real_, MDV = c(1L, rep(0L, length(times)))
    )
  }))
}

estimation_data <- function(subjects = 100L) {
  times <- c(0.5, 1, 2, 4, 8, 12, 24)
  do.call(rbind, lapply(seq_len(subjects), function(id) {
    clearance <- 4 * exp(0.18 * sin(id / 7))
    volume <- 40 * exp(0.12 * cos(id / 9))
    prediction <- oral_concentration(times, 100, clearance, volume)
    observation <- pmax(0.001, prediction + 0.025 * cos(times + id / 5))
    data.frame(
      ID = id, TIME = c(0, times), EVID = c(1L, rep(0L, length(times))),
      AMT = c(100, rep(0, length(times))),
      DV = c(NA_real_, observation), MDV = c(1L, rep(0L, length(times)))
    )
  }))
}

workloads <- list(
  tiny_simulation = list(
    repetitions = if (profile == "full") 10L else 4L,
    job = LibeRties::ls_job(
      "simulate", model, simulation_data(1L, c(1, 4)),
      arguments = list(nsim = 1L, n_cores = 1L, seed = 81001L),
      label = "executor benchmark: tiny simulation"
    )
  ),
  dense_simulation = list(
    repetitions = if (profile == "full") 6L else 3L,
    job = LibeRties::ls_job(
      "simulate", model, simulation_data(100L, seq(0.5, 24, by = 0.5)),
      arguments = list(nsim = 5L, n_cores = 2L, seed = 81002L),
      label = "executor benchmark: 100-subject dense simulation"
    )
  ),
  focei_estimation = list(
    repetitions = if (profile == "full") 4L else 2L,
    job = LibeRties::ls_job(
      "estimate", model, estimation_data(100L),
      arguments = list(
        method = "FOCEI", maxit = 4L, eta_maxit = 12L,
        tolerance = 1e-4, covariance = FALSE, n_cores = 1L,
        optimizer_backend = "r"
      ),
      label = "executor benchmark: 100-subject FOCEI estimation"
    )
  ),
  long_focei_estimation = list(
    repetitions = if (profile == "full") 6L else 1L,
    job = LibeRties::ls_job(
      "estimate", model, estimation_data(500L),
      arguments = list(
        method = "FOCEI", maxit = 6L, eta_maxit = 12L,
        tolerance = 1e-4, covariance = FALSE, n_cores = 1L,
        optimizer_backend = "r"
      ),
      label = "executor benchmark: 500-subject FOCEI estimation"
    )
  )
)

systemd_executor <- LibeRties::ls_systemd_executor(
  max_cores_per_job = 2L, storage_credential = credential
)
preflight_root <- tempfile("liberties-executor-preflight-", tmpdir = "/tmp")
on.exit(unlink(preflight_root, recursive = TRUE, force = TRUE), add = TRUE)
preflight <- LibeRties::ls_server_preflight(
  preflight_root, host = "127.0.0.1", behind_tls_proxy = TRUE,
  policy = LibeRties::ls_security_policy(production = TRUE),
  strict = TRUE, executor = systemd_executor
)

run_once <- function(executor_name, workload_name, repetition, order, job) {
  root <- tempfile(
    paste0("liberties-bench-", executor_name, "-"), tmpdir = "/tmp"
  )
  on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)
  executor <- if (executor_name == "systemd") systemd_executor else NULL
  queue <- LibeRties::ls_local_queue(
    root, max_workers = 1L,
    limits = list(
      max_runtime_seconds = 300, max_cpu_seconds = 1200,
      max_memory_mb = 4096, max_payload_mb = 64,
      max_result_mb = 256, max_storage_mb = 1024
    ),
    executor = executor
  )

  wall_started <- Sys.time()
  timer <- proc.time()[["elapsed"]]
  identifier <- queue$submit(job, start = FALSE)
  submit_seconds <- elapsed(timer)
  queue$poll(start = TRUE)
  dispatch_seconds <- elapsed(timer) - submit_seconds
  status <- queue$wait(identifier, timeout = 300, poll_interval = 0.02)
  if (!identical(status$status, "completed")) {
    stop(
      executor_name, " ", workload_name, " failed: ", status$error,
      call. = FALSE
    )
  }
  fetch_started <- proc.time()[["elapsed"]]
  result <- queue$result(identifier)
  result_fetch_seconds <- elapsed(fetch_started)
  total_seconds <- elapsed(timer)
  queue$poll(start = FALSE)

  submitted_at <- timestamp(status$submitted)
  started_at <- timestamp(status$started)
  finished_at <- timestamp(status$finished)
  queue_delay <- as.numeric(difftime(started_at, submitted_at, units = "secs"))
  worker_seconds <- as.numeric(difftime(finished_at, started_at, units = "secs"))
  core_seconds <- if (inherits(result, "nm_fit")) {
    safe_numeric(result$timing$total_seconds)
  } else NA_real_
  signature_values <- if (inherits(result, "nm_fit")) {
    c(result$objective, result$theta, result$omega, result$sigma)
  } else if (is.data.frame(result)) {
    c(
      nrow(result),
      sum(if ("IPRED" %in% names(result)) result$IPRED else 0, na.rm = TRUE),
      sum(if ("DV" %in% names(result)) result$DV else 0, na.rm = TRUE)
    )
  } else length(serialize(result, NULL, version = 3L))
  result_signature <- paste(
    format(signif(as.numeric(signature_values), 12L), scientific = TRUE),
    collapse = ":"
  )
  data.frame(
    workload = workload_name, repetition = repetition, order = order,
    executor = executor_name,
    total_seconds = total_seconds,
    submit_seconds = submit_seconds,
    dispatch_call_seconds = dispatch_seconds,
    queue_delay_seconds = queue_delay,
    worker_seconds = worker_seconds,
    orchestration_seconds = pmax(0, total_seconds - worker_seconds),
    result_fetch_seconds = result_fetch_seconds,
    engine_core_seconds = core_seconds,
    worker_wrapup_seconds = if (is.finite(core_seconds)) {
      pmax(0, worker_seconds - core_seconds)
    } else NA_real_,
    reported_cpu_seconds = safe_numeric(status$cpu_seconds),
    peak_memory_mb = safe_numeric(status$peak_memory_mb),
    result_bytes = safe_numeric(status$result_bytes),
    requested_cores = safe_numeric(status$requested_cores),
    isolation = as.character(status$isolation),
    systemd_profile = as.character(status$systemd_profile),
    result_signature = result_signature,
    wall_started = format(wall_started, "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC"),
    stringsAsFactors = FALSE
  )
}

cat("Warming page caches with one fresh process per executor...\n")
invisible(run_once(
  "callr", "warmup", 0L, 1L, workloads$tiny_simulation$job
))
invisible(run_once(
  "systemd", "warmup", 0L, 2L, workloads$tiny_simulation$job
))

records <- list()
for (workload_name in names(workloads)) {
  workload <- workloads[[workload_name]]
  cat("Benchmarking ", workload_name, " (", workload$repetitions,
      " paired repetitions)...\n", sep = "")
  for (repetition in seq_len(workload$repetitions)) {
    executor_order <- if (repetition %% 2L) {
      c("callr", "systemd")
    } else c("systemd", "callr")
    for (order in seq_along(executor_order)) {
      executor_name <- executor_order[[order]]
      cat("  ", repetition, "/", workload$repetitions, " ",
          executor_name, "\n", sep = "")
      records[[length(records) + 1L]] <- run_once(
        executor_name, workload_name, repetition, order, workload$job
      )
    }
  }
}
raw <- do.call(rbind, records)

pair_keys <- unique(raw[c("workload", "repetition")])
for (index in seq_len(nrow(pair_keys))) {
  pair <- raw[
    raw$workload == pair_keys$workload[[index]] &
      raw$repetition == pair_keys$repetition[[index]],
    , drop = FALSE
  ]
  if (nrow(pair) != 2L || length(unique(pair$result_signature)) != 1L) {
    stop(
      "Executor results were not scientifically equivalent for ",
      pair_keys$workload[[index]], " repetition ",
      pair_keys$repetition[[index]], ".",
      call. = FALSE
    )
  }
}

metrics <- c(
  "total_seconds", "queue_delay_seconds", "worker_seconds",
  "orchestration_seconds", "result_fetch_seconds", "engine_core_seconds",
  "worker_wrapup_seconds", "reported_cpu_seconds", "peak_memory_mb"
)
summary_rows <- list()
for (workload_name in unique(raw$workload)) {
  for (executor_name in c("callr", "systemd")) {
    subset <- raw[
      raw$workload == workload_name & raw$executor == executor_name,
      , drop = FALSE
    ]
    for (metric in metrics) {
      values <- subset[[metric]]
      values <- values[is.finite(values)]
      if (!length(values)) next
      summary_rows[[length(summary_rows) + 1L]] <- data.frame(
        workload = workload_name, executor = executor_name, metric = metric,
        n = length(values), mean = mean(values), median = stats::median(values),
        sd = if (length(values) > 1L) stats::sd(values) else NA_real_,
        minimum = min(values), p95 = unname(stats::quantile(values, 0.95)),
        maximum = max(values), stringsAsFactors = FALSE
      )
    }
  }
}
summary_table <- do.call(rbind, summary_rows)

comparison_rows <- list()
for (workload_name in unique(raw$workload)) {
  for (metric in c("total_seconds", "worker_seconds", "engine_core_seconds")) {
    medians <- summary_table[
      summary_table$workload == workload_name & summary_table$metric == metric,
      c("executor", "median"), drop = FALSE
    ]
    if (nrow(medians) != 2L) next
    callr_value <- medians$median[medians$executor == "callr"]
    systemd_value <- medians$median[medians$executor == "systemd"]
    paired <- merge(
      raw[raw$workload == workload_name & raw$executor == "callr",
          c("repetition", metric), drop = FALSE],
      raw[raw$workload == workload_name & raw$executor == "systemd",
          c("repetition", metric), drop = FALSE],
      by = "repetition", suffixes = c("_callr", "_systemd")
    )
    differences <- paired[[paste0(metric, "_systemd")]] -
      paired[[paste0(metric, "_callr")]]
    differences <- differences[is.finite(differences)]
    if (!length(differences)) next
    comparison_rows[[length(comparison_rows) + 1L]] <- data.frame(
      workload = workload_name, metric = metric,
      callr_median_seconds = callr_value,
      systemd_median_seconds = systemd_value,
      difference_of_medians_seconds = systemd_value - callr_value,
      paired_median_difference_seconds = stats::median(differences),
      paired_mean_difference_seconds = mean(differences),
      paired_minimum_difference_seconds = min(differences),
      paired_maximum_difference_seconds = max(differences),
      systemd_percent_change = 100 * (systemd_value / callr_value - 1),
      stringsAsFactors = FALSE
    )
  }
}
comparison <- do.call(rbind, comparison_rows)

environment <- list(
  schema = "liberties.executor-benchmark",
  version = 1L,
  checked = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC"),
  profile = profile,
  system = list(
    sysname = unname(Sys.info()[["sysname"]]),
    release = unname(Sys.info()[["release"]]),
    machine = unname(Sys.info()[["machine"]]),
    logical_cores = parallel::detectCores(logical = TRUE),
    r_version = R.version.string
  ),
  packages = as.list(vapply(
    c("LibeRties", "LibeRation", "LibeRtAD"),
    function(package) as.character(utils::packageVersion(package)),
    character(1)
  )),
  design = list(
    fresh_process_per_observation = TRUE,
    page_cache_warmup = TRUE,
    alternating_executor_order = TRUE,
    encrypted_storage_both_executors = TRUE,
    poll_interval_seconds = 0.02,
    systemd_preflight_ready = isTRUE(preflight$ready)
  )
)

utils::write.csv(raw, file.path(output_root, "raw.csv"), row.names = FALSE)
utils::write.csv(summary_table, file.path(output_root, "summary.csv"), row.names = FALSE)
utils::write.csv(comparison, file.path(output_root, "comparison.csv"), row.names = FALSE)
jsonlite::write_json(
  environment, file.path(output_root, "environment.json"),
  auto_unbox = TRUE, pretty = TRUE
)

format_table <- function(table) {
  header <- paste0("| ", paste(names(table), collapse = " | "), " |")
  rule <- paste0("| ", paste(rep("---", ncol(table)), collapse = " | "), " |")
  rows <- apply(table, 1L, function(row) {
    paste0("| ", paste(row, collapse = " | "), " |")
  })
  paste(c(header, rule, rows), collapse = "\n")
}
display <- comparison[comparison$metric %in% c(
  "total_seconds", "worker_seconds", "engine_core_seconds"
), , drop = FALSE]
numeric_columns <- vapply(display, is.numeric, logical(1))
display[numeric_columns] <- lapply(display[numeric_columns], function(x) {
  format(round(x, 4), nsmall = 4, trim = TRUE)
})
report <- c(
  "# LibeRties systemd versus callr executor benchmark",
  "",
  paste0("Run: ", environment$checked, "<br>"),
  paste0("Profile: `", profile, "`<br>"),
  paste0("R: ", R.version.string, "<br>"),
  paste0("Kernel: ", unname(Sys.info()[["release"]])),
  "",
  "Each observation is a new R worker. Both executors use the same typed job,",
  "durable queue, encrypted storage, installed libraries, result verification,",
  "and parent polling interval. Executor order alternates within each pair.",
  "The core time is LibeRation's internal fit time and is available only for",
  "the estimation workload.",
  "",
  format_table(display),
  "",
  "Positive differences mean systemd was slower; negative differences mean it",
  "was faster in this sample. Small sub-second differences should be interpreted",
  "as startup/polling noise unless they are stable across repetitions. These are",
  "descriptive local WSL measurements, not a cross-machine performance claim."
)
writeLines(report, file.path(output_root, "REPORT.md"), useBytes = TRUE)

cat("\nResults written to ", output_root, "\n", sep = "")
cat(paste(report, collapse = "\n"), "\n")
