args <- commandArgs(trailingOnly = TRUE)
`%||%` <- function(left, right) if (is.null(left)) right else left

script_arg <- grep("^--file=", commandArgs(), value = TRUE)
script_path <- if (length(script_arg)) {
  sub("^--file=", "", script_arg[[1L]])
} else {
  file.path("validation", "mu-referencing", "run-validation.R")
}
campaign_dir <- normalizePath(dirname(script_path), winslash = "/",
                              mustWork = TRUE)
root <- normalizePath(file.path(campaign_dir, "..", ".."), winslash = "/",
                      mustWork = TRUE)
source(file.path(root, "tools", "validation-runtime.R"), local = TRUE)

option_value <- function(name, default = NULL) {
  liber_validation_option(name, default, args = args)
}
split_option <- function(value) {
  liber_validation_split_option(value, uppercase = TRUE)
}
safe_number <- function(value) {
  value <- suppressWarnings(as.numeric(value))
  if (length(value) && is.finite(value[[1L]])) value[[1L]] else NA_real_
}
elapsed <- function() unname(proc.time()[["elapsed"]])

profile_name <- tolower(option_value("profile", "quick"))
profiles <- list(
  smoke = list(
    subjects = 8L, times = c(0.5, 2, 8, 24), maxit = 20L,
    eta_maxit = 40L, imp_samples = 20L, saem_iterations = 20L,
    saem_burn = 6L
  ),
  quick = list(
    subjects = 40L, times = c(0.5, 1, 2, 4, 8, 12, 24), maxit = 80L,
    eta_maxit = 100L, imp_samples = 80L, saem_iterations = 100L,
    saem_burn = 30L
  ),
  standard = list(
    subjects = 100L, times = c(0.5, 1, 2, 4, 8, 12, 24), maxit = 200L,
    eta_maxit = 150L, imp_samples = 200L, saem_iterations = 200L,
    saem_burn = 60L
  )
)
if (!profile_name %in% names(profiles)) {
  stop("Profile must be smoke, quick, or standard.", call. = FALSE)
}
profile <- profiles[[profile_name]]
profile$subjects <- as.integer(option_value("subjects", profile$subjects))

methods <- split_option(option_value("methods", "FOCEI,IMP,SAEM"))
supported_methods <- c("FOCEI", "IMP", "SAEM")
if (!length(methods) || any(!methods %in% supported_methods)) {
  stop("Methods must be a subset of FOCEI, IMP, and SAEM.", call. = FALSE)
}
repeats <- as.integer(option_value(
  "repeats", if (identical(profile_name, "standard")) 3L else 1L
))
warmups <- as.integer(option_value("warmups", 0L))
seed <- as.integer(option_value("seed", 20260727L))
if (!is.finite(repeats) || repeats < 1L ||
    !is.finite(warmups) || warmups < 0L) {
  stop("Repeats must be positive and warmups non-negative.", call. = FALSE)
}

stamp <- format(Sys.time(), "%Y%m%dT%H%M%S", tz = "UTC")
scenario_option <- tolower(option_value("scenario", "baseline-fixed"))
output <- liber_validation_output_directory(
  root, option_value("output"),
  file.path(
    campaign_dir, "results",
    paste0(stamp, "-", profile_name, "-", scenario_option)
  )
)
library_value <- option_value(
  "library", Sys.getenv("LIBER_VALIDATION_LIBRARY", "")
)
validation_runtime <- liber_validation_library(
  root, c("LibeRtAD", "LibeRation"), library = library_value,
  allow_release_library = identical(
    normalizePath(library_value, winslash = "/", mustWork = FALSE),
    normalizePath(
      liber_validation_dev_cache(root, "r-libraries", "release-build"),
      winslash = "/", mustWork = FALSE
    )
  )
)
suppressPackageStartupMessages(library(LibeRation))
liber_validation_assert_repository_hygiene(root)
source(file.path(campaign_dir, "scenarios.R"), local = TRUE)
scenario_name <- scenario_option
if (!scenario_name %in% mu_validation_scenario_names()) {
  stop(
    "Scenario must be one of: ",
    paste(mu_validation_scenario_names(), collapse = ", "), ".",
    call. = FALSE
  )
}

execute_path <- Sys.which("execute")
if (!nzchar(execute_path)) {
  stop("PsN execute is not available in PATH.", call. = FALSE)
}
configure_psn <- function() {
  if (.Platform$OS.type != "windows") {
    return(list(command = execute_path, prefix = character()))
  }
  script <- sub("[.]bat$", "", execute_path, ignore.case = TRUE)
  perl <- file.path(dirname(execute_path), "perl.exe")
  if (!file.exists(perl)) perl <- Sys.which("perl")
  if (!nzchar(perl) || !file.exists(script)) {
    stop("The Windows PsN Perl launcher could not be resolved.", call. = FALSE)
  }
  portable_root <- dirname(dirname(dirname(execute_path)))
  nonmem_paths <- c(
    file.path(portable_root, "nm_7.3.0_g", "run"),
    file.path(portable_root, "scripts"),
    file.path(portable_root, "Perl", "bin"),
    file.path(
      portable_root, "gfortran", "libexec", "gcc",
      "i586-pc-mingw32", "4.6.0"
    ),
    file.path(portable_root, "gfortran", "bin")
  )
  Sys.setenv(PATH = paste(c(nonmem_paths, Sys.getenv("PATH")), collapse = ";"))
  list(command = perl, prefix = shQuote(script))
}
psn <- configure_psn()
Sys.setenv(
  OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1",
  MKL_NUM_THREADS = "1", EIGEN_DONT_PARALLELIZE = "1"
)

scenario <- mu_validation_scenario(
  scenario_name, profile$subjects, profile$times, seed
)
models <- scenario$models
data <- scenario$data

fixture_dir <- file.path(output, "fixture")
control_dir <- file.path(output, "controls")
work_dir <- file.path(output, ".work")
dir.create(fixture_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(control_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(work_dir, recursive = TRUE, showWarnings = FALSE)
fixture_csv <- file.path(
  fixture_dir, paste0("mu-estimation-", scenario_name, ".csv")
)
utils::write.csv(data, fixture_csv, row.names = FALSE, na = ".")

nonmem_control <- function(method, parameterization) {
  mu_validation_nonmem_control(
    scenario, method, profile, seed, parameterization
  )
}
for (method in methods) {
  for (parameterization in c("conventional", "mu")) {
    writeLines(
      nonmem_control(method, parameterization),
      file.path(
        control_dir,
        paste0(tolower(method), "-", parameterization, ".mod")
      ),
      useBytes = TRUE
    )
  }
}

numeric_match <- function(lines, pattern) {
  line <- lines[grepl(pattern, lines, fixed = TRUE)]
  if (!length(line)) return(NA_real_)
  values <- regmatches(
    tail(line, 1L),
    gregexpr(
      "[-+]?[0-9]+(?:[.][0-9]*)?(?:[Ee][-+]?[0-9]+)?",
      tail(line, 1L), perl = TRUE
    )
  )[[1L]]
  if (!length(values)) NA_real_ else as.numeric(tail(values, 1L))
}
read_ext_final <- function(path) {
  lines <- readLines(path, warn = FALSE)
  headers <- grep("^[[:space:]]*ITERATION", lines)
  if (!length(headers)) stop("NONMEM extension has no ITERATION header.")
  header <- tail(headers, 1L)
  records <- lines[(header + 1L):length(lines)]
  records <- records[
    nzchar(trimws(records)) & !grepl("^TABLE", trimws(records))
  ]
  parsed <- utils::read.table(
    text = paste(c(lines[[header]], records), collapse = "\n"),
    header = TRUE, check.names = FALSE
  )
  final <- parsed[parsed$ITERATION == -1000000000, , drop = FALSE]
  if (!nrow(final)) final <- parsed[nrow(parsed), , drop = FALSE]
  field <- function(pattern) {
    column <- grep(pattern, names(final), value = TRUE)
    if (!length(column)) NA_real_ else safe_number(final[[column[[1L]]]][[1L]])
  }
  fields <- function(pattern) {
    columns <- grep(pattern, names(final), value = TRUE)
    if (!length(columns)) return(numeric())
    vapply(columns, function(column) {
      safe_number(final[[column]][[1L]])
    }, numeric(1))
  }
  omega_columns <- grep("^OMEGA", names(final), value = TRUE)
  omega <- vapply(seq_len(nrow(models$conventional$OMEGAS)), function(index) {
    row <- models$conventional$OMEGAS$ROW[[index]]
    column <- models$conventional$OMEGAS$COL[[index]]
    pattern <- paste0(
      "^OMEGA\\(\\s*", row, "\\s*,\\s*", column, "\\s*\\)$"
    )
    matched <- grep(pattern, omega_columns, value = TRUE, perl = TRUE)
    if (!length(matched) && length(omega_columns) ==
        nrow(models$conventional$OMEGAS)) {
      matched <- omega_columns[[index]]
    }
    if (!length(matched)) return(NA_real_)
    safe_number(final[[matched[[1L]]]][[1L]])
  }, numeric(1))
  list(
    objective = field("^(OBJ|OBJECTIVE)$"),
    theta = unname(fields("^THETA[0-9(]")),
    omega = omega,
    sigma = unname(fields("^SIGMA"))
  )
}
read_eta <- function(path) {
  table <- utils::read.table(path, skip = 1L, header = TRUE,
                             check.names = FALSE)
  eta_columns <- grep("^ETA", names(table), value = TRUE)
  if (!length(eta_columns)) stop("NONMEM table has no ETA column.")
  ids <- unique(table$ID)
  output <- vapply(eta_columns, function(column) {
    values <- tapply(
      table[[column]], table$ID, function(value) value[[1L]]
    )
    as.numeric(values[as.character(ids)])
  }, numeric(length(ids)))
  matrix(output, nrow = length(ids), ncol = length(eta_columns))
}
run_in_directory <- function(directory, expression) {
  old <- setwd(directory)
  on.exit(setwd(old), add = TRUE)
  force(expression)
}

empty_run <- function(engine, parameterization, specialization, method,
                      repetition, measured) {
  output <- data.frame(
    scenario = scenario_name,
    engine = engine, parameterization = parameterization,
    specialization = specialization, method = method,
    repetition = repetition, measured = measured, status = "error",
    error = "", subjects = profile$subjects, records = nrow(data),
    process_wall_seconds = NA_real_, core_seconds = NA_real_,
    startup_seconds = NA_real_, wrapup_seconds = NA_real_,
    objective = NA_real_, convergence = NA_integer_, iterations = NA_integer_,
    termination = "", objective_evaluations = NA_integer_,
    gradient_evaluations = NA_integer_, mu_enabled = FALSE,
    mu_active = FALSE, mu_reason = "", mu_recentered_mode_starts = 0L,
    mu_closed_form_updates = 0L, mu_closed_form_only_iterations = 0L,
    mu_gls_system_calls = 0L, mu_gls_cache_hits = 0L,
    mu_gls_cache_misses = 0L, mu_gls_vectorized = FALSE,
    mu_runtime_fallbacks = 0L,
    stringsAsFactors = FALSE
  )
  for (index in seq_len(nrow(models$conventional$THETAS))) {
    output[[paste0("theta", index)]] <- NA_real_
  }
  for (index in seq_len(nrow(models$conventional$OMEGAS))) {
    output[[paste0("omega", index)]] <- NA_real_
  }
  for (index in seq_len(nrow(models$conventional$SIGMAS))) {
    output[[paste0("sigma", index)]] <- NA_real_
  }
  output
}
runs <- list()
etas <- list()
append_result <- function(row, eta = matrix(numeric(), 0L, 0L)) {
  key <- paste(
    row$engine, row$parameterization, row$specialization, row$method,
    row$repetition, sep = "|"
  )
  runs[[key]] <<- row
  if (length(eta)) {
    eta <- as.matrix(eta)
    index <- expand.grid(
      subject = seq_len(nrow(eta)), eta = seq_len(ncol(eta))
    )
    etas[[key]] <<- data.frame(
      scenario = scenario_name,
      engine = row$engine, parameterization = row$parameterization,
      specialization = row$specialization, method = row$method,
      repetition = row$repetition, subject = index$subject,
      eta = index$eta, value = as.numeric(eta)
    )
  }
}

liberation_arguments <- function(method, specialization) {
  common <- list(
    maxit = profile$maxit, eta_maxit = profile$eta_maxit,
    tolerance = 1e-6, n_cores = 1L, covariance = FALSE,
    optimizer_backend = "auto", collect_output = FALSE
  )
  if (identical(method, "IMP")) {
    common <- c(common, list(
      n_imp = profile$imp_samples, seed = seed,
      mu_specialization = !identical(specialization, "disabled")
    ))
  }
  if (identical(method, "SAEM")) {
    common <- c(common, list(
      n_iter = profile$saem_iterations, burn = profile$saem_burn,
      mcmc_steps = 1L, mstep_maxit = 5L, seed = seed,
      mu_specialization = !identical(specialization, "disabled")
    ))
  }
  common
}
assign_parameter_vector <- function(row, prefix, values) {
  for (index in seq_along(values)) {
    field <- paste0(prefix, index)
    if (field %in% names(row)) row[[field]] <- safe_number(values[[index]])
  }
  row
}
run_liberation <- function(method, parameterization, specialization,
                           repetition, measured) {
  directory <- tempfile(
    paste0("liberation-", tolower(method), "-"), tmpdir = work_dir
  )
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(directory, recursive = TRUE, force = TRUE), add = TRUE)
  config <- list(
    model = models[[parameterization]], data = data, method = method,
    arguments = liberation_arguments(method, specialization),
    library_paths = unique(c(validation_runtime$path, .libPaths())),
    expected_versions = validation_runtime$expected
  )
  config_path <- file.path(directory, "config.rds")
  metrics_path <- file.path(directory, "metrics.rds")
  summary_path <- file.path(directory, "summary.rds")
  saveRDS(config, config_path, version = 3L)
  row <- empty_run(
    "LibeRation", parameterization, specialization, method,
    repetition, measured
  )
  started <- elapsed()
  status <- system2(
    file.path(
      R.home("bin"),
      if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"
    ),
    c(
      "--vanilla", shQuote(file.path(campaign_dir, "liberation-worker.R")),
      shQuote(config_path), shQuote(metrics_path), shQuote(summary_path)
    ),
    stdout = file.path(directory, "stdout.log"),
    stderr = file.path(directory, "stderr.log")
  )
  row$process_wall_seconds <- elapsed() - started
  if (!identical(status, 0L) || !file.exists(summary_path)) {
    details <- c(
      if (file.exists(file.path(directory, "stdout.log"))) {
        readLines(file.path(directory, "stdout.log"), warn = FALSE)
      },
      if (file.exists(file.path(directory, "stderr.log"))) {
        readLines(file.path(directory, "stderr.log"), warn = FALSE)
      }
    )
    row$error <- paste(c("R worker failed.", details), collapse = " ")
    return(list(row = row, eta = matrix(numeric(), 0L, 0L)))
  }
  summary <- readRDS(summary_path)
  metrics <- readRDS(metrics_path)
  row$status <- summary$status
  row$error <- summary$error
  row$core_seconds <- safe_number(metrics$core_seconds)
  row$startup_seconds <- safe_number(metrics$startup_seconds)
  row$wrapup_seconds <- safe_number(metrics$wrapup_seconds)
  row$objective <- safe_number(summary$objective)
  row$convergence <- as.integer(summary$convergence %||% NA_integer_)
  row$termination <- as.character(summary$termination %||% "")
  row$iterations <- as.integer(summary$iterations %||% NA_integer_)
  row <- assign_parameter_vector(row, "theta", summary$theta)
  row <- assign_parameter_vector(row, "omega", summary$omega)
  row <- assign_parameter_vector(row, "sigma", summary$sigma)
  for (field in c(
    "objective_evaluations", "gradient_evaluations", "mu_enabled",
    "mu_active", "mu_reason", "mu_recentered_mode_starts",
    "mu_closed_form_updates", "mu_closed_form_only_iterations",
    "mu_gls_system_calls", "mu_gls_cache_hits", "mu_gls_cache_misses",
    "mu_gls_vectorized", "mu_runtime_fallbacks"
  )) {
    row[[field]] <- summary[[field]]
  }
  list(row = row, eta = as.matrix(summary$eta))
}

run_nonmem <- function(method, parameterization, repetition, measured) {
  directory <- tempfile(
    paste0("nonmem-", tolower(method), "-"), tmpdir = work_dir
  )
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(directory, recursive = TRUE, force = TRUE), add = TRUE)
  utils::write.table(
    data, file.path(directory, "estimation.dat"), row.names = FALSE,
    col.names = FALSE, quote = FALSE, na = "."
  )
  writeLines(
    nonmem_control(method, parameterization),
    file.path(directory, "estimation.mod"), useBytes = TRUE
  )
  row <- empty_run(
    "NONMEM", parameterization, "native", method, repetition, measured
  )
  started <- elapsed()
  status <- run_in_directory(directory, system2(
    psn$command,
    c(psn$prefix, "-directory=psn-run", "estimation.mod"),
    stdout = file.path(directory, "stdout.log"),
    stderr = file.path(directory, "stderr.log")
  ))
  row$process_wall_seconds <- elapsed() - started
  listing <- file.path(directory, "psn-run", "NM_run1", "psn.lst")
  extension <- file.path(directory, "estimation.ext")
  table <- file.path(directory, "estimation.tab")
  if (!identical(status, 0L) || !file.exists(listing) ||
      !file.exists(extension) || !file.exists(table)) {
    details <- c(
      if (file.exists(file.path(directory, "stdout.log"))) {
        readLines(file.path(directory, "stdout.log"), warn = FALSE)
      },
      if (file.exists(file.path(directory, "stderr.log"))) {
        readLines(file.path(directory, "stderr.log"), warn = FALSE)
      }
    )
    row$error <- paste(c("PsN/NONMEM failed.", details), collapse = " ")
    return(list(row = row, eta = matrix(numeric(), 0L, 0L)))
  }
  lines <- readLines(listing, warn = FALSE)
  final <- read_ext_final(extension)
  row$status <- "ok"
  successful <- grepl(
    "MINIMIZATION SUCCESSFUL|ESTIMATION STEP WAS COMPLETED",
    lines, ignore.case = TRUE
  )
  row$convergence <- if (any(successful)) 0L else NA_integer_
  row$termination <- if (any(successful)) {
    trimws(tail(lines[successful], 1L))
  } else {
    "PsN/NONMEM completed without a recognized termination line"
  }
  row$core_seconds <- sum(c(
    numeric_match(lines, "Elapsed estimation time in seconds"),
    numeric_match(lines, "Elapsed covariance time in seconds")
  ), na.rm = TRUE)
  if (!is.finite(row$core_seconds) || row$core_seconds == 0) {
    row$core_seconds <- numeric_match(lines, "#CPUT: Total CPU Time in Seconds")
  }
  row$objective <- final$objective
  row <- assign_parameter_vector(row, "theta", final$theta)
  row <- assign_parameter_vector(row, "omega", final$omega)
  row <- assign_parameter_vector(row, "sigma", final$sigma)
  list(row = row, eta = read_eta(table))
}

variants <- list(
  list(engine = "NONMEM", parameterization = "conventional",
       specialization = "native"),
  list(engine = "NONMEM", parameterization = "mu",
       specialization = "native"),
  list(engine = "LibeRation", parameterization = "conventional",
       specialization = "ordinary"),
  list(engine = "LibeRation", parameterization = "mu",
       specialization = "enabled")
)
if (any(methods %in% c("IMP", "SAEM"))) {
  variants <- c(variants, list(list(
    engine = "LibeRation", parameterization = "mu",
    specialization = "disabled"
  )))
}

cat("MU comparison output:", output, "\n")
cat("Profile:", profile_name, "scenario:", scenario_name,
    "subjects:", profile$subjects,
    "records:", nrow(data), "methods:", paste(methods, collapse = ", "), "\n")
for (method in methods) {
  for (variant in variants) {
    if (identical(method, "FOCEI") &&
        identical(variant$specialization, "disabled")) next
    for (index in seq_len(warmups + repeats)) {
      measured <- index > warmups
      repetition <- if (measured) index - warmups else index - warmups - 1L
      cat(
        variant$engine, method, variant$parameterization,
        variant$specialization,
        if (measured) paste0("repeat ", repetition) else "warmup", "... "
      )
      result <- if (identical(variant$engine, "NONMEM")) {
        run_nonmem(method, variant$parameterization, repetition, measured)
      } else {
        run_liberation(
          method, variant$parameterization, variant$specialization,
          repetition, measured
        )
      }
      append_result(result$row, result$eta)
      cat(
        result$row$status,
        sprintf(
          " theta %.5g wall %.3fs core %.3fs\n",
          result$row$theta1, result$row$process_wall_seconds,
          result$row$core_seconds
        )
      )
    }
  }
}

run_frame <- do.call(rbind, runs)
row.names(run_frame) <- NULL
eta_frame <- if (length(etas)) do.call(rbind, etas) else data.frame()
measured_runs <- run_frame[run_frame$measured, , drop = FALSE]
measured_eta <- eta_frame[eta_frame$repetition > 0L, , drop = FALSE]

variant_key <- function(engine, parameterization, specialization) {
  paste(engine, parameterization, specialization, sep = "|")
}
comparison_definitions <- list(
  list(
    comparison = "NONMEM conventional vs MU",
    left = variant_key("NONMEM", "conventional", "native"),
    right = variant_key("NONMEM", "mu", "native"),
    type = "within"
  ),
  list(
    comparison = "LibeRation conventional vs MU specialized",
    left = variant_key("LibeRation", "conventional", "ordinary"),
    right = variant_key("LibeRation", "mu", "enabled"),
    type = "within"
  ),
  list(
    comparison = "LibeRation MU disabled vs specialized",
    left = variant_key("LibeRation", "mu", "disabled"),
    right = variant_key("LibeRation", "mu", "enabled"),
    type = "within"
  ),
  list(
    comparison = "NONMEM MU vs LibeRation MU specialized",
    left = variant_key("NONMEM", "mu", "native"),
    right = variant_key("LibeRation", "mu", "enabled"),
    type = "external"
  )
)
tolerances <- scenario$tolerances

parse_key <- function(key) strsplit(key, "|", fixed = TRUE)[[1L]]
maximum_parameter_relative_difference <- function(left, right, prefix, indices) {
  if (!length(indices)) return(NA_real_)
  fields <- paste0(prefix, indices)
  if (!all(fields %in% names(left)) || !all(fields %in% names(right))) {
    return(NA_real_)
  }
  left_value <- as.numeric(left[1L, fields, drop = TRUE])
  right_value <- as.numeric(right[1L, fields, drop = TRUE])
  max(
    abs(left_value - right_value) /
      pmax(abs(left_value), abs(right_value), 1e-8)
  )
}
parameter_passed <- function(value, tolerance, required) {
  if (!length(required)) return(TRUE)
  is.finite(value) && value <= tolerance
}
comparison_rows <- list()
for (definition in comparison_definitions) {
  left_key <- parse_key(definition$left)
  right_key <- parse_key(definition$right)
  for (method in methods) {
    if (identical(definition$comparison,
                  "LibeRation MU disabled vs specialized") &&
        identical(method, "FOCEI")) next
    for (repetition in seq_len(repeats)) {
      select_run <- function(key) {
        measured_runs[
          measured_runs$engine == key[[1L]] &
            measured_runs$parameterization == key[[2L]] &
            measured_runs$specialization == key[[3L]] &
            measured_runs$method == method &
            measured_runs$repetition == repetition,
          , drop = FALSE
        ]
      }
      left <- select_run(left_key)
      right <- select_run(right_key)
      left_eta <- measured_eta[
        measured_eta$engine == left_key[[1L]] &
          measured_eta$parameterization == left_key[[2L]] &
          measured_eta$specialization == left_key[[3L]] &
          measured_eta$method == method &
          measured_eta$repetition == repetition,
        , drop = FALSE
      ]
      right_eta <- measured_eta[
        measured_eta$engine == right_key[[1L]] &
          measured_eta$parameterization == right_key[[2L]] &
          measured_eta$specialization == right_key[[3L]] &
          measured_eta$method == method &
          measured_eta$repetition == repetition,
        , drop = FALSE
      ]
      tolerance <- tolerances[[definition$type]][[method]]
      execution_ok <- nrow(left) == 1L && nrow(right) == 1L &&
        identical(left$status[[1L]], "ok") &&
        identical(right$status[[1L]], "ok")
      theta_difference <- if (execution_ok) {
        maximum_parameter_relative_difference(
          left, right, "theta", scenario$compare$theta
        )
      } else NA_real_
      omega_difference <- if (execution_ok) {
        maximum_parameter_relative_difference(
          left, right, "omega", scenario$compare$omega
        )
      } else NA_real_
      sigma_difference <- if (execution_ok) {
        maximum_parameter_relative_difference(
          left, right, "sigma", scenario$compare$sigma
        )
      } else NA_real_
      eta_pairs <- if (execution_ok) {
        merge(
          left_eta[, c("subject", "eta", "value"), drop = FALSE],
          right_eta[, c("subject", "eta", "value"), drop = FALSE],
          by = c("subject", "eta"), suffixes = c("_left", "_right")
        )
      } else data.frame()
      eta_difference <- if (
        nrow(eta_pairs) == profile$subjects * scenario$n_eta
      ) {
        max(abs(eta_pairs$value_left - eta_pairs$value_right))
      } else NA_real_
      estimate_gate <- identical(definition$type, "external") ||
        identical(method, "FOCEI")
      estimates_passed <-
        parameter_passed(
          theta_difference, tolerance$theta, scenario$compare$theta
        ) &&
        parameter_passed(
          omega_difference, tolerance$omega, scenario$compare$omega
        ) &&
        parameter_passed(
          sigma_difference, tolerance$sigma, scenario$compare$sigma
        ) &&
        is.finite(eta_difference) &&
        eta_difference <= tolerance$eta
      comparison_rows[[length(comparison_rows) + 1L]] <- data.frame(
        scenario = scenario_name,
        comparison = definition$comparison, type = definition$type,
        method = method, repetition = repetition,
        execution_ok = execution_ok,
        gate_basis = if (estimate_gate) {
          "estimate and ETA agreement"
        } else {
          "descriptive finite-stochastic parameterization comparison"
        },
        left_theta1 = if (nrow(left)) left$theta1[[1L]] else NA_real_,
        right_theta1 = if (nrow(right)) right$theta1[[1L]] else NA_real_,
        maximum_theta_relative_difference = theta_difference,
        theta_relative_tolerance = tolerance$theta,
        maximum_omega_relative_difference = omega_difference,
        omega_relative_tolerance = tolerance$omega,
        maximum_sigma_relative_difference = sigma_difference,
        sigma_relative_tolerance = tolerance$sigma,
        maximum_eta_absolute_difference = eta_difference,
        eta_tolerance = tolerance$eta,
        objective_absolute_difference = if (execution_ok) {
          abs(left$objective[[1L]] - right$objective[[1L]])
        } else NA_real_,
        end_to_end_ratio_right_over_left = if (execution_ok) {
          right$process_wall_seconds[[1L]] / left$process_wall_seconds[[1L]]
        } else NA_real_,
        core_ratio_right_over_left = if (execution_ok) {
          right$core_seconds[[1L]] / left$core_seconds[[1L]]
        } else NA_real_,
        passed = execution_ok && (!estimate_gate || estimates_passed),
        stringsAsFactors = FALSE
      )
    }
  }
}
comparisons <- do.call(rbind, comparison_rows)

timings <- aggregate(
  cbind(process_wall_seconds, core_seconds) ~
    scenario + engine + parameterization + specialization + method,
  data = measured_runs, FUN = function(value) stats::median(value, na.rm = TRUE)
)
names(timings)[names(timings) == "process_wall_seconds"] <-
  "median_end_to_end_seconds"
names(timings)[names(timings) == "core_seconds"] <- "median_core_seconds"

coverage <- do.call(rbind, lapply(methods, function(method) {
  specialized <- measured_runs[
    measured_runs$engine == "LibeRation" &
      measured_runs$parameterization == "mu" &
      measured_runs$specialization == "enabled" &
      measured_runs$method == method,
    , drop = FALSE
  ]
  telemetry_ok <- if (identical(method, "IMP")) {
    nrow(specialized) == repeats &&
      all(specialized$mu_active) &&
      all(specialized$mu_recentered_mode_starts > 0L)
  } else if (identical(method, "SAEM")) {
    nrow(specialized) == repeats &&
      all(specialized$mu_active) &&
      all(specialized$mu_gls_vectorized) &&
      all(specialized$mu_closed_form_updates ==
            profile$saem_iterations) &&
      all(specialized$mu_closed_form_only_iterations ==
            profile$saem_iterations) &&
      all(specialized$mu_gls_system_calls == profile$saem_iterations) &&
      all(specialized$mu_runtime_fallbacks == 0L)
  } else {
    nrow(specialized) == repeats
  }
  data.frame(
    scenario = scenario_name,
    method = method,
    nonmem_conventional = sum(
      measured_runs$engine == "NONMEM" &
        measured_runs$parameterization == "conventional" &
        measured_runs$method == method &
        measured_runs$status == "ok"
    ),
    nonmem_mu = sum(
      measured_runs$engine == "NONMEM" &
        measured_runs$parameterization == "mu" &
        measured_runs$method == method &
        measured_runs$status == "ok"
    ),
    liberation_conventional = sum(
      measured_runs$engine == "LibeRation" &
        measured_runs$parameterization == "conventional" &
        measured_runs$method == method &
        measured_runs$status == "ok"
    ),
    liberation_mu_specialized = sum(
      measured_runs$engine == "LibeRation" &
        measured_runs$parameterization == "mu" &
        measured_runs$specialization == "enabled" &
        measured_runs$method == method &
        measured_runs$status == "ok"
    ),
    specialization_telemetry_passed = telemetry_ok,
    stringsAsFactors = FALSE
  )
}))

write_csv <- function(value, path) {
  temporary <- tempfile(".mu-evidence-", tmpdir = dirname(path), fileext = ".tmp")
  utils::write.csv(value, temporary, row.names = FALSE, na = "")
  if (!file.rename(temporary, path)) {
    unlink(temporary)
    stop("Unable to publish ", path, call. = FALSE)
  }
}
write_csv(run_frame, file.path(output, "runs.csv"))
write_csv(eta_frame, file.path(output, "eta-estimates.csv"))
write_csv(timings, file.path(output, "timings.csv"))

markdown_table <- function(frame) {
  if (!nrow(frame)) return("_No rows._")
  printable <- frame
  numeric <- vapply(printable, is.numeric, logical(1))
  printable[numeric] <- lapply(
    printable[numeric], function(value) format(value, digits = 5, trim = TRUE)
  )
  rows <- apply(printable, 1L, function(row) {
    paste0("| ", paste(row, collapse = " | "), " |")
  })
  c(
    paste0("| ", paste(names(printable), collapse = " | "), " |"),
    paste0("| ", paste(rep("---", ncol(printable)), collapse = " | "), " |"),
    rows
  )
}
all_passed <- all(comparisons$passed) &&
  all(coverage$specialization_telemetry_passed) &&
  all(measured_runs$status == "ok")
summary <- list(
  schema = "liber.mu-reference-comparison/1",
  passed = all_passed,
  profile = profile_name,
  scenario = scenario_name,
  scenario_description = scenario$description,
  methods = as.list(methods),
  subjects = profile$subjects,
  records = nrow(data),
  measured_repeats = repeats,
  warmups = warmups,
  comparison_checks = nrow(comparisons),
  comparison_failures = sum(!comparisons$passed),
  execution_failures = sum(measured_runs$status != "ok"),
  raw_nonmem_listings_retained = FALSE
)
report <- c(
  "# MU-referenced NONMEM comparison", "",
  "## Scope", "",
  paste0(
    "- Matched one-compartment IV-bolus ADVAN1/TRANS2 `",
    scenario_name, "` scenario with ",
    profile$subjects, " subjects and ", nrow(data), " records."
  ),
  paste0("- Design: ", scenario$description, "."),
  paste0("- Methods: ", paste(methods, collapse = ", "), "."),
  paste0(
    "- ", repeats, " measured fresh-process repetition(s), ",
    warmups, " unmeasured warm-up(s)."
  ),
  paste0(
    "- Compared free parameters: THETA ",
    paste(scenario$compare$theta, collapse = ","),
    if (length(scenario$compare$omega)) {
      paste0("; OMEGA ", paste(scenario$compare$omega, collapse = ","))
    } else "",
    if (length(scenario$compare$sigma)) {
      paste0("; SIGMA ", paste(scenario$compare$sigma, collapse = ","))
    } else "", "."
  ),
  "- Conventional and MU-referenced forms are algebraically equivalent at the individual-parameter level.",
  "- THETA, OMEGA, and SIGMA gates use maximum scale-aware relative differences; ETA gates use maximum absolute differences.",
  "- FOCEI within-engine and all external MU comparisons are numerical gates. Within-engine IMP/SAEM parameterization comparisons are descriptive because finite stochastic paths are not invariant to MU reparameterization.",
  "- Runtime is descriptive, not an acceptance criterion. End-to-end timing includes startup and wrap-up; core timing uses engine-reported estimation time.", "",
  "## Estimate and runtime comparisons", "",
  markdown_table(comparisons), "",
  "The timing ratios are right-hand variant divided by left-hand variant; values below 1 favour the right-hand variant.", "",
  "## Median timing", "",
  markdown_table(timings), "",
  "## Coverage and specialization telemetry", "",
  markdown_table(coverage), "",
  "## Result", "",
  if (all_passed) {
    "**PASS:** all execution, estimate/ETA agreement, and specialization telemetry checks passed."
  } else {
    paste0(
      "**NOT PASSED:** ", sum(!comparisons$passed),
      " comparison check(s) and ",
      sum(measured_runs$status != "ok"), " execution(s) failed."
    )
  },
  "",
  "## Evidence handling", "",
  "- NONMEM `.lst`, PsN run directories, stdout, stderr, and raw extension/table outputs were parsed in temporary per-run directories and deleted immediately.",
  "- Only generated controls, the synthetic fixture, and derived numerical evidence are retained.",
  "- Objective differences are reported descriptively because estimator-specific objective conventions and stochastic approximations are not identical.", ""
)
provenance <- liber_validation_provenance(
  root = root, packages = c("LibeRtAD", "LibeRation"),
  library = validation_runtime$path,
  inputs = c(
    file.path(root, "ecosystem.json"),
    file.path(campaign_dir, "run-validation.R"),
    file.path(campaign_dir, "liberation-worker.R"),
    file.path(campaign_dir, "scenarios.R"),
    fixture_csv,
    list.files(control_dir, full.names = TRUE)
  ),
  seeds = list(simulation = seed, estimators = seed),
  tolerances = tolerances,
  dependencies = c("jsonlite", "openssl"),
  metadata = list(
    profile = profile_name, profile_settings = profile,
    scenario = scenario_name, scenario_description = scenario$description,
    methods = as.list(methods), repeats = repeats, warmups = warmups,
    psn_execute = unname(execute_path), raw_nonmem_listings_retained = FALSE
  )
)
liber_validation_write_evidence(
  output, comparisons = comparisons, coverage = coverage,
  summary = summary, provenance = provenance, report = report
)

raw_listings <- list.files(output, pattern = "[.]lst$", recursive = TRUE,
                           full.names = TRUE, ignore.case = TRUE)
if (length(raw_listings)) {
  unlink(raw_listings, force = TRUE)
  stop("Raw NONMEM listings reached the evidence directory.", call. = FALSE)
}
if (dir.exists(work_dir)) unlink(work_dir, recursive = TRUE, force = TRUE)
cat("Completed. Report:", file.path(output, "REPORT.md"), "\n")
if (!all_passed) quit(save = "no", status = 1L)
