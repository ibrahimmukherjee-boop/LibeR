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
if (!requireNamespace("LibeRation", quietly = TRUE)) {
  stop("Install LibeRation before running experimental-family validation.",
       call. = FALSE)
}
if (!requireNamespace("jsonlite", quietly = TRUE)) {
  stop("The validation runner requires jsonlite.", call. = FALSE)
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
    "%-30s %-25s PASS (max |difference| %.6g)\n",
    case, quantity, difference
  ))
  invisible(difference)
}

add_condition <- function(case, family, quantity, observed, limit,
                          relation = c("less", "greater"), reference) {
  relation <- match.arg(relation)
  passed <- if (relation == "less") observed <= limit else observed >= limit
  comparisons[[length(comparisons) + 1L]] <<- data.frame(
    case = case, family = family, quantity = quantity,
    reference = reference, evidence = "convergence/metamorphic",
    maximum_absolute_difference = as.numeric(observed),
    tolerance = as.numeric(limit), compared_values = 1L,
    passed = passed, status = if (passed) "passed" else "failed",
    stringsAsFactors = FALSE
  )
  if (!passed) {
    stop(
      case, " ", quantity, " condition failed: observed ",
      format(observed, digits = 12), " was not ", relation, " than ",
      format(limit, digits = 12), ".", call. = FALSE
    )
  }
  cat(sprintf(
    "%-30s %-25s PASS (%g %s %g)\n",
    case, quantity, observed,
    if (relation == "less") "<=" else ">=", limit
  ))
  invisible(observed)
}

finite_difference <- function(model, data, step = 1e-5) {
  theta <- model$THETAS$Value
  vapply(seq_along(theta), function(index) {
    plus <- minus <- theta
    plus[[index]] <- plus[[index]] + step
    minus[[index]] <- minus[[index]] - step
    (
      LibeRation::nm_objective(
        model, data, theta = plus, gradient = FALSE
      )$value -
        LibeRation::nm_objective(
          model, data, theta = minus, gradient = FALSE
        )$value
    ) / (2 * step)
  }, numeric(1))
}

theta_table <- function(value, lower = -10, upper = 10, fixed = FALSE) {
  data.frame(
    THETA = seq_along(value), Value = value,
    LOWER = rep(lower, length(value)), UPPER = rep(upper, length(value)),
    FIX = rep(fixed, length(value))
  )
}
acknowledgement <- LibeRation::nm_experimental_config(
  TRUE, label = "canonical numerical validation"
)

# Continuous-discrete SDE: Ornstein--Uhlenbeck -------------------------------
sde_data <- data.frame(
  ID = "A", TIME = c(0, .5, 1.5, 3),
  DV = c(1.1, .7, .4, .25), MDV = 0L
)
sde_theta <- c(k = .4, diffusion = .3, observation_variance = .05)

make_ou_model <- function(substeps = 64L, method = "euler",
                          filter = "ekf", initial_variance = .2,
                          observation_variance = sde_theta[[3L]]) {
  theta <- c(
    k = sde_theta[[1L]],
    diffusion = sde_theta[[2L]],
    observation_variance = observation_variance
  )
  LibeRation::nm_model(
    INPUT = names(sde_data), ADVAN = 1,
    PRED = "CL=1;V=1;S1=1;F=0",
    ERROR = paste(
      "M0=1", paste0("P0=", format(initial_variance, digits = 17)),
      "DRIFT=-THETA(1)*STATE_x", "G0=THETA(2)", "HX=STATE_x",
      "R0=THETA(3)",
      sep = "\n"
    ),
    THETAS = theta_table(theta, 0, 2),
    KALMAN_CONFIG = LibeRation::nm_sde_config(
      states = "x", initial_mean = "M0",
      initial_covariance = matrix("P0", 1L),
      drift = "DRIFT", diffusion = matrix("G0", 1L),
      observation = "HX", observation_variance = "R0",
      baseline = "zero", by_dvid = FALSE, filter = filter,
      method = method, substeps = substeps, particles = 256L, seed = 71L
    )
  )
}

ou_reference <- function(time, observation, theta,
                         initial_mean = 1, initial_variance = .2) {
  mean <- initial_mean
  variance <- initial_variance
  nll <- 0
  predicted <- filtered <- filtered_variance <- numeric(length(time))
  for (index in seq_along(time)) {
    if (index > 1L) {
      interval <- time[[index]] - time[[index - 1L]]
      transition <- exp(-theta[[1L]] * interval)
      process_variance <- theta[[2L]]^2 / (2 * theta[[1L]]) *
        (1 - exp(-2 * theta[[1L]] * interval))
      mean <- transition * mean
      variance <- transition^2 * variance + process_variance
    }
    predicted[[index]] <- mean
    innovation <- observation[[index]] - mean
    innovation_variance <- variance + theta[[3L]]
    nll <- nll + log(innovation_variance) +
      innovation^2 / innovation_variance
    gain <- variance / innovation_variance
    mean <- mean + gain * innovation
    variance <- (1 - gain)^2 * variance +
      gain^2 * theta[[3L]]
    filtered[[index]] <- mean
    filtered_variance[[index]] <- variance
  }
  list(
    nll = nll, predicted = predicted, filtered = filtered,
    filtered_variance = filtered_variance
  )
}

ou_exact <- ou_reference(sde_data$TIME, sde_data$DV, sde_theta)
sde_steps <- c(4L, 16L, 64L, 256L)
sde_errors <- numeric(length(sde_steps))
for (index in seq_along(sde_steps)) {
  model <- make_ou_model(sde_steps[[index]])
  value <- LibeRation::nm_objective(model, sde_data, gradient = FALSE)$value
  sde_errors[[index]] <- abs(value - ou_exact$nll)
  convergence[[length(convergence) + 1L]] <- data.frame(
    family = "SDE", case = "Ornstein-Uhlenbeck filter",
    resolution = sde_steps[[index]], error = sde_errors[[index]],
    stringsAsFactors = FALSE
  )
}
add_comparison(
  "OU SDE filter", "SDE", "finest objective",
  "exact OU transition and scalar Kalman recursion",
  LibeRation::nm_objective(
    make_ou_model(max(sde_steps)), sde_data, gradient = FALSE
  )$value,
  ou_exact$nll, 3e-3
)
add_condition(
  "OU SDE filter", "SDE", "refinement monotonicity",
  max(diff(sde_errors)), 0, "less",
  "objective error must decrease as Euler substeps increase"
)
fine_ou <- make_ou_model(128L)
fine_score <- LibeRation::nm_objective(fine_ou, sde_data, gradient = TRUE)
add_comparison(
  "OU SDE filter", "SDE", "objective gradient",
  "central finite difference", fine_score$gradient,
  finite_difference(fine_ou, sde_data), 8e-5
)
add_comparison(
  "OU SDE filter", "SDE", "EKF/UKF linear equivalence",
  "linear-Gaussian identity",
  LibeRation::nm_objective(
    make_ou_model(128L, filter = "ekf"), sde_data, gradient = FALSE
  )$value,
  LibeRation::nm_objective(
    make_ou_model(128L, filter = "ukf"), sde_data, gradient = FALSE
  )$value,
  1e-7
)

# Seeded SDE simulation moments. The reference is the declared fixed-step
# Euler transition rather than the continuous limit.
simulation_subjects <- 4000L
simulation_substeps <- 64L
simulation_data <- data.frame(
  ID = rep(seq_len(simulation_subjects), each = 2L),
  TIME = rep(c(0, 1), simulation_subjects),
  DV = NA_real_, MDV = 0L
)
simulation_model <- make_ou_model(
  simulation_substeps, "euler", "ukf",
  initial_variance = 0, observation_variance = 0
)
euler_simulation <- LibeRation::nm_simulate(
  simulation_model, simulation_data, residual = TRUE, seed = 20260724L
)
milstein_model <- make_ou_model(
  simulation_substeps, "milstein", "ukf",
  initial_variance = 0, observation_variance = 0
)
milstein_simulation <- LibeRation::nm_simulate(
  milstein_model, simulation_data, residual = TRUE, seed = 20260724L
)
terminal <- euler_simulation$DV[euler_simulation$TIME == 1]
step <- 1 / simulation_substeps
increment_transition <- 1 - sde_theta[[1L]] * step
expected_mean <- increment_transition^simulation_substeps
expected_variance <- sde_theta[[2L]]^2 * step *
  sum(increment_transition^(2 * (0:(simulation_substeps - 1L))))
mean_tolerance <- 6 * sqrt(expected_variance / simulation_subjects)
variance_tolerance <- 6 * expected_variance *
  sqrt(2 / (simulation_subjects - 1L))
add_comparison(
  "OU SDE simulation", "SDE", "terminal mean",
  "fixed-step Euler moment", mean(terminal), expected_mean, mean_tolerance,
  "seeded Monte Carlo calibration"
)
add_comparison(
  "OU SDE simulation", "SDE", "terminal variance",
  "fixed-step Euler moment", stats::var(terminal), expected_variance,
  variance_tolerance, "seeded Monte Carlo calibration"
)
add_comparison(
  "OU SDE simulation", "SDE", "Euler/Milstein additive-noise identity",
  "zero Milstein correction for constant diffusion",
  euler_simulation$DV, milstein_simulation$DV, 0,
  "metamorphic"
)

# Delay differential equation: exact first two method-of-steps intervals -------
dde_times <- seq(0, .4, by = .05)
dde_data <- data.frame(
  ID = 1L, TIME = c(0, dde_times),
  EVID = c(1L, rep(0L, length(dde_times))),
  AMT = c(10, rep(0, length(dde_times))),
  CMT = 1L, DV = NA_real_,
  MDV = c(1L, rep(0L, length(dde_times)))
)
dde_theta <- c(k = .4, feedback = .05, delay = .2)
dde_exact <- function(time, theta = dde_theta) {
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
dde_exact_gradient <- function(time, theta = dde_theta) {
  step <- 1e-6
  gradient <- vapply(seq_along(theta), function(index) {
    plus <- minus <- theta
    plus[[index]] <- plus[[index]] + step
    minus[[index]] <- minus[[index]] - step
    (dde_exact(time, plus) - dde_exact(time, minus)) / (2 * step)
  }, numeric(length(time)))
  interval <- pmax(time - theta[[3L]], 0)
  equilibrium <- theta[[2L]] * 10 / theta[[1L]]
  displacement <- 10 - equilibrium
  gradient[, 3L] <- ifelse(
    time > theta[[3L]],
    exp(-theta[[1L]] * interval) * (
      (theta[[1L]] - theta[[2L]]) * equilibrium +
        theta[[2L]] * displacement *
          (-1 + theta[[1L]] * interval)
    ),
    0
  )
  gradient
}
make_dde_model <- function(step) {
  LibeRation::nm_model(
    INPUT = names(dde_data), ADVAN = 6, DOSECMP = 1, OBSCMP = 1,
    PRED = "K=THETA(1);B=THETA(2);TAU=THETA(3);S1=1",
    DES = "DADT(1)=-K*A(1)+B*LAG(A(1),TAU)",
    THETAS = theta_table(dde_theta, .0001, 2),
    DDE_CONFIG = LibeRation::nm_dde_config(
      history = 10, step = step, minimum_delay = dde_theta[[3L]]
    ),
    EXPERIMENTAL = acknowledgement
  )
}
dde_steps <- c(.05, .025, .0125, .00625)
dde_errors <- numeric(length(dde_steps))
dde_outputs <- vector("list", length(dde_steps))
comparison_rows <- dde_times != dde_theta[[3L]]
for (index in seq_along(dde_steps)) {
  simulation <- LibeRation::nm_simulate(
    make_dde_model(dde_steps[[index]]), dde_data
  )
  prediction <- tail(simulation$IPRED, length(dde_times))
  dde_outputs[[index]] <- prediction
  dde_errors[[index]] <- max(abs(
    prediction[comparison_rows] -
      dde_exact(dde_times)[comparison_rows]
  ))
  convergence[[length(convergence) + 1L]] <- data.frame(
    family = "DDE", case = "linear feedback method of steps",
    resolution = dde_steps[[index]], error = dde_errors[[index]],
    stringsAsFactors = FALSE
  )
}
add_comparison(
  "Linear DDE", "DDE", "finest prediction",
  "closed-form method-of-steps solution",
  dde_outputs[[length(dde_outputs)]][comparison_rows],
  dde_exact(dde_times)[comparison_rows], 6e-4
)
dde_ratio <- dde_errors[-1L] / dde_errors[-length(dde_errors)]
add_comparison(
  "Linear DDE", "DDE", "refinement error ratio",
  "second-order convergence with linearly interpolated smooth history",
  dde_ratio, rep(.25, length(dde_ratio)), .03,
  "convergence"
)
dde_derivative <- tail(
  LibeRation::nm_prediction_derivatives(
    make_dde_model(min(dde_steps)), dde_data
  )$jacobian,
  length(dde_times)
)
add_comparison(
  "Linear DDE", "DDE", "THETA/delay sensitivity",
  "closed-form method-of-steps derivative",
  dde_derivative[comparison_rows, ],
  dde_exact_gradient(dde_times)[comparison_rows, ], 1.5e-2
)

# Nonlinear index-1 DAE --------------------------------------------------------
dae_data <- data.frame(
  ID = 1L, TIME = c(0, 0, .5, 1, 2, 3),
  EVID = c(1L, rep(0L, 5L)), AMT = c(10, rep(0, 5L)),
  CMT = 1L, DV = NA_real_, MDV = c(1L, rep(0L, 5L))
)
dae_k <- .16
dae <- LibeRation::nm_model(
  INPUT = names(dae_data), OUTPUT = "A1",
  ADVAN = 6, DOSECMP = 1, OBSCMP = 1,
  PRED = "K=THETA(1);S1=1", DES = "DADT(1)=-Z",
  ALG = "RES(1)=Z*Z-K*A(1)",
  THETAS = theta_table(dae_k, .001, 2),
  DAE_CONFIG = LibeRation::nm_dae_config(
    "Z", initial = 1, tolerance = 1e-11, maxit = 20L,
    sparsity = matrix(TRUE, 1L)
  ),
  EXPERIMENTAL = acknowledgement
)
dae_simulation <- LibeRation::nm_simulate(dae, dae_data)
dae_expected <- (
  sqrt(10) - .5 * sqrt(dae_k) * dae_data$TIME
)^2
dae_gradient <- -.5 * sqrt(10 / dae_k) * dae_data$TIME +
  .25 * dae_data$TIME^2
add_comparison(
  "Nonlinear index-1 DAE", "DAE", "reduced-system prediction",
  "analytic positive-root reduction",
  dae_simulation$IPRED, dae_expected, 2e-6
)
add_comparison(
  "Nonlinear index-1 DAE", "DAE", "implicit sensitivity",
  "analytic implicit/reduced derivative",
  LibeRation::nm_prediction_derivatives(dae, dae_data)$jacobian[, 1L],
  dae_gradient, 3e-5
)

# QSP reaction network ---------------------------------------------------------
qsp_data <- data.frame(
  ID = 1L, TIME = c(0, 0, .25, .5, 1, 2, 4),
  EVID = c(1L, rep(0L, 6L)), AMT = c(10, rep(0, 6L)),
  CMT = 1L, DV = NA_real_, MDV = c(1L, rep(0L, 6L))
)
qsp_k <- .4
qsp_system <- LibeRation::nm_qsp_system(
  c("Drug", "Metabolite"), matrix(c(-1, 1), 2, 1),
  rates = "K*Drug", dose_species = "Drug",
  observation_species = "Drug"
)
qsp <- LibeRation::nm_qsp_model(
  qsp_system, INPUT = names(qsp_data), OUTPUT = c("A1", "A2"),
  PRED = "K=THETA(1);S1=1",
  THETAS = theta_table(qsp_k, .001, 2),
  EXPERIMENTAL = acknowledgement
)
qsp_simulation <- LibeRation::nm_simulate(qsp, qsp_data)
qsp_drug <- 10 * exp(-qsp_k * qsp_data$TIME)
qsp_metabolite <- 10 - qsp_drug
add_comparison(
  "First-order QSP network", "QSP", "species amounts",
  "closed-form irreversible conversion",
  c(qsp_simulation$A1, qsp_simulation$A2),
  c(qsp_drug, qsp_metabolite), 2e-7
)
add_comparison(
  "First-order QSP network", "QSP", "mass conservation",
  "stoichiometric invariant",
  qsp_simulation$A1 + qsp_simulation$A2,
  rep(10, nrow(qsp_simulation)), 2e-8,
  "conservation law"
)
add_comparison(
  "First-order QSP network", "QSP", "parameter sensitivity",
  "closed-form derivative",
  LibeRation::nm_prediction_derivatives(qsp, qsp_data)$jacobian[, 1L],
  -10 * qsp_data$TIME * exp(-qsp_k * qsp_data$TIME), 3e-6
)

# Immutable offline hybrid components -----------------------------------------
component_data <- data.frame(
  ID = 1L, TIME = 0:4, X = c(-1, -.25, .5, 1.25, 2),
  DV = c(.8, .5, .1, -.2, -.4), MDV = 0L
)
dense <- LibeRation::nm_component(
  "dense", "dense_nn", scope = "pred",
  inputs = c("THETA_1", "X"), outputs = "NN",
  weights = list(
    matrix(c(.4, -.6, .8, .3), 2, 2, byrow = TRUE),
    matrix(c(1.2, -.7), 1, 2)
  ),
  biases = list(c(.1, -.2), .05), activation = "tanh"
)
spline <- LibeRation::nm_component(
  "spline", "linear_spline", scope = "pred",
  inputs = "X", outputs = "SPLINE",
  knots = c(-1, 0, 2), values = c(0, 1, .5)
)
gp_training <- matrix(c(-1, .5, 2), ncol = 1)
gp_alpha <- c(.4, -.2, .3)
gp <- LibeRation::nm_component(
  "gp", "gaussian_process", scope = "pred",
  inputs = "X", outputs = "GP",
  training = gp_training, alpha = gp_alpha,
  lengthscale = .8, variance = 1.3, mean = -.1
)
component_model <- LibeRation::nm_model(
  INPUT = names(component_data), OUTPUT = c("NN", "SPLINE", "GP"),
  ADVAN = 1, PRED = "CL=1;V=1;S1=1;F=0",
  THETAS = theta_table(.7, -2, 2),
  COMPONENTS = list(dense, spline, gp),
  OUTCOMES = LibeRation::nm_outcome(
    "normal", prediction = "NN", scale = .2
  ),
  EXPERIMENTAL = acknowledgement
)
component_simulation <- LibeRation::nm_simulate(
  component_model, component_data, residual = FALSE
)
dense_reference <- function(theta, x) {
  hidden_1 <- tanh(.1 + .4 * theta - .6 * x)
  hidden_2 <- tanh(-.2 + .8 * theta + .3 * x)
  .05 + 1.2 * hidden_1 - .7 * hidden_2
}
spline_reference <- function(x) {
  ifelse(
    x <= -1, 0,
    ifelse(x <= 0, x + 1, ifelse(x <= 2, 1 - .25 * x, .5))
  )
}
gp_reference <- function(x) {
  -.1 + 1.3 * vapply(x, function(value) {
    sum(gp_alpha * exp(-.5 * ((value - gp_training[, 1L]) / .8)^2))
  }, numeric(1))
}
expected_dense <- dense_reference(.7, component_data$X)
add_comparison(
  "Offline components", "hybrid", "dense/spline/GP outputs",
  "independent component forward calculations",
  c(
    component_simulation$NN, component_simulation$SPLINE,
    component_simulation$GP
  ),
  c(
    expected_dense, spline_reference(component_data$X),
    gp_reference(component_data$X)
  ),
  2e-12
)
component_score <- LibeRation::nm_objective(
  component_model, component_data, gradient = TRUE
)
component_expected_objective <- -2 * sum(stats::dnorm(
  component_data$DV, expected_dense, .2, log = TRUE
))
add_comparison(
  "Offline components", "hybrid", "likelihood objective",
  "base R normal likelihood around independent dense output",
  component_score$value, component_expected_objective, 2e-10
)
add_comparison(
  "Offline components", "hybrid", "component gradient",
  "central finite difference",
  component_score$gradient,
  finite_difference(component_model, component_data), 3e-5
)

hybrid_data <- data.frame(
  ID = 1L, TIME = c(0, 0, .5, 1, 2, 4),
  EVID = c(1L, rep(0L, 5L)), AMT = c(10, rep(0, 5L)),
  CMT = 1L, DV = NA_real_, MDV = c(1L, rep(0L, 5L))
)
learned_loss <- LibeRation::nm_component(
  "learned_loss", "dense_nn", scope = "des",
  inputs = "A_1", outputs = "LOSS",
  weights = list(matrix(.4, 1, 1)), biases = list(0)
)
hybrid <- LibeRation::nm_model(
  INPUT = names(hybrid_data), OUTPUT = "A1",
  ADVAN = 6, DOSECMP = 1, OBSCMP = 1,
  PRED = "S1=1", DES = "DADT(1)=-LOSS",
  THETAS = theta_table(1, fixed = TRUE),
  COMPONENTS = learned_loss, EXPERIMENTAL = acknowledgement
)
hybrid_simulation <- LibeRation::nm_simulate(hybrid, hybrid_data)
add_comparison(
  "Learned hybrid dynamics", "hybrid", "DES trajectory",
  "closed-form linear component dynamics",
  hybrid_simulation$IPRED,
  10 * exp(-.4 * hybrid_data$TIME), 2e-7
)

# Evidence --------------------------------------------------------------------
coverage <- data.frame(
  family = c(
    "Additive-noise SDE filtering", "SDE simulation",
    "DDE method of steps", "Index-1 DAE",
    "QSP reaction networks", "Offline hybrid components",
    "General nonlinear/multiplicative SDE", "Large nonlinear DDE/DAE/QSP"
  ),
  reference = c(
    "exact OU transition and Kalman recursion",
    "seeded Euler moments and Euler/Milstein identity",
    "closed-form first two delay intervals and sensitivities",
    "nonlinear analytic reduction and implicit sensitivity",
    "closed-form reaction and mass conservation",
    "independent dense/spline/GP and learned ODE calculations",
    "canonical additive-noise case only",
    "canonical low-dimensional cases only"
  ),
  evidence_tier = c(
    rep("validated", 6L), "verified", "verified"
  ),
  recommended_use = c(
    rep("Experimental research only", 8L)
  ),
  stringsAsFactors = FALSE
)

results <- do.call(rbind, comparisons)
convergence_results <- do.call(rbind, convergence)
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
  convergence_results, file.path(output, "convergence.csv"),
  row.names = FALSE
)

provenance <- liber_validation_provenance(
  root = root, packages = c("LibeRtAD", "LibeRation"),
  library = validation_runtime$path,
  inputs = normalizePath(
    c(file.path(fixture_dir, "run-validation.R"),
      file.path(fixture_dir, "README.md")),
    winslash = "/", mustWork = TRUE
  ),
  seeds = list(sde_simulation = 20260724L),
  tolerances = split(results$tolerance, results$case),
  dependencies = c("Rcpp", "jsonlite", "openssl"),
  metadata = list(
    comparisons = nrow(results), passed = passed,
    sde_subjects = simulation_subjects,
    sde_substeps = simulation_substeps
  )
)
summary <- list(
  schema = "liber.experimental-family-validation/1",
  passed = passed,
  complete = TRUE,
  comparisons = split(results, seq_len(nrow(results))),
  convergence = split(
    convergence_results, seq_len(nrow(convergence_results))
  ),
  coverage = split(coverage, seq_len(nrow(coverage))),
  provenance = provenance
)

report <- c(
  "# LibeRation experimental-family validation report", "",
  paste("- Result:", if (passed) "**PASS**" else "**FAIL**"),
  paste("- Comparisons:", nrow(results)),
  paste("- Families:", paste(unique(results$family), collapse = ", ")),
  "", "## Interpretation", "",
  paste(
    "The canonical numerical contracts for SDE, DDE, DAE, QSP, and offline",
    "hybrid components passed independent analytic, convergence, conservation,",
    "metamorphic, derivative, and seeded Monte Carlo checks."
  ),
  "", "## Qualification boundary", "",
  paste(
    "These results do not validate every possible nonlinear system.",
    "The families remain restricted to experimental research use until broader",
    "property-based, stress, external, and application-specific campaigns are",
    "complete."
  )
)
liber_validation_write_evidence(
  output, comparisons = results, coverage = coverage, summary = summary,
  provenance = provenance, report = report
)
cat(
  "Experimental-family validation evidence:",
  normalizePath(output, winslash = "/"), "\n"
)
if (!passed) quit(status = 1L)
