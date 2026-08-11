args <- commandArgs(trailingOnly = TRUE)
run_nonmem <- "--run-nonmem" %in% args || "--run" %in% args
quick <- "--quick" %in% args
`%||%` <- function(left, right) if (is.null(left)) right else left

script_arg <- grep("^--file=", commandArgs(), value = TRUE)
script <- if (length(script_arg)) {
  sub("^--file=", "", script_arg[[1L]])
} else {
  file.path("validation", "estimation-methods", "run-validation.R")
}
campaign_dir <- normalizePath(dirname(script), winslash = "/", mustWork = TRUE)
root <- normalizePath(
  file.path(campaign_dir, "..", ".."), winslash = "/", mustWork = TRUE
)
source(file.path(root, "tools", "validation-runtime.R"), local = TRUE)

option_value <- function(name, default = NULL) {
  liber_validation_option(name, default, args = args)
}
numerical_mode <- option_value("mode", "nonmem_compatibility")
if (!numerical_mode %in% c("nonmem_compatibility", "liber_optimized")) {
  stop("--mode must be nonmem_compatibility or liber_optimized.", call. = FALSE)
}
validation_runtime <- liber_validation_library(
  root, c("LibeRtAD", "LibeRation"),
  library = option_value("library", Sys.getenv("LIBER_VALIDATION_LIBRARY", ""))
)
if (!requireNamespace("LibeRation", quietly = TRUE)) {
  stop("Install the exact LibeRation source stack before validation.", call. = FALSE)
}
if (!requireNamespace("jsonlite", quietly = TRUE)) {
  stop("Estimation validation requires jsonlite.", call. = FALSE)
}

inventory_path <- file.path(campaign_dir, "methods.csv")
inventory <- utils::read.csv(
  inventory_path, stringsAsFactors = FALSE, check.names = FALSE
)
expected_methods <- c(
  "FO", "FOCE", "FOCEI", "LAPLACE", "ITS", "GQ", "IMP", "SAEM",
  "BAYES", "HMC", "NUTS", "NPML", "NPAG"
)
if (!identical(inventory$method, expected_methods)) {
  stop("methods.csv must declare every nm_est method in API order.", call. = FALSE)
}

stamp <- format(Sys.time(), "%Y%m%dT%H%M%S", tz = "UTC")
output <- option_value(
  "output", file.path(campaign_dir, "results", stamp)
)
if (!grepl("^(?:[A-Za-z]:[/\\\\]|/)", output, perl = TRUE)) {
  output <- file.path(root, output)
}
dir.create(output, recursive = TRUE, showWarnings = FALSE)

data_path <- file.path(root, "validation", "nonmem", "estimation.dat")
data <- utils::read.table(
  data_path,
  col.names = c("ID", "TIME", "EVID", "AMT", "CMT", "DV", "MDV"),
  na.strings = "."
)
theta_lower <- 0.1
theta_upper <- 10
volume <- 20
omega <- 0.1
sigma <- 0.04
seed <- 20260724L

validation_model <- function(theta = 1, theta_fixed = FALSE) {
  LibeRation::nm_model(
    INPUT = names(data), ADVAN = 1L, TRANS = 2L,
    DOSECMP = 1L, OBSCMP = 1L,
    PRED = "CL=THETA(1)*exp(ETA(1));V=THETA(2);S1=V",
    ERROR = "Y=F+ERR(1)",
    THETAS = data.frame(
      THETA = 1:2, Value = c(theta, volume),
      LOWER = c(theta_lower, volume), UPPER = c(theta_upper, volume),
      FIX = c(isTRUE(theta_fixed), TRUE)
    ),
    OMEGAS = data.frame(OMEGA = 1L, Value = omega, FIX = TRUE),
    SIGMAS = data.frame(SIGMA = 1L, Value = sigma, FIX = TRUE),
    LIK_CONFIG = LibeRation::nm_lik_config(
      error = "additive", sigma_parameterization = "variance"
    ),
    NUMERICAL_MODE = numerical_mode
  )
}

subject_data <- lapply(split(data, data$ID), function(subject) {
  observed <- subject$EVID == 0L & subject$MDV == 0L & is.finite(subject$DV)
  list(
    time = subject$TIME[observed], dv = subject$DV[observed],
    amount = subject$AMT[subject$EVID == 1L][[1L]]
  )
})
conditional_loglik <- function(theta, eta, subject) {
  prediction <- subject$amount / volume *
    exp(-(theta * exp(eta) / volume) * subject$time)
  sum(stats::dnorm(subject$dv, prediction, sqrt(sigma), log = TRUE))
}
subject_marginal_loglik <- function(theta, subject) {
  joint <- function(eta) {
    conditional_loglik(theta, eta, subject) +
      stats::dnorm(eta, 0, sqrt(omega), log = TRUE)
  }
  mode <- stats::optimize(function(eta) -joint(eta), c(-4, 4))
  peak <- -mode$objective
  integral <- stats::integrate(
    function(eta) {
      exp(vapply(eta, joint, numeric(1)) - peak)
    },
    lower = -4, upper = 4, rel.tol = 2e-10, subdivisions = 1000L,
    stop.on.error = TRUE
  )
  peak + log(integral$value)
}
marginal_loglik <- function(theta) {
  sum(vapply(
    subject_data, function(subject) subject_marginal_loglik(theta, subject),
    numeric(1)
  ))
}
exact_fit <- stats::optimize(
  function(theta) -2 * marginal_loglik(theta),
  c(theta_lower, theta_upper), tol = 1e-9
)
exact_mle <- unname(exact_fit$minimum)

grid_size <- if (quick) 301L else 801L
posterior_grid <- seq(theta_lower, 5, length.out = grid_size)
posterior_log <- vapply(posterior_grid, marginal_loglik, numeric(1))
posterior_weight <- exp(posterior_log - max(posterior_log))
trapezoid <- function(x, y) {
  sum((head(y, -1L) + tail(y, -1L)) * diff(x) / 2)
}
normalizer <- trapezoid(posterior_grid, posterior_weight)
posterior_mean <- trapezoid(
  posterior_grid, posterior_weight * posterior_grid
) / normalizer
posterior_second <- trapezoid(
  posterior_grid, posterior_weight * posterior_grid^2
) / normalizer
posterior_sd <- sqrt(posterior_second - posterior_mean^2)
posterior_cdf <- c(
  0, cumsum(
    (head(posterior_weight, -1L) + tail(posterior_weight, -1L)) *
      diff(posterior_grid) / 2
  )
) / normalizer
posterior_quantile <- stats::approx(
  posterior_cdf, posterior_grid, xout = c(0.025, 0.5, 0.975),
  ties = "ordered"
)$y
names(posterior_quantile) <- c("2.5%", "50%", "97.5%")

fit_controls <- list(
  FO = list(),
  FOCE = list(),
  FOCEI = list(),
  LAPLACE = list(),
  ITS = list(),
  GQ = list(
    gq_grid = "tensor", gq_order = 11L, gq_adaptive = TRUE
  ),
  IMP = list(n_imp = if (quick) 200L else 500L, seed = seed),
  SAEM = list(
    n_iter = if (quick) 240L else 400L,
    burn = if (quick) 70L else 120L, mcmc_steps = 2L,
    mstep_maxit = if (quick) 8L else 12L, seed = seed
  ),
  BAYES = list(
    n_burn = if (quick) 1000L else 1200L,
    n_sample = if (quick) 1200L else 4000L, n_thin = 1L,
    step_scale = 0.04, eta_step = 0.45, seed = seed
  ),
  HMC = list(
    n_warmup = if (quick) 250L else 500L,
    n_sample = if (quick) 500L else 1200L,
    n_chains = if (quick) 2L else 4L, max_depth = 8L, seed = seed
  ),
  NUTS = list(
    n_warmup = if (quick) 250L else 500L,
    n_sample = if (quick) 500L else 1200L,
    n_chains = if (quick) 2L else 4L, max_depth = 8L, seed = seed
  )
)

fits <- list()
fit_errors <- list()
for (method in names(fit_controls)) {
  cat("LibeRation", method, "...\n")
  fit <- tryCatch(
    do.call(
      LibeRation::nm_est,
      c(
        list(
          model = validation_model(), data = data, method = method,
          maxit = 300L, eta_maxit = 150L, tolerance = 1e-8,
          collect_output = FALSE
        ),
        fit_controls[[method]]
      )
    ),
    error = identity
  )
  if (inherits(fit, "error")) {
    fit_errors[[method]] <- conditionMessage(fit)
  } else {
    fits[[method]] <- fit
  }
}

supports <- matrix(c(-0.7, -0.35, 0, 0.35, 0.7), ncol = 1L)
np_model <- validation_model(theta = exact_mle, theta_fixed = TRUE)
for (method in c("NPML", "NPAG")) {
  cat("LibeRation", method, "...\n")
  controls <- list(
    model = np_model, data = data, method = method, maxit = 50L,
    eta_maxit = 100L, tolerance = 1e-8, collect_output = FALSE,
    np_supports = supports, np_points = nrow(supports),
    np_min_weight = 0, np_weight_maxit = 5000L,
    np_estimate_population = FALSE, seed = seed,
    np_cycles = if (method == "NPML") 1L else 3L
  )
  if (method == "NPAG") {
    controls$np_grid_step <- 0.35
    controls$np_grid_decay <- 0.5
  }
  fit <- tryCatch(do.call(LibeRation::nm_est, controls), error = identity)
  if (inherits(fit, "error")) {
    fit_errors[[method]] <- conditionMessage(fit)
  } else {
    fits[[method]] <- fit
  }
}

np_loglik <- function(candidate_supports) {
  vapply(subject_data, function(subject) {
    vapply(candidate_supports[, 1L], function(eta) {
      conditional_loglik(exact_mle, eta, subject)
    }, numeric(1))
  }, numeric(nrow(candidate_supports)))
}
independent_em <- function(loglik, tolerance = 1e-12, maxit = 100000L) {
  weights <- rep(1 / ncol(loglik), ncol(loglik))
  for (iteration in seq_len(maxit)) {
    responsibility <- matrix(0, nrow(loglik), ncol(loglik))
    for (subject in seq_len(nrow(loglik))) {
      score <- log(pmax(weights, .Machine$double.xmin)) + loglik[subject, ]
      maximum <- max(score)
      probability <- exp(score - maximum)
      responsibility[subject, ] <- probability / sum(probability)
    }
    next_weights <- colMeans(responsibility)
    if (max(abs(next_weights - weights)) <= tolerance) {
      weights <- next_weights
      break
    }
    weights <- next_weights
  }
  marginal <- vapply(seq_len(nrow(loglik)), function(subject) {
    score <- log(pmax(weights, .Machine$double.xmin)) + loglik[subject, ]
    maximum <- max(score)
    maximum + log(sum(exp(score - maximum)))
  }, numeric(1))
  responsibility <- matrix(0, nrow(loglik), ncol(loglik))
  for (subject in seq_len(nrow(loglik))) {
    score <- log(pmax(weights, .Machine$double.xmin)) + loglik[subject, ]
    maximum <- max(score)
    probability <- exp(score - maximum)
    responsibility[subject, ] <- probability / sum(probability)
  }
  list(
    weights = weights, responsibilities = responsibility,
    log_likelihood = sum(marginal)
  )
}
npml_reference <- independent_em(t(np_loglik(supports)))

results <- list()
add_result <- function(method, reference, metric, candidate, expected,
                       tolerance, passed = NULL, detail = "") {
  difference <- if (is.numeric(candidate) && length(candidate) == 1L &&
                    is.numeric(expected) && length(expected) == 1L &&
                    is.finite(candidate) && is.finite(expected)) {
    abs(candidate - expected)
  } else NA_real_
  if (is.null(passed)) {
    passed <- is.finite(difference) && difference <= tolerance
  }
  results[[length(results) + 1L]] <<- data.frame(
    method = method, reference = reference, metric = metric,
    candidate = if (length(candidate) == 1L) as.numeric(candidate) else NA_real_,
    expected = if (length(expected) == 1L) as.numeric(expected) else NA_real_,
    absolute_difference = difference, tolerance = as.numeric(tolerance),
    status = if (is.na(passed)) "not-run" else if (passed) "passed" else "failed",
    passed = as.logical(passed), detail = as.character(detail),
    stringsAsFactors = FALSE
  )
}

for (method in expected_methods) {
  fit <- fits[[method]]
  if (is.null(fit)) {
    add_result(
      method, "LibeRation execution", "finite fit", NA_real_, 1, 0,
      passed = FALSE, detail = fit_errors[[method]] %||% "fit was not returned"
    )
  } else {
    valid <- is.finite(fit$objective) && all(is.finite(fit$theta)) &&
      all(is.finite(fit$omega)) && all(is.finite(fit$sigma)) &&
      identical(as.integer(fit$convergence), 0L)
    add_result(
      method, "LibeRation execution", "finite converged fit",
      as.numeric(valid), 1, 0, passed = valid
    )
  }
}

for (method in c("GQ", "IMP", "SAEM")) {
  tolerance <- c(GQ = 0.001, IMP = 0.06, SAEM = 0.12)[[method]]
  add_result(
    method, "independent adaptive marginal integration", "THETA1 MLE",
    fits[[method]]$theta[[1L]], exact_mle, tolerance
  )
}
for (method in c("BAYES", "HMC", "NUTS")) {
  mean_tolerance <- c(BAYES = 0.12, HMC = 0.08, NUTS = 0.08)[[method]]
  add_result(
    method, "independent normalized marginal posterior", "posterior mean THETA1",
    fits[[method]]$posterior$population$mean[["THETA1"]],
    posterior_mean, mean_tolerance
  )
  add_result(
    method, "independent normalized marginal posterior", "posterior SD THETA1",
    fits[[method]]$posterior$population$sd[["THETA1"]],
    posterior_sd, 0.08
  )
  candidate_quantile <- fits[[method]]$posterior$population$quantile[, "THETA1"]
  add_result(
    method, "independent normalized marginal posterior",
    "maximum posterior quantile difference",
    max(abs(candidate_quantile - posterior_quantile)), 0, 0.18
  )
}
for (method in c("HMC", "NUTS")) {
  fit <- fits[[method]]
  rhat <- fit$posterior$population$rhat[["THETA1"]]
  ess <- fit$posterior$population$ess[["THETA1"]]
  draws <- nrow(fit$chain)
  add_result(
    method, "sampler diagnostics", "R-hat THETA1", rhat, 1,
    0.05, passed = is.finite(rhat) && rhat <= 1.05
  )
  add_result(
    method, "sampler diagnostics", "ESS THETA1", ess,
    if (quick) 50 else 200, 0,
    passed = is.finite(ess) && ess >= if (quick) 50 else 200
  )
  add_result(
    method, "sampler diagnostics", "divergence fraction",
    fit$diagnostics$divergences / draws, 0, 0.01
  )
}

npml_fit <- fits$NPML
if (!is.null(npml_fit)) {
  support_order <- match(
    as.numeric(supports), as.numeric(npml_fit$nonparametric$supports)
  )
  comparable <- !anyNA(support_order)
  candidate_weights <- if (comparable) {
    npml_fit$nonparametric$weights[support_order]
  } else rep(NA_real_, nrow(supports))
  add_result(
    "NPML", "independent fixed-support EM", "maximum support-weight difference",
    max(abs(candidate_weights - npml_reference$weights)),
    0, 1e-6, passed = comparable &&
      max(abs(candidate_weights - npml_reference$weights)) <= 1e-6
  )
  add_result(
    "NPML", "independent fixed-support EM",
    "maximum posterior-probability difference",
    max(abs(
      npml_fit$nonparametric$posterior_probabilities -
        npml_reference$responsibilities
    )),
    0, 1e-6
  )
}
npag_fit <- fits$NPAG
if (!is.null(npag_fit)) {
  npag_reference <- independent_em(t(np_loglik(npag_fit$nonparametric$supports)))
  add_result(
    "NPAG", "independent adaptive-support EM",
    "maximum posterior-probability difference",
    max(abs(
      npag_fit$nonparametric$posterior_probabilities -
        npag_reference$responsibilities
    )),
    0, 1e-6
  )
  add_result(
    "NPAG", "independent likelihood-improvement reference",
    "adaptive minus fixed log-likelihood improvement",
    npag_fit$nonparametric$log_likelihood -
      npml_fit$nonparametric$log_likelihood,
    npag_reference$log_likelihood -
      npml_reference$log_likelihood, 1e-7
  )
}

configure_psn <- function() {
  execute <- Sys.which("execute")
  if (!nzchar(execute)) {
    stop("PsN execute is not available in PATH.", call. = FALSE)
  }
  if (.Platform$OS.type != "windows") {
    return(list(command = execute, prefix = character()))
  }
  script <- sub("[.]bat$", "", execute, ignore.case = TRUE)
  perl <- file.path(dirname(execute), "perl.exe")
  if (!file.exists(perl)) perl <- Sys.which("perl")
  if (!nzchar(perl) || !file.exists(script)) {
    stop("The Windows PsN Perl launcher could not be resolved.", call. = FALSE)
  }
  portable_root <- dirname(dirname(dirname(execute)))
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
nonmem_record <- function(method) {
  switch(
    method,
    FO = "METHOD=0 POSTHOC MAXEVAL=999 NOABORT SIGL=10 NSIG=3",
    FOCE = "METHOD=COND MAXEVAL=999 NOABORT SIGL=10 NSIG=3",
    FOCEI = "METHOD=COND INTERACTION MAXEVAL=999 NOABORT SIGL=10 NSIG=3",
    LAPLACE = paste(
      "METHOD=COND INTERACTION LAPLACIAN MAXEVAL=999",
      "NOABORT SIGL=10 NSIG=3"
    ),
    ITS = "METHOD=ITS INTERACTION NITER=300",
    IMP = paste0(
      "METHOD=IMP INTERACTION NITER=", if (quick) 300L else 600L,
      " ISAMPLE=", if (quick) 200L else 3000L
    ),
    SAEM = paste0(
      "METHOD=SAEM INTERACTION NBURN=", if (quick) 50L else 120L,
      " NITER=", if (quick) 160L else 400L, " ISAMPLE=2"
    )
  )
}
nonmem_control <- function(method) {
  c(
    paste("$PROBLEM LibeR estimation-method validation", method),
    "$INPUT ID TIME EVID AMT CMT DV MDV",
    "$DATA estimation.dat IGNORE=@",
    "$SUBROUTINES ADVAN1 TRANS2",
    "$PK",
    "CL=THETA(1)*EXP(ETA(1))",
    "V=THETA(2)",
    "S1=V",
    "$ERROR",
    "IPRED=F",
    "Y=F+EPS(1)",
    "$THETA (0.1,1,10)",
    "$THETA 20 FIX",
    "$OMEGA 0.1 FIX",
    "$SIGMA 0.04 FIX",
    paste("$ESTIMATION", nonmem_record(method)),
    paste(
      "$TABLE ID TIME EVID IPRED ETA(1) NOPRINT ONEHEADER",
      "FORMAT=s1PE15.8 FILE=estimation.tab"
    )
  )
}
read_ext_final <- function(path) {
  lines <- readLines(path, warn = FALSE)
  header <- tail(grep("^[[:space:]]*ITERATION", lines), 1L)
  if (!length(header)) stop("NONMEM extension has no ITERATION header.")
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
  list(theta = as.numeric(final$THETA1[[1L]]))
}
read_nonmem_table <- function(path) {
  utils::read.table(path, skip = 1L, header = TRUE, check.names = FALSE)
}
run_nonmem_method <- function(method, psn) {
  directory <- file.path(output, "nonmem", tolower(method))
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  file.copy(data_path, file.path(directory, "estimation.dat"), overwrite = TRUE)
  writeLines(
    nonmem_control(method), file.path(directory, "estimation.mod"),
    useBytes = TRUE
  )
  old <- setwd(directory)
  on.exit(setwd(old), add = TRUE)
  status <- system2(
    psn$command,
    c(psn$prefix, "-directory=psn-run", "estimation.mod"),
    stdout = "stdout.log", stderr = "stderr.log"
  )
  listing <- file.path("psn-run", "NM_run1", "psn.lst")
  if (!identical(status, 0L) || !file.exists(listing) ||
      !file.exists("estimation.ext") || !file.exists("estimation.tab")) {
    detail <- paste(
      c(
        if (file.exists("stdout.log")) readLines("stdout.log", warn = FALSE) else "",
        if (file.exists("stderr.log")) readLines("stderr.log", warn = FALSE) else ""
      ),
      collapse = "\n"
    )
    stop("NONMEM ", method, " failed. ", detail, call. = FALSE)
  }
  extension <- read_ext_final("estimation.ext")
  table <- read_nonmem_table("estimation.tab")
  eta_column <- grep("^ETA", names(table), value = TRUE)[[1L]]
  eta <- tapply(table[[eta_column]], table$ID, function(value) value[[1L]])
  list(theta = extension$theta, eta = unname(eta))
}

direct_methods <- c("FO", "FOCE", "FOCEI", "LAPLACE", "ITS", "IMP", "SAEM")
if (run_nonmem) {
  psn <- configure_psn()
  for (method in direct_methods) {
    cat("NONMEM", method, "...\n")
    reference <- tryCatch(run_nonmem_method(method, psn), error = identity)
    if (inherits(reference, "error")) {
      add_result(
        method, "matched NONMEM", "execution", NA_real_, 1, 0,
        passed = FALSE, detail = conditionMessage(reference)
      )
      next
    }
    row <- inventory[inventory$method == method, , drop = FALSE]
    theta_tolerance <- as.numeric(row$theta_tolerance)
    eta_tolerance <- as.numeric(row$eta_tolerance)
    add_result(
      method, paste0("matched NONMEM ", row$nonmem_mapping),
      "THETA1", fits[[method]]$theta[[1L]], reference$theta,
      theta_tolerance
    )
    add_result(
      method, paste0("matched NONMEM ", row$nonmem_mapping),
      "maximum ETA1 difference",
      max(abs(fits[[method]]$eta[, 1L] - reference$eta)),
      0, eta_tolerance
    )
  }
} else {
  for (method in direct_methods) {
    add_result(
      method, "matched NONMEM", "external comparison",
      NA_real_, NA_real_, 0, passed = NA,
      detail = "rerun with --run-nonmem"
    )
  }
}

comparison <- do.call(rbind, results)
coverage <- do.call(rbind, lapply(expected_methods, function(method) {
  rows <- comparison[comparison$method == method, , drop = FALSE]
  data.frame(
    method = method,
    executed_checks = sum(rows$status != "not-run"),
    passed_checks = sum(rows$status == "passed"),
    failed_checks = sum(rows$status == "failed"),
    not_run_checks = sum(rows$status == "not-run"),
    status = if (any(rows$status == "failed")) {
      "failed"
    } else if (any(rows$status == "not-run")) {
      "partial"
    } else "passed",
    stringsAsFactors = FALSE
  )
}))
passed <- !any(comparison$status == "failed")
complete <- passed && !any(comparison$status == "not-run")

tolerances <- list(
  exact_marginal_theta = list(GQ = 0.001, IMP = 0.06, SAEM = 0.12),
  posterior_mean_theta = list(BAYES = 0.12, HMC = 0.08, NUTS = 0.08),
  posterior_sd_theta = 0.08, posterior_quantile = 0.18,
  nonparametric_probability = 1e-6,
  nonmem = split(
    inventory[inventory$method %in% direct_methods, c(
      "theta_tolerance", "eta_tolerance"
    )],
    inventory$method[inventory$method %in% direct_methods]
  )
)
provenance <- liber_validation_provenance(
  root = root, packages = c("LibeRtAD", "LibeRation"),
  library = validation_runtime$path,
  inputs = c(script, inventory_path, data_path),
  seeds = list(estimation = seed),
  tolerances = tolerances,
  dependencies = c("Rcpp", "jsonlite", "openssl"),
  metadata = list(
    profile = if (quick) "quick" else "release",
    numerical_mode = numerical_mode,
    nonmem_requested = run_nonmem,
    nonmem_execute = unname(Sys.which("execute")),
    methods = as.list(expected_methods),
    exact_marginal_mle = exact_mle,
    posterior_mean = posterior_mean,
    posterior_sd = posterior_sd,
    passed = passed, complete = complete
  )
)
summary <- list(
  schema = "liber.estimation-method-validation/1",
  passed = passed, complete = complete,
  profile = if (quick) "quick" else "release",
  numerical_mode = numerical_mode,
  references = list(
    exact_marginal_mle = exact_mle,
    posterior_mean = posterior_mean, posterior_sd = posterior_sd,
    posterior_quantile = as.list(posterior_quantile)
  ),
  coverage = split(coverage, seq_len(nrow(coverage))),
  comparisons = split(comparison, seq_len(nrow(comparison))),
  provenance = provenance
)

markdown_table <- function(frame) {
  header <- "| Method | Executed | Passed | Failed | Not run | Status |"
  separator <- "|---|---:|---:|---:|---:|---|"
  rows <- apply(coverage, 1L, function(row) {
    paste0(
      "| ", row[["method"]], " | ", row[["executed_checks"]], " | ",
      row[["passed_checks"]], " | ", row[["failed_checks"]], " | ",
      row[["not_run_checks"]], " | ", row[["status"]], " |"
    )
  })
  paste(c(header, separator, rows), collapse = "\n")
}
report <- c(
  paste0("# Estimation-method validation: ", stamp), "",
  paste0("- Profile: `", if (quick) "quick" else "release", "`."),
  paste0("- Numerical mode: `", numerical_mode, "`."),
  paste0("- Exact marginal THETA1 optimum: ", format(exact_mle, digits = 10), "."),
  paste0(
    "- Independent posterior THETA1 mean (SD): ",
    format(posterior_mean, digits = 10), " (",
    format(posterior_sd, digits = 10), ")."
  ),
  paste0("- NONMEM requested: ", run_nonmem, "."),
  paste0("- Overall passed: ", passed, "; complete: ", complete, "."), "",
  "## Coverage", "", markdown_table(coverage), "",
  "The complete gate requires the matched NONMEM comparisons. Portable runs ",
  "without `--run-nonmem` retain those rows as `not-run`; they are never ",
  "converted into passes.", "",
  "Detailed numerical comparisons are in `comparisons.csv`; exact environment, ",
  "source, seed, dependency, tolerance, and input hashes are in `provenance.json`."
)
liber_validation_write_evidence(
  output, comparisons = comparison, coverage = coverage, summary = summary,
  provenance = provenance, report = report
)
cat("Estimation validation evidence:", normalizePath(output, winslash = "/"), "\n")
if (!passed) {
  stop("One or more estimation-method validation checks failed.", call. = FALSE)
}
if (run_nonmem && !complete) {
  stop("The requested complete NONMEM estimation gate is incomplete.", call. = FALSE)
}
