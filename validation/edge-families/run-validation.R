args <- commandArgs(trailingOnly = TRUE)
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
if (!requireNamespace("LibeRation", quietly = TRUE) ||
    !requireNamespace("jsonlite", quietly = TRUE)) {
  stop("Install LibeRation and jsonlite before edge-family validation.",
       call. = FALSE)
}

comparisons <- list()
convergence <- list()

add_comparison <- function(case, family, quantity, reference, observed, expected,
                           tolerance, evidence = "independent analytic") {
  observed <- as.numeric(observed)
  expected <- as.numeric(expected)
  difference <- if (
    length(observed) == length(expected) && length(observed) &&
    all(is.finite(c(observed, expected)))
  ) max(abs(observed - expected)) else Inf
  passed <- is.finite(difference) && difference <= tolerance
  comparisons[[length(comparisons) + 1L]] <<- data.frame(
    case = case, family = family, quantity = quantity,
    reference = reference, evidence = evidence,
    maximum_absolute_difference = difference, tolerance = tolerance,
    compared_values = max(length(observed), length(expected)),
    passed = passed, status = if (passed) "passed" else "failed",
    stringsAsFactors = FALSE
  )
  if (!passed) {
    stop(
      case, " ", quantity, " comparison failed; maximum absolute difference = ",
      format(difference, digits = 12), ", tolerance = ",
      format(tolerance, digits = 12), ".", call. = FALSE
    )
  }
  cat(sprintf(
    "%-31s %-27s PASS (max |difference| %.6g)\n",
    case, quantity, difference
  ))
  invisible(difference)
}

add_condition <- function(case, family, quantity, passed, observed, reference) {
  passed <- isTRUE(passed)
  comparisons[[length(comparisons) + 1L]] <<- data.frame(
    case = case, family = family, quantity = quantity,
    reference = reference, evidence = "contract/metamorphic",
    maximum_absolute_difference = if (passed) 0 else Inf, tolerance = 0,
    compared_values = 1L, passed = passed,
    status = if (passed) "passed" else "failed",
    stringsAsFactors = FALSE
  )
  if (!passed) stop(case, " ", quantity, " failed: ", observed, call. = FALSE)
  cat(sprintf("%-31s %-27s PASS\n", case, quantity))
  invisible(TRUE)
}

theta_table <- function(value, lower = -100, upper = 100, fixed = FALSE) {
  data.frame(
    THETA = seq_along(value), Value = value,
    LOWER = rep(lower, length(value)), UPPER = rep(upper, length(value)),
    FIX = rep(fixed, length(value))
  )
}

finite_difference <- function(model, data, step = 1e-5) {
  theta <- model$THETAS$Value
  vapply(seq_along(theta), function(index) {
    plus <- minus <- theta
    plus[[index]] <- plus[[index]] + step
    minus[[index]] <- minus[[index]] - step
    (
      LibeRation::nm_objective(model, data, theta = plus, gradient = FALSE)$value -
        LibeRation::nm_objective(
          model, data, theta = minus, gradient = FALSE
        )$value
    ) / (2 * step)
  }, numeric(1))
}

acknowledgement <- LibeRation::nm_experimental_config(
  TRUE, label = "edge-family numerical validation"
)

# Multiplicative SDE: geometric Brownian motion -------------------------------
gbm_theta <- c(mu = .2, diffusion = .35)
gbm_subjects <- 5000L
gbm_substeps <- 64L
gbm_data <- data.frame(
  ID = rep(seq_len(gbm_subjects), each = 2L),
  TIME = rep(c(0, 1), gbm_subjects), DV = NA_real_, MDV = 0L
)
make_gbm <- function(method, substeps = gbm_substeps) {
  LibeRation::nm_model(
    INPUT = names(gbm_data), ADVAN = 1,
    PRED = "CL=1;V=1;S1=1;F=0",
    ERROR = paste(
      "M0=1", "P0=0", "DRIFT=THETA(1)*STATE_x",
      "G0=THETA(2)*STATE_x", "HX=STATE_x", "R0=0", sep = "\n"
    ),
    THETAS = theta_table(gbm_theta, 0, 2),
    KALMAN_CONFIG = LibeRation::nm_sde_config(
      states = "x", initial_mean = "M0",
      initial_covariance = matrix("P0", 1L),
      drift = "DRIFT", diffusion = matrix("G0", 1L),
      observation = "HX", observation_variance = "R0",
      baseline = "zero", by_dvid = FALSE, filter = "particle",
      method = method, substeps = substeps, particles = 128L, seed = 91L
    )
  )
}
gbm_euler <- LibeRation::nm_simulate(
  make_gbm("euler"), gbm_data, residual = TRUE, seed = 2026072401L
)
gbm_milstein <- LibeRation::nm_simulate(
  make_gbm("milstein"), gbm_data, residual = TRUE, seed = 2026072401L
)
gbm_terminal_euler <- gbm_euler$DV[gbm_euler$TIME == 1]
gbm_terminal_milstein <- gbm_milstein$DV[gbm_milstein$TIME == 1]
gbm_step <- 1 / gbm_substeps
gbm_first <- 1 + gbm_theta[["mu"]] * gbm_step
gbm_euler_second <- gbm_first^2 +
  gbm_theta[["diffusion"]]^2 * gbm_step
gbm_milstein_second <- gbm_euler_second +
  .5 * gbm_theta[["diffusion"]]^4 * gbm_step^2
gbm_expected_mean <- gbm_first^gbm_substeps
gbm_expected_variance_euler <- gbm_euler_second^gbm_substeps -
  gbm_expected_mean^2
gbm_expected_variance_milstein <- gbm_milstein_second^gbm_substeps -
  gbm_expected_mean^2
gbm_mean_tolerance <- 7 * sqrt(
  max(gbm_expected_variance_euler, gbm_expected_variance_milstein) /
    gbm_subjects
)
gbm_variance_tolerance <- 8 * max(
  gbm_expected_variance_euler, gbm_expected_variance_milstein
) * sqrt(2 / (gbm_subjects - 1L))
add_comparison(
  "Geometric Brownian SDE", "SDE", "Euler terminal mean",
  "fixed-step multiplicative Euler moment",
  mean(gbm_terminal_euler), gbm_expected_mean, gbm_mean_tolerance,
  "seeded Monte Carlo calibration"
)
add_comparison(
  "Geometric Brownian SDE", "SDE", "Euler terminal variance",
  "fixed-step multiplicative Euler moment",
  stats::var(gbm_terminal_euler), gbm_expected_variance_euler,
  gbm_variance_tolerance, "seeded Monte Carlo calibration"
)
add_comparison(
  "Geometric Brownian SDE", "SDE", "Milstein terminal mean",
  "fixed-step diagonal Milstein moment",
  mean(gbm_terminal_milstein), gbm_expected_mean, gbm_mean_tolerance,
  "seeded Monte Carlo calibration"
)
add_comparison(
  "Geometric Brownian SDE", "SDE", "Milstein terminal variance",
  "fixed-step diagonal Milstein moment",
  stats::var(gbm_terminal_milstein), gbm_expected_variance_milstein,
  gbm_variance_tolerance, "seeded Monte Carlo calibration"
)

# Nonlinear logistic multiplicative SDE against an independent implementation.
logistic_theta <- c(growth = .8, capacity = 10, diffusion = .25)
logistic_subjects <- 4000L
logistic_reference_subjects <- 50000L
logistic_substeps <- 128L
logistic_data <- data.frame(
  ID = rep(seq_len(logistic_subjects), each = 2L),
  TIME = rep(c(0, 1), logistic_subjects), DV = NA_real_, MDV = 0L
)
logistic <- LibeRation::nm_model(
  INPUT = names(logistic_data), ADVAN = 1,
  PRED = "CL=1;V=1;S1=1;F=0",
  ERROR = paste(
    "M0=1", "P0=0",
    "DRIFT=THETA(1)*STATE_x*(1-STATE_x/THETA(2))",
    "G0=THETA(3)*STATE_x", "HX=STATE_x", "R0=0", sep = "\n"
  ),
  THETAS = theta_table(logistic_theta, 0, 20),
  KALMAN_CONFIG = LibeRation::nm_sde_config(
    states = "x", initial_mean = "M0",
    initial_covariance = matrix("P0", 1L),
    drift = "DRIFT", diffusion = matrix("G0", 1L),
    observation = "HX", observation_variance = "R0",
    baseline = "zero", by_dvid = FALSE, filter = "particle",
    method = "milstein", substeps = logistic_substeps,
    particles = 128L, seed = 97L
  )
)
logistic_simulation <- LibeRation::nm_simulate(
  logistic, logistic_data, residual = TRUE, seed = 2026072402L
)
logistic_terminal <- logistic_simulation$DV[logistic_simulation$TIME == 1]
set.seed(2026072403L)
logistic_reference <- rep(1, logistic_reference_subjects)
logistic_h <- 1 / logistic_substeps
for (step_index in seq_len(logistic_substeps)) {
  increment <- sqrt(logistic_h) * stats::rnorm(logistic_reference_subjects)
  drift <- logistic_theta[["growth"]] * logistic_reference *
    (1 - logistic_reference / logistic_theta[["capacity"]])
  diffusion <- logistic_theta[["diffusion"]] * logistic_reference
  logistic_reference <- logistic_reference + logistic_h * drift +
    diffusion * increment +
    .5 * diffusion * logistic_theta[["diffusion"]] *
      (increment^2 - logistic_h)
}
logistic_variance <- stats::var(logistic_reference)
logistic_mean_tolerance <- 7 * sqrt(
  logistic_variance *
    (1 / logistic_subjects + 1 / logistic_reference_subjects)
)
logistic_variance_tolerance <- 9 * logistic_variance * sqrt(
  2 / (logistic_subjects - 1L) +
    2 / (logistic_reference_subjects - 1L)
)
add_comparison(
  "Logistic multiplicative SDE", "SDE", "terminal mean",
  "independent fixed-step Milstein Monte Carlo",
  mean(logistic_terminal), mean(logistic_reference),
  logistic_mean_tolerance, "independent seeded Monte Carlo"
)
add_comparison(
  "Logistic multiplicative SDE", "SDE", "terminal variance",
  "independent fixed-step Milstein Monte Carlo",
  stats::var(logistic_terminal), logistic_variance,
  logistic_variance_tolerance, "independent seeded Monte Carlo"
)

# Particle SDE likelihood converges to a discrete scalar Kalman reference.
particle_data <- data.frame(
  ID = 1L, TIME = c(0, .5, 1.5, 3),
  DV = c(1.1, .7, .4, .25), MDV = 0L
)
particle_theta <- c(k = .4, diffusion = .3, observation_variance = .05)
particle_substeps <- 64L
make_particle_ou <- function(particles, ess_threshold = .5) {
  LibeRation::nm_model(
    INPUT = names(particle_data), ADVAN = 1,
    PRED = "CL=1;V=1;S1=1;F=0",
    ERROR = paste(
      "M0=1", "P0=.2", "DRIFT=-THETA(1)*STATE_x",
      "G0=THETA(2)", "HX=STATE_x", "R0=THETA(3)", sep = "\n"
    ),
    THETAS = theta_table(particle_theta, 0, 2),
    KALMAN_CONFIG = LibeRation::nm_sde_config(
      states = "x", initial_mean = "M0",
      initial_covariance = matrix("P0", 1L),
      drift = "DRIFT", diffusion = matrix("G0", 1L),
      observation = "HX", observation_variance = "R0",
      baseline = "zero", by_dvid = FALSE, filter = "particle",
      method = "euler", substeps = particle_substeps,
      particles = particles, ess_threshold = ess_threshold,
      seed = 20260724L
    )
  )
}
discrete_ou_reference <- function() {
  mean <- 1
  variance <- .2
  objective <- 0
  for (index in seq_along(particle_data$TIME)) {
    if (index > 1L) {
      interval <- particle_data$TIME[[index]] -
        particle_data$TIME[[index - 1L]]
      steps <- particle_substeps
      h <- interval / steps
      transition_step <- 1 - particle_theta[["k"]] * h
      transition <- transition_step^steps
      process_variance <- particle_theta[["diffusion"]]^2 * h *
        sum(transition_step^(2 * (0:(steps - 1L))))
      mean <- transition * mean
      variance <- transition^2 * variance + process_variance
    }
    innovation <- particle_data$DV[[index]] - mean
    innovation_variance <- variance +
      particle_theta[["observation_variance"]]
    objective <- objective + log(innovation_variance) +
      innovation^2 / innovation_variance
    gain <- variance / innovation_variance
    mean <- mean + gain * innovation
    variance <- (1 - gain)^2 * variance +
      gain^2 * particle_theta[["observation_variance"]]
  }
  objective
}
particle_counts <- c(512L, 2048L, 8192L)
particle_values <- vapply(particle_counts, function(count) {
  LibeRation::nm_objective(
    make_particle_ou(count), particle_data, gradient = FALSE
  )$value
}, numeric(1))
particle_reference <- discrete_ou_reference()
particle_errors <- abs(particle_values - particle_reference)
convergence[[length(convergence) + 1L]] <- data.frame(
  family = "SDE", case = "OU particle likelihood",
  resolution = particle_counts, error = particle_errors,
  stringsAsFactors = FALSE
)
add_comparison(
  "OU particle SDE", "SDE", "finest likelihood",
  "fixed-step discrete scalar Kalman recursion",
  particle_values[[length(particle_values)]], particle_reference, .12,
  "particle convergence to independent linear-Gaussian reference"
)
add_condition(
  "OU particle SDE", "SDE", "resolution improvement",
  particle_errors[[length(particle_errors)]] < particle_errors[[1L]],
  paste(particle_errors, collapse = ", "),
  "8192-particle error is smaller than 512-particle error"
)
particle_gradient_model <- make_particle_ou(2048L, ess_threshold = .001)
particle_score <- LibeRation::nm_objective(
  particle_gradient_model, particle_data, gradient = TRUE
)
add_comparison(
  "OU particle SDE", "SDE", "fixed-ancestry gradient",
  "central finite difference without discrete resampling changes",
  particle_score$gradient,
  finite_difference(particle_gradient_model, particle_data), 7e-4
)

# DDE event boundaries and a stiff smooth-history problem ---------------------
dde_theta <- c(k = .4, feedback = .05, delay = .2)
dde_doses <- data.frame(time = c(0, .15), amount = c(10, 4))
dde_data <- data.frame(
  ID = 1L,
  TIME = c(0, 0, .05, .1, .15, .15, .2, .25, .3, .35, .4),
  EVID = c(1L, 0L, 0L, 0L, 1L, rep(0L, 6L)),
  AMT = c(10, 0, 0, 0, 4, rep(0, 6L)),
  CMT = 1L, DV = NA_real_,
  MDV = c(1L, 0L, 0L, 0L, 1L, rep(0L, 6L))
)
dde_impulse <- function(time, event_time, amount, theta = dde_theta) {
  elapsed <- time - event_time
  present <- elapsed >= 0
  delayed <- elapsed > theta[["delay"]]
  interval <- pmax(elapsed - theta[["delay"]], 0)
  ifelse(present, amount * exp(-theta[["k"]] * pmax(elapsed, 0)), 0) +
    ifelse(
      delayed,
      theta[["feedback"]] * amount * interval *
        exp(-theta[["k"]] * interval),
      0
    )
}
dde_exact <- function(time, theta = dde_theta) {
  Reduce(`+`, Map(
    function(event_time, amount) dde_impulse(
      time, event_time, amount, theta
    ),
    dde_doses$time, dde_doses$amount
  ))
}
dde_delay_gradient <- function(time, theta = dde_theta) {
  Reduce(`+`, Map(function(event_time, amount) {
    elapsed <- time - event_time
    interval <- pmax(elapsed - theta[["delay"]], 0)
    ifelse(
      elapsed > theta[["delay"]],
      -theta[["feedback"]] * amount *
        exp(-theta[["k"]] * interval) *
        (1 - theta[["k"]] * interval),
      0
    )
  }, dde_doses$time, dde_doses$amount))
}
make_event_dde <- function(step = .002) {
  LibeRation::nm_model(
    INPUT = names(dde_data), ADVAN = 6, DOSECMP = 1, OBSCMP = 1,
    PRED = "K=THETA(1);B=THETA(2);TAU=THETA(3);S1=1",
    DES = "DADT(1)=-K*A(1)+B*LAG(A(1),TAU)",
    THETAS = theta_table(dde_theta, .0001, 2),
    DDE_CONFIG = LibeRation::nm_dde_config(
      history = 0, step = step, minimum_delay = .15
    ),
    EXPERIMENTAL = acknowledgement
  )
}
event_dde <- make_event_dde()
event_dde_simulation <- LibeRation::nm_simulate(event_dde, dde_data)
dde_observed <- dde_data$EVID == 0
add_comparison(
  "Repeated-bolus DDE", "DDE", "event-boundary prediction",
  "closed-form superposition through two method-of-steps intervals",
  event_dde_simulation$IPRED[dde_observed],
  dde_exact(dde_data$TIME[dde_observed]), 3e-4
)
event_dde_derivative <- LibeRation::nm_prediction_derivatives(
  event_dde, dde_data
)$jacobian
dde_boundary <- vapply(dde_data$TIME, function(time) {
  any(abs(time - (dde_doses$time + dde_theta[["delay"]])) < 1e-12)
}, logical(1))
dde_derivative_rows <- dde_observed & !dde_boundary
add_comparison(
  "Repeated-bolus DDE", "DDE", "event-boundary delay sensitivity",
  "analytic derivative of delayed-event superposition",
  event_dde_derivative[dde_derivative_rows, 3L],
  dde_delay_gradient(dde_data$TIME[dde_derivative_rows]), 8e-3
)

stiff_dde_theta <- c(k = 20, feedback = 1, delay = .05)
stiff_dde_times <- seq(0, .1, by = .01)
stiff_dde_data <- data.frame(
  ID = 1L, TIME = c(0, stiff_dde_times),
  EVID = c(1L, rep(0L, length(stiff_dde_times))),
  AMT = c(10, rep(0, length(stiff_dde_times))),
  CMT = 1L, DV = NA_real_,
  MDV = c(1L, rep(0L, length(stiff_dde_times)))
)
stiff_dde_exact <- function(time, theta = stiff_dde_theta) {
  k <- theta[[1L]]
  feedback <- theta[[2L]]
  delay <- theta[[3L]]
  equilibrium <- feedback * 10 / k
  displacement <- 10 - equilibrium
  first <- equilibrium + displacement * exp(-k * time)
  interval <- pmax(time - delay, 0)
  at_delay <- equilibrium + displacement * exp(-k * delay)
  second <- exp(-k * interval) * at_delay +
    feedback * equilibrium / k * (1 - exp(-k * interval)) +
    feedback * displacement * interval * exp(-k * interval)
  ifelse(time <= delay, first, second)
}
stiff_dde <- LibeRation::nm_model(
  INPUT = names(stiff_dde_data), ADVAN = 6,
  PRED = "K=THETA(1);B=THETA(2);TAU=THETA(3);S1=1",
  DES = "DADT(1)=-K*A(1)+B*LAG(A(1),TAU)",
  THETAS = theta_table(stiff_dde_theta, .0001, 50),
  DDE_CONFIG = LibeRation::nm_dde_config(
    history = 10, step = .000125, minimum_delay = .05
  ),
  EXPERIMENTAL = acknowledgement
)
stiff_dde_prediction <- tail(
  LibeRation::nm_simulate(stiff_dde, stiff_dde_data)$IPRED,
  length(stiff_dde_times)
)
add_comparison(
  "Stiff smooth-history DDE", "DDE", "trajectory",
  "closed-form two-interval method-of-steps solution",
  stiff_dde_prediction, stiff_dde_exact(stiff_dde_times), 8e-5
)
stiff_dde_jacobian <- tail(
  LibeRation::nm_prediction_derivatives(
    stiff_dde, stiff_dde_data
  )$jacobian,
  length(stiff_dde_times)
)
stiff_exact_gradient <- vapply(seq_along(stiff_dde_theta), function(index) {
  step <- 1e-5 * max(1, abs(stiff_dde_theta[[index]]))
  plus <- minus <- stiff_dde_theta
  plus[[index]] <- plus[[index]] + step
  minus[[index]] <- minus[[index]] - step
  (
    stiff_dde_exact(stiff_dde_times, plus) -
      stiff_dde_exact(stiff_dde_times, minus)
  ) / (2 * step)
}, numeric(length(stiff_dde_times)))
add_comparison(
  "Stiff smooth-history DDE", "DDE", "sensitivity",
  "central difference of closed-form solution",
  stiff_dde_jacobian, stiff_exact_gradient, 7e-3
)

# Larger block-sparse and coupled nonlinear DAE systems -----------------------
dae_states <- 6L
dae_amount <- c(10, 15, 20, 25, 30, 35)
dae_k <- c(.16, .25, .36, .49, .64, .81)
dae_times <- c(0, .05, .2, .5)
dae_data <- rbind(
  data.frame(
    ID = 1L, TIME = 0, EVID = 1L, AMT = dae_amount,
    CMT = seq_len(dae_states), DV = NA_real_, MDV = 1L
  ),
  data.frame(
    ID = 1L, TIME = dae_times, EVID = 0L, AMT = 0,
    CMT = 1L, DV = NA_real_, MDV = 0L
  )
)
dae_pred <- paste(
  c(
    paste0("K", seq_len(dae_states), "=THETA(", seq_len(dae_states), ")"),
    "S1=1"
  ),
  collapse = "\n"
)
dae_des <- paste0(
  "DADT(", seq_len(dae_states), ")=-Z", seq_len(dae_states),
  collapse = "\n"
)
dae_alg <- paste0(
  "RES(", seq_len(dae_states), ")=Z", seq_len(dae_states),
  "*Z", seq_len(dae_states), "-K", seq_len(dae_states),
  "*A(", seq_len(dae_states), ")",
  collapse = "\n"
)
large_dae <- LibeRation::nm_model(
  INPUT = names(dae_data), OUTPUT = paste0("A", seq_len(dae_states)),
  ADVAN = 6, DOSECMP = 1, OBSCMP = 1,
  PRED = dae_pred, DES = dae_des, ALG = dae_alg,
  THETAS = theta_table(dae_k, .001, 2),
  DAE_CONFIG = LibeRation::nm_dae_config(
    paste0("Z", seq_len(dae_states)), initial = 1,
    tolerance = 1e-10, maxit = 24L,
    sparsity = diag(TRUE, dae_states)
  ),
  EXPERIMENTAL = acknowledgement
)
large_dae_simulation <- LibeRation::nm_simulate(large_dae, dae_data)
dae_observed <- dae_data$EVID == 0
large_dae_expected <- vapply(seq_len(dae_states), function(index) {
  (
    sqrt(dae_amount[[index]]) -
      .5 * sqrt(dae_k[[index]]) * dae_times
  )^2
}, numeric(length(dae_times)))
add_comparison(
  "Six-block nonlinear DAE", "DAE", "state trajectories",
  "independent analytic block reductions",
  as.matrix(large_dae_simulation[
    dae_observed, paste0("A", seq_len(dae_states)), drop = FALSE
  ]),
  large_dae_expected, 4e-6
)
large_dae_gradient <- LibeRation::nm_prediction_derivatives(
  large_dae, dae_data
)$jacobian[dae_observed, 1L]
large_dae_expected_gradient <- -.5 * sqrt(
  dae_amount[[1L]] / dae_k[[1L]]
) * dae_times + .25 * dae_times^2
add_comparison(
  "Six-block nonlinear DAE", "DAE", "block sensitivity",
  "analytic reduced-system derivative",
  large_dae_gradient, large_dae_expected_gradient, 5e-5
)

coupled_theta <- c(k1 = 40, k2 = 25)
coupled_times <- c(0, .002, .01, .05, .1)
coupled_data <- rbind(
  data.frame(
    ID = 1L, TIME = 0, EVID = 1L, AMT = c(10, 5),
    CMT = 1:2, DV = NA_real_, MDV = 1L
  ),
  data.frame(
    ID = 1L, TIME = coupled_times, EVID = 0L, AMT = 0,
    CMT = 1L, DV = NA_real_, MDV = 0L
  )
)
coupled_dae <- LibeRation::nm_model(
  INPUT = names(coupled_data), OUTPUT = c("A1", "A2"),
  ADVAN = 6, DOSECMP = 1, OBSCMP = 1,
  PRED = "K1=THETA(1);K2=THETA(2);S1=1",
  DES = "DADT(1)=-Z1\nDADT(2)=-Z2",
  ALG = paste(
    "RES(1)=Z1+Z2-K1*A(1)",
    "RES(2)=Z2-K2*A(2)", sep = "\n"
  ),
  THETAS = theta_table(coupled_theta, .01, 100),
  DAE_CONFIG = LibeRation::nm_dae_config(
    c("Z1", "Z2"), initial = c(1, 1),
    tolerance = 1e-11, maxit = 20L,
    sparsity = matrix(c(TRUE, TRUE, FALSE, TRUE), 2L, byrow = TRUE)
  ),
  EXPERIMENTAL = acknowledgement
)
coupled_exact <- function(theta, time = coupled_times) {
  a2 <- 5 * exp(-theta[[2L]] * time)
  a1 <- 10 * exp(-theta[[1L]] * time) +
    theta[[2L]] * 5 *
      (exp(-theta[[2L]] * time) - exp(-theta[[1L]] * time)) /
      (theta[[1L]] - theta[[2L]])
  cbind(a1, a2)
}
coupled_simulation <- LibeRation::nm_simulate(coupled_dae, coupled_data)
coupled_observed <- coupled_data$EVID == 0
add_comparison(
  "Coupled stiff DAE", "DAE", "state trajectories",
  "closed-form triangular reduced system",
  as.matrix(coupled_simulation[
    coupled_observed, c("A1", "A2"), drop = FALSE
  ]),
  coupled_exact(coupled_theta), 8e-6
)
coupled_jacobian <- LibeRation::nm_prediction_derivatives(
  coupled_dae, coupled_data
)$jacobian[coupled_observed, 1:2, drop = FALSE]
coupled_exact_gradient <- vapply(seq_along(coupled_theta), function(index) {
  step <- 1e-5 * coupled_theta[[index]]
  plus <- minus <- coupled_theta
  plus[[index]] <- plus[[index]] + step
  minus[[index]] <- minus[[index]] - step
  (
    coupled_exact(plus)[, 1L] - coupled_exact(minus)[, 1L]
  ) / (2 * step)
}, numeric(length(coupled_times)))
add_comparison(
  "Coupled stiff DAE", "DAE", "implicit sensitivity",
  "central difference of closed-form reduced system",
  coupled_jacobian, coupled_exact_gradient, 8e-5
)

# Larger and stiff QSP networks -----------------------------------------------
chain_species <- paste0("S", seq_len(10L))
chain_stoichiometry <- matrix(0, 10L, 9L)
for (reaction in seq_len(9L)) {
  chain_stoichiometry[reaction, reaction] <- -1
  chain_stoichiometry[reaction + 1L, reaction] <- 1
}
chain_k <- 12
chain_times <- c(0, .01, .05, .1, .25, .5)
chain_data <- rbind(
  data.frame(
    ID = 1L, TIME = 0, EVID = 1L, AMT = 10,
    CMT = 1L, DV = NA_real_, MDV = 1L
  ),
  data.frame(
    ID = 1L, TIME = chain_times, EVID = 0L, AMT = 0,
    CMT = 1L, DV = NA_real_, MDV = 0L
  )
)
chain_system <- LibeRation::nm_qsp_system(
  chain_species, chain_stoichiometry,
  rates = paste0("K*", chain_species[seq_len(9L)]),
  dose_species = "S1", observation_species = "S1"
)
chain_model <- LibeRation::nm_qsp_model(
  chain_system, INPUT = names(chain_data), OUTPUT = paste0("A", 1:10),
  PRED = "K=THETA(1);S1=1",
  THETAS = theta_table(chain_k, .01, 50),
  EXPERIMENTAL = acknowledgement
)
chain_simulation <- LibeRation::nm_simulate(chain_model, chain_data)
chain_observed <- chain_data$EVID == 0
chain_expected <- vapply(seq_len(10L), function(species) {
  if (species < 10L) {
    10 * exp(-chain_k * chain_times) *
      (chain_k * chain_times)^(species - 1L) /
      factorial(species - 1L)
  } else {
    10 * (
      1 - rowSums(vapply(0:8, function(order) {
        exp(-chain_k * chain_times) *
          (chain_k * chain_times)^order / factorial(order)
      }, numeric(length(chain_times))))
    )
  }
}, numeric(length(chain_times)))
add_comparison(
  "Ten-species QSP chain", "QSP", "species trajectories",
  "closed-form Erlang reaction chain",
  as.matrix(chain_simulation[
    chain_observed, paste0("A", 1:10), drop = FALSE
  ]),
  chain_expected, 2e-6
)
add_comparison(
  "Ten-species QSP chain", "QSP", "mass conservation",
  "stoichiometric invariant",
  rowSums(chain_simulation[
    chain_observed, paste0("A", 1:10), drop = FALSE
  ]),
  rep(10, length(chain_times)), 2e-8, "conservation law"
)
chain_gradient <- LibeRation::nm_prediction_derivatives(
  chain_model, chain_data
)$jacobian[chain_observed, 1L]
add_comparison(
  "Ten-species QSP chain", "QSP", "parameter sensitivity",
  "closed-form first-species derivative",
  chain_gradient,
  -10 * chain_times * exp(-chain_k * chain_times), 4e-6
)

reversible_theta <- c(forward = 120, reverse = 80)
reversible_times <- c(0, .0005, .002, .01, .05)
reversible_data <- rbind(
  data.frame(
    ID = 1L, TIME = 0, EVID = 1L, AMT = 10,
    CMT = 1L, DV = NA_real_, MDV = 1L
  ),
  data.frame(
    ID = 1L, TIME = reversible_times, EVID = 0L, AMT = 0,
    CMT = 1L, DV = NA_real_, MDV = 0L
  )
)
reversible_system <- LibeRation::nm_qsp_system(
  c("A", "B"), matrix(c(-1, 1, 1, -1), 2L),
  rates = c("KF*A", "KR*B"), dose_species = "A",
  observation_species = "A"
)
reversible_model <- LibeRation::nm_qsp_model(
  reversible_system, INPUT = names(reversible_data), OUTPUT = c("A1", "A2"),
  PRED = "KF=THETA(1);KR=THETA(2);S1=1",
  THETAS = theta_table(reversible_theta, .01, 300),
  EXPERIMENTAL = acknowledgement
)
reversible_exact <- function(theta, time = reversible_times) {
  total <- 10
  equilibrium <- total * theta[[2L]] / sum(theta)
  a <- equilibrium + (total - equilibrium) * exp(-sum(theta) * time)
  cbind(a, total - a)
}
reversible_simulation <- LibeRation::nm_simulate(
  reversible_model, reversible_data
)
reversible_observed <- reversible_data$EVID == 0
add_comparison(
  "Stiff reversible QSP", "QSP", "species trajectories",
  "closed-form reversible reaction",
  as.matrix(reversible_simulation[
    reversible_observed, c("A1", "A2"), drop = FALSE
  ]),
  reversible_exact(reversible_theta), 2e-6
)
add_comparison(
  "Stiff reversible QSP", "QSP", "mass conservation",
  "stoichiometric invariant",
  reversible_simulation$A1[reversible_observed] +
    reversible_simulation$A2[reversible_observed],
  rep(10, length(reversible_times)), 2e-8, "conservation law"
)

recovery_times <- c(.1, .25, .5, 1, 2, 3)
recovery_noise <- c(.03, -.02, .015, -.01, .006, -.003)
recovery_data <- rbind(
  data.frame(
    ID = 1L, TIME = 0, EVID = 1L, AMT = 10, CMT = 1L,
    DV = NA_real_, MDV = 1L
  ),
  data.frame(
    ID = 1L, TIME = recovery_times, EVID = 0L, AMT = 0, CMT = 1L,
    DV = 10 * exp(-.7 * recovery_times) + recovery_noise, MDV = 0L
  )
)
recovery_system <- LibeRation::nm_qsp_system(
  c("Parent", "Product"), matrix(c(-1, 1), 2L, 1L),
  rates = "K*Parent", dose_species = "Parent",
  observation_species = "Parent"
)
recovery_model <- LibeRation::nm_qsp_model(
  recovery_system, INPUT = names(recovery_data),
  PRED = "K=THETA(1);S1=1", ERROR = "Y=F+ERR(1)",
  THETAS = theta_table(.5, .05, 2),
  SIGMAS = data.frame(SIGMA = 1L, Value = .01, FIX = TRUE),
  EXPERIMENTAL = acknowledgement
)
engine_recovery <- stats::optimize(
  function(k) LibeRation::nm_objective(
    recovery_model, recovery_data, theta = k, gradient = FALSE
  )$value,
  interval = c(.05, 2), tol = 1e-8
)$minimum
reference_recovery <- stats::optimize(
  function(k) sum(
    (
      recovery_data$DV[recovery_data$EVID == 0] -
        10 * exp(-k * recovery_times)
    )^2
  ),
  interval = c(.05, 2), tol = 1e-10
)$minimum
add_comparison(
  "QSP parameter recovery", "QSP", "estimated rate",
  "independent closed-form least-squares objective",
  engine_recovery, reference_recovery, 2e-6,
  "end-to-end compact recovery"
)

# Hybrid numerical and immutable-payload edges -------------------------------
hybrid_data <- data.frame(
  ID = 1L, TIME = 0:6,
  X = c(-1000, -2, -1, .5, 2, 10, 1000),
  Z = c(-2, -.5, 0, .25, 1, 2, 3),
  DV = c(-.5, -.2, .1, .5, 1, 1.5, 2), MDV = 0L
)
softplus <- LibeRation::nm_component(
  "stable_softplus", "dense_nn", scope = "pred",
  inputs = "X", outputs = "SOFT",
  weights = list(matrix(1, 1, 1), matrix(1, 1, 1)),
  biases = list(0, 0), activation = "softplus"
)
relu <- LibeRation::nm_component(
  "relu_pair", "dense_nn", scope = "pred",
  inputs = c("THETA_1", "Z"), outputs = c("R1", "R2"),
  weights = list(
    matrix(c(1, -.5, -.3, .8), 2, 2, byrow = TRUE),
    diag(2)
  ),
  biases = list(c(.1, -.2), c(0, 0)), activation = "relu"
)
spline <- LibeRation::nm_component(
  "boundary_spline", "linear_spline", scope = "pred",
  inputs = "Z", outputs = "SPL",
  knots = c(-1, 0, 2), values = c(0, 1, .5)
)
gp_training <- rbind(c(-1, -2), c(.5, 0), c(2, 3))
gp_alpha <- c(.4, -.25, .3)
gp <- LibeRation::nm_component(
  "anisotropic_gp", "gaussian_process", scope = "pred",
  inputs = c("THETA_1", "Z"), outputs = "GP",
  training = gp_training, alpha = gp_alpha,
  lengthscale = c(.4, 1.2), variance = 1.3, mean = -.1
)
hybrid_model <- LibeRation::nm_model(
  INPUT = names(hybrid_data), OUTPUT = c("SOFT", "R1", "R2", "SPL", "GP"),
  ADVAN = 1,
  PRED = paste(
    "CL=1;V=1;S1=1",
    "F=SOFT+R1+R2+SPL+GP", sep = "\n"
  ),
  ERROR = "Y=F+ERR(1)",
  THETAS = theta_table(.7, -2, 2),
  SIGMAS = data.frame(SIGMA = 1L, Value = .2, FIX = TRUE),
  COMPONENTS = list(softplus, relu, spline, gp),
  EXPERIMENTAL = acknowledgement
)
stable_softplus <- function(x) log1p(exp(-abs(x))) + pmax(x, 0)
relu_reference <- function(theta, z) {
  cbind(
    pmax(.1 + theta - .5 * z, 0),
    pmax(-.2 - .3 * theta + .8 * z, 0)
  )
}
spline_reference <- function(z) {
  ifelse(
    z <= -1, 0,
    ifelse(z <= 0, z + 1, ifelse(z <= 2, 1 - .25 * z, .5))
  )
}
gp_reference <- function(theta, z) {
  vapply(seq_along(z), function(index) {
    point <- c(theta, z[[index]])
    -.1 + 1.3 * sum(gp_alpha * exp(
      -.5 * rowSums(sweep(
        sweep(gp_training, 2L, point, "-"),
        2L, c(.4, 1.2), "/"
      )^2)
    ))
  }, numeric(1))
}
hybrid_reference <- function(theta) {
  relu_value <- relu_reference(theta, hybrid_data$Z)
  data.frame(
    SOFT = stable_softplus(hybrid_data$X),
    R1 = relu_value[, 1L], R2 = relu_value[, 2L],
    SPL = spline_reference(hybrid_data$Z),
    GP = gp_reference(theta, hybrid_data$Z)
  )
}
hybrid_simulation <- LibeRation::nm_simulate(
  hybrid_model, hybrid_data, residual = FALSE
)
hybrid_expected <- hybrid_reference(.7)
add_comparison(
  "Hybrid component edges", "hybrid", "component outputs",
  "independent stable-softplus ReLU spline and GP calculations",
  as.matrix(hybrid_simulation[
    , c("SOFT", "R1", "R2", "SPL", "GP"), drop = FALSE
  ]),
  as.matrix(hybrid_expected), 3e-11
)
add_condition(
  "Hybrid component edges", "hybrid", "extreme softplus finiteness",
  all(is.finite(hybrid_simulation$SOFT)) &&
    hybrid_simulation$SOFT[[1L]] == 0 &&
    abs(hybrid_simulation$SOFT[[nrow(hybrid_simulation)]] - 1000) < 1e-10,
  paste(hybrid_simulation$SOFT[c(1L, nrow(hybrid_simulation))], collapse = ", "),
  "stable softplus remains finite at -1000 and +1000"
)
hybrid_derivative <- LibeRation::nm_prediction_derivatives(
  hybrid_model, hybrid_data
)$jacobian[, 1L]
hybrid_reference_prediction <- function(theta) {
  value <- hybrid_reference(theta)
  rowSums(value)
}
hybrid_step <- 1e-6
hybrid_expected_derivative <- (
  hybrid_reference_prediction(.7 + hybrid_step) -
    hybrid_reference_prediction(.7 - hybrid_step)
) / (2 * hybrid_step)
add_comparison(
  "Hybrid component edges", "hybrid", "combined gradient",
  "central difference of independent component calculations",
  hybrid_derivative, hybrid_expected_derivative, 4e-5
)
tampered <- softplus
tampered$payload$weights[[1L]][1L, 1L] <- 2
tamper_error <- try(
  LibeRation::nm_model(
    INPUT = names(hybrid_data), ADVAN = 1,
    PRED = "CL=1;V=1;S1=1;F=SOFT",
    THETAS = theta_table(.7), COMPONENTS = tampered,
    EXPERIMENTAL = acknowledgement
  ),
  silent = TRUE
)
add_condition(
  "Hybrid component edges", "hybrid", "immutable payload rejection",
  inherits(tamper_error, "try-error"),
  if (inherits(tamper_error, "try-error")) "rejected" else "accepted",
  "modified component payload must fail its recorded hash"
)

# Evidence --------------------------------------------------------------------
coverage <- data.frame(
  family = c(
    "Multiplicative SDE simulation", "Nonlinear SDE simulation",
    "Particle SDE likelihood", "DDE delayed bolus events",
    "Stiff smooth-history DDE", "Larger block-sparse DAE",
    "Coupled stiff DAE", "Larger/stiff QSP",
    "QSP compact parameter recovery", "Hybrid numerical edges",
    "Arbitrary very-large or application-specific systems"
  ),
  evidence_tier = c(rep("validated", 10L), "experimental"),
  recommended_use = c(
    rep("Experimental research only", 10L),
    "Application-specific validation required"
  ),
  stringsAsFactors = FALSE
)
results <- do.call(rbind, comparisons)
convergence_results <- if (length(convergence)) {
  do.call(rbind, convergence)
} else {
  data.frame(
    family = character(), case = character(),
    resolution = numeric(), error = numeric()
  )
}
passed <- nrow(results) > 0L && all(results$passed)
stamp <- format(Sys.time(), "%Y%m%dT%H%M%S", tz = "UTC")
output <- option_value(
  "output", file.path(fixture_dir, "results", stamp)
)
if (!grepl("^(?:[A-Za-z]:[/\\\\]|/)", output, perl = TRUE)) {
  output <- file.path(root, output)
}
dir.create(output, recursive = TRUE, showWarnings = FALSE)
utils::write.csv(
  convergence_results, file.path(output, "convergence.csv"), row.names = FALSE
)

provenance <- liber_validation_provenance(
  root = root, packages = c("LibeRtAD", "LibeRation"),
  library = validation_runtime$path,
  inputs = normalizePath(
    c(
      file.path(fixture_dir, "run-validation.R"),
      file.path(fixture_dir, "README.md")
    ),
    winslash = "/", mustWork = TRUE
  ),
  seeds = list(
    gbm = 2026072401L, logistic_engine = 2026072402L,
    logistic_reference = 2026072403L, particle = 20260724L
  ),
  tolerances = split(results$tolerance, results$case),
  dependencies = c("Rcpp", "jsonlite", "openssl"),
  metadata = list(
    comparisons = nrow(results), passed = passed,
    gbm_subjects = gbm_subjects,
    logistic_subjects = logistic_subjects,
    logistic_reference_subjects = logistic_reference_subjects,
    particle_counts = particle_counts,
    dae_states = dae_states, qsp_species = length(chain_species)
  )
)
summary <- list(
  schema = "liber.edge-family-validation/1",
  passed = passed, complete = TRUE,
  comparisons = split(results, seq_len(nrow(results))),
  convergence = split(
    convergence_results, seq_len(nrow(convergence_results))
  ),
  coverage = split(coverage, seq_len(nrow(coverage))),
  provenance = provenance
)
report <- c(
  "# LibeRation experimental-family edge validation", "",
  paste("- Result:", if (passed) "**PASS**" else "**FAIL**"),
  paste("- Comparisons:", nrow(results)),
  paste("- Families:", paste(unique(results$family), collapse = ", ")),
  "", "## Interpretation", "",
  paste(
    "The named multiplicative/nonlinear SDE, particle, delayed-event/stiff DDE,",
    "larger/coupled DAE, larger/stiff QSP, recovery, and hybrid edge fixtures",
    "passed their independent numerical or contract references."
  ),
  "", "## Qualification boundary", "",
  paste(
    "This evidence is bounded by the declared fixtures and dimensions.",
    "Arbitrary very-large, strongly nonlinear, application-specific, or clinical",
    "systems require their own validation and remain experimental."
  )
)
liber_validation_write_evidence(
  output, comparisons = results, coverage = coverage, summary = summary,
  provenance = provenance, report = report
)
cat(
  "Edge-family validation evidence:",
  normalizePath(output, winslash = "/"), "\n"
)
if (!passed) quit(status = 1L)
