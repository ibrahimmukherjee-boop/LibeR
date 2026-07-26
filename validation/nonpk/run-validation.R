args <- commandArgs(trailingOnly = TRUE)
run_nonmem <- "--run-nonmem" %in% args
skip_nonmem <- "--skip-nonmem" %in% args

script_arg <- grep("^--file=", commandArgs(), value = TRUE)
script <- if (length(script_arg)) sub("^--file=", "", script_arg[[1L]]) else
  "run-validation.R"
fixture_dir <- normalizePath(dirname(script), winslash = "/", mustWork = TRUE)
root <- normalizePath(file.path(fixture_dir, "..", ".."),
                      winslash = "/", mustWork = TRUE)
source(file.path(root, "tools", "validation-runtime.R"), local = TRUE)

option_value <- function(name, default = NULL) {
  liber_validation_option(name, default, args = args)
}

validation_runtime <- liber_validation_library(
  root, c("LibeRtAD", "LibeRation"),
  library = option_value("library", Sys.getenv("LIBER_VALIDATION_LIBRARY", ""))
)
if (!requireNamespace("LibeRation", quietly = TRUE)) {
  stop("Install LibeRation before running non-PK validation.", call. = FALSE)
}
if (!requireNamespace("jsonlite", quietly = TRUE)) {
  stop("The validation runner requires jsonlite.", call. = FALSE)
}

old <- setwd(fixture_dir)
on.exit(setwd(old), add = TRUE)

comparisons <- list()
add_comparison <- function(case, family, quantity, reference, observed, expected,
                           tolerance, reference_class = "independent") {
  observed <- as.numeric(observed)
  expected <- as.numeric(expected)
  if (length(observed) != length(expected) || !length(observed)) {
    difference <- Inf
  } else {
    difference <- max(abs(observed - expected))
  }
  passed <- is.finite(difference) && difference <= tolerance
  comparisons[[length(comparisons) + 1L]] <<- data.frame(
    case = case, family = family, quantity = quantity,
    reference = reference, reference_class = reference_class,
    maximum_absolute_difference = difference, tolerance = tolerance,
    compared_values = max(length(observed), length(expected)),
    passed = passed, status = if (passed) "passed" else "failed",
    detail = "", stringsAsFactors = FALSE
  )
  if (!passed) {
    stop(
      case, " ", quantity, " comparison failed; maximum absolute difference = ",
      format(difference, digits = 12), ", tolerance = ",
      format(tolerance, digits = 12), ".", call. = FALSE
    )
  }
  cat(sprintf(
    "%-28s %-22s PASS (max |difference| %.6g)\n",
    case, quantity, difference
  ))
  invisible(difference)
}

add_unavailable <- function(case, family, quantity, reference, detail) {
  comparisons[[length(comparisons) + 1L]] <<- data.frame(
    case = case, family = family, quantity = quantity,
    reference = reference, reference_class = "external",
    maximum_absolute_difference = NA_real_, tolerance = NA_real_,
    compared_values = 0L, passed = NA, status = "not-run",
    detail = detail, stringsAsFactors = FALSE
  )
}

finite_difference <- function(model, data, step = 1e-5) {
  theta <- model$THETAS$Value
  vapply(seq_along(theta), function(index) {
    plus <- minus <- theta
    plus[[index]] <- plus[[index]] + step
    minus[[index]] <- minus[[index]] - step
    (LibeRation::nm_objective(
      model, data, theta = plus, gradient = FALSE
    )$value - LibeRation::nm_objective(
      model, data, theta = minus, gradient = FALSE
    )$value) / (2 * step)
  }, numeric(1))
}

validate_gradient <- function(case, family, model, data, tolerance = 3e-5) {
  objective <- LibeRation::nm_objective(model, data, gradient = TRUE)
  numerical <- finite_difference(model, data)
  add_comparison(
    case, family, "objective gradient", "central finite difference",
    objective$gradient, numerical, tolerance
  )
}

theta_table <- function(value, lower = -10, upper = 10) {
  data.frame(
    THETA = seq_along(value), Value = value,
    LOWER = rep(lower, length(value)), UPPER = rep(upper, length(value))
  )
}
base_data <- function(dv, time = seq_along(dv) - 1, id = 1L) {
  data.frame(ID = id, TIME = time, DV = dv, MDV = 0L)
}

# Normalized categorical and count likelihoods --------------------------------
binary_data <- data.frame(
  ID = rep(1:2, each = 3), TIME = rep(0:2, 2),
  DV = c(0, 1, 1, 1, 0, 1), MDV = 0L
)
binary <- LibeRation::nm_model(
  INPUT = names(binary_data), ADVAN = 1,
  PRED = "P=1/(1+exp(-THETA(1)));CL=1;V=1;S1=1;F=P",
  THETAS = theta_table(stats::qlogis(0.7)),
  OUTCOMES = LibeRation::nm_outcome("bernoulli", prediction = "P")
)
binary_score <- LibeRation::nm_objective(binary, binary_data, gradient = TRUE)
binary_expected <- -2 * sum(stats::dbinom(binary_data$DV, 1, 0.7, log = TRUE))
add_comparison(
  "Bernoulli", "categorical", "objective", "base R dbinom",
  binary_score$value, binary_expected, 1e-10
)
validate_gradient("Bernoulli", "categorical", binary, binary_data)

category_data <- base_data(c(0, 2, 1, 0, 1, 2))
category_probability <- c(0.2, 0.5, 0.3)
categorical <- LibeRation::nm_model(
  INPUT = names(category_data), ADVAN = 1,
  PRED = paste(
    "P0=0.2;P1=0.5;P2=0.3", "CL=1;V=1;S1=1;F=P1", sep = "\n"
  ),
  THETAS = theta_table(0),
  OUTCOMES = LibeRation::nm_outcome(
    "categorical", prediction = "P1",
    probabilities = c("P0", "P1", "P2"), categories = 0:2
  )
)
category_expected <- -2 * sum(log(category_probability[category_data$DV + 1L]))
add_comparison(
  "Categorical", "categorical", "objective", "multinomial factorization",
  LibeRation::nm_objective(categorical, category_data, gradient = FALSE)$value,
  category_expected, 1e-10
)

count_data <- base_data(c(0, 1, 2, 4, 3, 1))
poisson <- LibeRation::nm_model(
  INPUT = names(count_data), ADVAN = 1,
  PRED = "MU=exp(THETA(1));CL=1;V=1;S1=1;F=MU",
  THETAS = theta_table(log(2.3)),
  OUTCOMES = LibeRation::nm_outcome("poisson", prediction = "MU", max_count = 20)
)
add_comparison(
  "Poisson", "count", "objective", "base R dpois",
  LibeRation::nm_objective(poisson, count_data, gradient = FALSE)$value,
  -2 * sum(stats::dpois(count_data$DV, 2.3, log = TRUE)), 1e-10
)
validate_gradient("Poisson", "count", poisson, count_data)

negative_binomial <- LibeRation::nm_model(
  INPUT = names(count_data), ADVAN = 1,
  PRED = "MU=exp(THETA(1));SIZE=exp(THETA(2));CL=1;V=1;S1=1;F=MU",
  THETAS = theta_table(log(c(2.3, 3.4))),
  OUTCOMES = LibeRation::nm_outcome(
    "negative_binomial", prediction = "MU", dispersion = "SIZE", max_count = 20
  )
)
add_comparison(
  "Negative binomial", "count", "objective", "base R dnbinom",
  LibeRation::nm_objective(
    negative_binomial, count_data, gradient = FALSE
  )$value,
  -2 * sum(stats::dnbinom(count_data$DV, mu = 2.3, size = 3.4, log = TRUE)),
  2e-10
)
validate_gradient(
  "Negative binomial", "count", negative_binomial, count_data, 5e-5
)

# Event-time likelihoods -------------------------------------------------------
event_data <- data.frame(
  ID = c(rep(1L, 3), rep(2L, 3)),
  TIME = c(0, 1, 3, 0, 2, 5),
  DV = c(0, 0, 1, 0, 0, 0), MDV = 0L
)
hazard <- 0.2
tte <- LibeRation::nm_model(
  INPUT = names(event_data), ADVAN = 1,
  PRED = "HAZ=exp(THETA(1));CL=1;V=1;S1=1;F=HAZ",
  THETAS = theta_table(log(hazard)),
  OUTCOMES = LibeRation::nm_outcome("tte", prediction = "HAZ")
)
event_dt <- c(0, diff(event_data$TIME[1:3]), 0, diff(event_data$TIME[4:6]))
tte_expected <- -2 * sum(
  ifelse(event_data$DV == 1, log(hazard), 0) - hazard * event_dt
)
add_comparison(
  "Interval TTE", "time-to-event", "objective",
  "piecewise-exponential likelihood",
  LibeRation::nm_objective(tte, event_data, gradient = FALSE)$value,
  tte_expected, 1e-10
)
validate_gradient("Interval TTE", "time-to-event", tte, event_data)

recurrent_data <- event_data
recurrent_data$DV <- c(0, 1, 1, 0, 1, 0)
recurrent <- LibeRation::nm_model(
  INPUT = names(recurrent_data), ADVAN = 1,
  PRED = "HAZ=exp(THETA(1));CL=1;V=1;S1=1;F=HAZ",
  THETAS = theta_table(log(hazard)),
  OUTCOMES = LibeRation::nm_outcome("recurrent_event", prediction = "HAZ")
)
recurrent_expected <- -2 * sum(
  ifelse(recurrent_data$DV == 1, log(hazard), 0) - hazard * event_dt
)
add_comparison(
  "Recurrent event", "time-to-event", "objective",
  "counting-process likelihood",
  LibeRation::nm_objective(
    recurrent, recurrent_data, gradient = FALSE
  )$value,
  recurrent_expected, 1e-10
)

competing_data <- event_data
competing_data$DV <- c(0, 0, 2, 0, 1, 0)
h1 <- 0.12
h2 <- 0.07
competing <- LibeRation::nm_model(
  INPUT = names(competing_data), ADVAN = 1,
  PRED = paste(
    "H1=exp(THETA(1));H2=exp(THETA(2))",
    "CL=1;V=1;S1=1;F=H1+H2", sep = "\n"
  ),
  THETAS = theta_table(log(c(h1, h2))),
  OUTCOMES = LibeRation::nm_outcome(
    "competing_risks", prediction = "H1",
    cause_hazards = c(`1` = "H1", `2` = "H2")
  )
)
selected_hazard <- c(1, h1, h2)[match(competing_data$DV, c(0, 1, 2))]
competing_expected <- -2 * sum(
  ifelse(competing_data$DV == 0, 0, log(selected_hazard)) -
    (h1 + h2) * event_dt
)
add_comparison(
  "Competing risks", "time-to-event", "objective",
  "cause-specific hazard factorization",
  LibeRation::nm_objective(
    competing, competing_data, gradient = FALSE
  )$value,
  competing_expected, 1e-10
)
validate_gradient(
  "Competing risks", "time-to-event", competing, competing_data
)

# Observed discrete and continuous-time Markov models -------------------------
markov_data <- data.frame(
  ID = rep(1:2, each = 4), TIME = rep(0:3, 2),
  DV = c(0, 0, 1, 1, 1, 1, 0, 0), MDV = 0L
)
initial <- c(0.6, 0.4)
transition <- matrix(c(0.8, 0.2, 0.3, 0.7), 2, byrow = TRUE)
markov <- LibeRation::nm_model(
  INPUT = names(markov_data), ADVAN = 1,
  PRED = paste(
    "I0=.6;I1=.4;T00=.8;T01=.2;T10=.3;T11=.7",
    "CL=1;V=1;S1=1;F=I1", sep = "\n"
  ),
  THETAS = theta_table(0),
  OUTCOMES = LibeRation::nm_outcome(
    "markov", prediction = "I1", categories = 0:1,
    initial = c("I0", "I1"),
    transition = matrix(c("T00", "T01", "T10", "T11"), 2, byrow = TRUE)
  )
)
markov_loglik <- 0
for (subject in unique(markov_data$ID)) {
  state <- markov_data$DV[markov_data$ID == subject] + 1L
  markov_loglik <- markov_loglik + log(initial[state[[1L]]])
  for (index in 2:length(state)) {
    markov_loglik <- markov_loglik +
      log(transition[state[[index - 1L]], state[[index]]])
  }
}
add_comparison(
  "Observed Markov", "Markov", "objective",
  "independent transition factorization",
  LibeRation::nm_objective(markov, markov_data, gradient = FALSE)$value,
  -2 * markov_loglik, 1e-10
)

ctmc_data <- base_data(c(0, 0, 1, 1, 0), c(0, 0.4, 1.7, 3.2, 5.8))
q01 <- 0.18
q10 <- 0.11
ctmc <- LibeRation::nm_model(
  INPUT = names(ctmc_data), ADVAN = 1,
  PRED = paste(
    "PI0=.7;PI1=.3;Q01=exp(THETA(1));Q10=exp(THETA(2))",
    "CL=1;V=1;S1=1;F=PI1", sep = "\n"
  ),
  THETAS = theta_table(log(c(q01, q10))),
  OUTCOMES = LibeRation::nm_outcome(
    "continuous_time_markov", prediction = "PI1", categories = 0:1,
    initial = c("PI0", "PI1"), rates = c("Q01", "Q10")
  )
)
two_state_transition <- function(dt, q01, q10) {
  total <- q01 + q10
  decay <- exp(-total * dt)
  matrix(c(
    1 - q01 / total * (1 - decay), q01 / total * (1 - decay),
    q10 / total * (1 - decay), 1 - q10 / total * (1 - decay)
  ), 2, byrow = TRUE)
}
ctmc_state <- ctmc_data$DV + 1L
ctmc_loglik <- log(c(.7, .3)[ctmc_state[[1L]]])
for (index in 2:length(ctmc_state)) {
  probability <- two_state_transition(
    ctmc_data$TIME[[index]] - ctmc_data$TIME[[index - 1L]], q01, q10
  )
  ctmc_loglik <- ctmc_loglik +
    log(probability[ctmc_state[[index - 1L]], ctmc_state[[index]]])
}
add_comparison(
  "Observed CTMC", "continuous-time Markov", "objective",
  "analytic two-state matrix exponential",
  LibeRation::nm_objective(ctmc, ctmc_data, gradient = FALSE)$value,
  -2 * ctmc_loglik, 2e-10
)
validate_gradient(
  "Observed CTMC", "continuous-time Markov", ctmc, ctmc_data, 4e-5
)

# Hidden Markov exact path enumeration ----------------------------------------
hmm_data <- data.frame(
  ID = 1L, TIME = 0:4, DV = c(0, 0, 1, 1, 0), MDV = 0L, DVID = 1L
)
hmm_initial <- c(0.6, 0.4)
hmm_transition <- matrix(c(0.8, 0.2, 0.3, 0.7), 2, byrow = TRUE)
hmm_emission_zero <- c(0.9, 0.2)
hmm <- LibeRation::nm_model(
  INPUT = names(hmm_data), ADVAN = 1,
  PRED = "CL=1;V=1;S1=1;F=0",
  ERROR = paste(
    "I1=1/(1+exp(-THETA(1)));I2=1-I1",
    "T11=1/(1+exp(-THETA(2)));T12=1-T11",
    "T21=1/(1+exp(-THETA(3)));T22=1-T21",
    "E10=1/(1+exp(-THETA(4)));E20=1/(1+exp(-THETA(5)))",
    "E1=ifelse(DV==0,E10,1-E10);E2=ifelse(DV==0,E20,1-E20)",
    sep = "\n"
  ),
  THETAS = theta_table(stats::qlogis(c(.6, .8, .3, .9, .2))),
  HMM_CONFIG = LibeRation::nm_hmm_config(
    states = c("low", "high"), initial = c("I1", "I2"),
    transition = matrix(c("T11", "T12", "T21", "T22"), 2, byrow = TRUE),
    emission = c("E1", "E2"), by_dvid = FALSE
  )
)
paths <- as.matrix(expand.grid(rep(list(1:2), nrow(hmm_data))))
path_weight <- apply(paths, 1L, function(path) {
  value <- hmm_initial[path[[1L]]]
  for (index in seq_len(nrow(hmm_data))) {
    emission <- if (hmm_data$DV[[index]] == 0) hmm_emission_zero else
      1 - hmm_emission_zero
    value <- value * emission[path[[index]]]
    if (index < nrow(hmm_data)) {
      value <- value *
        hmm_transition[path[[index]], path[[index + 1L]]]
    }
  }
  value
})
hmm_likelihood <- sum(path_weight)
hmm_posterior <- path_weight / hmm_likelihood
hmm_smoothed <- t(vapply(seq_len(nrow(hmm_data)), function(index) {
  vapply(1:2, function(state) {
    sum(hmm_posterior[paths[, index] == state])
  }, numeric(1))
}, numeric(2)))
hmm_viterbi <- as.integer(paths[which.max(path_weight), ])
hmm_score <- LibeRation::nm_objective(hmm, hmm_data, gradient = FALSE)$value
hmm_decoded <- LibeRation::nm_hmm_decode(hmm, hmm_data, method = "all")
add_comparison(
  "Discrete HMM", "hidden Markov", "objective",
  "exhaustive state-path enumeration", hmm_score,
  -2 * log(hmm_likelihood), 1e-11
)
add_comparison(
  "Discrete HMM", "hidden Markov", "smoothed probabilities",
  "exhaustive state-path enumeration",
  unname(as.matrix(hmm_decoded[
    c("HMM_SMOOTH_PROB_low", "HMM_SMOOTH_PROB_high")
  ])),
  hmm_smoothed, 1e-11
)
add_comparison(
  "Discrete HMM", "hidden Markov", "Viterbi path",
  "exhaustive state-path enumeration",
  hmm_decoded$HMM_VITERBI_STATE_INDEX, hmm_viterbi, 0
)
validate_gradient(
  "Discrete HMM", "hidden Markov", hmm, hmm_data, 3e-5
)

# Continuous-time HMM with an analytic two-state transition -------------------
cthmm_data <- base_data(c(0, 0, 1, 0), c(0, .7, 2.1, 4.8))
cthmm <- LibeRation::nm_model(
  INPUT = names(cthmm_data), ADVAN = 1,
  PRED = "CL=1;V=1;S1=1;F=0",
  ERROR = paste(
    "I1=.65;I2=.35;Q12=exp(THETA(1));Q21=exp(THETA(2))",
    "E1=ifelse(DV==0,.88,.12);E2=ifelse(DV==0,.25,.75)", sep = "\n"
  ),
  THETAS = theta_table(log(c(.16, .09))),
  HMM_CONFIG = LibeRation::nm_cthmm_config(
    states = c("low", "high"), initial = c("I1", "I2"),
    generator = matrix(c("", "Q12", "Q21", ""), 2, byrow = TRUE),
    emission = c("E1", "E2"), by_dvid = FALSE
  )
)
alpha <- NULL
cthmm_loglik <- 0
for (index in seq_len(nrow(cthmm_data))) {
  prior <- if (index == 1L) c(.65, .35) else {
    drop(alpha %*% two_state_transition(
      cthmm_data$TIME[[index]] - cthmm_data$TIME[[index - 1L]], .16, .09
    ))
  }
  emission <- if (cthmm_data$DV[[index]] == 0) c(.88, .25) else c(.12, .75)
  weight <- prior * emission
  cthmm_loglik <- cthmm_loglik + log(sum(weight))
  alpha <- weight / sum(weight)
}
add_comparison(
  "Continuous-time HMM", "hidden Markov", "objective",
  "analytic two-state matrix exponential and forward recursion",
  LibeRation::nm_objective(cthmm, cthmm_data, gradient = FALSE)$value,
  -2 * cthmm_loglik, 2e-10
)
validate_gradient(
  "Continuous-time HMM", "hidden Markov", cthmm, cthmm_data, 5e-5
)

# Scalar linear Gaussian state-space model ------------------------------------
kalman_data <- base_data(c(.3, .1, -.4, .2, .5), c(0, .4, 1.5, 3.1, 5))
kalman_theta <- c(.35, .8, .25)
kalman <- LibeRation::nm_model(
  INPUT = names(kalman_data), ADVAN = 1,
  PRED = "CL=1;V=1;S1=1;F=0",
  ERROR = paste(
    "M0=0;P0=THETA(2)", "A11=exp(-THETA(1)*DT)",
    "Q11=THETA(2)*(1-exp(-2*THETA(1)*DT))",
    "H1=1;R1=THETA(3)*THETA(3)", sep = "\n"
  ),
  THETAS = theta_table(kalman_theta, .001, 10),
  KALMAN_CONFIG = LibeRation::nm_kalman_config(
    states = "deviation", initial_mean = "M0",
    initial_covariance = matrix("P0", 1),
    transition = matrix("A11", 1),
    process_covariance = matrix("Q11", 1),
    observation = "H1", observation_variance = "R1",
    baseline = "prediction", by_dvid = FALSE
  )
)
kalman_reference <- function(time, observation, theta) {
  mean <- 0
  covariance <- theta[[2L]]
  nll <- 0
  predicted <- filtered <- variance <- numeric(length(time))
  for (index in seq_along(time)) {
    if (index > 1L) {
      dt <- time[[index]] - time[[index - 1L]]
      a <- exp(-theta[[1L]] * dt)
      q <- theta[[2L]] * (1 - exp(-2 * theta[[1L]] * dt))
      mean <- a * mean
      covariance <- a^2 * covariance + q
    }
    predicted[[index]] <- mean
    innovation <- observation[[index]] - mean
    innovation_variance <- covariance + theta[[3L]]^2
    nll <- nll + log(innovation_variance) +
      innovation^2 / innovation_variance
    gain <- covariance / innovation_variance
    mean <- mean + gain * innovation
    covariance <- (1 - gain)^2 * covariance +
      gain^2 * theta[[3L]]^2
    filtered[[index]] <- mean
    variance[[index]] <- covariance
  }
  list(nll = nll, predicted = predicted, filtered = filtered, variance = variance)
}
kalman_expected <- kalman_reference(
  kalman_data$TIME, kalman_data$DV, kalman_theta
)
kalman_score <- LibeRation::nm_objective(
  kalman, kalman_data, gradient = FALSE
)$value
kalman_decoded <- LibeRation::nm_kalman_decode(kalman, kalman_data)
add_comparison(
  "Linear Kalman", "state-space", "objective",
  "independent scalar Kalman recursion",
  kalman_score, kalman_expected$nll, 2e-10
)
add_comparison(
  "Linear Kalman", "state-space", "filtered state",
  "independent scalar Kalman recursion",
  kalman_decoded$KF_FILTER_deviation, kalman_expected$filtered, 1e-11
)
add_comparison(
  "Linear Kalman", "state-space", "filtered variance",
  "independent scalar Kalman recursion",
  kalman_decoded$KF_FILTER_SD_deviation^2,
  kalman_expected$variance, 1e-11
)
validate_gradient(
  "Linear Kalman", "state-space", kalman, kalman_data, 3e-5
)

# Direct NONMEM overlap --------------------------------------------------------
run_execute <- function(model, expected_table) {
  execute <- Sys.which("execute")
  if (!nzchar(execute)) {
    stop("PsN execute is not available in PATH.", call. = FALSE)
  }
  stamp <- format(Sys.time(), "%Y%m%dT%H%M%S", tz = "UTC")
  directory <- paste0(
    tools::file_path_sans_ext(model), "_run_", stamp, "_", Sys.getpid()
  )
  if (.Platform$OS.type == "windows") {
    launcher <- sub("\\.bat$", "", execute, ignore.case = TRUE)
    perl <- file.path(dirname(execute), "perl.exe")
    if (!file.exists(perl)) perl <- Sys.which("perl")
    if (!nzchar(perl) || !file.exists(launcher)) {
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
    status <- system2(
      perl, c(shQuote(launcher), paste0("-directory=", directory), model)
    )
  } else {
    status <- system2(
      execute, c(paste0("-directory=", directory), model)
    )
  }
  if (!identical(status, 0L)) {
    stop("PsN execute returned status ", status, ".", call. = FALSE)
  }
  listing <- file.path(directory, "NM_run1", "psn.lst")
  if (!file.exists(listing) || !file.exists(expected_table)) {
    nmtran <- file.path(directory, "NM_run1", "nmtran_error.txt")
    detail <- if (file.exists(nmtran)) {
      paste(readLines(nmtran, warn = FALSE), collapse = "\n")
    } else ""
    stop("NONMEM execution did not complete. ", detail, call. = FALSE)
  }
  invisible(directory)
}

read_nonmem_table <- function(path) {
  utils::read.table(
    path, skip = 1L, header = TRUE, check.names = FALSE
  )
}

nonmem_cases <- list(
  list(
    name = "Bernoulli", family = "categorical",
    model = "bernoulli.mod", table = "bernoulli.tab",
    expected = ifelse(binary_data$DV == 1, .7, .3),
    liber_objective = binary_score$value
  ),
  list(
    name = "Interval TTE", family = "time-to-event",
    model = "tte.mod", table = "tte.tab",
    expected = exp(-hazard * event_dt) *
      ifelse(event_data$DV == 1, hazard, 1),
    liber_objective = LibeRation::nm_objective(
      tte, event_data, gradient = FALSE
    )$value
  ),
  list(
    name = "Observed Markov", family = "Markov",
    model = "markov.mod", table = "markov.tab",
    expected = c(.6, .8, .2, .7, .4, .7, .3, .8),
    liber_objective = LibeRation::nm_objective(
      markov, markov_data, gradient = FALSE
    )$value
  )
)

nonmem_available <- nzchar(Sys.which("execute"))
for (case in nonmem_cases) {
  if (skip_nonmem) {
    add_unavailable(
      case$name, case$family, "row likelihood", "NONMEM",
      "Skipped explicitly with --skip-nonmem."
    )
    next
  }
  if (!nonmem_available) {
    add_unavailable(
      case$name, case$family, "row likelihood", "NONMEM",
      "PsN execute was not available in PATH."
    )
    next
  }
  if (run_nonmem || !file.exists(case$table)) {
    error <- tryCatch({
      run_execute(case$model, case$table)
      NULL
    }, error = identity)
    if (!is.null(error)) {
      stop(
        "Direct NONMEM validation failed for ", case$name, ": ",
        conditionMessage(error), call. = FALSE
      )
    }
  }
  table <- read_nonmem_table(case$table)
  if (!"LIKE" %in% names(table)) {
    stop(case$table, " does not contain LIKE.", call. = FALSE)
  }
  add_comparison(
    paste(case$name, "NONMEM"), case$family, "row likelihood",
    "NONMEM 7.3 LIKELIHOOD", table$LIKE, case$expected, 2e-8, "external"
  )
  add_comparison(
    paste(case$name, "NONMEM"), case$family, "objective",
    "NONMEM 7.3 LIKELIHOOD", case$liber_objective,
    -2 * sum(log(table$LIKE)), 2e-7, "external"
  )
}

# Coverage declaration and evidence bundle ------------------------------------
coverage <- data.frame(
  family = c(
    "Bernoulli/categorical/ordinal", "Poisson/negative-binomial",
    "Binomial/ZIP/hurdle", "TTE/recurrent/competing risks",
    "Observed Markov/CTMC", "HMM", "CT-HMM", "HSMM/factorial HMM",
    "Linear Gaussian/ARMA state-space", "EKF/UKF",
    "Particle/switching state-space", "SDE", "DDE/DAE/QSP/hybrid"
  ),
  deterministic_reference = c(
    "base R + factorization", "base R", "base R unit fixtures",
    "analytic likelihood", "factorization + analytic matrix exponential",
    "exact path enumeration", "analytic matrix exponential + forward recursion",
    "exact expanded-state unit fixtures", "closed-form Kalman recursion",
    "linear-limit and finite-difference fixtures", "seeded reproducibility",
    "analytic moments and convergence fixtures",
    "analytic solution, mass-balance, gradient fixtures"
  ),
  direct_nonmem = c(
    "Bernoulli", "not in this campaign", "not in this campaign",
    "interval TTE", "discrete observed Markov", "no first-class counterpart",
    "no first-class counterpart", "no first-class counterpart",
    "no first-class counterpart", "no first-class counterpart",
    "no first-class counterpart", "no first-class counterpart",
    "model-specific only"
  ),
  release_status = c(
    "validated", "validated", "verified", "validated", "validated",
    "validated", "validated", "verified", "validated", "verified",
    "verified", "experimental", "experimental"
  ),
  stringsAsFactors = FALSE
)

results <- do.call(rbind, comparisons)
executed <- !is.na(results$passed)
passed <- any(executed) && all(results$passed[executed])
complete <- all(executed)
stamp <- format(Sys.time(), "%Y%m%dT%H%M%S", tz = "UTC")
output <- option_value("output", file.path(fixture_dir, "results", stamp))
if (!grepl("^(?:[A-Za-z]:[/\\\\]|/)", output, perl = TRUE)) {
  output <- file.path(root, output)
}
dir.create(output, recursive = TRUE, showWarnings = FALSE)

input_files <- list.files(
  fixture_dir, pattern = "[.](R|dat|mod|tab)$", full.names = TRUE
)
provenance <- liber_validation_provenance(
  root = root, packages = c("LibeRtAD", "LibeRation"),
  library = validation_runtime$path, inputs = input_files,
  seeds = list(),
  tolerances = split(results$tolerance, results$case),
  dependencies = c("Rcpp", "jsonlite", "openssl"),
  metadata = list(
    execute = unname(Sys.which("execute")),
    nonmem_requested = run_nonmem,
    nonmem_skipped = skip_nonmem,
    comparisons = nrow(results), executed_comparisons = sum(executed),
    passed = passed, complete = complete
  )
)
summary <- list(
  schema = "liber.nonpk-validation/1", passed = passed,
  complete = complete,
  comparisons = split(results, seq_len(nrow(results))),
  coverage = split(coverage, seq_len(nrow(coverage))),
  provenance = provenance
)

reference_counts <- table(results$reference_class, useNA = "ifany")
reference_count <- function(name) {
  if (name %in% names(reference_counts)) unname(reference_counts[[name]]) else 0L
}
report <- c(
  "# LibeRation non-PK validation report", "",
  paste("- Result:", if (passed) "**PASS**" else "**FAIL**"),
  paste("- Complete:", if (complete) "yes" else
    "no (one or more declared external comparisons were not run)"),
  paste("- Comparisons:", nrow(results)),
  paste("- Independent-reference comparisons:",
        reference_count("independent")),
  paste("- Direct external comparisons:",
        reference_count("external")),
  "", "## Scope", "",
  paste(
    "The release gate covers normalized categorical/count likelihoods,",
    "event-time likelihoods, observed Markov/CTMC models, exact HMM/CT-HMM",
    "likelihoods and decoders, and a closed-form linear Gaussian state-space",
    "model. NONMEM comparisons are limited to mathematically equivalent",
    "row-wise likelihood implementations."
  ),
  "", "## Important limitation", "",
  paste(
    "This is computational validation, not clinical qualification. Particle,",
    "SDE, DDE, QSP, and hybrid learned-component families retain their",
    "experimental or internally verified status until dedicated external and",
    "simulation-calibration campaigns are complete."
  )
)
liber_validation_write_evidence(
  output, comparisons = results, coverage = coverage, summary = summary,
  provenance = provenance, report = report
)

cat("Non-PK validation evidence:",
    normalizePath(output, winslash = "/"), "\n")
if (!passed) quit(status = 1L)
