.lity_variable_encoding <- function(design) {
  if (!length(design$variables)) return(data.frame(
    name = character(), initial = numeric(), lower = numeric(), upper = numeric(),
    type = character(), stringsAsFactors = FALSE
  ))
  rows <- lapply(design$variables, function(variable) {
    current <- variable$initial %||% .lity_variable_current(design, variable)
    if (variable$type == "categorical") {
      current <- match(current, variable$values) %||% 1L
      lower <- 1; upper <- length(variable$values)
    } else {
      current <- as.numeric(current)
      lower <- variable$lower; upper <- variable$upper
      span <- max(abs(current), 1)
      if (!is.finite(lower)) lower <- current - 5 * span
      if (!is.finite(upper)) upper <- current + 5 * span
    }
    data.frame(name = variable$name, initial = current, lower = lower, upper = upper,
               type = variable$type, stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

.lity_decode_values <- function(design, encoded) {
  values <- as.list(as.numeric(encoded))
  for (i in seq_along(values)) {
    variable <- design$variables[[i]]
    if (variable$type == "integer") values[[i]] <- round(values[[i]])
    if (variable$type == "discrete") values[[i]] <- variable$values[[which.min(abs(variable$values - values[[i]]))]]
    if (variable$type == "categorical") {
      index <- min(length(variable$values), max(1L, round(values[[i]])))
      values[[i]] <- variable$values[[index]]
    }
  }
  values
}

.lity_scalar_objective <- function(evaluation, criterion) {
  value <- evaluation$criteria$value[[1L]]
  if (!is.finite(value)) return(.Machine$double.xmax / 1e100)
  if (criterion$direction == "maximise") -value else value
}

.lity_stats_optim_control <- function(control) {
  allowed <- c(
    "trace", "fnscale", "parscale", "ndeps", "maxit", "abstol", "reltol",
    "alpha", "beta", "gamma", "REPORT", "factr", "pgtol", "lmm", "temp", "tmax"
  )
  control[intersect(names(control), allowed)]
}

.lity_objective_factory <- function(design, criterion, penalty = 1e8,
                                    progress = NULL, cancel = NULL) {
  cache <- new.env(parent = emptyenv())
  trace <- list(); evaluations <- 0L
  fn <- function(encoded) {
    key <- paste(format(encoded, digits = 15, scientific = TRUE), collapse = "|")
    if (exists(key, cache, inherits = FALSE)) return(get(key, cache, inherits = FALSE)$objective)
    if (is.function(cancel) && isTRUE(cancel())) .lity_stop("Optimisation cancelled.")
    candidate <- .lity_apply_values(design, .lity_decode_values(design, encoded))
    evaluated <- tryCatch(lity_evaluate(candidate, criterion, check_constraints = FALSE), error = identity)
    evaluations <<- evaluations + 1L
    if (inherits(evaluated, "error")) {
      objective <- penalty * 100 + evaluations
      constraints <- NULL; value <- NA_real_; error <- conditionMessage(evaluated)
    } else {
      constraints <- tryCatch(lity_constraint_check(candidate, evaluated), error = identity)
      violation <- if (inherits(constraints, "error")) penalty else sum(constraints$violation^2)
      objective <- .lity_scalar_objective(evaluated, criterion) + penalty * violation
      value <- evaluated$criteria$value[[1L]]; error <- ""
    }
    record <- list(iteration = evaluations, values = as.numeric(encoded),
                   criterion = value, objective = objective,
                   feasible = !inherits(constraints, "error") && (is.null(constraints) || all(constraints$feasible)),
                   error = error)
    trace[[length(trace) + 1L]] <<- record
    assign(key, list(objective = objective, evaluation = evaluated, design = candidate), cache)
    if (is.function(progress)) progress(record)
    objective
  }
  list(fn = fn, trace = function() trace, cache = cache, evaluations = function() evaluations)
}

.lity_pso <- function(fn, initial, lower, upper, control) {
  particles <- as.integer(control$particles %||% max(16L, 4L * length(initial)))
  iterations <- as.integer(control$maxit %||% 80L)
  inertia <- as.numeric(control$inertia %||% 0.72)
  cognitive <- as.numeric(control$cognitive %||% 1.49)
  social <- as.numeric(control$social %||% 1.49)
  positions <- matrix(stats::runif(particles * length(initial), lower, upper), particles, byrow = TRUE)
  positions[1L, ] <- initial
  velocities <- matrix(0, particles, length(initial))
  score <- apply(positions, 1L, fn)
  personal <- positions; personal_score <- score
  best_index <- which.min(score); best <- positions[best_index, ]; best_score <- score[[best_index]]
  stall <- 0L
  for (iteration in seq_len(iterations)) {
    old <- best_score
    for (particle in seq_len(particles)) {
      velocities[particle, ] <- inertia * velocities[particle, ] +
        cognitive * stats::runif(length(initial)) * (personal[particle, ] - positions[particle, ]) +
        social * stats::runif(length(initial)) * (best - positions[particle, ])
      positions[particle, ] <- pmin(upper, pmax(lower, positions[particle, ] + velocities[particle, ]))
      score[[particle]] <- fn(positions[particle, ])
      if (score[[particle]] < personal_score[[particle]]) {
        personal[particle, ] <- positions[particle, ]; personal_score[[particle]] <- score[[particle]]
      }
      if (score[[particle]] < best_score) {
        best <- positions[particle, ]; best_score <- score[[particle]]
      }
    }
    stall <- if (abs(old - best_score) <= (control$reltol %||% 1e-7) * max(1, abs(old))) stall + 1L else 0L
    if (stall >= (control$stall %||% 10L)) break
  }
  list(par = best, value = best_score, convergence = if (stall >= (control$stall %||% 10L)) 0L else 1L,
       message = if (stall >= (control$stall %||% 10L)) "PSO relative tolerance reached" else "PSO iteration limit reached")
}

.lity_coordinate_exchange <- function(fn, initial, lower, upper, design, control) {
  current <- initial; value <- fn(current); maxit <- as.integer(control$maxit %||% 40L)
  improved <- TRUE; iteration <- 0L
  while (improved && iteration < maxit) {
    improved <- FALSE; iteration <- iteration + 1L
    for (i in seq_along(current)) {
      variable <- design$variables[[i]]
      candidates <- if (variable$type %in% c("discrete", "categorical")) {
        if (variable$type == "categorical") seq_along(variable$values) else variable$values
      } else if (variable$type == "integer") seq(ceiling(lower[[i]]), floor(upper[[i]]))
      else seq(lower[[i]], upper[[i]], length.out = as.integer(control$grid_points %||% 15L))
      candidate_scores <- vapply(candidates, function(candidate) {
        trial <- current; trial[[i]] <- candidate; fn(trial)
      }, numeric(1))
      best <- which.min(candidate_scores)
      if (candidate_scores[[best]] + (control$reltol %||% 1e-8) < value) {
        current[[i]] <- candidates[[best]]; value <- candidate_scores[[best]]; improved <- TRUE
      }
    }
  }
  list(par = current, value = value, convergence = 0L,
       message = if (improved) "Coordinate-exchange iteration limit reached" else "Coordinate exchange converged")
}

.lity_allocation_sensitivity <- function(information, per_subject, criterion,
                                         tolerance = 1e-10) {
  supported <- c("D", "Ds", "A", "E", "c", "prediction_variance", "L")
  if (!criterion$type %in% supported) {
    .lity_stop(
      "Allocation equivalence-theorem updates are not implemented for `",
      criterion$type, "`. Use a general optimiser; supported smooth allocation ",
      "criteria are ", paste(supported, collapse = ", "), "."
    )
  }
  matrix <- information$matrix
  covariance <- information$covariance
  parameter_names <- rownames(matrix)
  subset <- .lity_match_parameters(criterion$parameters, parameter_names)
  quadratic_trace <- function(weight) {
    middle <- covariance %*% weight %*% covariance
    vapply(per_subject, function(item) sum(middle * t(item)), numeric(1))
  }
  score <- if (criterion$type == "D") {
    vapply(per_subject, function(item) sum(diag(covariance %*% item)), numeric(1))
  } else if (criterion$type == "A") {
    weights <- rep(as.numeric(criterion$weights %||% 1), length.out = length(subset))
    weight <- matrix(0, nrow(matrix), ncol(matrix))
    diag(weight)[subset] <- weights
    quadratic_trace(weight)
  } else if (criterion$type %in% c("c", "prediction_variance")) {
    contrast <- .lity_contrast(criterion, information)
    direction <- drop(covariance %*% contrast)
    vapply(per_subject, function(item) drop(crossprod(direction, item %*% direction)), numeric(1))
  } else if (criterion$type == "L") {
    L <- criterion$matrix
    if (ncol(L) != nrow(matrix)) .lity_stop("L-criterion matrix has the wrong number of columns.")
    weights <- rep(as.numeric(criterion$weights %||% 1), length.out = nrow(L))
    quadratic_trace(crossprod(L, weights * L))
  } else if (criterion$type == "Ds") {
    selected_covariance <- covariance[subset, subset, drop = FALSE]
    selected_inverse <- .lity_safe_inverse(selected_covariance)
    vapply(per_subject, function(item) {
      change <- covariance %*% item %*% covariance
      sum(diag(selected_inverse %*% change[subset, subset, drop = FALSE]))
    }, numeric(1))
  } else {
    selected_covariance <- covariance[subset, subset, drop = FALSE]
    effective <- .lity_safe_inverse(selected_covariance)
    decomposition <- eigen((effective + t(effective)) / 2, symmetric = TRUE)
    values <- rev(decomposition$values)
    vectors <- decomposition$vectors[, rev(seq_len(ncol(decomposition$vectors))), drop = FALSE]
    scale <- max(abs(values), 1)
    if (length(values) > 1L && abs(values[[2L]] - values[[1L]]) <= tolerance * scale) {
      .lity_stop(
        "E-optimal allocation is non-smooth because the minimum information ",
        "eigenvalue is repeated. Use a general derivative-free optimiser."
      )
    }
    eigenvector <- vectors[, 1L, drop = FALSE]
    vapply(per_subject, function(item) {
      change <- covariance %*% item %*% covariance
      effective_change <- effective %*%
        change[subset, subset, drop = FALSE] %*% effective
      drop(crossprod(eigenvector, effective_change %*% eigenvector))
    }, numeric(1))
  }
  if (any(!is.finite(score)) || max(score) <= 0) {
    .lity_stop("Criterion-specific allocation sensitivities are not finite and positive.")
  }
  score
}

.lity_allocation_optimise <- function(design, criterion, method, control, progress, cancel) {
  total <- sum(vapply(design$arms, `[[`, numeric(1), "size"))
  if (total < 1L) .lity_stop("Allocation optimisation requires at least one subject.")
  weight <- .lity_normalize_weights(vapply(design$arms, `[[`, numeric(1), "allocation"))
  trace <- list(); maxit <- as.integer(control$maxit %||% 100L)
  for (iteration in seq_len(maxit)) {
    if (is.function(cancel) && isTRUE(cancel())) .lity_stop("Optimisation cancelled.")
    candidate <- design
    sizes <- floor(total * weight)
    remainder <- total - sum(sizes)
    if (remainder > 0L) sizes[order(total * weight - sizes, decreasing = TRUE)[seq_len(remainder)]] <- sizes[order(total * weight - sizes, decreasing = TRUE)[seq_len(remainder)]] + 1L
    for (i in seq_along(candidate$arms)) {
      candidate$arms[[i]]$size <- sizes[[i]]; candidate$arms[[i]]$allocation <- weight[[i]]
    }
    info <- lity_information(candidate)
    per_subject <- lapply(seq_along(candidate$arms), function(i) {
      contribution <- info$arm_contributions[[i]]
      if (sizes[[i]] > 0) contribution / sizes[[i]] else {
        one <- candidate; one$arms[[i]]$size <- 1L
        others <- setdiff(seq_along(one$arms), i); for (j in others) one$arms[[j]]$size <- 0L
        lity_information(one)$matrix
      }
    })
    directional <- .lity_allocation_sensitivity(info, per_subject, criterion)
    old <- weight
    if (method == "multiplicative") weight <- .lity_normalize_weights(weight * pmax(directional, 1e-12))
    else {
      best <- which.max(directional); step <- 2 / (iteration + 2)
      weight <- (1 - step) * weight; weight[[best]] <- weight[[best]] + step
    }
    evaluation <- lity_evaluate(candidate, criterion)
    trace[[iteration]] <- list(iteration = iteration, values = weight,
                               criterion = evaluation$criteria$value[[1L]], objective = directional,
                               feasible = all(evaluation$constraints$feasible %||% TRUE), error = "")
    if (is.function(progress)) progress(trace[[iteration]])
    if (max(abs(weight - old)) < (control$reltol %||% 1e-6)) break
  }
  final <- design
  sizes <- floor(total * weight); remainder <- total - sum(sizes)
  if (remainder > 0L) {
    order_fraction <- order(total * weight - sizes, decreasing = TRUE)
    sizes[order_fraction[seq_len(remainder)]] <- sizes[order_fraction[seq_len(remainder)]] + 1L
  }
  for (i in seq_along(final$arms)) { final$arms[[i]]$size <- sizes[[i]]; final$arms[[i]]$allocation <- weight[[i]] }
  list(design = final, trace = trace, convergence = 0L,
       message = paste(method, "allocation optimisation completed"), evaluations = length(trace))
}

#' Optimise a LibeRality design
#'
#' @param design Design with [lity_variable()] definitions.
#' @param criterion Scalar criterion. Compound criteria are supported directly;
#'   use [lity_pareto()] for an unscalarised Pareto criterion.
#' @param method Automatic, gradient-based, simplex, particle-swarm, coordinate
#'   exchange, hybrid, multiplicative, or Fedorov-Wynn optimisation.
#' @param control Named optimiser controls.
#' @param penalty Quadratic constraint-violation penalty.
#' @param seed Reproducible seed.
#' @param progress Optional callback receiving every evaluation record.
#' @param cancel Optional function returning `TRUE` to cancel.
#' @param checkpoint Optional RDS checkpoint path.
#' @return A `lity_optimisation` result.
#' @export
lity_optimise <- function(design, criterion = lity_criterion_D(),
                          method = c("auto", "L-BFGS-B", "Nelder-Mead", "pso",
                                     "coordinate_exchange", "hybrid", "multiplicative", "fedorov_wynn"),
                          control = list(), penalty = 1e8, seed = 7301L,
                          progress = NULL, cancel = NULL, checkpoint = NULL) {
  started <- proc.time()[[3L]]; method <- match.arg(method); .lity_seed(seed)
  if (!inherits(criterion, "lity_criterion")) .lity_stop("`criterion` must be a LibeRality criterion.")
  if (criterion$type == "pareto") return(lity_pareto(design, criterion, control = control, seed = seed, progress = progress))
  initial_evaluation <- lity_evaluate(design, criterion)
  if (method %in% c("multiplicative", "fedorov_wynn")) {
    optimized <- .lity_allocation_optimise(design, criterion, method, control, progress, cancel)
    final_design <- optimized$design; trace <- optimized$trace
    convergence <- optimized$convergence; message <- optimized$message; evaluations <- optimized$evaluations
  } else {
    encoding <- .lity_variable_encoding(design)
    if (!nrow(encoding)) .lity_stop("The design has no optimisation variables. Add lity_variable() objects or use an allocation method.")
    if (method == "auto") method <- if (all(encoding$type == "continuous")) "L-BFGS-B" else "hybrid"
    objective <- .lity_objective_factory(design, criterion, penalty, progress, cancel)
    if (method == "L-BFGS-B") {
      fit <- stats::optim(encoding$initial, objective$fn, method = "L-BFGS-B",
                          lower = encoding$lower, upper = encoding$upper,
                          control = .lity_stats_optim_control(control))
    } else if (method == "Nelder-Mead") {
      bounded <- function(x) objective$fn(pmin(encoding$upper, pmax(encoding$lower, x)))
      if (length(encoding$initial) == 1L) {
        scalar <- stats::optimize(
          bounded, interval = c(encoding$lower, encoding$upper),
          tol = control$reltol %||% .Machine$double.eps^0.25
        )
        fit <- list(par = scalar$minimum, value = scalar$objective,
                    convergence = 0L, message = "Bounded scalar optimisation completed")
      } else {
        fit <- stats::optim(
          encoding$initial, bounded, method = "Nelder-Mead",
          control = .lity_stats_optim_control(control)
        )
        fit$par <- pmin(encoding$upper, pmax(encoding$lower, fit$par))
      }
    } else if (method == "coordinate_exchange") {
      fit <- .lity_coordinate_exchange(objective$fn, encoding$initial, encoding$lower,
                                        encoding$upper, design, control)
    } else {
      fit <- .lity_pso(objective$fn, encoding$initial, encoding$lower, encoding$upper, control)
      if (method == "hybrid" && any(encoding$type == "continuous")) {
        continuous <- which(encoding$type == "continuous")
        local_fn <- function(values) { point <- fit$par; point[continuous] <- values; objective$fn(point) }
        local <- stats::optim(fit$par[continuous], local_fn, method = "L-BFGS-B",
                              lower = encoding$lower[continuous], upper = encoding$upper[continuous],
                              control = utils::modifyList(list(maxit = 30L), control$local %||% list()))
        fit$par[continuous] <- local$par; fit$value <- local$value
        fit$convergence <- max(fit$convergence, local$convergence)
        fit$message <- paste(fit$message, "+ local L-BFGS-B:", local$message %||% "completed")
      }
    }
    final_design <- .lity_apply_values(design, .lity_decode_values(design, fit$par))
    trace <- objective$trace(); convergence <- fit$convergence; message <- fit$message %||% ""
    evaluations <- objective$evaluations()
  }
  final_evaluation <- lity_evaluate(final_design, criterion)
  result <- structure(list(
    schema = "liberality.optimisation", version = 1L, id = .lity_id("optimisation"),
    method = method, criterion = criterion, initial_design = design,
    design = final_design, initial_evaluation = initial_evaluation,
    evaluation = final_evaluation, trace = trace, convergence = convergence,
    message = message, evaluations = evaluations, seed = as.integer(seed),
    elapsed_seconds = proc.time()[[3L]] - started, created_at = .lity_now()
  ), class = "lity_optimisation")
  if (!is.null(checkpoint)) saveRDS(result, checkpoint, version = 3)
  result
}

#' @export
print.lity_optimisation <- function(x, ...) {
  cat("LibeRality optimisation\n")
  cat("  method:", x$method, " convergence:", x$convergence,
      " evaluations:", x$evaluations, "\n")
  cat("  initial:", x$initial_evaluation$criteria$value[[1L]],
      " final:", x$evaluation$criteria$value[[1L]], "\n")
  cat("  elapsed:", format(x$elapsed_seconds, digits = 5), "seconds\n")
  invisible(x)
}

.lity_dominated <- function(values, directions) {
  maximize <- directions == "maximise"
  transformed <- values
  transformed[, !maximize] <- -transformed[, !maximize, drop = FALSE]
  dominated <- logical(nrow(transformed))
  for (i in seq_len(nrow(transformed))) {
    dominated[[i]] <- any(vapply(setdiff(seq_len(nrow(transformed)), i), function(j) {
      all(transformed[j, ] >= transformed[i, ]) && any(transformed[j, ] > transformed[i, ])
    }, logical(1)))
  }
  dominated
}

#' Explore the Pareto frontier of a multi-objective design
#' @param design Design object.
#' @param criterion Pareto criterion.
#' @param n Number of candidate designs.
#' @param control Optional controls; `n` overrides the argument.
#' @param seed Reproducible seed.
#' @param progress Optional callback.
#' @export
lity_pareto <- function(design, criterion, n = 250L, control = list(), seed = 7301L,
                        progress = NULL) {
  if (!inherits(criterion, "lity_criterion") || criterion$type != "pareto") .lity_stop("A Pareto criterion is required.")
  encoding <- .lity_variable_encoding(design)
  if (!nrow(encoding)) .lity_stop("Pareto exploration requires design variables.")
  .lity_seed(seed); n <- as.integer(control$n %||% n)
  candidates <- matrix(stats::runif(n * nrow(encoding), encoding$lower, encoding$upper), n, byrow = TRUE)
  candidates[1L, ] <- encoding$initial
  values <- matrix(NA_real_, n, length(criterion$components))
  designs <- vector("list", n); evaluations <- vector("list", n)
  for (i in seq_len(n)) {
    designs[[i]] <- .lity_apply_values(design, .lity_decode_values(design, candidates[i, ]))
    evaluations[[i]] <- lity_evaluate(designs[[i]], criterion)
    values[i, ] <- evaluations[[i]]$criterion_details[[1L]]$details$components
    if (is.function(progress)) progress(list(iteration = i, values = candidates[i, ], criteria = values[i, ]))
  }
  colnames(values) <- names(criterion$components)
  directions <- vapply(criterion$components, `[[`, character(1), "direction")
  dominated <- .lity_dominated(values, directions)
  structure(list(
    schema = "liberality.pareto", version = 1L, criterion = criterion,
    design = design,
    candidates = candidates, values = values, directions = directions,
    dominated = dominated, frontier = which(!dominated),
    designs = designs, evaluations = evaluations, seed = as.integer(seed),
    created_at = .lity_now()
  ), class = c("lity_pareto", "lity_optimisation"))
}
