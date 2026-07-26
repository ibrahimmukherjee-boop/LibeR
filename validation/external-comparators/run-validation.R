#!/usr/bin/env Rscript

arguments <- commandArgs(trailingOnly = TRUE)

script_argument <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script <- if (length(script_argument)) {
  sub("^--file=", "", script_argument[[1L]])
} else {
  "validation/external-comparators/run-validation.R"
}
fixture_dir <- normalizePath(dirname(script), winslash = "/", mustWork = TRUE)
root <- normalizePath(
  file.path(fixture_dir, "..", ".."), winslash = "/", mustWork = TRUE
)
source(file.path(root, "tools", "validation-runtime.R"), local = TRUE)
value_after <- function(name, default = NULL) {
  liber_validation_option(name, default, args = arguments)
}
liber_validation_configure_rtools(root)

validation_runtime <- liber_validation_library(
  root, c("LibeRtAD", "LibeRation", "LibeRator"),
  library = value_after(
    "library", Sys.getenv("LIBER_VALIDATION_LIBRARY", "")
  )
)
external_library <- value_after(
  "external-library", file.path(root, ".external-comparator-lib")
)
if (dir.exists(external_library)) {
  external_library <- normalizePath(
    external_library, winslash = "/", mustWork = TRUE
  )
  .libPaths(unique(c(validation_runtime$path, external_library, .libPaths())))
} else {
  external_library <- NA_character_
  .libPaths(unique(c(validation_runtime$path, .libPaths())))
}

required_liber <- c("LibeRtAD", "LibeRation", "LibeRator", "jsonlite", "openssl")
missing_liber <- required_liber[
  !vapply(required_liber, requireNamespace, logical(1), quietly = TRUE)
]
if (length(missing_liber)) {
  stop(
    "Missing exact validation dependency: ",
    paste(missing_liber, collapse = ", "), call. = FALSE
  )
}

selected_groups <- strsplit(
  value_after("groups", "state-space,outcomes,numerical,population,dosing"),
  ",", fixed = TRUE
)[[1L]]
selected_groups <- unique(trimws(selected_groups[nzchar(trimws(selected_groups))]))
known_groups <- c(
  "state-space", "outcomes", "numerical", "population", "dosing"
)
unknown_groups <- setdiff(selected_groups, known_groups)
if (length(unknown_groups)) {
  stop("Unknown comparator group: ", paste(unknown_groups, collapse = ", "),
       call. = FALSE)
}
strict <- "--strict" %in% arguments

registry_path <- file.path(fixture_dir, "comparators.csv")
registry <- utils::read.csv(
  registry_path, stringsAsFactors = FALSE, check.names = FALSE
)
comparisons <- list()

append_result <- function(
    id, group, package, capability, comparator, quantity,
    observed = NA_real_, expected = NA_real_, tolerance = NA_real_,
    status = c("passed", "failed", "not-run"), detail = "",
    compared_values = 0L, required = FALSE) {
  status <- match.arg(status)
  difference <- if (
    status != "not-run" && length(observed) == length(expected) &&
    length(observed) && all(is.finite(c(observed, expected)))
  ) {
    max(abs(as.numeric(observed) - as.numeric(expected)))
  } else {
    NA_real_
  }
  comparisons[[length(comparisons) + 1L]] <<- data.frame(
    id = id, group = group, package = package, capability = capability,
    comparator = comparator, quantity = quantity,
    observed = if (length(observed) == 1L) as.numeric(observed) else NA_real_,
    expected = if (length(expected) == 1L) as.numeric(expected) else NA_real_,
    maximum_absolute_difference = difference,
    tolerance = as.numeric(tolerance),
    compared_values = as.integer(compared_values),
    status = status,
    passed = if (status == "passed") TRUE else if (status == "failed") FALSE else NA,
    required = isTRUE(required), detail = as.character(detail),
    stringsAsFactors = FALSE
  )
  invisible(status)
}

compare_values <- function(
    id, group, package, capability, comparator, quantity,
    observed, expected, tolerance, required = FALSE, detail = "") {
  finite <- length(observed) == length(expected) && length(observed) > 0L &&
    all(is.finite(c(observed, expected)))
  difference <- if (finite) {
    max(abs(as.numeric(observed) - as.numeric(expected)))
  } else {
    Inf
  }
  passed <- is.finite(difference) && difference <= tolerance
  append_result(
    id, group, package, capability, comparator, quantity,
    observed = if (length(observed) == 1L) observed else NA_real_,
    expected = if (length(expected) == 1L) expected else NA_real_,
    tolerance = tolerance, status = if (passed) "passed" else "failed",
    detail = detail, compared_values = max(length(observed), length(expected)),
    required = required
  )
  cat(sprintf(
    "%-22s %-31s %s (max |difference| %.6g; tolerance %.6g)\n",
    id, quantity, if (passed) "PASS" else "FAIL", difference, tolerance
  ))
  invisible(passed)
}

run_case <- function(
    id, group, package, capability, comparator, required, code,
    preflight = NULL) {
  if (!group %in% selected_groups) return(invisible(NULL))
  packages <- as.character(package)
  missing <- packages[
    !vapply(packages, requireNamespace, logical(1), quietly = TRUE)
  ]
  if (length(missing)) {
    append_result(
      id, group, paste(packages, collapse = " + "), capability, comparator,
      "availability", status = "not-run",
      detail = paste("Missing package(s):", paste(missing, collapse = ", ")),
      required = required
    )
    cat(sprintf("%-22s NOT RUN (%s)\n", id, paste(missing, collapse = ", ")))
    return(invisible(NULL))
  }
  if (is.function(preflight)) {
    reason <- preflight()
    if (is.character(reason) && length(reason) && nzchar(reason[[1L]])) {
      append_result(
        id, group, paste(packages, collapse = " + "), capability, comparator,
        "availability", status = "not-run", detail = reason[[1L]],
        required = required
      )
      cat(sprintf("%-22s NOT RUN (%s)\n", id, reason[[1L]]))
      return(invisible(NULL))
    }
  }
  tryCatch(
    force(code),
    error = function(error) {
      append_result(
        id, group, paste(packages, collapse = " + "), capability, comparator,
        "adapter execution", status = "failed",
        detail = conditionMessage(error), required = required
      )
      cat(sprintf("%-22s FAIL (%s)\n", id, conditionMessage(error)))
    }
  )
  invisible(NULL)
}

theta_table <- function(value, lower = -10, upper = 10, fixed = FALSE) {
  data.frame(
    THETA = seq_along(value), Value = as.numeric(value),
    LOWER = rep(lower, length(value)), UPPER = rep(upper, length(value)),
    FIX = rep(fixed, length(value))
  )
}

run_r_reference <- function(script, extra_arguments = character()) {
  script <- normalizePath(script, winslash = "/", mustWork = TRUE)
  output <- tempfile("liber-external-reference-", fileext = ".json")
  log <- tempfile("liber-external-reference-", fileext = ".log")
  arguments <- c(
    if (!is.na(external_library) && dir.exists(external_library)) {
      paste0("--library=", external_library)
    } else {
      character()
    },
    paste0("--output=", output),
    extra_arguments
  )
  rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") {
    "Rscript.exe"
  } else {
    "Rscript"
  })

  restore <- list()
  if (.Platform$OS.type == "windows") {
    restore <- list(
      PATH = Sys.getenv("PATH", unset = NA_character_),
      Path = Sys.getenv("Path", unset = NA_character_),
      COMPILER_PATH = Sys.getenv("COMPILER_PATH", unset = NA_character_),
      rxBINPREF = Sys.getenv("rxBINPREF", unset = NA_character_)
    )
    on.exit({
      for (name in names(restore)) {
        if (is.na(restore[[name]])) {
          Sys.unsetenv(name)
        } else {
          do.call(Sys.setenv, stats::setNames(list(restore[[name]]), name))
        }
      }
    }, add = TRUE)
    compiler_candidates <- Sys.glob(
      "C:/rtools*/x86_64-w64-mingw32.static.posix/bin/g++.exe"
    )
    if (!length(compiler_candidates)) {
      stop("No Rtools compiler was found for the external reference process.")
    }
    compiler_directory <- dirname(tail(sort(compiler_candidates), 1L))
    rtools_root <- dirname(dirname(compiler_directory))
    clean_path <- paste(
      c(
        compiler_directory, file.path(rtools_root, "usr", "bin"),
        dirname(rscript), "C:/Windows/System32", "C:/Windows"
      ),
      collapse = .Platform$path.sep
    )
    # Windows may carry both `Path` and `PATH`. rxode2's nested shell otherwise
    # discovers the old NONMEM compiler before Rtools.
    Sys.unsetenv("Path")
    Sys.setenv(
      PATH = clean_path, COMPILER_PATH = compiler_directory,
      rxBINPREF = paste0(gsub("\\\\", "/", compiler_directory), "/")
    )
  }

  status <- suppressWarnings(system2(
    rscript, c(shQuote(script), shQuote(arguments)),
    stdout = log, stderr = log
  ))
  if (!identical(as.integer(status), 0L) || !file.exists(output)) {
    detail <- if (file.exists(log)) {
      paste(tail(readLines(log, warn = FALSE), 30L), collapse = "\n")
    } else {
      "No subprocess log was produced."
    }
    stop("External reference process failed:\n", detail, call. = FALSE)
  }
  jsonlite::fromJSON(output, simplifyVector = TRUE)
}

# KFAS: exact matched scalar linear Gaussian state-space model -----------------
run_case(
  id = "state_kfas", group = "state-space", package = "KFAS",
  capability = "Linear Gaussian state-space inference", comparator = "KFAS",
  required = TRUE,
  code = {
    observation <- c(.3, .1, -.4, .2, .5)
    data <- data.frame(
      ID = 1L, TIME = 0:4, DV = observation, MDV = 0L
    )
    theta <- c(k = .35, stationary_variance = .8, observation_sd = .25)
    model <- LibeRation::nm_model(
      INPUT = names(data), ADVAN = 1,
      PRED = "CL=1;V=1;S1=1;F=0",
      ERROR = paste(
        "M0=0;P0=THETA(2)",
        "A11=exp(-THETA(1)*DT)",
        "Q11=THETA(2)*(1-exp(-2*THETA(1)*DT))",
        "H1=1;R1=THETA(3)*THETA(3)", sep = "\n"
      ),
      THETAS = theta_table(theta, .001, 10),
      KALMAN_CONFIG = LibeRation::nm_kalman_config(
        states = "deviation", initial_mean = "M0",
        initial_covariance = matrix("P0", 1L),
        transition = matrix("A11", 1L),
        process_covariance = matrix("Q11", 1L),
        observation = "H1", observation_variance = "R1",
        baseline = "prediction", by_dvid = FALSE
      )
    )
    score <- LibeRation::nm_objective(model, data, gradient = FALSE)$value
    decoded <- LibeRation::nm_kalman_decode(model, data)

    transition <- exp(-theta[["k"]])
    process_variance <- theta[["stationary_variance"]] *
      (1 - exp(-2 * theta[["k"]]))
    SSMcustom <- KFAS::SSMcustom
    kfas_model <- KFAS::SSModel(
      observation ~ -1 + SSMcustom(
        Z = matrix(1), T = matrix(transition), R = matrix(1),
        Q = matrix(process_variance), a1 = 0,
        P1 = matrix(theta[["stationary_variance"]]),
        P1inf = matrix(0), n = length(observation),
        state_names = "deviation"
      ),
      H = matrix(theta[["observation_sd"]]^2)
    )
    kfas <- KFAS::KFS(
      kfas_model, filtering = "state", smoothing = "none",
      simplify = FALSE
    )
    kfas_objective <- -2 * as.numeric(stats::logLik(kfas_model)) -
      length(observation) * log(2 * pi)
    kfas_filtered <- drop(kfas$att)
    kfas_variance <- drop(kfas$Ptt[1L, 1L, ])

    compare_values(
      "state_kfas", "state-space", "KFAS",
      "Linear Gaussian state-space inference", "KFAS",
      "objective without Gaussian constant", score, kfas_objective, 2e-8,
      required = TRUE
    )
    compare_values(
      "state_kfas", "state-space", "KFAS",
      "Linear Gaussian state-space inference", "KFAS",
      "filtered state", decoded$KF_FILTER_deviation, kfas_filtered, 2e-8,
      required = TRUE
    )
    compare_values(
      "state_kfas", "state-space", "KFAS",
      "Linear Gaussian state-space inference", "KFAS",
      "filtered variance", decoded$KF_FILTER_SD_deviation^2,
      kfas_variance, 2e-8, required = TRUE
    )
  }
)

# pomp/bssm: replicated particle likelihoods against an exact state-space fit -
run_case(
  id = "state_pomp_bssm", group = "state-space",
  package = c("pomp", "bssm"),
  capability = "Particle and partially observed Markov inference",
  comparator = "pomp + bssm", required = FALSE,
  code = {
    observations <- c(1.1, .7, .4, .25)
    theta <- c(k = .4, diffusion = .3, observation_variance = .05)
    substeps <- 64L
    particles <- 4096L
    replicates <- 8L
    data <- data.frame(
      ID = 1L, TIME = 0:3, DV = observations, MDV = 0L
    )
    model <- LibeRation::nm_model(
      INPUT = names(data), ADVAN = 1,
      PRED = "CL=1;V=1;S1=1;F=0",
      ERROR = paste(
        "M0=1", "P0=.2", "DRIFT=-THETA(1)*STATE_x",
        "G0=THETA(2)", "HX=STATE_x", "R0=THETA(3)", sep = "\n"
      ),
      THETAS = theta_table(theta, 0, 2),
      KALMAN_CONFIG = LibeRation::nm_sde_config(
        states = "x", initial_mean = "M0",
        initial_covariance = matrix("P0", 1L),
        drift = "DRIFT", diffusion = matrix("G0", 1L),
        observation = "HX", observation_variance = "R0",
        baseline = "zero", by_dvid = FALSE, filter = "particle",
        method = "euler", substeps = substeps,
        particles = 8192L, seed = 20260724L
      )
    )
    liber_objective <- LibeRation::nm_objective(
      model, data, gradient = FALSE
    )$value

    step <- 1 / substeps
    transition_step <- 1 - theta[["k"]] * step
    transition <- transition_step^substeps
    process_variance <- theta[["diffusion"]]^2 * step *
      sum(transition_step^(2 * (0:(substeps - 1L))))
    initial_gain <- .2 / (.2 + theta[["observation_variance"]])
    conditional_mean <- 1 + initial_gain * (observations[[1L]] - 1)
    conditional_variance <- (1 - initial_gain) * .2
    initial_loglik <- stats::dnorm(
      observations[[1L]], 1,
      sqrt(.2 + theta[["observation_variance"]]), log = TRUE
    )
    rinit <- function(initial_mean, initial_variance, ...) {
      c(x = stats::rnorm(1, initial_mean, sqrt(initial_variance)))
    }
    rprocess <- function(x, k, diffusion, delta.t, ...) {
      c(x = stats::rnorm(
        1, (1 - k * delta.t) * x, diffusion * sqrt(delta.t)
      ))
    }
    dmeasure <- function(y, x, observation_variance, log, ...) {
      stats::dnorm(y, x, sqrt(observation_variance), log = log)
    }
    pomp_model <- pomp::pomp(
      data = data.frame(time = 1:3, y = observations[-1L]),
      times = "time", t0 = 0,
      params = c(
        k = theta[["k"]], diffusion = theta[["diffusion"]],
        observation_variance = theta[["observation_variance"]],
        initial_mean = conditional_mean,
        initial_variance = conditional_variance
      ),
      rinit = rinit,
      rprocess = pomp::discrete_time(rprocess, delta.t = step),
      dmeasure = dmeasure, statenames = "x",
      paramnames = c(
        "k", "diffusion", "observation_variance",
        "initial_mean", "initial_variance"
      )
    )
    set.seed(20260724L)
    pomp_objectives <- replicate(
      replicates,
      -2 * (
        as.numeric(pomp::logLik(pomp::pfilter(pomp_model, Np = particles))) +
          initial_loglik
      ) - length(observations) * log(2 * pi)
    )

    bssm_model <- bssm::ssm_ulg(
      y = observations, Z = 1,
      H = sqrt(theta[["observation_variance"]]),
      T = matrix(transition, 1L),
      R = matrix(sqrt(process_variance), 1L),
      a1 = 1, P1 = matrix(.2, 1L), state_names = "x"
    )
    exact_objective <- -2 * as.numeric(stats::logLik(bssm_model)) -
      length(observations) * log(2 * pi)
    bssm_objectives <- vapply(seq_len(replicates), function(seed) {
      -2 * bssm::bootstrap_filter(
        bssm_model, particles = particles, seed = 20260724L + seed
      )$logLik - length(observations) * log(2 * pi)
    }, numeric(1))

    compare_values(
      "state_pomp_bssm", "state-space", "pomp + bssm",
      "Particle and partially observed Markov inference", "bssm",
      "LibeR particle objective", liber_objective, exact_objective, .12,
      detail = "8192 particles versus exact matched linear-Gaussian likelihood"
    )
    compare_values(
      "state_pomp_bssm", "state-space", "pomp + bssm",
      "Particle and partially observed Markov inference", "pomp",
      "replicated pomp particle objective", mean(pomp_objectives),
      exact_objective, .1,
      detail = "mean of eight independently seeded 4096-particle filters"
    )
    compare_values(
      "state_pomp_bssm", "state-space", "pomp + bssm",
      "Particle and partially observed Markov inference", "bssm",
      "replicated bssm bootstrap objective", mean(bssm_objectives),
      exact_objective, .1,
      detail = "mean of eight independently seeded 4096-particle filters"
    )
  }
)

# glmmTMB: matched normalized likelihoods and independently coordinated fits ---
run_case(
  id = "outcomes_glmmtmb", group = "outcomes",
  package = c("glmmTMB", "TMB"),
  capability = "Binomial and zero-inflated likelihoods",
  comparator = "glmmTMB", required = TRUE,
  code = {
    binary_data <- data.frame(
      ID = 1L, TIME = 0:11,
      DV = c(0, 1, 1, 0, 1, 1, 1, 0, 1, 1, 0, 1), MDV = 0L
    )
    binary_fit <- glmmTMB::glmmTMB(
      DV ~ 1, data = binary_data, family = stats::binomial()
    )
    binary_theta <- unname(glmmTMB::fixef(binary_fit)$cond)
    binary_model <- LibeRation::nm_model(
      INPUT = names(binary_data), ADVAN = 1,
      PRED = "P=1/(1+exp(-THETA(1)));CL=1;V=1;S1=1;F=P",
      THETAS = theta_table(binary_theta),
      OUTCOMES = LibeRation::nm_outcome("bernoulli", prediction = "P")
    )
    binary_objective <- LibeRation::nm_objective(
      binary_model, binary_data, gradient = FALSE
    )$value
    compare_values(
      "outcomes_glmmtmb", "outcomes", "glmmTMB",
      "Binomial and zero-inflated likelihoods", "glmmTMB",
      "Bernoulli objective", binary_objective,
      -2 * as.numeric(stats::logLik(binary_fit)), 2e-8, required = TRUE
    )
    binary_liber_fit <- stats::optim(
      0, function(value) LibeRation::nm_objective(
        binary_model, binary_data, theta = value, gradient = FALSE
      )$value, method = "BFGS", control = list(reltol = 1e-12)
    )
    compare_values(
      "outcomes_glmmtmb", "outcomes", "glmmTMB",
      "Binomial and zero-inflated likelihoods", "glmmTMB",
      "Bernoulli fitted logit", binary_liber_fit$par, binary_theta,
      2e-6, required = TRUE
    )

    zip_data <- data.frame(
      ID = 1L, TIME = 0:19,
      DV = c(0, 0, 1, 2, 0, 3, 1, 0, 2, 4, 0, 1, 3, 0, 2, 1, 0, 5, 2, 0),
      MDV = 0L
    )
    zip_fit <- glmmTMB::glmmTMB(
      DV ~ 1, ziformula = ~1, data = zip_data, family = stats::poisson()
    )
    zip_fixef <- glmmTMB::fixef(zip_fit)
    zip_theta <- c(
      unname(zip_fixef$cond[[1L]]), unname(zip_fixef$zi[[1L]])
    )
    zip_model <- LibeRation::nm_model(
      INPUT = names(zip_data), ADVAN = 1,
      PRED = paste(
        "MU=exp(THETA(1));ZP=1/(1+exp(-THETA(2)))",
        "CL=1;V=1;S1=1;F=MU", sep = "\n"
      ),
      THETAS = theta_table(zip_theta),
      OUTCOMES = LibeRation::nm_outcome(
        "zero_inflated_poisson", prediction = "MU",
        zero_probability = "ZP", max_count = 30
      )
    )
    zip_objective <- LibeRation::nm_objective(
      zip_model, zip_data, gradient = FALSE
    )$value
    compare_values(
      "outcomes_glmmtmb", "outcomes", "glmmTMB",
      "Binomial and zero-inflated likelihoods", "glmmTMB",
      "zero-inflated Poisson objective", zip_objective,
      -2 * as.numeric(stats::logLik(zip_fit)), 2e-7, required = TRUE
    )
    zip_liber_fit <- stats::optim(
      c(log(mean(zip_data$DV) + .1), stats::qlogis(.2)),
      function(value) LibeRation::nm_objective(
        zip_model, zip_data, theta = value, gradient = FALSE
      )$value,
      method = "BFGS", control = list(reltol = 1e-12, maxit = 500)
    )
    compare_values(
      "outcomes_glmmtmb", "outcomes", "glmmTMB",
      "Binomial and zero-inflated likelihoods", "glmmTMB",
      "zero-inflated Poisson fitted parameters",
      zip_liber_fit$par, zip_theta, 2e-4, required = TRUE
    )
  }
)

# hmmTMB: matched binary two-state HMM likelihood and decoding ----------------
run_case(
  id = "hmm_hmmtmb", group = "outcomes",
  package = c("hmmTMB", "TMB"),
  capability = "HMM likelihood filtering and decoding",
  comparator = "hmmTMB", required = FALSE,
  code = {
    hmm_data <- data.frame(
      ID = 1L, TIME = 0:4, DV = c(0, 0, 1, 1, 0),
      MDV = 0L, DVID = 1L
    )
    hmm_model <- LibeRation::nm_model(
      INPUT = names(hmm_data), ADVAN = 1,
      PRED = "CL=1;V=1;S1=1;F=0",
      THETAS = theta_table(1, 0.001, 10, fixed = TRUE),
      ERROR = paste(
        "I1=.6;I2=.4", "T11=.8;T12=.2;T21=.3;T22=.7",
        "E10=.9;E20=.2",
        "E1=ifelse(DV==0,E10,1-E10)",
        "E2=ifelse(DV==0,E20,1-E20)", sep = "\n"
      ),
      HMM_CONFIG = LibeRation::nm_hmm_config(
        states = c("low", "high"), initial = c("I1", "I2"),
        transition = matrix(
          c("T11", "T12", "T21", "T22"), 2L, byrow = TRUE
        ),
        emission = c("E1", "E2"), by_dvid = FALSE
      )
    )
    liber_objective <- LibeRation::nm_objective(
      hmm_model, hmm_data, gradient = FALSE
    )$value
    liber_decoded <- LibeRation::nm_hmm_decode(
      hmm_model, hmm_data, method = "all"
    )

    dat <- data.frame(ID = 0L, y = hmm_data$DV)
    assign("dat", dat, envir = .GlobalEnv)
    on.exit(rm("dat", envir = .GlobalEnv), add = TRUE)
    hmm_reference <- hmmTMB::HMM$new(
      file = file.path(fixture_dir, "hmmtmb-binary.hmm")
    )
    hmm_reference$setup()
    objective <- hmm_reference$tmb_obj()
    parameters <- objective$par
    parameters[grepl("delta", names(parameters))] <- stats::qlogis(.6)
    reference_objective <- 2 * objective$fn(parameters)

    parameter_list <- objective$env$parList(parameters)
    hmm_reference$update_par(parameter_list)
    reference_smoothed <- unname(hmm_reference$state_probs())
    reference_viterbi <- as.integer(hmm_reference$viterbi())
    compare_values(
      "hmm_hmmtmb", "outcomes", "hmmTMB",
      "HMM likelihood filtering and decoding", "hmmTMB",
      "HMM objective", liber_objective, reference_objective, 2e-10
    )
    compare_values(
      "hmm_hmmtmb", "outcomes", "hmmTMB",
      "HMM likelihood filtering and decoding", "hmmTMB",
      "smoothed state probabilities",
      unname(as.matrix(liber_decoded[
        c("HMM_SMOOTH_PROB_low", "HMM_SMOOTH_PROB_high")
      ])),
      reference_smoothed, 2e-10
    )
    compare_values(
      "hmm_hmmtmb", "outcomes", "hmmTMB",
      "HMM likelihood filtering and decoding", "hmmTMB",
      "Viterbi path", liber_decoded$HMM_VITERBI_STATE_INDEX,
      reference_viterbi, 0
    )
  }
)

# deSolve: independent reaction-network integration ----------------------------
run_case(
  id = "numerical_desolve", group = "numerical", package = "deSolve",
  capability = "QSP reaction-network trajectories", comparator = "deSolve",
  required = TRUE,
  code = {
    data <- data.frame(
      ID = 1L, TIME = c(0, 0, .25, .5, 1, 2, 4),
      EVID = c(1L, rep(0L, 6L)), AMT = c(10, rep(0, 6L)),
      CMT = 1L, DV = NA_real_, MDV = c(1L, rep(0L, 6L))
    )
    rate <- .4
    system <- LibeRation::nm_qsp_system(
      c("Drug", "Metabolite"), matrix(c(-1, 1), 2L, 1L),
      rates = "K*Drug", dose_species = "Drug",
      observation_species = "Drug"
    )
    model <- LibeRation::nm_qsp_model(
      system, INPUT = names(data), OUTPUT = c("A1", "A2"),
      PRED = "K=THETA(1);S1=1",
      THETAS = theta_table(rate, .001, 2),
      EXPERIMENTAL = LibeRation::nm_experimental_config(
        TRUE, label = "external deSolve validation"
      )
    )
    liber <- LibeRation::nm_simulate(model, data)
    reference <- deSolve::ode(
      y = c(Drug = 10, Metabolite = 0),
      times = unique(data$TIME),
      func = function(time, state, parameters) {
        conversion <- parameters[["rate"]] * state[["Drug"]]
        list(c(Drug = -conversion, Metabolite = conversion))
      },
      parms = c(rate = rate), method = "lsoda",
      rtol = 1e-12, atol = 1e-14
    )
    reference_index <- match(data$TIME, reference[, "time"])
    compare_values(
      "numerical_desolve", "numerical", "deSolve",
      "QSP reaction-network trajectories", "deSolve",
      "species trajectories", c(liber$A1, liber$A2),
      c(reference[reference_index, "Drug"],
        reference[reference_index, "Metabolite"]),
      2e-7, required = TRUE
    )
    compare_values(
      "numerical_desolve", "numerical", "deSolve",
      "QSP reaction-network trajectories", "deSolve",
      "mass conservation", liber$A1 + liber$A2,
      reference[reference_index, "Drug"] +
        reference[reference_index, "Metabolite"],
      2e-8, required = TRUE
    )
  }
)

# COPASI: independent nonlinear reaction-network integration ------------------
locate_copasi <- function() {
  candidates <- c(
    Sys.which("CopasiSE"),
    file.path(root, ".external-tools", "COPASI", "bin", "CopasiSE.exe"),
    Sys.glob(file.path(
      root, ".external-tools", "COPASI", "*", "bin",
      c("CopasiSE", "CopasiSE.exe")
    )),
    file.path(
      Sys.getenv("COPASIDIR"), "bin", c("CopasiSE", "CopasiSE.exe")
    )
  )
  candidates <- unique(candidates[nzchar(candidates) & file.exists(candidates)])
  if (!length(candidates)) "" else normalizePath(
    candidates[[1L]], winslash = "/", mustWork = TRUE
  )
}
copasi_executable <- locate_copasi()
copasi_example <- file.path(
  dirname(dirname(copasi_executable)), "share", "copasi", "examples",
  "brusselator.cps"
)
copasi_preflight <- function() {
  if (!nzchar(copasi_executable)) return("COPASI CopasiSE is unavailable.")
  if (!file.exists(copasi_example)) {
    return("The installed COPASI Brusselator reference model is unavailable.")
  }
  ""
}

run_case(
  id = "numerical_copasi", group = "numerical", package = "jsonlite",
  capability = "Nonlinear QSP reaction-network trajectories",
  comparator = "COPASI", required = FALSE,
  preflight = copasi_preflight,
  code = {
    report_path <- tempfile("copasi-brusselator-", fileext = ".txt")
    on.exit(unlink(report_path), add = TRUE)
    copasi_output <- system2(
      copasi_executable,
      c(
        "--nologo", "--scheduled-task", "Time-Course",
        "--report-file", shQuote(report_path), shQuote(copasi_example)
      ),
      stdout = TRUE, stderr = TRUE
    )
    copasi_status <- attr(copasi_output, "status")
    if ((!is.null(copasi_status) && copasi_status != 0L) ||
        !file.exists(report_path)) {
      stop(
        "COPASI reference runner failed: ",
        paste(copasi_output, collapse = "\n"), call. = FALSE
      )
    }
    report <- readLines(report_path, warn = FALSE)
    header <- grep("^# Time[[:space:]]+X[[:space:]]+Y", report)
    if (length(header) != 1L) {
      stop("COPASI report did not contain the expected time/X/Y table.",
           call. = FALSE)
    }
    rows <- report[(header + 1L):length(report)]
    rows <- rows[nzchar(trimws(rows))]
    reference <- utils::read.table(
      text = paste(rows, collapse = "\n"), header = FALSE,
      col.names = c("TIME", "X", "Y")
    )
    reference <- reference[reference$TIME <= 10, , drop = FALSE]

    qsp_data <- rbind(
      data.frame(
        ID = 1L, TIME = 0, EVID = 1L, AMT = 3,
        CMT = 1L, DV = NA_real_, MDV = 1L
      ),
      data.frame(
        ID = 1L, TIME = 0, EVID = 1L, AMT = 3,
        CMT = 2L, DV = NA_real_, MDV = 1L
      ),
      data.frame(
        ID = 1L, TIME = reference$TIME, EVID = 0L, AMT = 0,
        CMT = 1L, DV = NA_real_, MDV = 0L
      )
    )
    qsp_system <- LibeRation::nm_qsp_system(
      c("X", "Y"),
      matrix(c(1, 0, 1, -1, -1, 1, -1, 0), 2L, 4L),
      rates = c("SRC", "X*X*Y", "B*X", "X"),
      dose_species = "X", observation_species = "X"
    )
    qsp_model <- LibeRation::nm_qsp_model(
      qsp_system, INPUT = names(qsp_data), OUTPUT = c("A1", "A2"),
      PRED = "SRC=THETA(1);B=THETA(2);S1=1;S2=1",
      THETAS = theta_table(c(.5, 3), .001, 10, fixed = TRUE),
      EXPERIMENTAL = LibeRation::nm_experimental_config(
        TRUE, label = "external COPASI validation"
      )
    )
    liber <- LibeRation::nm_simulate(qsp_model, qsp_data)
    observed <- qsp_data$EVID == 0L
    compare_values(
      "numerical_copasi", "numerical", "COPASI",
      "Nonlinear QSP reaction-network trajectories", "COPASI LSODA",
      "Brusselator X/Y trajectories",
      c(liber$A1[observed], liber$A2[observed]),
      c(reference$X, reference$Y), 2e-5
    )
  }
)

# SciML/Sundials: independent ODE, SDE, DDE, and DAE implementations ----------
locate_julia <- function() {
  candidates <- c(
    Sys.which("julia"),
    Sys.glob(file.path(
      Sys.getenv("USERPROFILE"), ".julia", "juliaup", "julia-*",
      "bin", "julia.exe"
    ))
  )
  candidates <- unique(candidates[nzchar(candidates) & file.exists(candidates)])
  if (!length(candidates)) "" else normalizePath(
    tail(sort(candidates), 1L), winslash = "/", mustWork = TRUE
  )
}
julia_executable <- locate_julia()
julia_project <- file.path(root, ".external-tools", "julia-project")
julia_preflight <- function() {
  if (!nzchar(julia_executable)) return("Julia executable is unavailable.")
  if (!file.exists(file.path(julia_project, "Project.toml"))) {
    return("The isolated SciML Julia environment is unavailable.")
  }
  ""
}

run_case(
  id = "numerical_sciml", group = "numerical", package = "jsonlite",
  capability = "SDE DDE DAE and QSP numerical contracts",
  comparator = "SciML and Sundials", required = FALSE,
  preflight = julia_preflight,
  code = {
    reference_path <- tempfile("sciml-reference-", fileext = ".json")
    on.exit(unlink(reference_path), add = TRUE)
    command_output <- system2(
      julia_executable,
      c(
        paste0("--project=", shQuote(julia_project)),
        shQuote(file.path(fixture_dir, "sciml-reference.jl")),
        shQuote(reference_path)
      ),
      stdout = TRUE, stderr = TRUE
    )
    command_status <- attr(command_output, "status")
    if (!is.null(command_status) && command_status != 0L) {
      stop(
        "Julia/SciML reference runner failed: ",
        paste(command_output, collapse = "\n"), call. = FALSE
      )
    }
    reference <- jsonlite::read_json(reference_path, simplifyVector = TRUE)
    experimental <- LibeRation::nm_experimental_config(
      TRUE, label = "external SciML validation"
    )

    qsp_times <- as.numeric(reference$qsp$times)
    qsp_data <- data.frame(
      ID = 1L, TIME = c(0, qsp_times),
      EVID = c(1L, rep(0L, length(qsp_times))),
      AMT = c(10, rep(0, length(qsp_times))),
      CMT = 1L, DV = NA_real_,
      MDV = c(1L, rep(0L, length(qsp_times)))
    )
    qsp_system <- LibeRation::nm_qsp_system(
      c("Drug", "Metabolite"), matrix(c(-1, 1), 2L, 1L),
      rates = "K*Drug", dose_species = "Drug",
      observation_species = "Drug"
    )
    qsp_model <- LibeRation::nm_qsp_model(
      qsp_system, INPUT = names(qsp_data), OUTPUT = c("A1", "A2"),
      PRED = "K=THETA(1);S1=1",
      THETAS = theta_table(.4, .001, 2), EXPERIMENTAL = experimental
    )
    qsp_liber <- LibeRation::nm_simulate(qsp_model, qsp_data)
    qsp_liber <- c(qsp_liber$A1[-1L], qsp_liber$A2[-1L])
    compare_values(
      "numerical_sciml", "numerical", "Julia/SciML",
      "SDE DDE DAE and QSP numerical contracts", "OrdinaryDiffEq",
      "QSP species trajectories", qsp_liber,
      as.numeric(reference$qsp$states), 2e-7
    )

    advan14_times <- as.numeric(reference$advan14$times)
    advan14_data <- data.frame(
      ID = 1L, TIME = c(0, advan14_times),
      EVID = c(1L, rep(0L, length(advan14_times))),
      AMT = c(100, rep(0, length(advan14_times))),
      CMT = 1L, DV = NA_real_,
      MDV = c(1L, rep(0L, length(advan14_times)))
    )
    advan14_model <- LibeRation::nm_model(
      INPUT = names(advan14_data), OUTPUT = c("A1", "A2"),
      ADVAN = 14, DOSECMP = 1, OBSCMP = 2,
      PRED = "KFAST=THETA(1);KSLOW=THETA(2);S2=1",
      DES = paste(
        "DADT(1)=-KFAST*A(1)",
        "DADT(2)=KFAST*A(1)-KSLOW*A(2)", sep = "\n"
      ),
      THETAS = theta_table(c(1000, 1), .001, 2000, fixed = TRUE),
      ODE_CONTROL = list(rtol = 1e-9, atol = 1e-12)
    )
    advan14_liber <- LibeRation::nm_simulate(
      advan14_model, advan14_data
    )
    advan14_liber <- c(
      advan14_liber$A1[-1L], advan14_liber$A2[-1L]
    )
    compare_values(
      "numerical_sciml", "numerical", "Julia/SciML",
      "SDE DDE DAE and QSP numerical contracts", "OrdinaryDiffEq Rodas5P",
      "ADVAN14 stiff-state trajectories", advan14_liber,
      as.numeric(reference$advan14$states), 2e-6
    )

    dde_times <- as.numeric(reference$dde$times)
    dde_data <- data.frame(
      ID = 1L, TIME = c(0, dde_times),
      EVID = c(1L, rep(0L, length(dde_times))),
      AMT = c(10, rep(0, length(dde_times))),
      CMT = 1L, DV = NA_real_,
      MDV = c(1L, rep(0L, length(dde_times)))
    )
    dde_model <- LibeRation::nm_model(
      INPUT = names(dde_data), ADVAN = 6, DOSECMP = 1, OBSCMP = 1,
      PRED = "K=THETA(1);B=THETA(2);TAU=THETA(3);S1=1",
      DES = "DADT(1)=-K*A(1)+B*LAG(A(1),TAU)",
      THETAS = theta_table(c(.4, .15, 1), .0001, 2),
      DDE_CONFIG = LibeRation::nm_dde_config(
        history = 10, step = .001, minimum_delay = 1
      ),
      EXPERIMENTAL = experimental
    )
    dde_liber <- LibeRation::nm_simulate(dde_model, dde_data)$IPRED[-1L]
    compare_values(
      "numerical_sciml", "numerical", "Julia/SciML",
      "SDE DDE DAE and QSP numerical contracts", "DelayDiffEq",
      "DDE state trajectory", dde_liber,
      as.numeric(reference$dde$state), 1.2e-4
    )

    dae_times <- as.numeric(reference$dae$times)
    dae_data <- data.frame(
      ID = 1L, TIME = c(0, dae_times),
      EVID = c(1L, rep(0L, length(dae_times))),
      AMT = c(10, rep(0, length(dae_times))),
      CMT = 1L, DV = NA_real_,
      MDV = c(1L, rep(0L, length(dae_times)))
    )
    dae_model <- LibeRation::nm_model(
      INPUT = names(dae_data), OUTPUT = "A1",
      ADVAN = 6, DOSECMP = 1, OBSCMP = 1,
      PRED = "K=THETA(1);S1=1", DES = "DADT(1)=-Z",
      ALG = "RES(1)=Z*Z-K*A(1)",
      THETAS = theta_table(.16, .001, 2),
      DAE_CONFIG = LibeRation::nm_dae_config(
        "Z", initial = 1, tolerance = 1e-11, maxit = 20L,
        sparsity = matrix(TRUE, 1L)
      ),
      EXPERIMENTAL = experimental
    )
    dae_liber <- LibeRation::nm_simulate(dae_model, dae_data)$IPRED[-1L]
    compare_values(
      "numerical_sciml", "numerical", "Julia/SciML",
      "SDE DDE DAE and QSP numerical contracts", "Sundials IDA",
      "DAE differential-state trajectory", dae_liber,
      as.numeric(reference$dae$state), 3e-6
    )

    subjects <- as.integer(reference$sde$trajectories)
    sde_data <- data.frame(
      ID = rep(seq_len(subjects), each = 2L),
      TIME = rep(c(0, 1), subjects), DV = NA_real_, MDV = 0L
    )
    sde_model <- LibeRation::nm_model(
      INPUT = names(sde_data), ADVAN = 1,
      PRED = "CL=1;V=1;S1=1;F=0",
      ERROR = paste(
        "M0=1", "P0=0", "DRIFT=-THETA(1)*STATE_x",
        "G0=THETA(2)", "HX=STATE_x", "R0=0", sep = "\n"
      ),
      THETAS = theta_table(c(.4, .3), 0, 2),
      KALMAN_CONFIG = LibeRation::nm_sde_config(
        states = "x", initial_mean = "M0",
        initial_covariance = matrix("P0", 1L),
        drift = "DRIFT", diffusion = matrix("G0", 1L),
        observation = "HX", observation_variance = "R0",
        baseline = "zero", by_dvid = FALSE, filter = "ukf",
        method = "euler", substeps = 64L
      )
    )
    sde_liber <- LibeRation::nm_simulate(
      sde_model, sde_data, residual = TRUE, seed = 20260724L
    )
    sde_terminal <- sde_liber$DV[sde_liber$TIME == 1]
    sde_variance <- mean(c(
      stats::var(sde_terminal), as.numeric(reference$sde$terminal_variance)
    ))
    compare_values(
      "numerical_sciml", "numerical", "Julia/SciML",
      "SDE DDE DAE and QSP numerical contracts", "StochasticDiffEq",
      "SDE terminal mean", mean(sde_terminal),
      as.numeric(reference$sde$terminal_mean),
      6 * sqrt(2 * sde_variance / subjects),
      detail = "independent seeded Monte Carlo implementations"
    )
    compare_values(
      "numerical_sciml", "numerical", "Julia/SciML",
      "SDE DDE DAE and QSP numerical contracts", "StochasticDiffEq",
      "SDE terminal variance", stats::var(sde_terminal),
      as.numeric(reference$sde$terminal_variance),
      6 * sde_variance * sqrt(4 / (subjects - 1)),
      detail = "independent seeded Monte Carlo implementations"
    )
  }
)

# nlmixr2: matched FO, FOCE, and FOCEI population estimation ------------------
source(file.path(fixture_dir, "nlmixr2-fixtures.R"), local = TRUE)

run_case(
  id = "population_nlmixr2", group = "population",
  package = c("nlmixr2", "nlmixr2est", "rxode2"),
  capability = "FO FOCE and FOCEI population estimation",
  comparator = "nlmixr2", required = FALSE,
  code = {
    data_path <- file.path(root, "validation", "nonmem", "estimation.dat")
    reference <- run_r_reference(
      file.path(fixture_dir, "nlmixr2-reference.R"),
      paste0("--data=", normalizePath(
        data_path, winslash = "/", mustWork = TRUE
      ))
    )
    data <- utils::read.table(
      data_path,
      col.names = c("ID", "TIME", "EVID", "AMT", "CMT", "DV", "MDV"),
      na.strings = "."
    )
    model <- LibeRation::nm_model(
      INPUT = names(data), ADVAN = 1, TRANS = 2,
      DOSECMP = 1, OBSCMP = 1,
      PRED = "CL=THETA(1)*exp(ETA(1));V=THETA(2);S1=V",
      ERROR = "Y=F+ERR(1)",
      THETAS = data.frame(
        THETA = 1:2, Value = c(1, 20), LOWER = c(.1, .1),
        UPPER = c(10, 100), FIX = c(FALSE, TRUE)
      ),
      OMEGAS = data.frame(OMEGA = 1L, Value = .1, FIX = TRUE),
      SIGMAS = data.frame(SIGMA = 1L, Value = .04, FIX = TRUE),
      LIK_CONFIG = LibeRation::nm_lik_config(
        error = "additive", sigma_parameterization = "variance"
      )
    )
    for (method in c("FO", "FOCE", "FOCEI")) {
      fit <- LibeRation::nm_est(
        model, data, method = method, maxit = 300L, eta_maxit = 150L,
        tolerance = 1e-8, collect_output = TRUE
      )
      expected <- reference$methods[[method]]
      compare_values(
        "population_nlmixr2", "population", "nlmixr2",
        "FO FOCE and FOCEI population estimation", "nlmixr2",
        paste(method, "population clearance"),
        unname(as.numeric(fit$theta[[1L]])),
        unname(as.numeric(expected$clearance)), 2e-5,
        detail = "Matched fixed-variance one-compartment population model"
      )
      if (identical(method, "FO")) {
        compare_values(
          "population_nlmixr2", "population", "nlmixr2",
          "FO FOCE and FOCEI population estimation", "nlmixr2",
          "FO objective", fit$objective,
          unname(as.numeric(expected$objective)), 2e-5,
          detail = "FO likelihood conventions are identical for this fixture"
        )
      } else {
        compare_values(
          "population_nlmixr2", "population", "nlmixr2",
          "FO FOCE and FOCEI population estimation", "nlmixr2",
          paste(method, "empirical Bayes estimates"),
          unname(as.numeric(fit$eta)),
          unname(as.numeric(expected$eta)), 2e-5,
          detail = paste(
            "FOCE/Laplace objectives omit different constants; population",
            "parameters and conditional modes are compared directly"
          )
        )
      }
    }
  }
)

# nlmixr2: advanced population features ---------------------------------------
run_case(
  id = "population_nlmixr2_advanced", group = "population",
  package = c("nlmixr2", "nlmixr2est", "rxode2"),
  capability = paste(
    "Estimated variance correlated OMEGA IOV BLQ and",
    "time-varying covariates"
  ),
  comparator = "nlmixr2", required = FALSE,
  code = {
    reference <- run_r_reference(file.path(
      fixture_dir, "nlmixr2-advanced-reference.R"
    ))

    variance_data <- nlmixr2_population_data()
    variance_model <- LibeRation::nm_model(
      INPUT = names(variance_data), ADVAN = 1, TRANS = 2,
      DOSECMP = 1, OBSCMP = 1,
      PRED = "CL=THETA(1)*exp(ETA(1));V=THETA(2);S1=V",
      ERROR = "Y=F+ERR(1)",
      THETAS = data.frame(
        THETA = 1:2, Value = c(1.8, 20), LOWER = c(.2, 20),
        UPPER = c(8, 20), FIX = c(FALSE, TRUE)
      ),
      OMEGAS = data.frame(OMEGA = 1L, Value = .12, FIX = FALSE),
      SIGMAS = data.frame(SIGMA = 1L, Value = .18^2, FIX = FALSE),
      LIK_CONFIG = LibeRation::nm_lik_config(
        error = "additive", sigma_parameterization = "variance"
      )
    )
    variance_fit <- LibeRation::nm_est(
      variance_model, variance_data, method = "FOCEI",
      maxit = 300L, eta_maxit = 150L, tolerance = 1e-8,
      collect_output = TRUE
    )
    expected <- reference$cases$estimated_variance
    compare_values(
      "population_nlmixr2_advanced", "population", "nlmixr2",
      "Estimated population variance", "nlmixr2",
      "estimated-variance fixed effect",
      variance_fit$theta[[1L]], expected$clearance, .01,
      detail = "CL is compared on the natural scale"
    )
    compare_values(
      "population_nlmixr2_advanced", "population", "nlmixr2",
      "Estimated population variance", "nlmixr2",
      "estimated OMEGA variance",
      variance_fit$omega[[1L]], expected$omega, .005
    )
    compare_values(
      "population_nlmixr2_advanced", "population", "nlmixr2",
      "Estimated population variance", "nlmixr2",
      "estimated residual standard deviation",
      sqrt(variance_fit$sigma[[1L]]), expected$residual_sd, .002,
      detail = "LibeRation variance is converted to nlmixr2 residual SD"
    )
    compare_values(
      "population_nlmixr2_advanced", "population", "nlmixr2",
      "Estimated population variance", "nlmixr2",
      "estimated-variance empirical Bayes estimates",
      as.numeric(variance_fit$eta), as.numeric(expected$eta), .003
    )

    correlated_data <- nlmixr2_population_data(
      32L, correlated = TRUE
    )
    correlated_model <- LibeRation::nm_model(
      INPUT = names(correlated_data), ADVAN = 1, TRANS = 2,
      DOSECMP = 1, OBSCMP = 1,
      PRED = paste(
        "CL=THETA(1)*exp(ETA(1))",
        "V=THETA(2)*exp(ETA(2))", "S1=V", sep = ";"
      ),
      ERROR = "Y=F+ERR(1)",
      THETAS = data.frame(
        THETA = 1:2, Value = c(1.8, 18), LOWER = c(.2, 5),
        UPPER = c(8, 60), FIX = FALSE
      ),
      OMEGAS = data.frame(
        OMEGA = 1:3, ROW = c(1L, 2L, 2L), COL = c(1L, 1L, 2L),
        Value = c(.12, .03, .18), FIX = FALSE
      ),
      SIGMAS = data.frame(SIGMA = 1L, Value = .15^2, FIX = TRUE),
      LIK_CONFIG = LibeRation::nm_lik_config(
        error = "additive", omega = "full",
        sigma_parameterization = "variance"
      )
    )
    correlated_fit <- LibeRation::nm_est(
      correlated_model, correlated_data, method = "FOCEI",
      maxit = 400L, eta_maxit = 180L, tolerance = 1e-8,
      collect_output = TRUE
    )
    expected <- reference$cases$correlated_omega
    compare_values(
      "population_nlmixr2_advanced", "population", "nlmixr2",
      "Correlated random effects", "nlmixr2",
      "correlated-OMEGA fixed effects",
      correlated_fit$theta, as.numeric(expected$theta), .01
    )
    compare_values(
      "population_nlmixr2_advanced", "population", "nlmixr2",
      "Correlated random effects", "nlmixr2",
      "estimated full OMEGA lower triangle",
      correlated_fit$omega, as.numeric(expected$omega), .005,
      detail = "Both results use variance/covariance coordinates"
    )
    compare_values(
      "population_nlmixr2_advanced", "population", "nlmixr2",
      "Correlated random effects", "nlmixr2",
      "correlated-OMEGA empirical Bayes estimates",
      as.numeric(correlated_fit$eta), as.numeric(expected$eta), .003
    )

    iov_data <- nlmixr2_iov_data()
    iov_model <- LibeRation::nm_model(
      INPUT = names(iov_data), ADVAN = 1, TRANS = 2,
      DOSECMP = 1, OBSCMP = 1,
      PRED = "CL=THETA(1)*exp(ETA(1)+ETA(2));V=THETA(2);S1=V",
      ERROR = "Y=F+ERR(1)",
      THETAS = data.frame(
        THETA = 1:2, Value = c(1.8, 20), LOWER = c(.2, 20),
        UPPER = c(8, 20), FIX = c(FALSE, TRUE)
      ),
      OMEGAS = data.frame(
        OMEGA = 1:2, Value = c(.08, .04), FIX = TRUE
      ),
      SIGMAS = data.frame(SIGMA = 1L, Value = .15^2, FIX = TRUE),
      LIK_CONFIG = LibeRation::nm_lik_config(
        error = "additive", sigma_parameterization = "variance",
        iov = 1L, occasion_col = "OCC"
      )
    )
    iov_fit <- LibeRation::nm_est(
      iov_model, iov_data, method = "FOCEI",
      maxit = 300L, eta_maxit = 180L, tolerance = 1e-8,
      collect_output = TRUE
    )
    expected <- reference$cases$iov
    compare_values(
      "population_nlmixr2_advanced", "population", "nlmixr2",
      "Inter-occasion variability", "nlmixr2",
      "IOV population clearance",
      iov_fit$theta[[1L]], expected$clearance, .005
    )
    compare_values(
      "population_nlmixr2_advanced", "population", "nlmixr2",
      "Inter-occasion variability", "nlmixr2",
      "between-subject ETA modes",
      iov_fit$eta[, 1L], as.numeric(expected$eta), .002
    )
    compare_values(
      "population_nlmixr2_advanced", "population", "nlmixr2",
      "Inter-occasion variability", "nlmixr2",
      "occasion-specific ETA modes",
      as.numeric(iov_fit$eta[, 2:3, drop = FALSE]),
      as.numeric(expected$iov), .002,
      detail = "nlmixr2's ID/OCC table is reshaped to LibeRation ETA columns"
    )

    for (method in c("m3", "m4")) {
      blq_data <- nlmixr2_blq_data(method)
      blq_model <- LibeRation::nm_model(
        INPUT = names(blq_data), ADVAN = 1, TRANS = 2,
        DOSECMP = 1, OBSCMP = 1,
        PRED = "CL=THETA(1)*exp(ETA(1));V=THETA(2);S1=V",
        ERROR = "Y=F+ERR(1)",
        THETAS = data.frame(
          THETA = 1:2, Value = c(1.8, 20), LOWER = c(.2, 20),
          UPPER = c(8, 20), FIX = c(FALSE, TRUE)
        ),
        OMEGAS = data.frame(OMEGA = 1L, Value = .12, FIX = TRUE),
        SIGMAS = data.frame(SIGMA = 1L, Value = .15^2, FIX = TRUE),
        LIK_CONFIG = LibeRation::nm_lik_config(
          error = "additive", sigma_parameterization = "variance",
          blq_method = method
        )
      )
      blq_fit <- LibeRation::nm_est(
        blq_model, blq_data, method = "FOCEI",
        maxit = 300L, eta_maxit = 180L, tolerance = 1e-8,
        collect_output = TRUE
      )
      expected <- reference$cases[[paste0("blq_", method)]]
      compare_values(
        "population_nlmixr2_advanced", "population", "nlmixr2",
        "Censored observations", "nlmixr2",
        paste(toupper(method), "population clearance"),
        blq_fit$theta[[1L]], expected$clearance, .01
      )
      compare_values(
        "population_nlmixr2_advanced", "population", "nlmixr2",
        "Censored observations", "nlmixr2",
        paste(toupper(method), "empirical Bayes estimates"),
        as.numeric(blq_fit$eta), as.numeric(expected$eta), .006
      )
    }

    covariate_data <- nlmixr2_timevarying_data()
    covariate_model <- LibeRation::nm_model(
      INPUT = names(covariate_data), PRED_MODE = "pred",
      COVARIATES = "WT",
      PRED = paste(
        "CL=THETA(1)*exp(THETA(2)*(WT-70)/20+ETA(1))",
        "F=100/20*exp(-CL/20*TIME)", sep = ";"
      ),
      ERROR = "Y=F+ERR(1)",
      THETAS = data.frame(
        THETA = 1:2, Value = c(1.8, .5), LOWER = c(.2, -2),
        UPPER = c(8, 2), FIX = FALSE
      ),
      OMEGAS = data.frame(OMEGA = 1L, Value = .1, FIX = TRUE),
      SIGMAS = data.frame(SIGMA = 1L, Value = .12^2, FIX = TRUE),
      LIK_CONFIG = LibeRation::nm_lik_config(
        error = "additive", sigma_parameterization = "variance"
      )
    )
    covariate_fit <- LibeRation::nm_est(
      covariate_model, covariate_data, method = "FOCEI",
      maxit = 300L, eta_maxit = 180L, tolerance = 1e-8,
      collect_output = TRUE
    )
    expected <- reference$cases$timevarying_covariate
    compare_values(
      "population_nlmixr2_advanced", "population", "nlmixr2",
      "Time-varying covariates", "nlmixr2",
      "time-varying covariate fixed effects",
      covariate_fit$theta, as.numeric(expected$theta), .01
    )
    compare_values(
      "population_nlmixr2_advanced", "population", "nlmixr2",
      "Time-varying covariates", "nlmixr2",
      "time-varying covariate ETA modes",
      as.numeric(covariate_fit$eta), as.numeric(expected$eta), .006
    )
  }
)

# Independent analytic gates for features without a native nlmixr2 contract --
run_case(
  id = "population_mixture_analytic", group = "population",
  package = "stats", capability = "Subject-level finite mixtures",
  comparator = "Independent aggregated Gaussian likelihood",
  required = TRUE,
  code = {
    mixture_data <- nlmixr2_mixture_data()
    probability <- c(.65, .35)
    residual_sd <- .25
    subjects <- split(mixture_data$DV, mixture_data$ID)
    component_loglik <- function(theta) {
      do.call(rbind, lapply(subjects, function(observation) {
        vapply(theta, function(location) {
          sum(stats::dnorm(
            observation, location, residual_sd, log = TRUE
          ))
        }, numeric(1))
      }))
    }
    mixture_objective <- function(theta) {
      loglik <- component_loglik(theta)
      -2 * sum(vapply(seq_len(nrow(loglik)), function(row) {
        terms <- log(probability) + loglik[row, ]
        anchor <- max(terms)
        anchor + log(sum(exp(terms - anchor)))
      }, numeric(1)))
    }
    reference <- stats::optim(
      c(1, 4), mixture_objective, method = "L-BFGS-B",
      lower = c(0, 2.5), upper = c(2.5, 6),
      control = list(factr = 1e7, pgtol = 1e-10)
    )
    model <- LibeRation::nm_model(
      INPUT = names(mixture_data), PRED_MODE = "pred",
      PRED = "F=ifelse(MIXNUM==1,THETA(1),THETA(2))",
      ERROR = "Y=F+ERR(1)",
      THETAS = data.frame(
        THETA = 1:2, Value = c(1, 4), LOWER = c(0, 2.5),
        UPPER = c(2.5, 6), FIX = FALSE
      ),
      SIGMAS = data.frame(
        SIGMA = 1L, Value = residual_sd^2, FIX = TRUE
      ),
      LIK_CONFIG = LibeRation::nm_lik_config(
        error = "additive", sigma_parameterization = "variance",
        mixtures = LibeRation::nm_mixture(
          probability, c("low", "high")
        )
      )
    )
    fit <- LibeRation::nm_est(
      model, mixture_data, method = "FOCEI",
      maxit = 300L, eta_maxit = 100L, tolerance = 1e-9,
      collect_output = TRUE
    )
    compare_values(
      "population_mixture_analytic", "population", "stats",
      "Subject-level finite mixtures",
      "Independent aggregated Gaussian likelihood",
      "mixture component estimates", fit$theta, reference$par, 2e-4
    )
    # LibeRation intentionally omits the Gaussian log(2*pi) constant from
    # its normal objective. Restore it before comparing the exact likelihood.
    normalized_objective <- fit$objective +
      nrow(mixture_data) * log(2 * pi)
    compare_values(
      "population_mixture_analytic", "population", "stats",
      "Subject-level finite mixtures",
      "Independent aggregated Gaussian likelihood",
      "normalized subject-mixture objective",
      normalized_objective, reference$value, 5e-4
    )
    loglik <- component_loglik(fit$theta)
    analytic_posterior <- t(vapply(seq_len(nrow(loglik)), function(row) {
      terms <- log(probability) + loglik[row, ]
      weight <- exp(terms - max(terms))
      weight / sum(weight)
    }, numeric(2)))
    liber_posterior <- LibeRation::nm_mixture_posterior(
      fit, mixture_data
    )
    compare_values(
      "population_mixture_analytic", "population", "stats",
      "Subject-level finite mixtures",
      "Independent aggregated Gaussian likelihood",
      "mixture posterior probabilities",
      as.numeric(as.matrix(
        liber_posterior[c("P_low", "P_high")]
      )),
      as.numeric(analytic_posterior), 2e-7
    )
  }
)

run_case(
  id = "population_prior_analytic", group = "population",
  package = "stats", capability = "Population parameter priors",
  comparator = "Closed-form Gaussian MAP and analytic prior densities",
  required = TRUE,
  code = {
    prior_data <- nlmixr2_prior_data()
    observation_sd <- .4
    prior_mean <- 1.5
    prior_sd <- .2
    expected_map <- (
      sum(prior_data$DV) / observation_sd^2 +
        prior_mean / prior_sd^2
    ) / (
      nrow(prior_data) / observation_sd^2 + 1 / prior_sd^2
    )
    map_model <- LibeRation::nm_model(
      INPUT = names(prior_data), PRED_MODE = "pred",
      PRED = "F=THETA(1)", ERROR = "Y=F+ERR(1)",
      THETAS = data.frame(
        THETA = 1L, Value = 1, LOWER = -5, UPPER = 8, FIX = FALSE
      ),
      SIGMAS = data.frame(
        SIGMA = 1L, Value = observation_sd^2, FIX = TRUE
      ),
      LIK_CONFIG = LibeRation::nm_lik_config(
        error = "additive", sigma_parameterization = "variance",
        priors = LibeRation::nm_prior(
          "THETA1", "normal", mean = prior_mean, sd = prior_sd
        )
      )
    )
    map_fit <- LibeRation::nm_est(
      map_model, prior_data, method = "FOCEI",
      maxit = 200L, eta_maxit = 80L, tolerance = 1e-10,
      collect_output = TRUE
    )
    compare_values(
      "population_prior_analytic", "population", "stats",
      "Population parameter priors",
      "Closed-form Gaussian MAP and analytic prior densities",
      "normal-prior MAP estimate",
      map_fit$theta[[1L]], expected_map, 2e-6
    )
    expected_objective <- sum(
      log(observation_sd^2) +
        (prior_data$DV - expected_map)^2 / observation_sd^2
    ) - 2 * stats::dnorm(
      expected_map, prior_mean, prior_sd, log = TRUE
    )
    compare_values(
      "population_prior_analytic", "population", "stats",
      "Population parameter priors",
      "Closed-form Gaussian MAP and analytic prior densities",
      "normal-prior penalized objective",
      map_fit$objective, expected_objective, 2e-6
    )

    event_data <- data.frame(
      ID = 1L, TIME = 0, EVID = 1L, AMT = 100, CMT = 1L,
      DV = NA_real_, MDV = 1L
    )
    prior_rows <- do.call(rbind, list(
      LibeRation::nm_prior(
        "THETA1", "normal", mean = 1.5, sd = .7
      ),
      LibeRation::nm_prior(
        "THETA2", "half_normal", mean = 18, sd = 4
      ),
      LibeRation::nm_prior(
        "SIGMA1", "lognormal", mean = -1, sd = .4
      ),
      LibeRation::nm_prior(
        "OMEGA1", "inverse_gamma", shape = 3, rate = .2
      )
    ))
    make_prior_model <- function(priors = NULL) {
      LibeRation::nm_model(
        INPUT = names(event_data), ADVAN = 1,
        PRED = "CL=THETA(1)*exp(ETA(1));V=THETA(2);S1=V",
        ERROR = "Y=F+ERR(1)",
        THETAS = data.frame(
          THETA = 1:2, Value = c(2, 20), FIX = TRUE
        ),
        OMEGAS = data.frame(
          OMEGA = 1L, Value = .12, FIX = TRUE
        ),
        SIGMAS = data.frame(
          SIGMA = 1L, Value = .25, FIX = TRUE
        ),
        LIK_CONFIG = LibeRation::nm_lik_config(priors = priors)
      )
    }
    values <- c(2, 20, .25, .12)
    prior_model <- make_prior_model(prior_rows)
    prior_parameters <- list(
      theta = values[1:2], sigma = values[[3L]], omega = values[[4L]]
    )
    observed_prior <- LibeRation:::.nm_prior_nll(
      prior_model, prior_parameters
    )
    observed_gradient <- LibeRation:::.nm_prior_nll_native_gradient(
      prior_model, prior_parameters
    )
    expected_log_density <- c(
      stats::dnorm(values[[1L]], 1.5, .7, log = TRUE),
      log(2) + stats::dnorm(values[[2L]], 18, 4, log = TRUE),
      stats::dlnorm(values[[3L]], -1, .4, log = TRUE),
      3 * log(.2) - lgamma(3) -
        4 * log(values[[4L]]) - .2 / values[[4L]]
    )
    expected_gradient <- c(
      2 * (values[[1L]] - 1.5) / .7^2,
      2 * (values[[2L]] - 18) / 4^2,
      2 / values[[3L]] +
        2 * (log(values[[3L]]) + 1) / (.4^2 * values[[3L]]),
      2 * 4 / values[[4L]] - 2 * .2 / values[[4L]]^2
    )
    compare_values(
      "population_prior_analytic", "population", "stats",
      "Population parameter priors",
      "Closed-form Gaussian MAP and analytic prior densities",
      "all supported prior-family contributions",
      observed_prior,
      -2 * sum(expected_log_density), 2e-10
    )
    compare_values(
      "population_prior_analytic", "population", "stats",
      "Population parameter priors",
      "Closed-form Gaussian MAP and analytic prior densities",
      "all supported prior-family gradients",
      observed_gradient,
      expected_gradient, 2e-9
    )
  }
)

# mapbayr: matched MAP ETA recovery on its distributed reference model ---------
configure_windows_compiler <- function() {
  if (.Platform$OS.type != "windows") return("")
  candidates <- Sys.glob(
    "C:/rtools*/x86_64-w64-mingw32.static.posix/bin/g++.exe"
  )
  if (!length(candidates)) {
    return("No C++ compiler was found for mapbayr/mrgsolve model compilation.")
  }
  compiler_directory <- dirname(tail(sort(candidates), 1L))
  rtools_root <- dirname(dirname(compiler_directory))
  Sys.setenv(PATH = paste(
    compiler_directory, file.path(rtools_root, "usr", "bin"),
    Sys.getenv("PATH"), sep = .Platform$path.sep
  ), R_MAKEVARS_USER = file.path(root, "tools", "Makevars.rtools45"))
  if (!nzchar(Sys.which("g++"))) {
    return("The detected Windows C++ compiler could not be added to PATH.")
  }
  ""
}

run_case(
  id = "dosing_mapbayr", group = "dosing",
  package = c("mapbayr", "mrgsolve"),
  capability = "MAP individual parameters and predictions",
  comparator = "mapbayr", required = FALSE,
  preflight = configure_windows_compiler,
  code = {
    map_model <- mapbayr::exmodel(
      1, add_exdata = TRUE, ID = 1, cache = FALSE, quiet = TRUE
    )
    map_fit <- mapbayr::mapbayest(
      map_model, method = "L-BFGS-B", hessian = FALSE,
      verbose = FALSE, progress = FALSE,
      control = list(maxit = 500, factr = 1e7)
    )
    map_eta <- as.numeric(mapbayr::get_eta(map_fit))

    data_path <- system.file(
      "exmodel", "data_to_fit001.csv", package = "mapbayr"
    )
    data <- utils::read.csv(data_path, na.strings = c(".", "NA"))
    data <- data[data$ID == 1L, , drop = FALSE]
    names(data) <- toupper(names(data))
    data$RATE <- 0
    data$RATE[data$EVID == 1L] <- 0
    data$SS <- 0L

    liber_model <- LibeRation::nm_model(
      INPUT = names(data), ADVAN = 2, TRANS = 2,
      DOSECMP = 1, OBSCMP = 2,
      PRED = paste(
        "CL=THETA(1)*exp(ETA(1))",
        "V=THETA(2)*exp(ETA(2))",
        "KA=THETA(3)*exp(ETA(3))",
        "S2=V", sep = "\n"
      ),
      ERROR = "Y=F*(1+ERR(1))",
      THETAS = theta_table(c(4, 70, 1), fixed = TRUE),
      OMEGAS = data.frame(
        OMEGA = 1:3, Value = rep(.2, 3), FIX = TRUE
      ),
      SIGMAS = data.frame(SIGMA = 1L, Value = .05, FIX = TRUE),
      LIK_CONFIG = LibeRation::nm_lik_config(
        sigma_parameterization = "variance"
      )
    )
    liber_fit <- LibeRation::nm_individual_fit(
      liber_model, data, maxit = 500, tolerance = 1e-10
    )
    compare_values(
      "dosing_mapbayr", "dosing", "mapbayr + mrgsolve",
      "MAP individual parameters and predictions", "mapbayr",
      "MAP ETA estimates", as.numeric(liber_fit$eta), map_eta,
      2e-5, required = FALSE,
      detail = "Matched mapbayr distributed one-compartment oral reference model"
    )
  }
)

# posologyr: matched LibeRator patient individualisation -----------------------
run_case(
  id = "dosing_posologyr", group = "dosing",
  package = c("posologyr", "rxode2"),
  capability = "MAP individual parameters",
  comparator = "posologyr", required = FALSE,
  code = {
    reference <- run_r_reference(
      file.path(fixture_dir, "posologyr-reference.R")
    )
    model <- LibeRation::nm_model(
      INPUT = c(
        "ID", "TIME", "EVID", "AMT", "RATE", "CMT", "DV", "MDV",
        "II", "SS", "ADDL"
      ),
      ADVAN = 2, TRANS = 2, DOSECMP = 1, OBSCMP = 2,
      PRED = paste(
        "CL=THETA(1)*exp(ETA(1))",
        "V=THETA(2)*exp(ETA(2))",
        "KA=THETA(3)*exp(ETA(3))",
        "S2=V", sep = "\n"
      ),
      ERROR = "Y=F*(1+ERR(1))",
      THETAS = data.frame(
        THETA = 1:3, Value = c(4, 70, 1),
        LOWER = c(.004, .07, .001), UPPER = c(4000, 70000, 1000),
        FIX = TRUE
      ),
      OMEGAS = data.frame(
        OMEGA = 1:3, Value = rep(.2, 3), FIX = TRUE
      ),
      SIGMAS = data.frame(SIGMA = 1L, Value = .05, FIX = TRUE),
      LIK_CONFIG = LibeRation::nm_lik_config(
        sigma_parameterization = "variance"
      )
    )
    patient <- LibeRator::lator_patient_new(
      "POSOLOGYR-001", "EXTERNAL-VALIDATION",
      "Published posologyr example"
    )
    patient <- LibeRator::lator_patient_add_event(
      patient, "dose", 0, "Comparator drug", 2000, "mg",
      metadata = list(rate = 4000, duration = .5, cmt = 1L)
    )
    patient <- LibeRator::lator_patient_add_event(
      patient, "concentration", 1, "Comparator drug", 25, "mg/L"
    )
    patient <- LibeRator::lator_patient_add_event(
      patient, "concentration", 14, "Comparator drug", 5.5, "mg/L"
    )
    endpoint <- LibeRator::lator_endpoint_aed(
      "Comparator drug", 5, 25, "mg/L",
      source = "Software comparison target; not a clinical recommendation"
    )
    assessment <- LibeRator::lator_assess(
      patient, model, endpoint, maxit = 1000, tolerance = 1e-10
    )
    compare_values(
      "dosing_posologyr", "dosing", "posologyr",
      "MAP individual parameters", "posologyr",
      "LibeRator MAP ETA estimates", unname(as.numeric(assessment$eta)),
      unname(as.numeric(reference$eta)), 1e-5,
      detail = paste(
        "Matched public posologyr one-compartment oral example with a",
        "half-hour input; regimen helper semantics are not claimed equivalent"
      )
    )
    compare_values(
      "dosing_posologyr", "dosing", "posologyr",
      "MAP individual parameters", "posologyr",
      "posologyr target concentration self-check",
      unname(as.numeric(reference$target$concentration)), 20, 1e-8,
      detail = paste(
        "Confirms the external helper reached its requested target;",
        "dose equality is excluded because route/history contracts differ"
      )
    )
  }
)

# Evidence --------------------------------------------------------------------
results <- if (length(comparisons)) {
  do.call(rbind, comparisons)
} else {
  data.frame(
    id = character(), group = character(), package = character(),
    capability = character(), comparator = character(), quantity = character(),
    observed = numeric(), expected = numeric(),
    maximum_absolute_difference = numeric(), tolerance = numeric(),
    compared_values = integer(), status = character(), passed = logical(),
    required = logical(), detail = character(), stringsAsFactors = FALSE
  )
}

case_status <- lapply(split(results, results$id), function(rows) {
  status <- if (any(rows$status == "failed")) {
    "failed"
  } else if (all(rows$status == "not-run")) {
    "not-run"
  } else if (any(rows$status == "not-run")) {
    "incomplete"
  } else {
    "passed"
  }
  data.frame(
    id = rows$id[[1L]], group = rows$group[[1L]],
    required = any(rows$required), status = status,
    comparisons = sum(rows$status != "not-run"),
    detail = paste(unique(rows$detail[nzchar(rows$detail)]), collapse = "; "),
    stringsAsFactors = FALSE
  )
})
coverage <- if (length(case_status)) do.call(rbind, case_status) else data.frame()

failed <- any(results$status == "failed")
required_missing <- any(
  coverage$required & coverage$status %in% c("not-run", "incomplete")
)
optional_missing <- any(
  !coverage$required & coverage$status %in% c("not-run", "incomplete")
)
complete <- !required_missing
passed <- nrow(results) > 0L && !failed && complete
strict_passed <- passed && (!strict || !optional_missing)

stamp <- format(Sys.time(), "%Y%m%dT%H%M%S", tz = "UTC")
output <- value_after(
  "output", file.path(fixture_dir, "results", stamp)
)
if (!grepl("^(?:[A-Za-z]:[/\\\\]|/)", output, perl = TRUE)) {
  output <- file.path(root, output)
}
dir.create(output, recursive = TRUE, showWarnings = FALSE)
utils::write.csv(
  results, file.path(output, "comparisons.csv"), row.names = FALSE
)
utils::write.csv(
  coverage, file.path(output, "coverage.csv"), row.names = FALSE
)
file.copy(
  registry_path, file.path(output, "comparators.csv"), overwrite = TRUE
)

external_dependencies <- unique(c(
  "KFAS", "TMB", "glmmTMB", "hmmTMB", "deSolve", "pomp", "bssm",
  "nlmixr2", "nlmixr2est", "rxode2", "mapbayr", "mrgsolve", "posologyr"
))
provenance <- liber_validation_provenance(
  root = root,
  packages = c("LibeRtAD", "LibeRation", "LibeRator"),
  library = validation_runtime$path,
  inputs = c(
    file.path(fixture_dir, "run-validation.R"),
    file.path(fixture_dir, "sciml-reference.jl"),
    file.path(fixture_dir, "nlmixr2-reference.R"),
    file.path(fixture_dir, "nlmixr2-advanced-reference.R"),
    file.path(fixture_dir, "nlmixr2-fixtures.R"),
    file.path(fixture_dir, "posologyr-reference.R"),
    file.path(fixture_dir, "hmmtmb-binary.hmm"),
    file.path(fixture_dir, "README.md"), registry_path,
    file.path(julia_project, "Project.toml"),
    file.path(julia_project, "Manifest.toml")
  ),
  seeds = list(),
  tolerances = stats::setNames(
    as.list(results$tolerance[is.finite(results$tolerance)]),
    paste(
      results$id[is.finite(results$tolerance)],
      results$quantity[is.finite(results$tolerance)], sep = "::"
    )
  ),
  dependencies = external_dependencies,
  metadata = list(
    suite = "Independent open-source comparator validation",
    selected_groups = selected_groups, strict = strict,
    external_library = external_library, complete = complete,
    passed = passed, strict_passed = strict_passed,
    external_runtimes = list(
      julia = if (nzchar(julia_executable)) {
        paste(system2(julia_executable, "--version", stdout = TRUE),
              collapse = " ")
      } else {
        NA_character_
      },
      copasi = if (nzchar(copasi_executable)) {
        "COPASI CopasiSE (exact executable recorded in local installation)"
      } else {
        NA_character_
      }
    )
  ),
  output = file.path(output, "provenance.json")
)
jsonlite::write_json(
  list(
    schema = "liber.external-comparator-validation/1",
    passed = passed, complete = complete,
    strict = strict, strict_passed = strict_passed,
    failed_comparisons = sum(results$status == "failed"),
    unavailable_required_cases = sum(
      coverage$required & coverage$status %in% c("not-run", "incomplete")
    ),
    unavailable_optional_cases = sum(
      !coverage$required & coverage$status %in% c("not-run", "incomplete")
    ),
    coverage = split(coverage, seq_len(nrow(coverage))),
    comparisons = split(results, seq_len(nrow(results))),
    provenance = provenance
  ),
  file.path(output, "summary.json"), auto_unbox = TRUE, pretty = TRUE,
  null = "null", digits = 17
)

report <- c(
  "# Independent external-comparator validation", "",
  paste("- Result:", if (passed) "**PASS**" else "**INCOMPLETE OR FAILED**"),
  paste("- Strict result:", if (strict_passed) "**PASS**" else "**FAIL**"),
  paste("- Required comparator set complete:", if (complete) "yes" else "no"),
  paste("- Numerical comparisons:", sum(results$status != "not-run")),
  paste("- Failed comparisons:", sum(results$status == "failed")),
  "", "## Coverage", "",
  "| Comparator case | Group | Required | Status |",
  "|---|---|---:|---|",
  if (nrow(coverage)) vapply(seq_len(nrow(coverage)), function(index) {
    paste0(
      "| ", coverage$id[[index]], " | ", coverage$group[[index]], " | ",
      if (coverage$required[[index]]) "yes" else "no", " | ",
      coverage$status[[index]], " |"
    )
  }, character(1)) else "| none | - | - | not-run |",
  "", "## Interpretation", "",
  paste(
    "These comparisons supplement rather than replace analytic and",
    "property-based validation. KFAS and deSolve provide independent numerical",
    "implementations. glmmTMB is a useful likelihood/frontend comparator but",
    "shares CppAD ancestry, so it is not an independent validation of LibeRtAD."
  ),
  "", "A comparator that was unavailable is recorded as `not-run`; it is never",
  "converted into a pass."
)
writeLines(report, file.path(output, "REPORT.md"), useBytes = TRUE)

cat(
  "External-comparator validation:",
  if (strict_passed) "PASS" else if (passed) "PASS (optional comparator unavailable)" else "FAIL",
  "\nEvidence:", normalizePath(output, winslash = "/", mustWork = TRUE), "\n"
)
if (!strict_passed) quit(status = 1L)
