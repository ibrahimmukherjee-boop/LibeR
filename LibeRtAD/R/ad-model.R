.ad_named_values <- function(x, required, what = "values") {
  nms <- names(x)
  x <- as.numeric(x)
  if (!is.null(nms)) names(x) <- nms
  if (is.null(nms)) {
    if (length(x) != length(required)) {
      .ad_stop("Unnamed ", what, " must have length ", length(required), ".")
    }
    names(x) <- required
    return(x)
  }
  missing <- setdiff(required, nms)
  if (length(missing)) {
    .ad_stop("Missing ", what, ": ", paste(missing, collapse = ", "))
  }
  x[required]
}

#' Pointer-backed compiled automatic-differentiation model
#'
#' `ADModel` is deliberately light: the serializable IR is retained for worker
#' reconstruction, while C++ owns the executable program and persistent tape.
#'
#' @export
ADModel <- R6::R6Class(
  "ADModel",
  public = list(
    #' @field ir Serializable intermediate representation created by [ad_ir()].
    ir = NULL,
    #' @field wrt Character vector naming the active differentiation inputs.
    wrt = NULL,
    #' @field outputs Character vector naming the active model outputs.
    outputs = NULL,
    #' @field dynamic Character vector naming non-differentiated inputs retained
    #'   as CppAD dynamic parameters.
    dynamic = NULL,
    #' @field dynamic_values Current named values of the tape's dynamic parameters.
    dynamic_values = NULL,
    #' @field recording_values Complete named input values used for the current
    #'   tape's semantic cache probe.
    recording_values = NULL,

    #' @description
    #' Create a pointer-backed model from a validated intermediate representation.
    #' @param ir A `libertad_ir` object created by [ad_ir()].
    #' @return A new `ADModel` object.
    initialize = function(ir) {
      if (!inherits(ir, "libertad_ir")) {
        .ad_stop("`ir` must be created by ad_ir().")
      }
      self$ir <- ir
      self$outputs <- ir$output_names
      private$program_ptr_ <- .libertad_program_create(ir)
    },

    #' @description
    #' Record a persistent CppAD tape at a named parameter point.
    #' @param at Named numeric values for every model input.
    #' @param wrt Input names with respect to which derivatives are required.
    #' @param outputs Output assignment names to place on the tape.
    #' @param optimize Whether to run CppAD tape optimization.
    #' @return The model, invisibly.
    record = function(at, wrt = names(at), outputs = self$outputs,
                      optimize = TRUE) {
      at <- .ad_named_values(at, self$ir$input_names, "recording values")
      if (is.null(wrt) || !length(wrt)) wrt <- self$ir$input_names
      wrt <- unique(as.character(wrt))
      unknown <- setdiff(wrt, self$ir$input_names)
      if (length(unknown)) .ad_stop("Unknown differentiation input(s): ", paste(unknown, collapse = ", "))
      outputs <- unique(as.character(outputs))
      unknown_out <- setdiff(outputs, self$ir$output_names)
      if (length(unknown_out)) .ad_stop("Unknown tape output(s): ", paste(unknown_out, collapse = ", "))
      private$tape_ptr_ <- .libertad_tape_create(
        private$program_ptr_, at, wrt, outputs, isTRUE(optimize)
      )
      self$wrt <- wrt
      self$dynamic <- setdiff(self$ir$input_names, wrt)
      self$dynamic_values <- at[self$dynamic]
      self$recording_values <- at
      self$outputs <- outputs
      invisible(self)
    },

    #' @description
    #' Update non-differentiated inputs without recording a new tape.
    #' @param values Named values for every dynamic parameter. An unnamed vector
    #'   may be supplied in the order shown by `$dynamic`.
    #' @return The model, invisibly.
    set_dynamic = function(values) {
      private$require_tape()
      values <- .ad_named_values(values, self$dynamic, "dynamic parameter values")
      self$dynamic_values <- .libertad_tape_new_dynamic(private$tape_ptr_, values)
      invisible(self)
    },

    #' @description
    #' Evaluate model outputs with the compiled program or recorded tape.
    #' @param at Named input values. Taped evaluation requires the active `wrt`
    #'   inputs; untaped evaluation requires every IR input.
    #' @param taped Use the persistent tape when available.
    #' @return A named numeric vector of model outputs.
    value = function(at, taped = self$has_tape()) {
      if (isTRUE(taped)) {
        private$require_tape()
        x <- private$tape_values(at)
        return(.libertad_tape_value(private$tape_ptr_, x))
      }
      at <- .ad_named_values(at, self$ir$input_names, "program values")
      .libertad_program_value(private$program_ptr_, at, self$outputs)
    },

    #' @description
    #' Evaluate the exact output-by-input Jacobian of the recorded tape.
    #' @param at Named values for the active differentiation inputs.
    #' @return A numeric matrix with one row per output and one column per input.
    jacobian = function(at) {
      private$require_tape()
      x <- private$tape_values(at)
      .libertad_tape_jacobian(private$tape_ptr_, x)
    },

    #' @description
    #' Evaluate the exact gradient of a single-output tape.
    #' @param at Named values for the active differentiation inputs.
    #' @return A numeric gradient vector.
    gradient = function(at) {
      private$require_tape()
      if (length(self$outputs) != 1L) {
        .ad_stop("gradient() requires a tape with exactly one output; use jacobian().")
      }
      drop(self$jacobian(at))
    },

    #' @description
    #' Evaluate the exact Hessian of a single-output tape.
    #' @param at Named values for the active differentiation inputs.
    #' @return A square numeric Hessian matrix.
    hessian = function(at) {
      private$require_tape()
      if (length(self$outputs) != 1L) {
        .ad_stop("hessian() requires a tape with exactly one output.")
      }
      x <- private$tape_values(at)
      .libertad_tape_hessian(private$tape_ptr_, x)
    },

    #' @description
    #' Evaluate a single-output value and its exact gradient together.
    #' @param at Named values for the active differentiation inputs.
    #' @return A list containing `value` and `gradient`.
    value_gradient = function(at) {
      private$require_tape()
      if (length(self$outputs) != 1L) {
        .ad_stop("value_gradient() requires a tape with exactly one output.")
      }
      x <- private$tape_values(at)
      .libertad_tape_value_gradient(private$tape_ptr_, x)
    },

    #' @description
    #' Return tape dimensions, operation counts, dynamic-parameter state, and
    #' comparison-change telemetry.
    #' @return A named list describing the current persistent tape.
    tape_info = function() {
      private$require_tape()
      .libertad_tape_info(private$tape_ptr_)
    },

    #' @description
    #' Create a portable cache of the optimized CppAD graph and its metadata.
    #' The serializable IR remains included as the auditable source of truth.
    #' @return A `libertad_tape_cache` list suitable for `saveRDS()`.
    tape_cache = function() {
      private$require_tape()
      at <- self$recording_values
      if (is.null(at) || !identical(names(at), self$ir$input_names)) {
        .ad_stop("The tape has no complete recording point; record it again before caching.")
      }
      at[self$dynamic] <- self$dynamic_values
      original_dynamic <- self$dynamic_values
      if (length(original_dynamic)) {
        on.exit(self$set_dynamic(original_dynamic), add = TRUE)
      }
      factors <- 0.5 + seq_along(at) / max(1L, length(at))
      candidates <- lapply(c(0, 1e-4, 1e-2, -1e-4), function(step) {
        candidate <- at + step * pmax(1, abs(at)) * factors
        names(candidate) <- names(at)
        candidate
      })
      semantic_probes <- Filter(Negate(is.null), lapply(candidates, function(candidate) {
        tryCatch({
          direct <- self$value(candidate, taped = FALSE)
          taped <- self$value(candidate, taped = TRUE)
          if (any(!is.finite(c(direct, taped))) || !isTRUE(all.equal(
            unname(direct), unname(taped),
            tolerance = 1e-12, check.attributes = FALSE
          ))) return(NULL)
          jacobian <- self$jacobian(candidate[self$wrt])
          if (any(!is.finite(jacobian))) jacobian <- NULL
          list(at = candidate, value = direct, jacobian = jacobian)
        }, error = function(error) NULL)
      }))
      if (!length(semantic_probes)) {
        .ad_stop("The recorded graph is not semantically consistent with its source IR.")
      }
      structure(list(
        version = 2L,
        cppad_version = ad_engine_info()$cppad_version,
        cppad_source_commit = ad_engine_info()$cppad_source_commit,
        ir = self$ir,
        graph_json = .libertad_tape_graph_json(private$tape_ptr_),
        domain = self$wrt,
        dynamic = self$dynamic,
        dynamic_values = original_dynamic,
        range = self$outputs,
        semantic_probes = semantic_probes
      ), class = "libertad_tape_cache")
    },

    #' @description
    #' Save the optimized CppAD graph for fast worker reconstruction.
    #' @param path Destination `.rds` path.
    #' @return The normalized cache path, invisibly.
    save_tape = function(path) {
      path <- normalizePath(path, mustWork = FALSE)
      dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
      saveRDS(self$tape_cache(), path, version = 3L)
      invisible(path)
    },

    #' @description
    #' Report whether this model owns a recorded CppAD tape.
    #' @return One logical value. Raw external pointers are intentionally not
    #'   exposed because replacing or clearing them can invalidate C++ state.
    has_tape = function() !is.null(private$tape_ptr_),

    #' @description
    #' Reconstruct a tape from an already validated portable cache. This is an
    #' internal lifecycle operation; it never accepts or exposes raw pointers.
    #' @param graph_json Serialized CppAD graph JSON.
    #' @param domain Active differentiation-input names.
    #' @param dynamic Dynamic-parameter names.
    #' @param dynamic_values Current dynamic-parameter values.
    #' @param range Output names.
    #' @param recording_values Complete cache recording point.
    #' @return The model, invisibly.
    .restore_tape = function(graph_json, domain, dynamic, dynamic_values,
                             range, recording_values) {
      inputs <- self$ir$input_names
      domain <- as.character(domain)
      dynamic <- as.character(dynamic)
      range <- as.character(range)
      if (anyDuplicated(c(domain, dynamic)) || length(intersect(domain, dynamic)) ||
          !setequal(c(domain, dynamic), inputs) ||
          !identical(dynamic, setdiff(inputs, domain))) {
        .ad_stop("The restored tape domain/dynamic contract is invalid.")
      }
      if (!length(domain) || !length(range) || anyDuplicated(range) ||
          any(!range %in% self$ir$output_names)) {
        .ad_stop("The restored tape range contract is invalid.")
      }
      dynamic_values <- .ad_named_values(
        dynamic_values, dynamic, "restored dynamic parameter values"
      )
      recording_values <- .ad_named_values(
        recording_values, inputs, "restored recording values"
      )
      private$tape_ptr_ <- .libertad_tape_from_graph_json(
        private$program_ptr_, graph_json, domain, dynamic,
        dynamic_values, range
      )
      self$wrt <- domain
      self$dynamic <- dynamic
      self$dynamic_values <- dynamic_values
      self$outputs <- range
      self$recording_values <- recording_values
      invisible(self)
    },

    #' @description
    #' Print a concise summary of the compiled program and tape state.
    #' @param ... Unused.
    #' @return The model, invisibly.
    print = function(...) {
      cat("LibeRtAD compiled model\n")
      cat("  inputs:", paste(self$ir$input_names, collapse = ", "), "\n")
      cat("  outputs:", paste(self$outputs, collapse = ", "), "\n")
      cat("  tape:", if (!self$has_tape()) "not recorded" else paste("recorded wrt", paste(self$wrt, collapse = ", ")), "\n")
      if (self$has_tape() && length(self$dynamic)) {
        cat("  dynamic:", paste(self$dynamic, collapse = ", "), "\n")
      }
      invisible(self)
    }
  ),
  private = list(
    program_ptr_ = NULL,
    tape_ptr_ = NULL,
    require_tape = function() {
      if (is.null(private$tape_ptr_)) {
        .ad_stop("No tape has been recorded. Call $record(at, wrt, outputs) first.")
      }
    },
    tape_values = function(at) {
      nms <- names(at)
      if (!is.null(nms) && length(self$dynamic)) {
        supplied <- intersect(self$dynamic, nms)
        if (length(supplied)) {
          next_values <- self$dynamic_values
          next_values[supplied] <- as.numeric(at[supplied])
          self$set_dynamic(next_values)
        }
      }
      .ad_named_values(at, self$wrt, "tape values")
    }
  )
)

#' Load a cached LibeRtAD tape
#'
#' Reconstructs an [ADModel] directly from a saved CppAD graph while retaining
#' and validating the model IR and exact bundled-CppAD provenance.
#' @param path An `.rds` file created by [ADModel]$save_tape().
#' @return A ready-to-evaluate `ADModel`.
#' @export
ad_load_tape <- function(path) {
  .ad_load_tape_cache(readRDS(path))
}

.ad_load_tape_cache <- function(cache) {
  if (!inherits(cache, "libertad_tape_cache") ||
      !identical(cache$version, 2L)) {
    .ad_stop("`path` is not a supported LibeRtAD tape cache.")
  }
  engine <- ad_engine_info()
  if (!identical(cache$cppad_version, engine$cppad_version) ||
      !identical(cache$cppad_source_commit, engine$cppad_source_commit)) {
    .ad_stop("The tape cache was created by a different bundled CppAD build.")
  }
  if (!inherits(cache$ir, "libertad_ir") ||
      !identical(cache$ir$version, 1L)) {
    .ad_stop("The tape cache does not contain a supported source IR.")
  }
  domain <- as.character(cache$domain)
  dynamic <- as.character(cache$dynamic)
  range <- as.character(cache$range)
  inputs <- as.character(cache$ir$input_names)
  if (anyDuplicated(c(domain, dynamic)) || length(intersect(domain, dynamic)) ||
      !setequal(c(domain, dynamic), inputs) ||
      !identical(dynamic, setdiff(inputs, domain))) {
    .ad_stop("The tape cache domain/dynamic contract is inconsistent with its source IR.")
  }
  if (!length(domain) || !length(range) || anyDuplicated(range) ||
      any(!range %in% cache$ir$output_names)) {
    .ad_stop("The tape cache range contract is inconsistent with its source IR.")
  }
  probes <- cache$semantic_probes
  if (!is.list(probes) || !length(probes) ||
      any(!vapply(probes, function(probe) {
        is.list(probe) && !is.null(probe$at) && !is.null(probe$value)
      }, logical(1)))) {
    .ad_stop("The tape cache has no semantic IR-to-graph probes.")
  }
  probe_at <- .ad_named_values(probes[[1L]]$at, inputs, "cache semantic-probe inputs")
  if (any(!is.finite(probe_at)) ||
      !isTRUE(all.equal(
        unname(probe_at[dynamic]), unname(as.numeric(cache$dynamic_values)),
        tolerance = 0, check.attributes = FALSE
      ))) {
    .ad_stop("The tape cache semantic probe does not match its dynamic parameters.")
  }
  model <- ADModel$new(cache$ir)
  model$.restore_tape(
    cache$graph_json, domain, dynamic, cache$dynamic_values, range, probe_at
  )
  consistent <- all(vapply(probes, function(probe) {
    tryCatch({
      current <- .ad_named_values(probe$at, inputs, "cache semantic-probe inputs")
      direct <- model$value(current, taped = FALSE)
      taped <- model$value(current, taped = TRUE)
      valid <- all(is.finite(c(direct, taped))) && isTRUE(all.equal(
        unname(direct), unname(taped), tolerance = 1e-12,
        check.attributes = FALSE
      )) && isTRUE(all.equal(
        unname(direct), unname(probe$value), tolerance = 1e-12,
        check.attributes = FALSE
      ))
      if (valid && !is.null(probe$jacobian)) {
        jacobian <- model$jacobian(current[domain])
        valid <- all(is.finite(jacobian)) && isTRUE(all.equal(
          unname(jacobian), unname(probe$jacobian), tolerance = 1e-11,
          check.attributes = FALSE
        ))
      }
      valid
    }, error = function(error) FALSE)
  }, logical(1)))
  if (!consistent) {
    .ad_stop("The cached CppAD graph is not semantically consistent with its source IR.")
  }
  if (length(dynamic)) model$set_dynamic(cache$dynamic_values)
  model
}

#' Compile an R-like mathematical model
#'
#' @inheritParams ad_ir
#' @param at Optional named recording point. When supplied, a persistent tape
#'   is recorded immediately.
#' @param wrt Inputs with respect to which derivatives are required.
#' @param optimize Whether CppAD should optimize the recorded tape.
#' @return An `ADModel` R6 object.
#' @examples
#' model <- ad_compile(
#'   "CL = THETA(1) * exp(ETA(1))\nPENALTY = log(CL)^2",
#'   at = c(THETA_1 = 2, ETA_1 = 0),
#'   wrt = c("THETA_1", "ETA_1"),
#'   outputs = "PENALTY"
#' )
#' model$value_gradient(c(THETA_1 = 2, ETA_1 = 0))
#' model$hessian(c(THETA_1 = 2, ETA_1 = 0))
#' @export
ad_compile <- function(code, inputs = character(), outputs = NULL, at = NULL,
                       wrt = names(at), optimize = TRUE) {
  model <- ADModel$new(ad_ir(code, inputs = inputs, outputs = outputs))
  if (!is.null(at)) {
    model$record(at, wrt = wrt, outputs = outputs %||% model$outputs,
                 optimize = optimize)
  }
  model
}

`%||%` <- function(x, y) if (is.null(x)) y else x

#' Report supported compiler constructs
#' @return A named list of accepted indexed inputs, operators, mathematical
#'   functions, conditionals, and deliberate language limitations.
#' @examples
#' ad_supported()
#' @export
ad_supported <- function() {
  list(
    indexed_inputs = c("THETA", "ETA", "SIGMA", "ERR"),
    operators = c("+", "-", "*", "/", "^"),
    math = c("exp", "log", "sqrt", "sin", "cos", "tan", "tanh", "abs", "expm1", "log1p"),
    conditionals = "ifelse() with <, <=, >, >=, ==, or !=",
    matrix_frontend = "ad_matrix_ir() lowers fixed-shape guarded matrix operations to the scalar IR",
    limitations = c(
      "the base expression language is scalar; fixed-shape matrices use ad_matrix_ir()",
      "runtime if/for/while constructs are rejected",
      "unknown function calls are rejected rather than evaluated in R"
    )
  )
}

#' C++ engine and dependency information
#' @return A named list describing the compiled backend and dependency versions.
#' @examples
#' ad_engine_info()
#' @export
ad_engine_info <- function() {
  .libertad_engine_info()
}

#' Inspect CppAD allocator state
#'
#' Reports CppAD allocator bytes owned by the current execution thread. This
#' is primarily a tape-lifetime diagnostic: `inuse_bytes` should return close
#' to its baseline after pointer-backed models are removed and garbage
#' collection runs. Cached `available_bytes` are reusable allocator blocks,
#' not leaked live tapes, and may be released explicitly.
#' @param release_available Release reusable blocks currently cached by CppAD
#'   for this thread before returning the report.
#' @return A named list with thread, parallel-state, live-allocation, cached,
#'   and released-byte telemetry.
#' @examples
#' ad_allocator_info()
#' @export
ad_allocator_info <- function(release_available = FALSE) {
  if (length(release_available) != 1L || is.na(release_available)) {
    .ad_stop("`release_available` must be TRUE or FALSE.")
  }
  .libertad_allocator_info(isTRUE(release_available))
}

#' Benchmark nested-AD-safe CppAD checkpoint prototypes
#'
#' Compares repeated direct recordings with `chkpoint_two` prototypes for an
#' ADVAN1 interval and a 2-by-2 matrix state update. The checkpoint objects are
#' explicitly configured for the nested AD route used by LibeRation curvature
#' calculations. Results are diagnostic; production selection remains guarded
#' by measured performance and tape size.
#' @param repetitions Number of repeated kernel uses on each outer tape.
#' @param evaluations Number of zero-order evaluations used for timing.
#' @return A named list of operation counts, accuracy checks, and timings.
#' @export
ad_checkpoint_probe <- function(repetitions = 64L, evaluations = 1000L) {
  .libertad_checkpoint_probe(as.integer(repetitions), as.integer(evaluations))
}
