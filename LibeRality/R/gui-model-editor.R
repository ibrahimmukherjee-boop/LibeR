.lity_gui_model_rows <- function(value) {
  if (is.null(value)) return(list())
  if (is.data.frame(value)) {
    return(lapply(seq_len(nrow(value)), function(index) {
      as.list(value[index, , drop = FALSE])
    }))
  }
  if (!is.list(value)) {
    .lity_stop("Parameter edits must be supplied as rows.")
  }
  value
}

.lity_gui_model_number <- function(row, field, label, finite = TRUE) {
  value <- suppressWarnings(as.numeric(row[[field]]))
  if (length(value) != 1L || is.na(value) || (finite && !is.finite(value))) {
    .lity_stop(label, " requires one ", if (finite) "finite " else "",
               "numeric value.")
  }
  value
}

.lity_gui_model_table <- function(value, type) {
  rows <- .lity_gui_model_rows(value)
  if (!length(rows)) {
    if (identical(type, "theta")) {
      .lity_stop("A model must retain at least one THETA.")
    }
    column <- toupper(type)
    return(data.frame(
      stats::setNames(list(integer()), column),
      Value = numeric(), FIX = logical(), stringsAsFactors = FALSE
    ))
  }
  values <- vapply(rows, function(row) {
    .lity_gui_model_number(row, "value", paste(toupper(type), "initial"))
  }, numeric(1))
  fixed <- vapply(rows, function(row) isTRUE(row$fixed), logical(1))
  if (identical(type, "theta")) {
    lower <- vapply(rows, function(row) {
      .lity_gui_model_number(
        row, "lower", "THETA lower bound", finite = FALSE
      )
    }, numeric(1))
    upper <- vapply(rows, function(row) {
      .lity_gui_model_number(
        row, "upper", "THETA upper bound", finite = FALSE
      )
    }, numeric(1))
    return(data.frame(
      THETA = seq_along(rows), Value = values, LOWER = lower, UPPER = upper,
      FIX = fixed, stringsAsFactors = FALSE
    ))
  }
  if (identical(type, "omega")) {
    row_index <- vapply(rows, function(row) {
      as.integer(.lity_gui_model_number(row, "row", "OMEGA row"))
    }, integer(1))
    column_index <- vapply(rows, function(row) {
      as.integer(.lity_gui_model_number(row, "col", "OMEGA column"))
    }, integer(1))
    return(data.frame(
      OMEGA = seq_along(rows), ROW = row_index, COL = column_index,
      Value = values, FIX = fixed, stringsAsFactors = FALSE
    ))
  }
  data.frame(
    SIGMA = seq_along(rows), Value = values, FIX = fixed,
    stringsAsFactors = FALSE
  )
}

.lity_gui_update_model <- function(design, event) {
  current <- design$model
  theta <- .lity_gui_model_table(event$theta, "theta")
  omega <- .lity_gui_model_table(event$omega, "omega")
  sigma <- .lity_gui_model_table(event$sigma, "sigma")
  updates <- list(
    PK_SOURCE = paste(as.character(event$pk %||% ""), collapse = "\n"),
    PRED_SOURCE = paste(as.character(event$pred %||% ""), collapse = "\n"),
    DES = paste(as.character(event$des %||% ""), collapse = "\n"),
    THETAS = theta, OMEGAS = omega, SIGMAS = sigma
  )
  if (!isFALSE(event$errorEditable)) {
    updates$ERROR <- paste(
      as.character(event$error %||% ""), collapse = "\n"
    )
  }
  updated <- do.call(
    LibeRation::nm_model_update,
    c(
      list(model = current),
      updates,
      list(name = trimws(as.character(
        event$name %||% .lity_model_name(current)
      )[[1L]]))
    )
  )
  old_hash <- .lity_hash(current)
  provenance <- design$metadata$model_provenance %||%
    attr(current, "lity_provenance", exact = TRUE) %||% list()
  provenance$edited_in <- "LibeRality"
  provenance$edited_at <- .lity_now()
  provenance$parameter_source <- "design-edited values"
  attr(updated, "lity_provenance") <- provenance
  for (index in seq_along(design$scenarios)) {
    design$scenarios[[index]]$theta <- NULL
    design$scenarios[[index]]$omega <- NULL
    design$scenarios[[index]]$sigma <- NULL
    design$scenarios[[index]]$model <- NULL
  }
  design$model <- updated
  design$alternative_models <- list()
  design$prior_fim <- NULL
  design$id <- .lity_id("design")
  history <- design$metadata$model_history %||% list()
  history[[length(history) + 1L]] <- list(
    changed_at = .lity_now(), previous_hash = old_hash,
    model_hash = .lity_hash(updated), provenance = provenance,
    operation = "model_edit"
  )
  design$metadata$model_provenance <- provenance
  design$metadata$model_history <- history
  validation <- lity_validate(design)
  if (!validation$valid) {
    .lity_stop(
      "The edited model is incompatible with the design: ",
      paste(validation$errors, collapse = "; ")
    )
  }
  design
}
