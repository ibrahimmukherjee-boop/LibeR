.ad_matrix_shape <- function(shape, what) {
  shape <- as.integer(shape)
  if (length(shape) == 1L) shape <- c(shape, 1L)
  if (length(shape) != 2L || anyNA(shape) || any(shape < 1L)) {
    .ad_stop(what, " must be a positive fixed shape `c(nrow, ncol)`.")
  }
  unname(shape)
}

.ad_matrix_name <- function(name, what = "matrix name") {
  name <- as.character(name)
  if (length(name) != 1L || is.na(name) ||
      !grepl("^[A-Za-z][A-Za-z0-9_.]*$", name)) {
    .ad_stop(what, " must be one syntactically simple name.")
  }
  name
}

.ad_matrix_internal_names <- function(name, shape) {
  output <- base::matrix(character(prod(shape)), shape[[1L]], shape[[2L]])
  for (column in seq_len(shape[[2L]])) for (row in seq_len(shape[[1L]])) {
    output[row, column] <- paste0(".admx_", name, "_r", row, "_c", column)
  }
  output
}

.ad_matrix_input_names <- function(name, shape) {
  output <- base::matrix(character(prod(shape)), shape[[1L]], shape[[2L]])
  for (column in seq_len(shape[[2L]])) for (row in seq_len(shape[[1L]])) {
    output[row, column] <- paste0(name, "__r", row, "_c", column)
  }
  output
}

.ad_matrix_labels <- function(name, shape) {
  output <- base::matrix(character(prod(shape)), shape[[1L]], shape[[2L]])
  for (column in seq_len(shape[[2L]])) for (row in seq_len(shape[[1L]])) {
    output[row, column] <- paste0(name, "[", row, ",", column, "]")
  }
  output
}

.ad_matrix_list <- function(nrow, ncol, value = NULL) {
  output <- base::matrix(vector("list", nrow * ncol), nrow, ncol)
  if (!is.null(value)) for (i in seq_len(length(output))) output[[i]] <- value
  output
}

.ad_matrix_symbols <- function(names) {
  output <- .ad_matrix_list(nrow(names), ncol(names))
  for (i in seq_len(length(names))) output[[i]] <- as.name(names[[i]])
  output
}

.ad_matrix_call <- function(operator, left, right = NULL) {
  if (is.null(right)) as.call(list(as.name(operator), left)) else
    as.call(list(as.name(operator), left, right))
}

.ad_matrix_sum <- function(values) {
  if (!length(values)) return(0)
  Reduce(function(left, right) .ad_matrix_call("+", left, right), values)
}

.ad_matrix_binary <- function(left, right, operator) {
  if (!identical(dim(left), dim(right))) .ad_stop("Matrix shapes are incompatible for `", operator, "`.")
  output <- .ad_matrix_list(nrow(left), ncol(left))
  for (i in seq_len(length(output))) output[[i]] <- .ad_matrix_call(operator, left[[i]], right[[i]])
  output
}

.ad_matrix_multiply <- function(left, right) {
  if (ncol(left) != nrow(right)) .ad_stop("Matrix shapes are incompatible for multiplication.")
  output <- .ad_matrix_list(nrow(left), ncol(right))
  for (column in seq_len(ncol(right))) for (row in seq_len(nrow(left))) {
    output[[row, column]] <- .ad_matrix_sum(lapply(seq_len(ncol(left)), function(k) {
      .ad_matrix_call("*", left[[row, k]], right[[k, column]])
    }))
  }
  output
}

.ad_matrix_identity <- function(n) {
  output <- .ad_matrix_list(n, n, 0)
  for (i in seq_len(n)) output[[i, i]] <- 1
  output
}

.ad_matrix_scale <- function(matrix, scalar) {
  output <- .ad_matrix_list(nrow(matrix), ncol(matrix))
  for (i in seq_len(length(output))) output[[i]] <- .ad_matrix_call("*", matrix[[i]], scalar)
  output
}

.ad_matrix_cholesky <- function(matrix) {
  if (nrow(matrix) != ncol(matrix)) .ad_stop("Cholesky input must be square.")
  n <- nrow(matrix)
  lower <- .ad_matrix_list(n, n, 0)
  for (row in seq_len(n)) for (column in seq_len(row)) {
    previous <- if (column > 1L) seq_len(column - 1L) else integer()
    residual <- .ad_matrix_call(
      "-", matrix[[row, column]],
      .ad_matrix_sum(lapply(previous, function(k) {
        .ad_matrix_call("*", lower[[row, k]], lower[[column, k]])
      }))
    )
    lower[[row, column]] <- if (row == column) {
      .ad_matrix_call("sqrt", residual)
    } else .ad_matrix_call("/", residual, lower[[column, column]])
  }
  lower
}

.ad_matrix_triangular_solve <- function(triangular, rhs, lower = TRUE, transpose = FALSE) {
  if (nrow(triangular) != ncol(triangular) || nrow(triangular) != nrow(rhs)) {
    .ad_stop("Triangular solve requires a square coefficient matrix and a conformable right-hand side.")
  }
  if (isTRUE(transpose)) {
    triangular <- t(triangular)
    lower <- !isTRUE(lower)
  }
  n <- nrow(triangular)
  output <- .ad_matrix_list(n, ncol(rhs), 0)
  order <- if (isTRUE(lower)) seq_len(n) else rev(seq_len(n))
  for (column in seq_len(ncol(rhs))) for (row in order) {
    known <- if (isTRUE(lower)) seq_len(row - 1L) else if (row < n) (row + 1L):n else integer()
    residual <- .ad_matrix_call(
      "-", rhs[[row, column]],
      .ad_matrix_sum(lapply(known, function(k) {
        .ad_matrix_call("*", triangular[[row, k]], output[[k, column]])
      }))
    )
    output[[row, column]] <- .ad_matrix_call("/", residual, triangular[[row, row]])
  }
  output
}

.ad_matrix_solve_no_pivot <- function(matrix, rhs) {
  if (nrow(matrix) != ncol(matrix) || nrow(matrix) != nrow(rhs)) {
    .ad_stop("Solve requires a square coefficient matrix and a conformable right-hand side.")
  }
  n <- nrow(matrix)
  lower <- .ad_matrix_identity(n)
  upper <- .ad_matrix_list(n, n, 0)
  for (row in seq_len(n)) {
    for (column in row:n) {
      previous <- if (row > 1L) seq_len(row - 1L) else integer()
      upper[[row, column]] <- .ad_matrix_call(
        "-", matrix[[row, column]],
        .ad_matrix_sum(lapply(previous, function(k) {
          .ad_matrix_call("*", lower[[row, k]], upper[[k, column]])
        }))
      )
    }
    if (row < n) for (next_row in (row + 1L):n) {
      previous <- if (row > 1L) seq_len(row - 1L) else integer()
      numerator <- .ad_matrix_call(
        "-", matrix[[next_row, row]],
        .ad_matrix_sum(lapply(previous, function(k) {
          .ad_matrix_call("*", lower[[next_row, k]], upper[[k, row]])
        }))
      )
      lower[[next_row, row]] <- .ad_matrix_call("/", numerator, upper[[row, row]])
    }
  }
  intermediate <- .ad_matrix_triangular_solve(lower, rhs, lower = TRUE)
  .ad_matrix_triangular_solve(upper, intermediate, lower = FALSE)
}

.ad_matrix_exponential <- function(matrix, order, scaling) {
  if (nrow(matrix) != ncol(matrix)) .ad_stop("Matrix exponential input must be square.")
  order <- as.integer(order)
  scaling <- as.integer(scaling)
  if (length(order) != 1L || is.na(order) || order < 4L || order > 30L) {
    .ad_stop("Matrix-exponential `order` must be between 4 and 30.")
  }
  if (length(scaling) != 1L || is.na(scaling) || scaling < 0L || scaling > 16L) {
    .ad_stop("Matrix-exponential `scaling` must be between 0 and 16.")
  }
  n <- nrow(matrix)
  reduced <- .ad_matrix_scale(matrix, 1 / (2^scaling))
  result <- .ad_matrix_identity(n)
  term <- .ad_matrix_identity(n)
  for (k in seq_len(order)) {
    term <- .ad_matrix_scale(.ad_matrix_multiply(term, reduced), 1 / k)
    result <- .ad_matrix_binary(result, term, "+")
  }
  if (scaling) for (i in seq_len(scaling)) result <- .ad_matrix_multiply(result, result)
  result
}

.ad_matrix_scalar <- function(value, objects, what) {
  if (is.numeric(value) && length(value) == 1L && is.finite(value)) return(as.numeric(value))
  value <- as.character(value)
  if (length(value) != 1L || !value %in% names(objects) ||
      !identical(dim(objects[[value]]), c(1L, 1L))) {
    .ad_stop(what, " must be one finite number or the name of a scalar matrix value.")
  }
  objects[[value]][[1L]]
}

#' Declare one fixed-shape matrix-AD operation
#'
#' @param name Output name.
#' @param op Operation name; see [ad_matrix_supported()].
#' @param ... Operation-specific named fields.
#' @return A serializable operation specification for [ad_matrix_ir()].
#' @export
ad_matrix_op <- function(name, op, ...) {
  c(list(name = .ad_matrix_name(name), op = as.character(op)), list(...))
}

#' Compile a fixed-shape matrix operation graph to LibeRtAD scalar IR
#'
#' Matrix shapes and algorithms are fixed at compile time. Cholesky and SPD
#' solves require a positive-definite path; general solves use a fixed
#' no-pivot LU path. The matrix exponential is a fixed scaling-and-Taylor
#' approximation, making its derivative the exact derivative of the recorded
#' approximation rather than of an adaptively selected algorithm.
#'
#' @param inputs Named list of fixed input shapes.
#' @param operations List of [ad_matrix_op()] specifications.
#' @param outputs Operation names to expose; defaults to the final operation.
#' @return A serializable `libertad_matrix_ir` containing the matrix contract
#'   and its scalar `libertad_ir` lowering.
#' @export
ad_matrix_ir <- function(inputs, operations, outputs = NULL) {
  if (!is.list(inputs) || is.null(names(inputs)) || !length(inputs) ||
      any(!nzchar(names(inputs))) || anyDuplicated(names(inputs))) {
    .ad_stop("`inputs` must be a non-empty uniquely named list of fixed shapes.")
  }
  input_names <- vapply(names(inputs), .ad_matrix_name, character(1), what = "input name")
  input_shapes <- Map(function(shape, name) .ad_matrix_shape(shape, paste0("shape for `", name, "`")),
                      inputs, input_names)
  names(input_shapes) <- input_names
  input_layout <- Map(function(name, shape) list(
    shape = shape, scalar_names = as.vector(.ad_matrix_input_names(name, shape)),
    labels = as.vector(.ad_matrix_labels(name, shape))
  ), input_names, input_shapes)
  names(input_layout) <- input_names
  scalar_inputs <- unlist(lapply(input_layout, `[[`, "scalar_names"), use.names = FALSE)
  state <- .ad_compile_state(scalar_inputs)
  objects <- Map(function(layout) {
    .ad_matrix_symbols(base::matrix(layout$scalar_names, layout$shape[[1L]], layout$shape[[2L]]))
  }, input_layout)
  operations <- as.list(operations)
  if (!length(operations)) .ad_stop("`operations` must contain at least one operation.")
  operation_contracts <- list()
  source <- character()
  emit <- function(name, expressions) {
    internal <- .ad_matrix_internal_names(name, dim(expressions))
    symbols <- .ad_matrix_symbols(internal)
    for (i in seq_len(length(expressions))) {
      statement <- call("<-", as.name(internal[[i]]), expressions[[i]])
      .ad_compile_statement(statement, state, length(source) + 1L)
      source <<- c(source, paste(deparse(statement, width.cutoff = 500L), collapse = ""))
    }
    symbols
  }
  fetch <- function(name, field) {
    name <- as.character(name)
    if (length(name) != 1L || !name %in% names(objects)) {
      .ad_stop("Unknown matrix `", name, "` in operation field `", field, "`.")
    }
    objects[[name]]
  }
  for (index in seq_along(operations)) {
    specification <- operations[[index]]
    if (!is.list(specification)) .ad_stop("Matrix operation ", index, " must be a list.")
    name <- .ad_matrix_name(specification$name, paste0("operation ", index, " name"))
    if (name %in% names(objects)) .ad_stop("Matrix value `", name, "` is already defined.")
    op <- as.character(specification$op)
    if (length(op) != 1L || is.na(op)) .ad_stop("Matrix operation ", index, " has no valid `op`.")
    expression <- switch(op,
      constant = {
        value <- as.matrix(specification$value)
        if (!is.numeric(value) || any(!is.finite(value))) .ad_stop("Matrix constants must be finite numeric matrices.")
        output <- .ad_matrix_list(nrow(value), ncol(value))
        for (i in seq_len(length(value))) output[[i]] <- value[[i]]
        output
      },
      identity = .ad_matrix_identity(.ad_matrix_shape(c(specification$n, specification$n), "identity shape")[[1L]]),
      transpose = t(fetch(specification$x, "x")),
      add = .ad_matrix_binary(fetch(specification$x, "x"), fetch(specification$y, "y"), "+"),
      subtract = .ad_matrix_binary(fetch(specification$x, "x"), fetch(specification$y, "y"), "-"),
      hadamard = .ad_matrix_binary(fetch(specification$x, "x"), fetch(specification$y, "y"), "*"),
      scale = .ad_matrix_scale(fetch(specification$x, "x"), .ad_matrix_scalar(specification$scalar, objects, "`scalar`")),
      matmul = .ad_matrix_multiply(fetch(specification$x, "x"), fetch(specification$y, "y")),
      cholesky = .ad_matrix_cholesky(fetch(specification$x, "x")),
      triangular_solve = .ad_matrix_triangular_solve(
        fetch(specification$a, "a"), fetch(specification$b, "b"),
        lower = specification$lower %||% TRUE,
        transpose = specification$transpose %||% FALSE
      ),
      solve = {
        a <- fetch(specification$a, "a"); b <- fetch(specification$b, "b")
        method <- specification$method %||% "spd"
        if (identical(method, "spd")) {
          lower <- .ad_matrix_cholesky(a)
          intermediate <- .ad_matrix_triangular_solve(lower, b, lower = TRUE)
          .ad_matrix_triangular_solve(lower, intermediate, lower = TRUE, transpose = TRUE)
        } else if (identical(method, "no_pivot")) .ad_matrix_solve_no_pivot(a, b) else
          .ad_stop("Matrix solve `method` must be `spd` or `no_pivot`.")
      },
      logdet = {
        lower <- .ad_matrix_cholesky(fetch(specification$x, "x"))
        .ad_matrix_list(1L, 1L, .ad_matrix_call(
          "*", 2, .ad_matrix_sum(lapply(seq_len(nrow(lower)), function(i) {
            .ad_matrix_call("log", lower[[i, i]])
          }))
        ))
      },
      matrix_exp = {
        matrix <- fetch(specification$x, "x")
        if (nrow(matrix) != ncol(matrix)) .ad_stop("Matrix exponential input must be square.")
        order <- as.integer(specification$order %||% 18L)
        scaling <- as.integer(specification$scaling %||% 4L)
        if (length(order) != 1L || is.na(order) || order < 4L || order > 30L) {
          .ad_stop("Matrix-exponential `order` must be between 4 and 30.")
        }
        if (length(scaling) != 1L || is.na(scaling) || scaling < 0L || scaling > 16L) {
          .ad_stop("Matrix-exponential `scaling` must be between 0 and 16.")
        }
        prefix <- paste0("internal.", index, ".", name, ".expm.")
        reduced <- emit(paste0(prefix, "scaled"), .ad_matrix_scale(matrix, 1 / (2^scaling)))
        result <- emit(paste0(prefix, "sum.0"), .ad_matrix_identity(nrow(matrix)))
        term <- emit(paste0(prefix, "term.0"), .ad_matrix_identity(nrow(matrix)))
        for (k in seq_len(order)) {
          term <- emit(
            paste0(prefix, "term.", k),
            .ad_matrix_scale(.ad_matrix_multiply(term, reduced), 1 / k)
          )
          result <- emit(
            paste0(prefix, "sum.", k),
            .ad_matrix_binary(result, term, "+")
          )
        }
        if (scaling) for (square in seq_len(scaling)) {
          result <- emit(
            paste0(prefix, "square.", square),
            .ad_matrix_multiply(result, result)
          )
        }
        result
      },
      symmetric_rank_update = {
        x <- fetch(specification$x, "x")
        update <- .ad_matrix_scale(
          .ad_matrix_multiply(x, t(x)),
          .ad_matrix_scalar(specification$alpha %||% 1, objects, "`alpha`")
        )
        if (is.null(specification$base)) update else .ad_matrix_binary(
          .ad_matrix_scale(
            fetch(specification$base, "base"),
            .ad_matrix_scalar(specification$beta %||% 1, objects, "`beta`")
          ), update, "+"
        )
      },
      quadratic_form = {
        x <- fetch(specification$x, "x"); a <- fetch(specification$a, "a")
        if (ncol(x) != 1L || nrow(a) != ncol(a) || nrow(a) != nrow(x)) {
          .ad_stop("Quadratic form requires a column vector and a conformable square matrix.")
        }
        .ad_matrix_multiply(t(x), .ad_matrix_multiply(a, x))
      },
      covariance = {
        lower <- fetch(specification$x, "x")
        if (nrow(lower) != ncol(lower)) .ad_stop("Covariance construction requires a square lower-triangular input.")
        for (row in seq_len(nrow(lower))) for (column in seq_len(ncol(lower))) {
          if (column > row) lower[[row, column]] <- 0
          if (row == column && isTRUE(specification$log_diagonal %||% TRUE)) {
            lower[[row, column]] <- .ad_matrix_call("exp", lower[[row, column]])
          }
        }
        .ad_matrix_multiply(lower, t(lower))
      },
      .ad_stop("Unsupported matrix operation: ", op)
    )
    objects[[name]] <- emit(name, expression)
    operation_contracts[[name]] <- list(
      op = op, shape = dim(expression),
      path = if (op %in% c("cholesky", "logdet") ||
                 (op == "solve" && identical(specification$method %||% "spd", "spd"))) {
        "positive-definite"
      } else if (op == "solve") "fixed-no-pivot" else if (op == "matrix_exp") {
        paste0("fixed-order-", specification$order %||% 18L,
               "-scaling-", specification$scaling %||% 4L)
      } else "branch-free"
    )
  }
  outputs <- outputs %||% names(operation_contracts)[[length(operation_contracts)]]
  outputs <- unique(as.character(outputs))
  if (!length(outputs) || any(!outputs %in% names(objects))) {
    .ad_stop("Unknown requested matrix output(s): ", paste(setdiff(outputs, names(objects)), collapse = ", "))
  }
  output_layout <- lapply(outputs, function(name) list(
    shape = dim(objects[[name]]), labels = as.vector(.ad_matrix_labels(name, dim(objects[[name]])))
  ))
  names(output_layout) <- outputs
  scalar_output_names <- unlist(lapply(output_layout, `[[`, "labels"), use.names = FALSE)
  scalar_output_nodes <- unlist(lapply(outputs, function(name) {
    vapply(as.vector(objects[[name]]), function(symbol) {
      get(as.character(symbol), envir = state$symbols, inherits = FALSE)
    }, integer(1))
  }), use.names = FALSE)
  scalar_ir <- structure(list(
    version = 1L, code = paste(source, collapse = "\n"),
    input_names = state$inputs, nodes = state$nodes,
    output_names = scalar_output_names, output_nodes = scalar_output_nodes
  ), class = "libertad_ir")
  scalar_to_public <- unlist(unname(lapply(input_layout, function(layout) {
    stats::setNames(layout$labels, layout$scalar_names)
  })))
  structure(list(
    version = 1L, inputs = input_layout, operations = operations,
    contracts = operation_contracts, output_names = outputs,
    outputs = output_layout, scalar_to_public = scalar_to_public,
    scalar_ir = scalar_ir
  ), class = "libertad_matrix_ir")
}

.ad_matrix_flatten <- function(ir, at) {
  if (is.numeric(at) && !is.null(names(at)) &&
      all(unlist(lapply(ir$inputs, `[[`, "scalar_names"), use.names = FALSE) %in% names(at))) {
    required <- unlist(lapply(ir$inputs, `[[`, "scalar_names"), use.names = FALSE)
    return(.ad_named_values(at, required, "matrix input values"))
  }
  if (!is.list(at) || is.null(names(at))) {
    .ad_stop("Matrix input values must be a named list of matrices or a named flattened vector.")
  }
  missing <- setdiff(names(ir$inputs), names(at))
  if (length(missing)) .ad_stop("Missing matrix input(s): ", paste(missing, collapse = ", "))
  output <- numeric()
  for (name in names(ir$inputs)) {
    layout <- ir$inputs[[name]]
    value <- at[[name]]
    if (prod(layout$shape) == 1L && is.numeric(value) && length(value) == 1L) {
      value <- base::matrix(value, 1L, 1L)
    } else value <- as.matrix(value)
    if (!is.numeric(value) || !identical(dim(value), layout$shape) || any(!is.finite(value))) {
      .ad_stop("Input `", name, "` must be a finite numeric matrix with shape ",
               paste(layout$shape, collapse = " x "), ".")
    }
    values <- as.numeric(value); names(values) <- layout$scalar_names
    output <- c(output, values)
  }
  output
}

.ad_matrix_expand_names <- function(ir, names, what) {
  names <- unique(as.character(names))
  scalar <- unlist(lapply(ir$inputs, `[[`, "scalar_names"), use.names = FALSE)
  labels <- unlist(lapply(ir$inputs, `[[`, "labels"), use.names = FALSE)
  output <- character()
  for (name in names) {
    if (name %in% names(ir$inputs)) output <- c(output, ir$inputs[[name]]$scalar_names) else if (name %in% scalar) {
      output <- c(output, name)
    } else if (name %in% labels) output <- c(output, scalar[[match(name, labels)]]) else
      .ad_stop("Unknown ", what, ": ", name)
  }
  unique(output)
}

.ad_matrix_reshape <- function(ir, values, outputs) {
  result <- list(); cursor <- 0L
  for (name in outputs) {
    layout <- ir$outputs[[name]]; count <- prod(layout$shape)
    result[[name]] <- base::matrix(
      as.numeric(values[cursor + seq_len(count)]), layout$shape[[1L]], layout$shape[[2L]],
      dimnames = NULL
    )
    cursor <- cursor + count
  }
  result
}

#' Pointer-backed fixed-shape matrix automatic-differentiation model
#' @export
ADMatrixModel <- R6::R6Class(
  "ADMatrixModel",
  public = list(
    #' @field ir Serializable fixed-shape matrix IR.
    ir = NULL,
    #' @field scalar Underlying pointer-backed scalar [ADModel].
    scalar = NULL,
    #' @field outputs Matrix outputs active on the current tape.
    outputs = NULL,
    #' @description Construct a matrix model from a validated IR.
    #' @param ir A `libertad_matrix_ir` from [ad_matrix_ir()].
    initialize = function(ir) {
      if (!inherits(ir, "libertad_matrix_ir") || !identical(ir$version, 1L)) {
        .ad_stop("`ir` must be created by ad_matrix_ir().")
      }
      self$ir <- ir; self$scalar <- ADModel$new(ir$scalar_ir); self$outputs <- ir$output_names
    },
    #' @description Record a persistent tape.
    #' @param at Named list of fixed-shape input matrices.
    #' @param wrt Matrix inputs or individual element labels to differentiate.
    #' @param outputs Matrix outputs to place on the tape.
    #' @param optimize Run CppAD tape optimization.
    #' @return The model, invisibly.
    record = function(at, wrt = names(self$ir$inputs), outputs = self$ir$output_names,
                      optimize = TRUE) {
      outputs <- unique(as.character(outputs))
      if (any(!outputs %in% self$ir$output_names)) .ad_stop("Unknown matrix tape output.")
      scalar_outputs <- unlist(lapply(self$ir$outputs[outputs], `[[`, "labels"), use.names = FALSE)
      self$scalar$record(
        .ad_matrix_flatten(self$ir, at),
        wrt = .ad_matrix_expand_names(self$ir, wrt, "matrix differentiation input"),
        outputs = scalar_outputs, optimize = optimize
      )
      self$outputs <- outputs
      invisible(self)
    },
    #' @description Evaluate matrix outputs.
    #' @param at Named list of fixed-shape input matrices.
    #' @param taped Use the persistent tape when available.
    #' @return A named list of numeric matrices.
    value = function(at, taped = !is.null(self$scalar$tape_ptr)) {
      flat <- .ad_matrix_flatten(self$ir, at)
      if (isTRUE(taped)) {
        if (length(self$scalar$dynamic)) self$scalar$set_dynamic(flat[self$scalar$dynamic])
        values <- self$scalar$value(flat[self$scalar$wrt], taped = TRUE)
      } else values <- self$scalar$value(flat, taped = FALSE)
      .ad_matrix_reshape(self$ir, values, self$outputs)
    },
    #' @description Evaluate the output-element by input-element Jacobian.
    #' @param at Named list of fixed-shape input matrices.
    #' @return A numeric matrix with public element labels.
    jacobian = function(at) {
      flat <- .ad_matrix_flatten(self$ir, at)
      if (length(self$scalar$dynamic)) self$scalar$set_dynamic(flat[self$scalar$dynamic])
      result <- self$scalar$jacobian(flat[self$scalar$wrt])
      colnames(result) <- unname(self$ir$scalar_to_public[colnames(result)])
      result
    },
    #' @description Evaluate the gradient of one scalar matrix output.
    #' @param at Named list of fixed-shape input matrices.
    #' @return A named numeric gradient.
    gradient = function(at) {
      if (sum(vapply(self$ir$outputs[self$outputs], function(x) prod(x$shape), numeric(1))) != 1L) {
        .ad_stop("gradient() requires exactly one scalar matrix output.")
      }
      drop(self$jacobian(at))
    },
    #' @description Evaluate the Hessian of one scalar matrix output.
    #' @param at Named list of fixed-shape input matrices.
    #' @return A numeric Hessian matrix with public element labels.
    hessian = function(at) {
      flat <- .ad_matrix_flatten(self$ir, at)
      if (length(self$scalar$dynamic)) self$scalar$set_dynamic(flat[self$scalar$dynamic])
      result <- self$scalar$hessian(flat[self$scalar$wrt])
      labels <- unname(self$ir$scalar_to_public[self$scalar$wrt])
      dimnames(result) <- list(labels, labels)
      result
    },
    #' @description Evaluate one scalar matrix output and its gradient.
    #' @param at Named list of fixed-shape input matrices.
    #' @return A list containing `value` and `gradient`.
    value_gradient = function(at) list(value = self$value(at), gradient = self$gradient(at)),
    #' @description Return underlying tape and derivative-strategy telemetry.
    #' @return A named list.
    tape_info = function() self$scalar$tape_info(),
    #' @description Create a portable matrix tape cache.
    #' @return A serializable `libertad_matrix_tape_cache`.
    tape_cache = function() structure(list(
      version = 1L, matrix_ir = self$ir, outputs = self$outputs,
      scalar_cache = self$scalar$tape_cache()
    ), class = "libertad_matrix_tape_cache"),
    #' @description Save the portable matrix tape cache.
    #' @param path Destination `.rds` path.
    #' @return The normalized path, invisibly.
    save_tape = function(path) {
      path <- normalizePath(path, mustWork = FALSE)
      saveRDS(self$tape_cache(), path, version = 3L)
      invisible(path)
    }
  )
)

#' Compile a fixed-shape matrix automatic-differentiation model
#' @param ir A `libertad_matrix_ir` from [ad_matrix_ir()].
#' @param at Optional named list recording point.
#' @param wrt Matrix inputs or individual public/scalar element names.
#' @param outputs Matrix outputs to record.
#' @param optimize Optimize the CppAD tape.
#' @return An [ADMatrixModel] object.
#' @export
ad_matrix_compile <- function(ir, at = NULL, wrt = names(ir$inputs),
                              outputs = ir$output_names, optimize = TRUE) {
  model <- ADMatrixModel$new(ir)
  if (!is.null(at)) model$record(at, wrt = wrt, outputs = outputs, optimize = optimize)
  model
}

#' Load a saved matrix tape cache
#' @param path File created by `ADMatrixModel$save_tape()`.
#' @return A recorded [ADMatrixModel].
#' @export
ad_matrix_load_tape <- function(path) {
  cache <- readRDS(path)
  if (!inherits(cache, "libertad_matrix_tape_cache") || !identical(cache$version, 1L)) {
    .ad_stop("`path` is not a supported LibeRtAD matrix tape cache.")
  }
  model <- ADMatrixModel$new(cache$matrix_ir)
  model$scalar <- .ad_load_tape_cache(cache$scalar_cache)
  model$outputs <- cache$outputs
  model
}

#' Report the fixed-shape matrix AD surface
#' @return A list of supported operations and guarded path contracts.
#' @export
ad_matrix_supported <- function() list(
  operations = c(
    "constant", "identity", "transpose", "add", "subtract", "hadamard",
    "scale", "matmul", "cholesky", "triangular_solve", "solve", "logdet",
    "matrix_exp", "symmetric_rank_update", "quadratic_form", "covariance"
  ),
  solve_paths = c("spd", "no_pivot"),
  contracts = c(
    "all shapes are fixed and serialized",
    "cholesky, logdet, and SPD solve require positive-definite inputs",
    "general solve records one no-pivot path",
    "matrix_exp differentiates a fixed scaling-and-Taylor approximation",
    "arbitrary SVD/eigendecomposition and dynamic shapes are deliberately unsupported"
  )
)

#' @export
print.libertad_matrix_ir <- function(x, ...) {
  cat("LibeRtAD fixed-shape matrix IR\n")
  cat("  inputs:", paste(vapply(names(x$inputs), function(name) {
    paste0(name, " ", paste(x$inputs[[name]]$shape, collapse = "x"))
  }, character(1)), collapse = ", "), "\n")
  cat("  operations:", length(x$operations), " outputs:", paste(x$output_names, collapse = ", "), "\n")
  invisible(x)
}
