args <- commandArgs(trailingOnly = TRUE)
`%||%` <- function(left, right) if (is.null(left)) right else left

script_arg <- grep("^--file=", commandArgs(), value = TRUE)
script_path <- if (length(script_arg)) sub("^--file=", "", script_arg[[1L]]) else
  file.path("validation", "benchmark", "benchmark.R")
benchmark_dir <- normalizePath(dirname(script_path), winslash = "/", mustWork = TRUE)
root <- normalizePath(file.path(benchmark_dir, "..", ".."), winslash = "/", mustWork = TRUE)
source(file.path(root, "tools", "validation-runtime.R"), local = TRUE)

option_value <- function(name, default = NULL) {
  liber_validation_option(name, default, args = args)
}
option_flag <- function(name, default = FALSE) {
  liber_validation_flag(name, default, args = args)
}
split_option <- function(value) {
  liber_validation_split_option(value, uppercase = TRUE)
}

validation_runtime <- liber_validation_library(
  root, c("LibeRtAD", "LibeRation"),
  library = option_value("library", Sys.getenv("LIBER_VALIDATION_LIBRARY", ""))
)
nlmixr2_library <- option_value(
  "nlmixr-library", Sys.getenv("LIBER_NLMIXR2_LIBRARY", "")
)
if (nzchar(nlmixr2_library)) {
  nlmixr2_library <- normalizePath(
    nlmixr2_library, winslash = "/", mustWork = TRUE
  )
  .libPaths(unique(c(nlmixr2_library, .libPaths())))
}

profile_name <- tolower(option_value("profile", "quick"))
scenario_name <- tolower(option_value("scenario", "iv-bolus"))
profiles <- list(
  smoke = list(subjects = 8L, times = c(0.5, 2, 8, 24), simulations = 5L,
               maxit = 30L, eta_maxit = 60L, imp_samples = 20L,
               saem_iterations = 20L, saem_burn = 6L,
               bayes_burn = 50L, bayes_samples = 100L, bayes_thin = 1L),
  quick = list(subjects = 20L, times = c(0.5, 1, 2, 4, 8, 12, 24), simulations = 25L,
               maxit = 80L, eta_maxit = 100L, imp_samples = 50L,
               saem_iterations = 60L, saem_burn = 20L,
               bayes_burn = 200L, bayes_samples = 500L, bayes_thin = 1L),
  standard = list(subjects = 100L, times = c(0.5, 1, 2, 4, 8, 12, 24), simulations = 100L,
                  maxit = 200L, eta_maxit = 150L, imp_samples = 200L,
                  saem_iterations = 200L, saem_burn = 60L,
                  bayes_burn = 1000L, bayes_samples = 2000L, bayes_thin = 1L),
  large = list(subjects = 1000L, times = c(0.5, 1, 2, 4, 8, 12, 24),
               simulations = 100L, maxit = 100L, eta_maxit = 120L,
               imp_samples = 100L, saem_iterations = 100L, saem_burn = 30L,
               bayes_burn = 500L, bayes_samples = 1000L, bayes_thin = 1L),
  `very-large` = list(subjects = 5000L, times = c(1, 4, 12, 24),
                      simulations = 25L, maxit = 50L, eta_maxit = 80L,
                      imp_samples = 50L, saem_iterations = 60L, saem_burn = 20L,
                      bayes_burn = 250L, bayes_samples = 500L, bayes_thin = 1L)
)
if (!profile_name %in% names(profiles)) {
  stop("Unknown profile. Use smoke, quick, standard, large, or very-large.",
       call. = FALSE)
}
profile <- profiles[[profile_name]]
profile$subjects <- as.integer(option_value("subjects", profile$subjects))
profile$simulations <- as.integer(option_value("simulations", profile$simulations))
liberation_numerical_mode <- tolower(option_value(
  "numerical-mode", "nonmem_compatibility"
))
if (identical(liberation_numerical_mode, "liber_optimised")) {
  liberation_numerical_mode <- "liber_optimized"
}
if (!liberation_numerical_mode %in%
    c("nonmem_compatibility", "liber_optimized")) {
  stop(
    "Numerical mode must be nonmem_compatibility or liber_optimized.",
    call. = FALSE
  )
}
matched_controls <- list(
  profile = "matched",
  outer_budget = as.integer(profile$maxit),
  eta_budget = as.integer(profile$eta_maxit),
  tolerance = 1e-6,
  significant_digits = 6L,
  derivative_digits = 8L,
  imp_iterations = as.integer(profile$maxit),
  imp_samples = as.integer(profile$imp_samples),
  saem_burn = as.integer(profile$saem_burn),
  saem_stationary = as.integer(profile$saem_iterations),
  saem_total = as.integer(profile$saem_burn + profile$saem_iterations),
  saem_samples_per_iteration = 2L,
  bayes_burn = as.integer(profile$bayes_burn),
  bayes_samples = as.integer(profile$bayes_samples),
  bayes_thin = as.integer(profile$bayes_thin),
  liberation_numerical_mode = liberation_numerical_mode,
  saem_kernel = tolower(option_value("saem-kernel", "auto")),
  fsaem_refresh = as.integer(option_value("fsaem-refresh", 25L)),
  fsaem_rescue_probability = as.numeric(option_value(
    "fsaem-rescue-probability", 0.1
  )),
  fsaem_parameter_refresh = as.numeric(option_value(
    "fsaem-parameter-refresh", 0.15
  )),
  fsaem_low_acceptance = as.numeric(option_value(
    "fsaem-low-acceptance", 0.1
  )),
  bayes_outer_kernel = tolower(option_value("bayes-outer-kernel", "auto")),
  bayes_adaptive_start = as.integer(option_value("bayes-adaptive-start", 50L)),
  bayes_adaptive_interval = as.integer(option_value(
    "bayes-adaptive-interval", 10L
  ))
)
if (!matched_controls$saem_kernel %in% c("auto", "random_walk", "fsaem")) {
  stop("SAEM kernel must be auto, random_walk, or fsaem.", call. = FALSE)
}
if (!matched_controls$bayes_outer_kernel %in%
    c("auto", "isotropic", "adaptive_metropolis")) {
  stop(
    "BAYES outer kernel must be auto, isotropic, or adaptive_metropolis.",
    call. = FALSE
  )
}
if (is.na(matched_controls$fsaem_refresh) ||
    matched_controls$fsaem_refresh < 1L ||
    is.na(matched_controls$bayes_adaptive_start) ||
    matched_controls$bayes_adaptive_start < 2L ||
    is.na(matched_controls$bayes_adaptive_interval) ||
    matched_controls$bayes_adaptive_interval < 1L ||
    !is.finite(matched_controls$fsaem_rescue_probability) ||
    matched_controls$fsaem_rescue_probability < 0 ||
    matched_controls$fsaem_rescue_probability >= 1 ||
    !is.finite(matched_controls$fsaem_parameter_refresh) ||
    matched_controls$fsaem_parameter_refresh <= 0 ||
    !is.finite(matched_controls$fsaem_low_acceptance) ||
    matched_controls$fsaem_low_acceptance < 0 ||
    matched_controls$fsaem_low_acceptance >= 1) {
  stop("Stochastic kernel intervals and adaptive thresholds are invalid.",
       call. = FALSE)
}

method_alias <- tolower(option_value("methods", "deterministic"))
methods <- if (identical(method_alias, "deterministic")) {
  c("FO", "FOCE", "FOCEI", "LAPLACE")
} else if (identical(method_alias, "all")) {
  c("FO", "FOCE", "FOCEI", "LAPLACE", "ITS", "IMP", "SAEM", "BAYES")
} else split_option(method_alias)
supported_methods <- c(
  "FO", "FOCE", "FOCEI", "LAPLACE", "ITS", "IMP", "SAEM", "BAYES"
)
nlmixr2_supported_methods <- c(
  "FO", "FOCE", "FOCEI", "LAPLACE", "IMP", "SAEM"
)
if (!length(methods) || any(!methods %in% supported_methods)) {
  stop("Methods must be deterministic, all, or a comma-separated subset of ",
       paste(supported_methods, collapse = ", "), ".", call. = FALSE)
}
nlmixr2_run_methods <- split_option(option_value(
  "nlmixr-methods", paste(nlmixr2_supported_methods, collapse = ",")
))
if (any(!nlmixr2_run_methods %in% nlmixr2_supported_methods)) {
  stop(
    "nlmixr2 methods must be a subset of: ",
    paste(nlmixr2_supported_methods, collapse = ", "), ".", call. = FALSE
  )
}
engines <- split_option(option_value("engines", "NONMEM,LIBERATION,NLMIXR2"))
if (any(!engines %in% c("NONMEM", "LIBERATION", "NLMIXR2"))) {
  stop(
    "Engines must contain NONMEM, LIBERATION, and/or NLMIXR2.",
    call. = FALSE
  )
}
repeats <- as.integer(option_value("repeats", if (profile_name == "smoke") 1L else 3L))
warmups <- as.integer(option_value("warmups", 1L))
if (is.na(repeats) || repeats < 1L || is.na(warmups) || warmups < 0L) {
  stop("Repeats must be positive and warmups non-negative.", call. = FALSE)
}
include_covariance <- option_flag("covariance", TRUE)
run_simulation <- option_flag("simulation", TRUE)
resume <- option_flag("resume", FALSE)
seed <- as.integer(option_value("seed", 20260714L))
optimizer_backend <- tolower(option_value("optimizer", "auto"))
if (!optimizer_backend %in% c("auto", "native", "r")) {
  stop("Optimizer must be auto, native, or r.", call. = FALSE)
}
population_objective <- tolower(option_value("population-objective", "cpp"))
if (!population_objective %in% c("cpp", "r")) {
  stop("Population objective must be cpp or r.", call. = FALSE)
}

if (!requireNamespace("LibeRation", quietly = TRUE)) {
  stop("Install LibeRation before running the benchmark.", call. = FALSE)
}
nlmixr2_packages <- c("nlmixr2", "nlmixr2est", "rxode2")
if ("NLMIXR2" %in% engines) {
  missing_nlmixr2 <- nlmixr2_packages[!vapply(
    nlmixr2_packages, requireNamespace, logical(1), quietly = TRUE
  )]
  if (length(missing_nlmixr2)) {
    stop(
      "The NLMIXR2 benchmark engine requires: ",
      paste(missing_nlmixr2, collapse = ", "), ".", call. = FALSE
    )
  }
}
source(file.path(benchmark_dir, "scenarios.R"), local = TRUE)
if (!scenario_name %in% benchmark_scenario_names()) {
  stop(
    "Unknown scenario. Use one of: ",
    paste(benchmark_scenario_names(), collapse = ", "), ".", call. = FALSE
  )
}
execute_path <- Sys.which("execute")
if ("NONMEM" %in% engines && !nzchar(execute_path)) {
  stop("PsN execute is not available in PATH.", call. = FALSE)
}

stamp <- format(Sys.time(), "%Y%m%dT%H%M%S", tz = "UTC")
output_root <- option_value(
  "output",
  file.path(
    benchmark_dir, "results",
    paste0(stamp, "-", profile_name, "-", scenario_name)
  )
)
output_root <- normalizePath(output_root, winslash = "/", mustWork = FALSE)
dir.create(output_root, recursive = TRUE, showWarnings = FALSE)
raw_path <- file.path(output_root, "raw-results.csv")
timing_comparison_path <- file.path(output_root, "paired-timing-comparison.csv")
engine_comparison_path <- file.path(output_root, "engine-timing-comparison.csv")
parameter_comparison_path <- file.path(output_root, "parameter-comparison.csv")
parameter_estimates_path <- file.path(output_root, "parameter-estimates.csv")

elapsed <- function() unname(proc.time()[["elapsed"]])
numeric_match <- function(lines, pattern) {
  line <- grep(pattern, lines, ignore.case = TRUE, value = TRUE)
  if (!length(line)) return(NA_real_)
  values <- regmatches(
    tail(line, 1L),
    gregexpr("[-+]?[0-9]+(?:[.][0-9]*)?(?:[Ee][-+]?[0-9]+)?", tail(line, 1L),
             perl = TRUE)
  )[[1L]]
  if (!length(values)) NA_real_ else as.numeric(tail(values, 1L))
}
safe_number <- function(value) {
  value <- suppressWarnings(as.numeric(value))
  if (length(value) && is.finite(value[[1L]])) value[[1L]] else NA_real_
}

scenario <- benchmark_scenario(
  scenario_name, profile$subjects, profile$times, seed
)
data <- scenario$data
model <- scenario$model
nonmem_model <- scenario$nonmem_model %||% model
comparison_mapping <- scenario$comparison_mapping %||% "direct"
if ("NONMEM" %in% engines && !isTRUE(scenario$nonmem_supported)) {
  stop(
    "Scenario '", scenario_name,
    "' is currently native-only because its expanded ETA layout has no direct matched control stream. ",
    "Use --engines=LIBERATION.", call. = FALSE
  )
}

# BAYES uses a dedicated posterior target. Each free THETA receives the same
# proper normal prior in both engines, while OMEGA and SIGMA are fixed. This
# avoids comparing NONMEM's NWPRI defaults with a different LibeRation prior,
# or conflating scalar inverse-gamma and matrix inverse-Wishart conventions.
bayes_model <- model
bayes_nonmem_model <- nonmem_model
bayes_prior_mean <- as.numeric(model$THETAS$Value)
bayes_prior_sd <- pmax(abs(bayes_prior_mean) * 0.5, 0.5)
bayes_priors <- do.call(rbind, lapply(seq_along(bayes_prior_mean), function(index) {
  LibeRation::nm_prior(
    paste0("THETA", index), distribution = "normal",
    mean = bayes_prior_mean[[index]], sd = bayes_prior_sd[[index]]
  )
}))
bayes_model$LIK_CONFIG$priors <- bayes_priors
bayes_model$OMEGAS$FIX[] <- TRUE
bayes_model$SIGMAS$FIX[] <- TRUE
bayes_nonmem_model$OMEGAS$FIX[] <- TRUE
bayes_nonmem_model$SIGMAS$FIX[] <- TRUE

benchmark_model <- function(
    method, engine = c("liberation", "nonmem", "nlmixr2")) {
  engine <- match.arg(engine)
  if (!identical(method, "BAYES")) {
    return(if (identical(engine, "nonmem")) nonmem_model else model)
  }
  if (identical(engine, "nonmem")) bayes_nonmem_model else bayes_model
}

nonmem_bayes_prior_records <- function() {
  n_theta <- length(bayes_prior_mean)
  covariance <- diag(bayes_prior_sd^2, n_theta, n_theta)
  covariance_rows <- vapply(seq_len(n_theta), function(row) {
    values <- vapply(seq_len(row), function(column) {
      format(
        covariance[row, column], digits = 15L,
        scientific = FALSE, trim = TRUE
      )
    }, character(1))
    if (row == 1L) values[[1L]] <- paste(values[[1L]], "FIX")
    paste(" ", paste(values, collapse = " "))
  }, character(1))
  c(
    "$PRIOR NWPRI",
    paste(
      "$THETAP",
      paste0(
        "(",
        format(
          bayes_prior_mean, digits = 15L,
          scientific = FALSE, trim = TRUE
        ),
        " FIX)"
      ),
      collapse = " "
    ),
    if (n_theta == 1L) {
      paste("$THETAPV", covariance_rows[[1L]])
    } else {
      c(paste0("$THETAPV BLOCK(", n_theta, ")"), covariance_rows)
    }
  )
}

fixture_dir <- file.path(output_root, "fixture")
dir.create(fixture_dir, recursive = TRUE, showWarnings = FALSE)
utils::write.table(
  data, file.path(fixture_dir, "benchmark.dat"), row.names = FALSE,
  col.names = FALSE, quote = FALSE, na = "."
)
saveRDS(
  list(
    model = model, nonmem_model = nonmem_model,
    bayes_model = bayes_model, bayes_nonmem_model = bayes_nonmem_model,
    bayes_priors = bayes_priors, data = data
  ),
  file.path(fixture_dir, "fixture.rds"), version = 3L
)
git_state <- liber_validation_git(root)
validation_provenance <- liber_validation_provenance(
  root = root, packages = c("LibeRtAD", "LibeRation"),
  library = validation_runtime$path,
  inputs = c(
    file.path(root, "ecosystem.json"),
    file.path(benchmark_dir, "benchmark.R"),
    file.path(benchmark_dir, "liberation-worker.R"),
    file.path(benchmark_dir, "nlmixr2-worker.R"),
    file.path(benchmark_dir, "scenarios.R"),
    file.path(fixture_dir, "benchmark.dat"),
    file.path(fixture_dir, "fixture.rds")
  ),
  seeds = list(simulation = seed),
  tolerances = list(estimation = matched_controls$tolerance),
  dependencies = c(
    "Rcpp", "jsonlite", "openssl",
    if ("NLMIXR2" %in% engines) nlmixr2_packages else character()
  ),
  metadata = list(
    profile = profile_name, scenario = scenario_name, methods = as.list(methods),
    engines = as.list(engines), repeats = repeats, warmups = warmups,
    covariance = include_covariance, simulation = run_simulation,
    optimizer_backend = optimizer_backend, population_objective = population_objective,
    controls = matched_controls,
    bayes_prior = list(
      family = "normal", mean = as.list(bayes_prior_mean),
      sd = as.list(bayes_prior_sd), omega_fixed = TRUE, sigma_fixed = TRUE,
      burn = profile$bayes_burn, samples = profile$bayes_samples,
      thin = profile$bayes_thin
    )
  ),
  output = file.path(output_root, "provenance.json")
)

method_covariance <- function(method) {
  isTRUE(include_covariance) && method %in% c(
    "FO", "FOCE", "FOCEI", "LAPLACE", "ITS", "GQ", "IMP", "SAEM"
  )
}
liberation_arguments <- function(method) {
  common <- list(
    method = method, maxit = matched_controls$outer_budget,
    eta_maxit = matched_controls$eta_budget,
    tolerance = matched_controls$tolerance, n_cores = 1L,
    numerical_mode = matched_controls$liberation_numerical_mode,
    covariance = method_covariance(method),
    covariance_type = "hessian", optimizer_backend = optimizer_backend
  )
  if (method == "IMP") common <- c(common, list(
    n_imp = matched_controls$imp_samples, seed = seed
  ))
  if (method == "SAEM") common <- c(common, list(
    n_iter = matched_controls$saem_total,
    burn = matched_controls$saem_burn,
    mcmc_steps = matched_controls$saem_samples_per_iteration,
    mstep_maxit = 5L, seed = seed,
    saem_kernel = matched_controls$saem_kernel,
    fsaem_refresh = matched_controls$fsaem_refresh,
    fsaem_rescue_probability = matched_controls$fsaem_rescue_probability,
    fsaem_parameter_refresh = matched_controls$fsaem_parameter_refresh,
    fsaem_low_acceptance = matched_controls$fsaem_low_acceptance
  ))
  if (method == "BAYES") common <- c(common, list(
    n_burn = matched_controls$bayes_burn,
    n_sample = matched_controls$bayes_samples,
    n_thin = matched_controls$bayes_thin, seed = seed,
    outer_kernel = matched_controls$bayes_outer_kernel,
    adaptive_start = matched_controls$bayes_adaptive_start,
    adaptive_interval = matched_controls$bayes_adaptive_interval
  ))
  common
}
nonmem_estimation_record <- function(method) {
  switch(
    method,
    FO = sprintf(
      "$ESTIMATION METHOD=0 POSTHOC MAXEVAL=%d NOABORT SIGL=%d NSIG=%d PRINT=0 NOPRIOR=1",
      matched_controls$outer_budget, matched_controls$derivative_digits,
      matched_controls$significant_digits
    ),
    FOCE = sprintf(
      "$ESTIMATION METHOD=COND MAXEVAL=%d NOABORT SIGL=%d NSIG=%d PRINT=0 NOPRIOR=1",
      matched_controls$outer_budget, matched_controls$derivative_digits,
      matched_controls$significant_digits
    ),
    FOCEI = sprintf(
      paste0(
        "$ESTIMATION METHOD=COND INTERACTION MAXEVAL=%d NOABORT ",
        "SIGL=%d NSIG=%d PRINT=0 NOPRIOR=1"
      ),
      matched_controls$outer_budget, matched_controls$derivative_digits,
      matched_controls$significant_digits
    ),
    LAPLACE = sprintf(
      paste0(
        "$ESTIMATION METHOD=COND INTERACTION LAPLACIAN MAXEVAL=%d NOABORT ",
        "SIGL=%d NSIG=%d PRINT=0 NOPRIOR=1"
      ),
      matched_controls$outer_budget, matched_controls$derivative_digits,
      matched_controls$significant_digits
    ),
    ITS = sprintf(
      "$ESTIMATION METHOD=ITS INTERACTION NITER=%d CTYPE=0 PRINT=0 NOPRIOR=1 SEED=%d",
      matched_controls$outer_budget, seed
    ),
    IMP = sprintf(
      paste0(
        "$ESTIMATION METHOD=IMP INTERACTION NITER=%d ISAMPLE=%d ",
        "CTYPE=0 PRINT=0 NOPRIOR=1 SEED=%d"
      ),
      matched_controls$imp_iterations, matched_controls$imp_samples, seed
    ),
    SAEM = sprintf(
      paste0(
        "$ESTIMATION METHOD=SAEM INTERACTION NBURN=%d NITER=%d ISAMPLE=%d ",
        "CTYPE=0 PRINT=0 NOPRIOR=1 SEED=%d"
      ),
      matched_controls$saem_burn, matched_controls$saem_stationary,
      matched_controls$saem_samples_per_iteration, seed
    ),
    BAYES = sprintf(
      paste0(
        "$ESTIMATION METHOD=BAYES INTERACTION NBURN=%d NITER=%d ",
        "PRINT=0 NOABORT NOPRIOR=0 SEED=%d FILE=benchmark.ext"
      ),
      matched_controls$bayes_burn, matched_controls$bayes_samples, seed
    )
  )
}
nonmem_control <- function(workload, method = "SIMULATION") {
  estimation_options <- if (workload == "estimation") {
    sub("^[$]ESTIMATION[[:space:]]+", "", nonmem_estimation_record(method))
  } else NULL
  method_model <- benchmark_model(method, "nonmem")
  control_text <- LibeRation::nm_control_write(
    method_model, data = "benchmark.dat IGNORE=@",
    estimation = estimation_options,
    covariance = if (workload == "estimation" && method_covariance(method)) {
      paste0(
        "MATRIX=R PRINT=E SIGL=", matched_controls$derivative_digits
      )
    } else FALSE
  )
  dde_control <- grepl("(?m)^;DDE[[:space:]]*$", control_text, perl = TRUE)
  if (dde_control) {
    control_text <- sub("^;DDE[[:space:]]*\\r?\\n", "", control_text, perl = TRUE)
  }
  control_text <- gsub(";", "\n  ", control_text, fixed = TRUE)
  records <- strsplit(control_text, "\n", fixed = TRUE)[[1L]]
  subroutine_record <- grep("^[$]SUBROUTINES", trimws(records))
  if (method_model$ADVAN %in% c(6L, 13L) && length(subroutine_record) == 1L &&
      !grepl("TOL[[:space:]]*=", records[[subroutine_record]], ignore.case = TRUE)) {
    records[[subroutine_record]] <- paste(records[[subroutine_record]], "TOL=9")
  }
  error_record <- match("$ERROR", trimws(records))
  if (!is.na(error_record) && !any(grepl("^[[:space:]]*IPRED[[:space:]]*=", records))) {
    records <- append(records, "  IPRED=F", after = error_record)
  }
  problem_record <- grep("^[$]PROBLEM", trimws(records))[[1L]]
  records[[problem_record]] <- paste(
    "$PROBLEM LibeR benchmark", scenario_name, workload, method
  )
  if (workload == "estimation" && identical(method, "BAYES")) {
    estimation_record <- grep("^[$]ESTIMATION", trimws(records))[[1L]]
    records <- append(
      records, nonmem_bayes_prior_records(), after = estimation_record - 1L
    )
  }
  if (dde_control) records <- c(";DDE", records)
  if (workload == "estimation") {
    records <- c(records,
      "$TABLE ID TIME EVID IPRED ETA(1) NOPRINT ONEHEADER FORMAT=s1PE15.8 FILE=benchmark.tab")
  } else {
    records <- c(
      records,
      sprintf("$SIMULATION (%d) ONLYSIM SUBPROBLEMS=%d", seed, profile$simulations),
      "$TABLE ID TIME EVID DV IPRED ETA(1) NOPRINT ONEHEADER FORMAT=s1PE15.8 FILE=benchmark.tab"
    )
  }
  paste(records, collapse = "\n")
}

copy_fixture <- function(directory) {
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  file.copy(file.path(fixture_dir, "benchmark.dat"),
            file.path(directory, "benchmark.dat"), overwrite = TRUE)
}
run_in_directory <- function(directory, expression) {
  old <- setwd(directory)
  on.exit(setwd(old), add = TRUE)
  force(expression)
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
    file.path(portable_root, "scripts"), file.path(portable_root, "Perl", "bin"),
    file.path(portable_root, "gfortran", "libexec", "gcc", "i586-pc-mingw32", "4.6.0"),
    file.path(portable_root, "gfortran", "bin")
  )
  Sys.setenv(PATH = paste(c(nonmem_paths, Sys.getenv("PATH")), collapse = ";"))
  list(command = perl, prefix = shQuote(script))
}
psn <- if ("NONMEM" %in% engines) configure_psn() else NULL

read_ext_final <- function(path) {
  if (!file.exists(path)) return(list())
  lines <- readLines(path, warn = FALSE)
  headers <- grep("^[[:space:]]*ITERATION", lines)
  if (!length(headers)) return(list())
  header <- tail(headers, 1L)
  tail_lines <- lines[(header + 1L):length(lines)]
  tail_lines <- tail_lines[nzchar(trimws(tail_lines)) & !grepl("^TABLE", trimws(tail_lines))]
  parsed <- tryCatch(utils::read.table(
    text = paste(c(lines[[header]], tail_lines), collapse = "\n"),
    header = TRUE, check.names = FALSE
  ), error = function(error) NULL)
  if (is.null(parsed) || !nrow(parsed)) return(list())
  final <- parsed[parsed$ITERATION == -1000000000, , drop = FALSE]
  if (!nrow(final)) final <- parsed[nrow(parsed), , drop = FALSE]
  value <- function(pattern) {
    column <- grep(pattern, names(final), value = TRUE)
    if (!length(column)) NA_real_ else safe_number(final[[column[[1L]]]][[1L]])
  }
  list(
    objective = value("^(OBJ|OBJECTIVE)$"),
    theta1 = value("^THETA1$"), theta2 = value("^THETA2$"),
    omega1 = value("^OMEGA"), sigma1 = value("^SIGMA")
  )
}

read_nonmem_simulation <- function(path) {
  if (!file.exists(path)) return(list())
  lines <- readLines(path, warn = FALSE)
  # NONMEM emits a TABLE/header block for every SUBPROBLEM. Keep only numeric
  # records so repeated headers do not make read.table() fail.
  records <- lines[grepl("^[[:space:]]*[-+]?[0-9]", lines)]
  table <- tryCatch(utils::read.table(
    text = paste(records, collapse = "\n"), header = FALSE
  ), error = function(error) NULL)
  if (is.null(table) || !nrow(table)) return(list())
  if (ncol(table) < 4L) return(list())
  observed <- table[[3L]] == 0L
  values <- as.numeric(table[[4L]][observed])
  list(
    output_rows = nrow(table), observation_rows = sum(observed),
    dv_mean = mean(values, na.rm = TRUE), dv_sd = stats::sd(values, na.rm = TRUE),
    checksum = sum(values * seq_along(values), na.rm = TRUE)
  )
}

empty_row <- function(engine, workload, method, repeat_index, measured) {
  data.frame(
    engine = engine, workload = workload, method = method, profile = profile_name,
    scenario = scenario_name,
    release = liber_validation_manifest(root)$release,
    git_commit = git_state$commit,
    libertad_version = as.character(utils::packageVersion("LibeRtAD")),
    liberation_version = as.character(utils::packageVersion("LibeRation")),
    nlmixr2_version = if (requireNamespace("nlmixr2", quietly = TRUE)) {
      as.character(utils::packageVersion("nlmixr2"))
    } else "",
    rxode2_version = if (requireNamespace("rxode2", quietly = TRUE)) {
      as.character(utils::packageVersion("rxode2"))
    } else "",
    validation_library = validation_runtime$path,
    repetition = as.integer(repeat_index), measured = isTRUE(measured),
    subjects = profile$subjects, input_records = nrow(data),
    simulation_replicates = if (workload == "simulation") profile$simulations else 1L,
    covariance = workload == "estimation" && method_covariance(method),
    status = "error", error = "", process_wall_seconds = NA_real_,
    process_exit_status = NA_integer_,
    worker_total_seconds = NA_real_, startup_seconds = NA_real_,
    core_seconds = NA_real_, fit_seconds = NA_real_, covariance_seconds = NA_real_,
    peak_r_heap_mb = NA_real_, input_payload_bytes = NA_real_,
    result_payload_bytes = NA_real_,
    process_cpu_seconds = NA_real_, timing_source = "", objective = NA_real_,
    convergence = NA_integer_, theta1 = NA_real_, theta2 = NA_real_,
    omega1 = NA_real_, sigma1 = NA_real_, output_rows = NA_integer_,
    optimizer_backend = "", objective_backend = "",
    population_parameter_evaluations = NA_integer_,
    population_shared_state_hits = NA_integer_, objective_evaluations = NA_integer_,
    gradient_evaluations = NA_integer_, conditional_iterations = NA_integer_,
    conditional_evaluations = NA_integer_, tape_records = NA_integer_,
    tape_retapes = NA_integer_, shared_prediction_tapes = NA_integer_,
    its_mstep_schedule = "", its_acceleration = "",
    imp_sampling = "", imp_proposal = "", imp_sample_schedule = "",
    imp_mstep_schedule = "", saem_kernel = "",
    stochastic_stopped_early = FALSE,
    stochastic_retained_support = NA_integer_,
    stochastic_phase_timing = "", bayes_outer_kernel = "",
    stochastic_outer_acceptance = NA_real_,
    stochastic_eta_acceptance = NA_real_, posterior_min_ess = NA_real_,
    posterior_median_ess = NA_real_,
    observation_rows = NA_integer_, dv_mean = NA_real_, dv_sd = NA_real_,
    checksum = NA_real_, stringsAsFactors = FALSE
  )
}
write_csv <- function(frame, path) {
  utils::write.table(
    frame, path, sep = ",", dec = ".", row.names = FALSE, col.names = TRUE,
    quote = TRUE, qmethod = "double", na = ""
  )
}
raw_rows <- if (resume && file.exists(raw_path)) {
  previous <- utils::read.csv(raw_path, stringsAsFactors = FALSE, check.names = FALSE)
  split(previous, seq_len(nrow(previous)))
} else list()
same_run <- function(row, engine, workload, method, repeat_index, measured) {
  identical(as.character(row$engine[[1L]]), engine) &&
    identical(as.character(row$workload[[1L]]), workload) &&
    identical(as.character(row$method[[1L]]), method) &&
    identical(as.integer(row$repetition[[1L]]), as.integer(repeat_index)) &&
    identical(as.logical(row$measured[[1L]]), isTRUE(measured)) &&
    "git_commit" %in% names(row) &&
    identical(as.character(row$git_commit[[1L]]), git_state$commit) &&
    "liberation_version" %in% names(row) &&
    identical(as.character(row$liberation_version[[1L]]),
              as.character(utils::packageVersion("LibeRation")))
}
append_row <- function(row) {
  if (length(raw_rows)) {
    replace <- vapply(raw_rows, function(existing) same_run(
      existing, row$engine[[1L]], row$workload[[1L]], row$method[[1L]],
      row$repetition[[1L]], row$measured[[1L]]
    ), logical(1))
    raw_rows <<- raw_rows[!replace]
  }
  raw_rows[[length(raw_rows) + 1L]] <<- row
  write_csv(do.call(rbind, raw_rows), raw_path)
}

run_liberation <- function(workload, method, repeat_index, measured) {
  label <- sprintf("repeat-%03d", repeat_index)
  directory <- file.path(output_root, "liberation", tolower(workload), tolower(method), label)
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  config <- list(
    workload = workload, method = method,
    model = benchmark_model(method, "liberation"), data = data,
    library_paths = unique(c(validation_runtime$path, .libPaths())),
    expected_versions = validation_runtime$expected,
    cpp_population_objective = identical(population_objective, "cpp"),
    arguments = if (workload == "estimation") liberation_arguments(method) else list(
      nsim = profile$simulations, random_effects = TRUE, residual = TRUE,
      seed = seed, n_cores = 1L,
      numerical_mode = matched_controls$liberation_numerical_mode
    )
  )
  config_path <- file.path(directory, "config.rds")
  metrics_path <- file.path(directory, "metrics.rds")
  summary_path <- file.path(directory, "summary.rds")
  saveRDS(config, config_path, version = 3L)
  row <- empty_row("LibeRation", workload, method, repeat_index, measured)
  row$input_payload_bytes <- unname(file.info(config_path)$size)
  started <- elapsed()
  status <- system2(
    file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"),
    c("--vanilla", shQuote(file.path(benchmark_dir, "liberation-worker.R")),
      shQuote(config_path), shQuote(metrics_path), shQuote(summary_path)),
    stdout = file.path(directory, "stdout.log"),
    stderr = file.path(directory, "stderr.log")
  )
  row$process_wall_seconds <- elapsed() - started
  row$process_exit_status <- as.integer(status)
  if (identical(status, 0L) && file.exists(metrics_path) && file.exists(summary_path)) {
    metrics <- readRDS(metrics_path)
    summary <- readRDS(summary_path)
    row$status <- metrics$status
    row$error <- metrics$error
    row$worker_total_seconds <- safe_number(metrics$worker_total_seconds)
    row$startup_seconds <- safe_number(metrics$startup_seconds)
    row$core_seconds <- safe_number(metrics$engine_total_seconds)
    row$fit_seconds <- safe_number(metrics$fit_seconds)
    row$covariance_seconds <- safe_number(metrics$covariance_seconds)
    row$peak_r_heap_mb <- safe_number(metrics$peak_r_heap_mb)
    row$result_payload_bytes <- safe_number(file.info(summary_path)$size)
    row$timing_source <- paste0(
      "LibeRation post-initialization estimation plus covariance elapsed time; ",
      "fresh-process wall time retained end-to-end"
    )
    row$objective <- safe_number(summary$objective)
    row$convergence <- as.integer(summary$convergence %||% NA_integer_)
    row$theta1 <- safe_number(summary$theta[[1L]] %||% NA_real_)
    row$theta2 <- safe_number(summary$theta[[2L]] %||% NA_real_)
    row$omega1 <- safe_number(summary$omega[[1L]] %||% NA_real_)
    row$sigma1 <- safe_number(summary$sigma[[1L]] %||% NA_real_)
    for (field in c(
      "optimizer_backend", "objective_backend", "population_parameter_evaluations",
      "population_shared_state_hits", "objective_evaluations", "gradient_evaluations",
      "conditional_iterations", "conditional_evaluations", "tape_records",
      "tape_retapes", "shared_prediction_tapes", "its_mstep_schedule",
      "its_acceleration", "imp_sampling", "imp_proposal",
      "imp_sample_schedule", "imp_mstep_schedule", "saem_kernel",
      "stochastic_stopped_early", "stochastic_retained_support",
      "stochastic_phase_timing",
      "bayes_outer_kernel", "stochastic_outer_acceptance",
      "stochastic_eta_acceptance", "posterior_min_ess",
      "posterior_median_ess"
    )) row[[field]] <- summary[[field]] %||% row[[field]]
    for (field in c("output_rows", "observation_rows", "dv_mean", "dv_sd", "checksum")) {
      row[[field]] <- safe_number(summary[[field]])
    }
  } else {
    row$error <- paste("Fresh R process returned status", status)
  }
  row
}

run_nlmixr2 <- function(workload, method, repeat_index, measured) {
  label <- sprintf("repeat-%03d", repeat_index)
  directory <- file.path(
    output_root, "nlmixr2", tolower(workload), tolower(method), label
  )
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  arguments <- if (workload == "estimation") {
    c(liberation_arguments(method), list(
      significant_digits = matched_controls$significant_digits,
      print_every = 0L
    ))
  } else list(
    nsim = profile$simulations, random_effects = TRUE, residual = TRUE,
    seed = seed, n_cores = 1L
  )
  config <- list(
    workload = workload, method = method,
    model = benchmark_model(method, "nlmixr2"), data = data,
    library_paths = unique(c(
      validation_runtime$path, nlmixr2_library, .libPaths()
    )),
    expected_versions = validation_runtime$expected,
    arguments = arguments
  )
  config_path <- file.path(directory, "config.rds")
  metrics_path <- file.path(directory, "metrics.rds")
  summary_path <- file.path(directory, "summary.rds")
  saveRDS(config, config_path, version = 3L)
  row <- empty_row("nlmixr2", workload, method, repeat_index, measured)
  row$input_payload_bytes <- unname(file.info(config_path)$size)
  started <- elapsed()
  # Start the fresh process with a clean Rtools environment. On Windows,
  # changing PATH only after rxode2 has loaded is too late because parts of its
  # compiler discovery are process-initialization state.
  restore_toolchain <- getFromNamespace(
    ".nm_nlmixr_toolchain_guard", "LibeRation"
  )()
  process <- tryCatch(
    processx::run(
      file.path(
        R.home("bin"),
        if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"
      ),
      c(
        "--vanilla", file.path(benchmark_dir, "nlmixr2-worker.R"),
        config_path, metrics_path, summary_path
      ),
      env = c(
        PATH = Sys.getenv("PATH"), Path = Sys.getenv("PATH"),
        BINPREF = Sys.getenv("BINPREF"), rxBINPREF = Sys.getenv("rxBINPREF"),
        COMPILER_PATH = Sys.getenv("COMPILER_PATH")
      ),
      stdout = file.path(directory, "stdout.log"),
      stderr = file.path(directory, "stderr.log"),
      error_on_status = FALSE,
      windows_hide_window = TRUE,
      cleanup_tree = TRUE
    ),
    finally = restore_toolchain()
  )
  status <- process$status
  row$process_exit_status <- as.integer(status)
  row$process_wall_seconds <- elapsed() - started
  if (file.exists(metrics_path) && file.exists(summary_path)) {
    metrics <- readRDS(metrics_path)
    summary <- readRDS(summary_path)
    row$status <- metrics$status
    row$error <- metrics$error
    if (identical(row$status, "ok") && !identical(status, 0L)) {
      row$error <- paste0(
        "Result serialized successfully before Windows worker teardown status ",
        status, "."
      )
    }
    row$worker_total_seconds <- safe_number(metrics$worker_total_seconds)
    row$startup_seconds <- safe_number(metrics$startup_seconds)
    row$core_seconds <- safe_number(metrics$engine_total_seconds)
    row$fit_seconds <- safe_number(metrics$fit_seconds)
    row$covariance_seconds <- safe_number(metrics$covariance_seconds)
    row$peak_r_heap_mb <- safe_number(metrics$peak_r_heap_mb)
    row$result_payload_bytes <- safe_number(file.info(summary_path)$size)
    row$timing_source <- paste0(
      "nlmixr2 estimator call including estimator-internal preparation and ",
      "requested covariance; fresh-process wall time retained end-to-end"
    )
    row$objective <- safe_number(summary$objective)
    row$convergence <- as.integer(summary$convergence %||% NA_integer_)
    row$theta1 <- safe_number(summary$theta[[1L]] %||% NA_real_)
    row$theta2 <- safe_number(summary$theta[[2L]] %||% NA_real_)
    row$omega1 <- safe_number(summary$omega[[1L]] %||% NA_real_)
    row$sigma1 <- safe_number(summary$sigma[[1L]] %||% NA_real_)
    row$optimizer_backend <- "nlmixr2"
    row$objective_backend <- "nlmixr2"
    for (field in c("output_rows", "observation_rows", "dv_mean", "dv_sd", "checksum")) {
      row[[field]] <- safe_number(summary[[field]])
    }
  } else {
    row$error <- paste("Fresh nlmixr2 R process returned status", status)
  }
  row
}

run_nonmem <- function(workload, method, repeat_index, measured) {
  label <- sprintf("repeat-%03d", repeat_index)
  directory <- file.path(output_root, "nonmem", tolower(workload), tolower(method), label)
  copy_fixture(directory)
  writeLines(nonmem_control(workload, method), file.path(directory, "benchmark.mod"), useBytes = TRUE)
  row <- empty_row("NONMEM", workload, method, repeat_index, measured)
  psn_directory <- "psn-run"
  if (dir.exists(file.path(directory, psn_directory))) {
    suffix <- gsub("[^0-9]", "", format(Sys.time(), "%Y%m%dT%H%M%OS6", tz = "UTC"))
    psn_directory <- paste0("psn-run-attempt-", suffix)
  }
  dde_arguments <- if (benchmark_model(method, "nonmem")$ADVAN %in% 16:18) {
    c("-no-check_nmtran", "-nmfe_options=-prdefault -xmloff -dde")
  } else character()
  command_args <- c(
    "benchmark.mod", paste0("-directory=", psn_directory), "-clean=0",
    "-no-prepend_options_to_lst", dde_arguments
  )
  started <- elapsed()
  process_arguments <- getFromNamespace(
    ".nm_nonmem_process_arguments", "LibeRation"
  )(execute_path, command_args, directory)
  process <- do.call(processx::run, process_arguments)
  status <- process$status
  writeLines(process$stdout %||% "", file.path(directory, "stdout.log"))
  writeLines(process$stderr %||% "", file.path(directory, "stderr.log"))
  row$process_wall_seconds <- elapsed() - started
  row$process_exit_status <- as.integer(status)
  listing_candidates <- c(
    file.path(directory, psn_directory, "NM_run1", "psn.lst"),
    file.path(directory, "benchmark.lst")
  )
  listing <- listing_candidates[file.exists(listing_candidates)][1L]
  if (identical(status, 0L) && length(listing) && !is.na(listing)) {
    lines <- readLines(listing, warn = FALSE)
    row$status <- "ok"
    row$process_cpu_seconds <- numeric_match(lines, "#CPUT: Total CPU Time in Seconds")
    if (workload == "estimation") {
      row$fit_seconds <- numeric_match(lines, "Elapsed estimation time in seconds")
      row$covariance_seconds <- numeric_match(lines, "Elapsed covariance time in seconds")
      row$core_seconds <- sum(c(row$fit_seconds, row$covariance_seconds), na.rm = TRUE)
      if (!is.finite(row$core_seconds) || row$core_seconds == 0) {
        row$core_seconds <- row$process_cpu_seconds
        row$timing_source <- "NONMEM total CPU fallback"
      } else row$timing_source <- "NONMEM reported estimation plus covariance elapsed time"
      final <- read_ext_final(file.path(directory, "benchmark.ext"))
      for (field in names(final)) row[[field]] <- final[[field]]
    } else {
      simulation_elapsed <- numeric_match(lines, "Elapsed simulation time in seconds")
      row$core_seconds <- if (is.finite(simulation_elapsed)) simulation_elapsed else
        row$process_cpu_seconds
      row$timing_source <- if (is.finite(simulation_elapsed))
        "NONMEM reported simulation elapsed time" else "NONMEM total CPU fallback"
      summary <- read_nonmem_simulation(file.path(directory, "benchmark.tab"))
      for (field in names(summary)) row[[field]] <- summary[[field]]
    }
  } else {
    row$error <- paste("PsN execute returned status", status)
  }
  row
}

jobs <- lapply(methods, function(method) list(workload = "estimation", method = method))
if (run_simulation) jobs <- c(jobs, list(list(workload = "simulation", method = "SIMULATION")))

cat("Benchmark output:", output_root, "\n")
cat("Profile:", profile_name, "scenario:", scenario_name, "subjects:", profile$subjects,
    "records:", nrow(data), "repeats:", repeats, "warmups:", warmups, "\n")
for (job in jobs) {
  for (engine in engines) {
    if (engine == "NLMIXR2" && job$workload == "estimation" &&
        !job$method %in% nlmixr2_run_methods) {
      cat(sprintf(
        "NLMIXR2 estimation %s ... not run (%s)\n",
        job$method,
        if (job$method %in% nlmixr2_supported_methods) {
          "excluded from this run"
        } else "no exact estimator mapping"
      ))
      next
    }
    for (index in seq_len(warmups + repeats)) {
      measured <- index > warmups
      repeat_index <- if (measured) index - warmups else 0L - (warmups - index)
      completed <- if (resume && length(raw_rows)) vapply(raw_rows, function(existing) {
        engine_label <- switch(
          engine, LIBERATION = "LibeRation", NONMEM = "NONMEM", NLMIXR2 = "nlmixr2"
        )
        same_run(existing, engine_label,
                 job$workload, job$method, repeat_index, measured) &&
          identical(as.character(existing$status[[1L]]), "ok")
      }, logical(1)) else FALSE
      if (any(completed)) {
        cat(sprintf("%s %s %s %s %d/%d ... skipped (already successful)\n",
                    engine, job$workload, job$method,
                    if (measured) "repeat" else "warmup",
                    index, warmups + repeats))
        next
      }
      cat(sprintf("%s %s %s %s %d/%d ... ",
                  engine, job$workload, job$method,
                  if (measured) "repeat" else "warmup",
                  index, warmups + repeats))
      row <- switch(
        engine,
        LIBERATION = run_liberation(
          job$workload, job$method, repeat_index, measured
        ),
        NLMIXR2 = run_nlmixr2(
          job$workload, job$method, repeat_index, measured
        ),
        NONMEM = run_nonmem(
          job$workload, job$method, repeat_index, measured
        )
      )
      append_row(row)
      cat(row$status, sprintf("wall %.3fs core %.3fs\n",
                              row$process_wall_seconds, row$core_seconds))
    }
  }
}

raw <- do.call(rbind, raw_rows)
measured <- raw[raw$measured & raw$status == "ok", , drop = FALSE]
summaries <- lapply(split(measured, interaction(
  measured$workload, measured$method, measured$engine, drop = TRUE
)), function(frame) {
  data.frame(
    engine = frame$engine[[1L]], workload = frame$workload[[1L]],
    method = frame$method[[1L]], repeats = nrow(frame),
    median_end_to_end_seconds = stats::median(frame$process_wall_seconds),
    min_end_to_end_seconds = min(frame$process_wall_seconds),
    max_end_to_end_seconds = max(frame$process_wall_seconds),
    median_core_seconds = stats::median(frame$core_seconds, na.rm = TRUE),
    median_noncore_overhead_seconds = stats::median(
      frame$process_wall_seconds - frame$core_seconds, na.rm = TRUE
    ),
    median_fit_seconds = stats::median(frame$fit_seconds, na.rm = TRUE),
    median_covariance_seconds = stats::median(frame$covariance_seconds, na.rm = TRUE),
    median_peak_r_heap_mb = stats::median(frame$peak_r_heap_mb, na.rm = TRUE),
    median_input_payload_mb = stats::median(frame$input_payload_bytes, na.rm = TRUE) / 1024^2,
    median_result_payload_mb = stats::median(frame$result_payload_bytes, na.rm = TRUE) / 1024^2,
    optimizer_backend = paste(unique(frame$optimizer_backend[nzchar(frame$optimizer_backend)]),
                              collapse = "+"),
    objective_backend = paste(unique(frame$objective_backend[nzchar(frame$objective_backend)]),
                              collapse = "+"),
    median_population_parameter_evaluations = stats::median(
      frame$population_parameter_evaluations, na.rm = TRUE
    ),
    median_population_shared_state_hits = stats::median(
      frame$population_shared_state_hits, na.rm = TRUE
    ),
    median_objective_evaluations = stats::median(frame$objective_evaluations, na.rm = TRUE),
    median_gradient_evaluations = stats::median(frame$gradient_evaluations, na.rm = TRUE),
    median_conditional_evaluations = stats::median(frame$conditional_evaluations, na.rm = TRUE),
    median_tape_retapes = stats::median(frame$tape_retapes, na.rm = TRUE),
    its_mstep_schedule = paste(unique(
      frame$its_mstep_schedule[nzchar(frame$its_mstep_schedule)]
    ), collapse = "+"),
    its_acceleration = paste(unique(
      frame$its_acceleration[nzchar(frame$its_acceleration)]
    ), collapse = "+"),
    imp_sampling = paste(unique(
      frame$imp_sampling[nzchar(frame$imp_sampling)]
    ), collapse = "+"),
    imp_proposal = paste(unique(
      frame$imp_proposal[nzchar(frame$imp_proposal)]
    ), collapse = "+"),
    imp_sample_schedule = paste(unique(
      frame$imp_sample_schedule[nzchar(frame$imp_sample_schedule)]
    ), collapse = "+"),
    imp_mstep_schedule = paste(unique(
      frame$imp_mstep_schedule[nzchar(frame$imp_mstep_schedule)]
    ), collapse = "+"),
    saem_kernel = paste(unique(frame$saem_kernel[nzchar(frame$saem_kernel)]),
                        collapse = "+"),
    stochastic_early_stop_rate = mean(frame$stochastic_stopped_early),
    median_stochastic_retained_support = stats::median(
      frame$stochastic_retained_support, na.rm = TRUE
    ),
    bayes_outer_kernel = paste(unique(
      frame$bayes_outer_kernel[nzchar(frame$bayes_outer_kernel)]
    ), collapse = "+"),
    median_stochastic_outer_acceptance = stats::median(
      frame$stochastic_outer_acceptance, na.rm = TRUE
    ),
    median_stochastic_eta_acceptance = stats::median(
      frame$stochastic_eta_acceptance, na.rm = TRUE
    ),
    median_posterior_min_ess = stats::median(
      frame$posterior_min_ess, na.rm = TRUE
    ),
    median_posterior_median_ess = stats::median(
      frame$posterior_median_ess, na.rm = TRUE
    ),
    stringsAsFactors = FALSE
  )
})
summary_table <- if (length(summaries)) do.call(rbind, summaries) else data.frame()
write_csv(summary_table, file.path(output_root, "summary.csv"))

comparisons <- list()
for (key in unique(paste(measured$workload, measured$method, sep = "::"))) {
  parts <- strsplit(key, "::", fixed = TRUE)[[1L]]
  frame <- summary_table[summary_table$workload == parts[[1L]] &
                           summary_table$method == parts[[2L]], , drop = FALSE]
  nonmem <- frame[frame$engine == "NONMEM", , drop = FALSE]
  liber <- frame[frame$engine == "LibeRation", , drop = FALSE]
  if (nrow(nonmem) == 1L && nrow(liber) == 1L) {
    comparisons[[length(comparisons) + 1L]] <- data.frame(
      workload = parts[[1L]], method = parts[[2L]],
      mapping = if (!identical(comparison_mapping, "direct")) {
        comparison_mapping
      } else if (parts[[2L]] %in% c("FO", "FOCE", "FOCEI", "LAPLACE", "SIMULATION")) {
        "direct"
      } else if (identical(parts[[2L]], "BAYES")) {
        "matched posterior and iteration controls"
      } else "matched iteration/sample controls",
      nonmem_end_to_end_seconds = nonmem$median_end_to_end_seconds,
      liberation_end_to_end_seconds = liber$median_end_to_end_seconds,
      end_to_end_ratio_nonmem_over_liberation =
        nonmem$median_end_to_end_seconds / liber$median_end_to_end_seconds,
      nonmem_core_seconds = nonmem$median_core_seconds,
      liberation_core_seconds = liber$median_core_seconds,
      core_ratio_nonmem_over_liberation = nonmem$median_core_seconds / liber$median_core_seconds,
      nonmem_noncore_overhead_seconds = nonmem$median_noncore_overhead_seconds,
      liberation_noncore_overhead_seconds = liber$median_noncore_overhead_seconds,
      stringsAsFactors = FALSE
    )
  }
}
comparison <- if (length(comparisons)) do.call(rbind, comparisons) else data.frame()
if (nrow(comparison)) {
  comparison <- comparison[order(match(
    comparison$method, c(supported_methods, "SIMULATION")
  )), , drop = FALSE]
}
write_csv(comparison, timing_comparison_path)

engine_comparisons <- list()
for (key in unique(paste(measured$workload, measured$method, sep = "::"))) {
  parts <- strsplit(key, "::", fixed = TRUE)[[1L]]
  frame <- summary_table[
    summary_table$workload == parts[[1L]] &
      summary_table$method == parts[[2L]], , drop = FALSE
  ]
  nonmem <- frame[frame$engine == "NONMEM", , drop = FALSE]
  if (nrow(nonmem) != 1L) next
  for (comparator in c("LibeRation", "nlmixr2")) {
    candidate <- frame[frame$engine == comparator, , drop = FALSE]
    if (nrow(candidate) != 1L) next
    engine_comparisons[[length(engine_comparisons) + 1L]] <- data.frame(
      workload = parts[[1L]], method = parts[[2L]], engine = comparator,
      mapping = if (!identical(comparison_mapping, "direct")) {
        comparison_mapping
      } else if (parts[[2L]] %in%
                 c("FO", "FOCE", "FOCEI", "LAPLACE", "SIMULATION")) {
        "direct"
      } else if (parts[[2L]] == "IMP") {
        "matched importance-sampling controls"
      } else if (parts[[2L]] == "SAEM") {
        "matched burn-in, iteration, and sample controls"
      } else if (parts[[2L]] == "BAYES") {
        "matched posterior and iteration controls"
      } else {
        "matched iteration/sample controls"
      },
      nonmem_end_to_end_seconds = nonmem$median_end_to_end_seconds,
      engine_end_to_end_seconds = candidate$median_end_to_end_seconds,
      end_to_end_ratio_nonmem_over_engine =
        nonmem$median_end_to_end_seconds / candidate$median_end_to_end_seconds,
      nonmem_core_seconds = nonmem$median_core_seconds,
      engine_core_seconds = candidate$median_core_seconds,
      core_ratio_nonmem_over_engine =
        nonmem$median_core_seconds / candidate$median_core_seconds,
      stringsAsFactors = FALSE
    )
  }
}
engine_comparison <- if (length(engine_comparisons)) {
  do.call(rbind, engine_comparisons)
} else data.frame()
if (nrow(engine_comparison)) {
  engine_comparison <- engine_comparison[order(
    match(engine_comparison$method, c(supported_methods, "SIMULATION")),
    match(engine_comparison$engine, c("LibeRation", "nlmixr2"))
  ), , drop = FALSE]
}
write_csv(engine_comparison, engine_comparison_path)

write_timing_plot <- function(path, device = c("png", "svg")) {
  device <- match.arg(device)
  if (!nrow(summary_table)) return(invisible(FALSE))
  if (device == "png") {
    grDevices::png(path, width = 1900L, height = 980L, res = 150L)
  } else {
    grDevices::svg(path, width = 12.7, height = 6.55, pointsize = 11)
  }
  on.exit(grDevices::dev.off(), add = TRUE)
  old <- graphics::par(no.readonly = TRUE)
  on.exit(graphics::par(old), add = TRUE)
  graphics::par(
    mfrow = c(1L, 2L), mar = c(5.2, 8.2, 3.5, 1.0),
    oma = c(0, 0, 2.5, 0), las = 1, family = "sans"
  )
  engine_order <- intersect(
    c("NONMEM", "LibeRation", "nlmixr2"), unique(summary_table$engine)
  )
  method_order <- intersect(
    c(supported_methods, "SIMULATION"), unique(summary_table$method)
  )
  colours <- c(
    NONMEM = "#355C7D", LibeRation = "#2A9D8F", nlmixr2 = "#D08C3F"
  )[engine_order]
  draw_panel <- function(column, title) {
    values <- matrix(
      NA_real_, nrow = length(engine_order), ncol = length(method_order),
      dimnames = list(engine_order, method_order)
    )
    for (engine in engine_order) for (method in method_order) {
      row <- summary_table[
        summary_table$engine == engine & summary_table$method == method,
        , drop = FALSE
      ]
      if (nrow(row) == 1L) values[engine, method] <- row[[column]][[1L]]
    }
    positive <- values[is.finite(values) & values > 0]
    limits <- if (length(positive)) {
      c(max(0.01, min(positive) / 1.8), max(positive) * 1.5)
    } else c(0.01, 1)
    graphics::barplot(
      values, beside = TRUE, horiz = TRUE, log = "x", xlim = limits,
      col = colours, border = NA, names.arg = method_order,
      xlab = "Elapsed time (seconds, log scale)", main = title,
      cex.names = 0.82
    )
    graphics::grid(nx = NULL, ny = NA, col = "#D7DCE2", lty = 1)
    graphics::box(col = "#9AA3AC")
  }
  draw_panel("median_end_to_end_seconds", "End-to-end")
  draw_panel("median_core_seconds", "Core estimation/simulation")
  graphics::mtext(
    "Matched-control pharmacometric benchmark", outer = TRUE,
    side = 3, line = 0.4, cex = 1.25, font = 2
  )
  graphics::legend(
    "bottom", inset = c(0, -0.17), xpd = NA, horiz = TRUE,
    legend = engine_order, fill = colours, border = NA, bty = "n", cex = 0.9
  )
  invisible(TRUE)
}
write_timing_plot(file.path(output_root, "timing-comparison.png"), "png")
write_timing_plot(file.path(output_root, "timing-comparison.svg"), "svg")

estimation_results <- measured[measured$workload == "estimation", , drop = FALSE]
parameter_summaries <- lapply(split(estimation_results, interaction(
  estimation_results$method, estimation_results$engine, drop = TRUE
)), function(frame) {
  data.frame(
    engine = frame$engine[[1L]], method = frame$method[[1L]],
    repeats = nrow(frame),
    median_objective = stats::median(frame$objective, na.rm = TRUE),
    median_theta1 = stats::median(frame$theta1, na.rm = TRUE),
    median_theta2 = stats::median(frame$theta2, na.rm = TRUE),
    median_omega1 = stats::median(frame$omega1, na.rm = TRUE),
    median_sigma1 = stats::median(frame$sigma1, na.rm = TRUE),
    stringsAsFactors = FALSE
  )
})
parameter_estimates <- if (length(parameter_summaries)) {
  do.call(rbind, parameter_summaries)
} else data.frame()
write_csv(parameter_estimates, parameter_estimates_path)

relative_difference <- function(liberation, nonmem) {
  if (!is.finite(liberation) || !is.finite(nonmem) || nonmem == 0) return(NA_real_)
  100 * (liberation - nonmem) / abs(nonmem)
}
parameter_pairs <- list()
for (method in supported_methods) {
  frame <- parameter_estimates[parameter_estimates$method == method, , drop = FALSE]
  nonmem <- frame[frame$engine == "NONMEM", , drop = FALSE]
  liber <- frame[frame$engine == "LibeRation", , drop = FALSE]
  if (nrow(nonmem) == 1L && nrow(liber) == 1L) {
    parameter_pairs[[length(parameter_pairs) + 1L]] <- data.frame(
      method = method,
      mapping = if (!identical(comparison_mapping, "direct")) {
        comparison_mapping
      } else if (method %in% c("FO", "FOCE", "FOCEI", "LAPLACE")) {
        "direct"
      } else if (identical(method, "BAYES")) {
        "matched posterior and iteration controls"
      } else "matched iteration/sample controls",
      nonmem_theta1 = nonmem$median_theta1, liberation_theta1 = liber$median_theta1,
      theta1_relative_difference_percent = relative_difference(liber$median_theta1, nonmem$median_theta1),
      nonmem_theta2 = nonmem$median_theta2, liberation_theta2 = liber$median_theta2,
      theta2_relative_difference_percent = relative_difference(liber$median_theta2, nonmem$median_theta2),
      nonmem_omega1 = nonmem$median_omega1, liberation_omega1 = liber$median_omega1,
      omega1_relative_difference_percent = relative_difference(liber$median_omega1, nonmem$median_omega1),
      nonmem_sigma1 = nonmem$median_sigma1, liberation_sigma1 = liber$median_sigma1,
      sigma1_relative_difference_percent = relative_difference(liber$median_sigma1, nonmem$median_sigma1),
      stringsAsFactors = FALSE
    )
  }
}
parameter_comparison <- if (length(parameter_pairs)) do.call(rbind, parameter_pairs) else data.frame()
write_csv(parameter_comparison, parameter_comparison_path)

markdown_table <- function(frame, digits = 3L) {
  if (!nrow(frame)) return("No paired successful measurements were available.")
  display <- frame
  numeric_columns <- vapply(display, is.numeric, logical(1))
  display[numeric_columns] <- lapply(display[numeric_columns], function(value) {
    ifelse(is.finite(value), formatC(value, digits = digits, format = "f"), "")
  })
  header <- paste0("| ", paste(names(display), collapse = " | "), " |")
  separator <- paste0("| ", paste(rep("---", ncol(display)), collapse = " | "), " |")
  rows <- apply(display, 1L, function(row) paste0("| ", paste(row, collapse = " | "), " |"))
  paste(c(header, separator, rows), collapse = "\n")
}

report <- c(
  paste0("# NONMEM, LibeRation, and nlmixr2 benchmark: ", stamp), "",
  "## Scope", "",
  paste0("- Profile: `", profile_name, "` (", profile$subjects, " subjects, ",
         nrow(data), " input records, ", profile$simulations, " simulation replicates)."),
  paste0("- Scenario: `", scenario_name, "` - ", scenario$description, "."),
  paste0("- Comparator mapping: `", comparison_mapping, "`."),
  paste0("- Measured repetitions: ", repeats, "; unmeasured warm-ups: ", warmups, "."),
  paste0("- Estimation methods: ", paste(methods, collapse = ", "), "."),
  paste0("- Engines: ", paste(engines, collapse = ", "), "."),
  paste0(
    "- nlmixr2 methods run: ",
    paste(intersect(methods, nlmixr2_run_methods), collapse = ", "),
    if (any(!methods %in% nlmixr2_run_methods)) paste0(
      "; not run: ",
      paste(setdiff(methods, nlmixr2_run_methods), collapse = ", ")
    ) else "", "."
  ),
  paste0("- LibeRation outer optimizer: `", optimizer_backend, "`."),
  paste0("- LibeRation population objective: `", population_objective, "`."),
  paste0(
    "- Matched-control profile: outer budget ", matched_controls$outer_budget,
    ", ETA budget ", matched_controls$eta_budget,
    ", target tolerance 1e-", matched_controls$significant_digits, "."
  ),
  "- NONMEM FO estimation requests `POSTHOC` for comparable individual ETA estimation.",
  paste0(
    "- BAYES uses ", profile$bayes_burn, " burn-in and ",
    profile$bayes_samples, " retained iterations with identical normal THETA priors; ",
    "OMEGA and SIGMA are fixed in both engines."
  ),
  paste0("- Covariance requested where directly comparable: ", include_covariance, "."), "",
  "End-to-end time is measured outside a fresh process. NONMEM starts through a fresh PsN `execute` directory; LibeRation and nlmixr2 each start through a fresh `Rscript --vanilla` process and serialize a result summary before exit.",
  "Core estimation time is model fitting plus requested covariance. LibeRation excludes initial context/tape construction from core time while retaining it in end-to-end wall time. NONMEM uses its estimation/covariance timers when exposed and otherwise its reported total CPU time. nlmixr2 reports the complete estimator call, including estimator-internal model preparation and covariance because it does not expose a stable separate compilation/covariance timer. Simulation uses the timed engine call, with NONMEM falling back to total CPU time when needed.", "",
  "A ratio above 1 means NONMEM took longer; below 1 means the comparator took longer.", "",
  "## Median timing comparison", "", markdown_table(engine_comparison), "",
  "## Numerical sanity check", "",
  "Relative differences are `(LibeRation - NONMEM) / abs(NONMEM) * 100`. Objective values are not compared because method-specific constants and reported objective definitions can differ.", "",
  markdown_table(if (nrow(parameter_comparison)) parameter_comparison[c(
    "method", "mapping", "theta1_relative_difference_percent",
    "theta2_relative_difference_percent", "omega1_relative_difference_percent",
    "sigma1_relative_difference_percent"
  )] else parameter_comparison), "",
  "## Environment", "",
  paste0("- OS: ", Sys.info()[["sysname"]], " ", Sys.info()[["release"]], " (", R.version$platform, ")"),
  paste0("- CPU: ", Sys.getenv("PROCESSOR_IDENTIFIER", unset = "not reported")),
  paste0("- R: ", R.version.string),
  paste0("- LibeRation: ", as.character(utils::packageVersion("LibeRation"))),
  paste0("- LibeRtAD: ", as.character(utils::packageVersion("LibeRtAD"))),
  if (requireNamespace("nlmixr2", quietly = TRUE)) paste0(
    "- nlmixr2: ", as.character(utils::packageVersion("nlmixr2")),
    "; nlmixr2est: ", as.character(utils::packageVersion("nlmixr2est")),
    "; rxode2: ", as.character(utils::packageVersion("rxode2"))
  ) else "- nlmixr2: not installed",
  paste0("- Ecosystem release: `", liber_validation_manifest(root)$release, "`."),
  paste0("- Git commit: `", git_state$commit, "`."),
  paste0("- Tracked worktree clean: ", git_state$tracked_worktree_clean, "."),
  paste0("- Validation library: `", validation_runtime$path, "`."),
  if (nzchar(nlmixr2_library)) paste0(
    "- nlmixr2 library: `", nlmixr2_library, "`."
  ) else "- nlmixr2 library: standard R library search path.",
  paste0("- PsN execute: `", execute_path, "`"), "",
  "## Interpretation limits", "",
  "- These are matched workflow benchmarks, not proof of mathematical equivalence. Parameter outputs are retained in `raw-results.csv` for sanity checking.",
  "- Fresh-process wall time includes startup and output creation but excludes fixture generation and post-run report parsing for both engines.",
  "- FO/FOCE/FOCEI/LAPLACE have direct method mappings across all included engines. ITS/IMP/SAEM use their defining iterative update families and matched nominal iteration/sample controls; proposal kernels, random streams, and undocumented internal stopping details remain implementation-specific.",
  "- nlmixr2 has no exact ITS or BAYES counterpart in this harness, so those cells are deliberately omitted rather than replaced with a different algorithm.",
  "- SAEM performs the same burn-in plus stationary iteration total and the same nominal samples per iteration in both engines.",
  "- BAYES compares a dedicated matched posterior and equal burn-in/retained-iteration counts. The samplers and random-number streams remain implementation-specific.",
  "- Run on an otherwise idle machine, keep both engines single-threaded, and use the standard profile for decision-grade comparisons.", ""
)
writeLines(report, file.path(output_root, "REPORT.md"), useBytes = TRUE)

metadata <- list(
  timestamp_utc = stamp, profile = profile_name, settings = profile,
  scenario = scenario_name, scenario_description = scenario$description,
  comparison_mapping = comparison_mapping,
  truth = scenario$truth,
  matched_controls = matched_controls,
  bayes_prior = list(
    family = "normal", mean = bayes_prior_mean, sd = bayes_prior_sd,
    omega_fixed = TRUE, sigma_fixed = TRUE
  ),
  optimizer_backend = optimizer_backend,
  population_objective = population_objective,
  methods = methods, nlmixr2_run_methods = nlmixr2_run_methods,
  engines = engines, repeats = repeats, warmups = warmups,
  covariance = include_covariance, simulation = run_simulation, seed = seed,
  system = Sys.info(), r_version = R.version.string,
  liberation_version = as.character(utils::packageVersion("LibeRation")),
  libertad_version = as.character(utils::packageVersion("LibeRtAD")),
  nlmixr2_version = if (requireNamespace("nlmixr2", quietly = TRUE)) {
    as.character(utils::packageVersion("nlmixr2"))
  } else NA_character_,
  nlmixr2est_version = if (requireNamespace("nlmixr2est", quietly = TRUE)) {
    as.character(utils::packageVersion("nlmixr2est"))
  } else NA_character_,
  rxode2_version = if (requireNamespace("rxode2", quietly = TRUE)) {
    as.character(utils::packageVersion("rxode2"))
  } else NA_character_,
  release = liber_validation_manifest(root)$release,
  git = git_state,
  validation_library = validation_runtime$path,
  nlmixr2_library = nlmixr2_library,
  provenance_sha256 = liber_validation_sha256(file.path(output_root, "provenance.json")),
  execute = unname(execute_path), library_paths = .libPaths()
)
saveRDS(metadata, file.path(output_root, "metadata.rds"), version = 3L)
cat("Completed. Report:", file.path(output_root, "REPORT.md"), "\n")
