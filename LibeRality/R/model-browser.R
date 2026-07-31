.lity_default_liberation_workspace <- function() {
  configured <- Sys.getenv("LIBERATION_WORKSPACE", "")
  if (!nzchar(configured)) configured <- getOption("LibeRation.workspace", "")
  if (nzchar(configured)) return(path.expand(configured))
  home <- path.expand(Sys.getenv("USERPROFILE", unset = "~"))
  base <- if (.Platform$OS.type == "windows") file.path(home, "Documents") else home
  file.path(base, "LibeR", "workspace")
}

.lity_model_route <- function(model) {
  mode <- as.character(model$PRED_MODE %||% "pk")[[1L]]
  advan <- as.integer(model$ADVAN %||% NA_integer_)
  trans <- as.integer(model$TRANS %||% NA_integer_)
  if (identical(mode, "pred") ||
      identical(as.character(model$SOLVER %||% ""), "direct")) {
    return(list(
      mode = "pred",
      label = "Direct $PRED",
      description = "Row-wise direct prediction model; ADVAN/TRANS are not used for propagation."
    ))
  }
  base <- paste0(
    if (is.finite(advan)) paste0("ADVAN", advan) else "ADVAN unspecified",
    if (is.finite(trans)) paste0(" / TRANS", trans) else ""
  )
  if (identical(mode, "pk_pred")) {
    return(list(
      mode = mode,
      label = paste0(base, " + $PRED"),
      description = "ADVAN propagation followed by a post-ADVAN $PRED layer."
    ))
  }
  list(
    mode = "pk", label = base,
    description = "ADVAN/PREDPP-style structural model."
  )
}

.lity_model_name <- function(model, fallback = "Pharmacometric model") {
  value <- attr(model, "name", exact = TRUE)
  if (is.null(value) || !nzchar(as.character(value)[[1L]])) {
    route <- .lity_model_route(model)
    if (identical(route$mode, "pred")) return("Direct $PRED model")
    advan <- as.integer(model$ADVAN %||% NA_integer_)
    trans <- as.integer(model$TRANS %||% NA_integer_)
    value <- if (is.finite(advan) && advan == 1L) {
      "One-compartment IV PK"
    } else if (is.finite(advan) && advan == 2L) {
      "One-compartment oral PK"
    } else if (is.finite(advan) && advan == 3L) {
      "Two-compartment IV PK"
    } else if (is.finite(advan) && advan == 4L) {
      "Two-compartment oral PK"
    } else if (is.finite(advan) && advan %in% c(7L, 11L)) {
      "Three-compartment IV PK"
    } else if (is.finite(advan) && advan == 12L) {
      "Three-compartment oral PK"
    } else if (is.finite(advan)) {
      paste0("ADVAN", advan, if (is.finite(trans)) paste0(" / TRANS", trans) else "", " model")
    } else fallback
  }
  as.character(value)[[1L]]
}

.lity_parameter_rows <- function(model) {
  rows <- list()
  theta <- model$THETAS %||% data.frame()
  if (nrow(theta)) {
    rows <- c(rows, lapply(seq_len(nrow(theta)), function(i) list(
      type = "THETA", name = paste0("THETA(", i, ")"),
      index = as.integer(i), row = as.integer(i), col = as.integer(i),
      value = as.numeric(theta$Value[[i]]),
      lower = as.numeric(theta$LOWER[[i]] %||% NA_real_),
      upper = as.numeric(theta$UPPER[[i]] %||% NA_real_),
      fixed = isTRUE(theta$FIX[[i]])
    )))
  }
  omega <- model$OMEGAS %||% data.frame()
  if (nrow(omega)) {
    rows <- c(rows, lapply(seq_len(nrow(omega)), function(i) {
      row <- as.integer(omega$ROW[[i]] %||% i)
      col <- as.integer(omega$COL[[i]] %||% row)
      list(type = "OMEGA", name = paste0("OMEGA(", row, ",", col, ")"),
           index = as.integer(i), row = row, col = col,
           value = as.numeric(omega$Value[[i]]), lower = NA_real_,
           upper = NA_real_, fixed = isTRUE(omega$FIX[[i]]))
    }))
  }
  sigma <- model$SIGMAS %||% data.frame()
  if (nrow(sigma)) {
    rows <- c(rows, lapply(seq_len(nrow(sigma)), function(i) list(
      type = "SIGMA", name = paste0("SIGMA(", i, ")"),
      index = as.integer(i), row = as.integer(i), col = as.integer(i),
      value = as.numeric(sigma$Value[[i]]), lower = NA_real_,
      upper = NA_real_, fixed = isTRUE(sigma$FIX[[i]])
    )))
  }
  rows
}

.lity_model_family <- function(model) {
  if (!is.null(model$HMM_CONFIG)) return("Hidden Markov")
  outcomes <- model$OUTCOMES %||% list()
  families <- unique(vapply(outcomes, function(x) {
    as.character(x$family %||% "")
  }, character(1)))
  families <- families[nzchar(families)]
  if (length(families)) return(paste(families, collapse = ", "))
  if (isTRUE(model$USE_ODE)) return("ODE")
  if (nzchar(as.character(model$DES %||% ""))) return("Differential equation")
  "Continuous PK/PD"
}

.lity_model_diagram <- function(model) {
  graph <- model$GRAPH %||% list()
  compartments <- graph$compartments
  if (!is.data.frame(compartments) || !nrow(compartments)) {
    states <- unique(c(
      suppressWarnings(as.integer(model$DOSECMP %||% 1L)),
      suppressWarnings(as.integer(model$OBSCMP %||% 1L)),
      suppressWarnings(as.integer(model$n_state %||% 1L))
    ))
    count <- max(states[is.finite(states)], 1L)
    compartments <- data.frame(
      id = seq_len(count), name = paste("Compartment", seq_len(count)),
      state = paste0("A", seq_len(count)), stringsAsFactors = FALSE
    )
  }
  compartment_rows <- lapply(seq_len(nrow(compartments)), function(i) list(
    id = as.integer(compartments$id[[i]] %||% i),
    name = as.character(compartments$name[[i]] %||% paste("Compartment", i)),
    state = as.character(compartments$state[[i]] %||% paste0("A", i)),
    dose = identical(as.integer(compartments$id[[i]] %||% i),
                     as.integer(model$DOSECMP %||% 1L)),
    observe = identical(as.integer(compartments$id[[i]] %||% i),
                        as.integer(model$OBSCMP %||% 1L))
  ))
  flows <- graph$flows %||% graph$edges %||% data.frame()
  flow_rows <- if (is.data.frame(flows) && nrow(flows)) {
    lapply(seq_len(nrow(flows)), function(i) list(
      from = as.integer(flows$from[[i]] %||% flows$source[[i]] %||% NA_integer_),
      to = as.integer(flows$to[[i]] %||% flows$target[[i]] %||% NA_integer_),
      parameter = as.character(flows$parameter[[i]] %||% flows$label[[i]] %||% "")
    ))
  } else list()
  list(compartments = compartment_rows, flows = flow_rows,
       source = as.character(graph$source %||% "model"))
}

.lity_model_outcomes <- function(model) {
  outcomes <- model$OUTCOMES %||% list()
  if (length(outcomes)) {
    return(lapply(seq_along(outcomes), function(i) {
      outcome <- outcomes[[i]]
      outcome_names <- names(outcomes)
      fallback_name <- if (!is.null(outcome_names) &&
                           length(outcome_names) >= i &&
                           nzchar(outcome_names[[i]])) {
        outcome_names[[i]]
      } else paste("Outcome", i)
      list(
        name = as.character(outcome$name %||% fallback_name),
        family = as.character(outcome$family %||% "continuous"),
        dvid = as.integer(outcome$dvid %||% i)
      )
    }))
  }
  if (!is.null(model$HMM_CONFIG)) {
    states <- length(model$HMM_CONFIG$states %||% c(1, 2))
    return(list(list(name = "Hidden state emission",
                          family = if (states <= 2L) "bernoulli" else "ordinal",
                          dvid = 1L)))
  }
  list(list(name = "Continuous outcome", family = "normal", dvid = 1L))
}

.lity_model_detail <- function(model, provenance = NULL) {
  provenance <- provenance %||%
    attr(model, "liberation_provenance", exact = TRUE) %||%
    attr(model, "library_provenance", exact = TRUE) %||%
    list(source = "Built-in", parameter_source = "template values")
  source <- as.character(provenance$source %||%
    if (!is.null(provenance$library_id)) "LibeRary" else "Built-in")[[1L]]
  route <- .lity_model_route(model)
  outcome_families <- vapply(
    model$OUTCOMES %||% list(),
    function(outcome) as.character(outcome$family %||% ""),
    character(1)
  )
  generated_ctmc <- any(
    outcome_families == "continuous_time_markov" &
      vapply(
        model$OUTCOMES %||% list(),
        function(outcome) length(outcome$initial %||% numeric()) > 2L,
        logical(1)
      )
  )
  list(
    name = .lity_model_name(model),
    source = source,
    sourceLabel = as.character(provenance$label %||% provenance$library_id %||%
      provenance$template %||% source)[[1L]],
    parameterSource = as.character(provenance$parameter_source %||%
      if (!is.null(provenance$library_id)) "published values" else "template values")[[1L]],
    advan = as.integer(model$ADVAN %||% NA_integer_),
    trans = as.integer(model$TRANS %||% NA_integer_),
    predMode = route$mode,
    typeLabel = route$label,
    typeDescription = route$description,
    family = .lity_model_family(model),
    doseCmt = as.integer(model$DOSECMP %||% 1L),
    observationCmt = as.integer(model$OBSCMP %||% 1L),
    covariates = as.character(model$COVARIATES %||% character()),
    outcomes = .lity_model_outcomes(model),
    parameters = .lity_parameter_rows(model),
    diagram = .lity_model_diagram(model),
    code = list(
      pk = as.character(model$PK_SOURCE %||% model$PRED %||% ""),
      pred = as.character(model$PRED_SOURCE %||% ""),
      des = as.character(model$DES %||% ""),
      error = as.character(model$ERROR %||% "")
    ),
    editor = list(
      name = .lity_model_name(model),
      predMode = route$mode,
      pk = as.character(model$PK_SOURCE %||% model$PRED %||% ""),
      pred = as.character(model$PRED_SOURCE %||% ""),
      des = as.character(model$DES %||% ""),
      error = as.character(model$ERROR %||% ""),
      errorEditable = !generated_ctmc,
      parameters = .lity_parameter_rows(model)
    ),
    hash = .lity_hash(model),
    provenance = provenance
  )
}

.lity_model_record <- function(id, source, label, subtitle = "", group = "",
                               status = "", advan = NA_integer_,
                               trans = NA_integer_, family = "",
                               parameter_source = "", reviewed = TRUE,
                               metadata = list(), pred_mode = "",
                               type_label = "") {
  list(
    id = id, key = paste(source, id, sep = ":"),
    source = source, label = label, subtitle = subtitle, group = group,
    status = status, advan = as.integer(advan), trans = as.integer(trans),
    family = family, parameterSource = parameter_source,
    predMode = pred_mode, typeLabel = type_label,
    reviewed = isTRUE(reviewed), metadata = metadata
  )
}

.lity_builtin_catalogue <- function() {
  example <- lity_example()$design$model
  example_route <- .lity_model_route(example)
  records <- list(.lity_model_record(
    "teaching-oral-pk", "builtin", "One-compartment oral PK",
    "ADVAN2 / TRANS2 teaching model", "Teaching examples", "Built-in",
    example$ADVAN, example$TRANS, "Continuous PK", "template values",
    metadata = list(kind = "teaching"),
    pred_mode = example_route$mode, type_label = example_route$label
  ))
  templates <- tryCatch(LibeRation::nm_structural_templates(), error = function(e) NULL)
  if (is.null(templates) || !nrow(templates)) return(records)
  for (i in seq_len(nrow(templates))) {
    template <- as.character(templates$template[[i]])
    model <- LibeRation::nm_model_template(template)
    route <- .lity_model_route(model)
    label <- as.character(templates$model[[i]] %||% .lity_model_name(
      model, gsub("_", " ", template)
    ))
    records[[length(records) + 1L]] <- .lity_model_record(
      template, "builtin", label,
      as.character(templates$notes[[i]] %||% ""), "LibeRation templates",
      "Built-in", model$ADVAN, model$TRANS, .lity_model_family(model),
      "template values", metadata = list(kind = "template", template = template),
      pred_mode = route$mode, type_label = route$label
    )
  }
  records
}

.lity_liberation_catalogue <- function(workspace) {
  workspace_path <- if (inherits(workspace, "nm_workspace")) {
    workspace$path
  } else if (!is.null(workspace)) {
    path.expand(as.character(workspace)[[1L]])
  } else ""
  if (!nzchar(workspace_path) || !dir.exists(workspace_path)) {
    return(list(records = list(), message = "No LibeRation workspace was found."))
  }
  ws <- if (inherits(workspace, "nm_workspace")) workspace else
    tryCatch(LibeRation::nm_workspace(workspace), error = identity)
  if (inherits(ws, "error")) return(list(records = list(), message = conditionMessage(ws)))
  projects <- tryCatch(LibeRation::nm_project_list(ws), error = identity)
  if (inherits(projects, "error") || !nrow(projects)) {
    return(list(records = list(), message = "The LibeRation workspace contains no projects."))
  }
  records <- list()
  for (i in seq_len(nrow(projects))) {
    project_id <- as.character(projects$id[[i]])
    project_name <- as.character(projects$name[[i]])
    entries <- tryCatch(LibeRation::nm_project_list(ws, project_id), error = function(e) NULL)
    if (is.null(entries) || !nrow(entries)) next
    label_by_id <- stats::setNames(as.character(entries$label), as.character(entries$id))
    for (j in seq_len(nrow(entries))) {
      entry <- entries[j, , drop = FALSE]
      if (!isTRUE(entry$has_model[[1L]])) next
      kind <- as.character(entry$entry_type[[1L]] %||% "version")
      result_type <- as.character(entry$result_type[[1L]] %||% "")
      if (kind == "run" && !identical(result_type, "estimation")) next
      parent <- as.character(entry$parent_id[[1L]] %||% "")
      parent_label <- if (nzchar(parent) && parent %in% names(label_by_id)) {
        unname(label_by_id[[parent]])
      } else ""
      subtitle <- if (kind == "run") {
        paste(c(parent_label, as.character(entry$method[[1L]] %||% "estimation"),
                "final estimates"), collapse = " / ")
      } else "Model version / initial estimates"
      records[[length(records) + 1L]] <- .lity_model_record(
        as.character(entry$id[[1L]]), "liberation", as.character(entry$label[[1L]]),
        subtitle, project_name, if (kind == "run") "Completed run" else "Model version",
        parameter_source = if (kind == "run") "final estimates" else "initial estimates",
        metadata = list(project = project_id, projectName = project_name,
                        snapshot = as.character(entry$id[[1L]]), entryType = kind,
                        parent = parent, parentLabel = parent_label)
      )
    }
  }
  list(records = records, message = if (length(records)) "" else
    "No model versions or completed estimation runs were found.")
}

.lity_liberary_catalogue <- function(root = NULL) {
  if (!requireNamespace("LibeRary", quietly = TRUE)) {
    return(list(records = list(), message = "Install LibeRary to browse extracted models."))
  }
  arguments <- list()
  if (!is.null(root) && nzchar(as.character(root)[[1L]])) arguments$root <- root
  entries <- tryCatch(do.call(LibeRary::library_list, arguments), error = identity)
  if (inherits(entries, "error")) {
    return(list(records = list(), message = conditionMessage(entries)))
  }
  records <- lapply(seq_len(nrow(entries)), function(i) {
    entry <- entries[i, , drop = FALSE]
    status <- as.character(entry$status[[1L]] %||% "")
    reviewed <- isTRUE(entry$qualified[[1L]]) ||
      status %in% c("validated", "review", "reviewed", "published", "qualified")
    .lity_model_record(
      as.character(entry$library_id[[1L]]), "liberary",
      as.character(entry$title[[1L]] %||% entry$library_id[[1L]]),
      paste(Filter(nzchar, c(as.character(entry$compound[[1L]] %||% ""),
                             as.character(entry$population[[1L]] %||% ""))),
            collapse = " / "),
      as.character(entry$compound[[1L]] %||% "Catalogue"), status,
      entry$advan[[1L]], entry$trans[[1L]],
      as.character(entry$model_type[[1L]] %||% ""),
      "published values", reviewed,
      metadata = list(libraryId = as.character(entry$library_id[[1L]]),
                      confidence = as.numeric(entry$confidence_overall[[1L]] %||% NA_real_),
                      qualified = isTRUE(entry$qualified[[1L]]),
                      blockers = as.character(entry$qualification_blockers[[1L]] %||% ""))
    )
  })
  list(records = records, message = if (length(records)) "" else
    "The LibeRary catalogue contains no entries.")
}

.lity_model_catalogue <- function(workspace = NULL, library_root = NULL) {
  liberation <- .lity_liberation_catalogue(workspace)
  liberary <- .lity_liberary_catalogue(library_root)
  list(
    records = c(.lity_builtin_catalogue(), liberation$records, liberary$records),
    messages = list(liberation = liberation$message, liberary = liberary$message),
    workspace = as.character(workspace %||% ""),
    libraryRoot = as.character(library_root %||% "")
  )
}

.lity_resolve_model_record <- function(record, workspace = NULL,
                                       library_root = NULL) {
  source <- as.character(record$source)[[1L]]
  if (identical(source, "builtin")) {
    if (identical(record$id, "teaching-oral-pk")) {
      model <- lity_example()$design$model
      template <- "teaching-oral-pk"
    } else {
      model <- LibeRation::nm_model_template(as.character(record$id)[[1L]])
      template <- as.character(record$id)[[1L]]
    }
    provenance <- list(source = "Built-in", template = template,
                       label = record$label, parameter_source = "template values",
                       imported_at = .lity_now())
    attr(model, "lity_provenance") <- provenance
    return(list(model = model, provenance = provenance))
  }
  if (identical(source, "liberation")) {
    if (is.null(workspace)) .lity_stop("No LibeRation workspace is configured.")
    metadata <- record$metadata
    model <- lity_model_from_liberation(
      workspace, metadata$project, metadata$snapshot,
      use_estimates = identical(metadata$entryType, "run")
    )
    provenance <- attr(model, "liberation_provenance", exact = TRUE)
    provenance$label <- paste(metadata$projectName, record$label, sep = " / ")
    return(list(model = model, provenance = provenance))
  }
  if (identical(source, "liberary")) {
    model <- lity_model_from_liberary(
      record$metadata$libraryId, root = library_root,
      allow_draft = !isTRUE(record$reviewed)
    )
    provenance <- attr(model, "library_provenance", exact = TRUE)
    provenance$source <- "LibeRary"
    provenance$label <- record$label
    provenance$parameter_source <- "published values"
    return(list(model = model, provenance = provenance))
  }
  .lity_stop("Unsupported model source.")
}

.lity_covariate_default <- function(name) {
  upper <- toupper(name)
  if (upper %in% c("WT", "WEIGHT", "WTKG")) return(70)
  if (upper %in% c("AGE", "AGEYR")) return(40)
  if (upper %in% c("SEX", "MALE", "FEMALE", "GENOTYPE")) return(0)
  1
}

.lity_model_compatibility <- function(design, model) {
  available <- unique(unlist(lapply(design$arms, function(arm) names(arm$events))))
  required <- unique(as.character(model$COVARIATES %||% character()))
  missing <- setdiff(required, available)
  covariates <- lapply(missing, function(name) list(
    name = name, suggested = .lity_covariate_default(name)
  ))
  warnings <- character()
  old_dose <- as.integer(design$model$DOSECMP %||% 1L)
  old_obs <- as.integer(design$model$OBSCMP %||% old_dose)
  new_dose <- as.integer(model$DOSECMP %||% 1L)
  new_obs <- as.integer(model$OBSCMP %||% new_dose)
  if (!identical(old_dose, new_dose) || !identical(old_obs, new_obs)) {
    warnings <- c(warnings, paste0(
      "Schedule compartments will be remapped from dose/observation ",
      old_dose, "/", old_obs, " to ", new_dose, "/", new_obs, "."
    ))
  }
  if (length(missing)) {
    warnings <- c(warnings,
      "Required covariates are absent from the current schedules; provide design values below.")
  }
  if (length(design$alternative_models)) {
    warnings <- c(warnings, "Existing alternative models will be cleared because they belong to the previous primary model.")
  }
  if (!is.null(design$prior_fim)) {
    warnings <- c(warnings, "The prior information matrix will be cleared because its parameter dimensions may no longer match.")
  }
  list(valid = TRUE, requiredCovariates = covariates, warnings = warnings)
}

.lity_endpoints_from_model <- function(model, current) {
  outcomes <- .lity_model_outcomes(model)
  explicit <- length(model$OUTCOMES %||% list()) || !is.null(model$HMM_CONFIG)
  if (!explicit) return(current)
  endpoints <- lapply(seq_along(outcomes), function(i) {
    outcome <- outcomes[[i]]
    family <- tolower(outcome$family)
    type <- if (family %in% c("bernoulli", "binary")) "binary" else
      if (family %in% c("categorical", "ordinal", "markov",
                        "continuous_time_markov")) "ordinal" else
      if (family %in% c("poisson", "negative_binomial", "binomial",
                        "zero_inflated_poisson", "hurdle")) "count" else
      if (family %in% c("tte", "time_to_event", "competing_risks")) "time_to_event" else
      if (family %in% c("recurrent_event")) "recurrent_event" else "continuous"
    thresholds <- if (identical(type, "ordinal")) c(-0.5, 0.5) else NULL
    lity_endpoint(
      outcome$name, type = type, dvid = as.integer(outcome$dvid %||% i),
      thresholds = thresholds,
      distribution = if (type == "continuous") family else NULL,
      metadata = list(source = "model", family = family)
    )
  })
  names(endpoints) <- make.unique(vapply(endpoints, `[[`, character(1), "name"))
  endpoints
}

.lity_apply_model <- function(design, model, provenance, covariates = list()) {
  compatibility <- .lity_model_compatibility(design, model)
  provided <- names(covariates)
  missing <- vapply(compatibility$requiredCovariates, `[[`, character(1), "name")
  unresolved <- setdiff(missing, provided)
  if (length(unresolved)) {
    .lity_stop("Provide design values for required covariates: ",
               paste(unresolved, collapse = ", "), ".")
  }
  new_dose <- as.integer(model$DOSECMP %||% 1L)
  new_obs <- as.integer(model$OBSCMP %||% new_dose)
  for (id in names(design$arms)) {
    arm <- design$arms[[id]]
    dose_rows <- arm$events$EVID != 0
    observation_rows <- arm$events$EVID == 0
    arm$events$CMT[dose_rows] <- new_dose
    arm$events$CMT[observation_rows] <- new_obs
    for (name in missing) {
      value <- suppressWarnings(as.numeric(covariates[[name]]))
      if (length(value) != 1L || !is.finite(value)) {
        .lity_stop("Covariate `", name, "` requires one finite design value.")
      }
      arm$events[[name]] <- value
    }
    design$arms[[id]] <- arm
  }
  for (i in seq_along(design$scenarios)) {
    design$scenarios[[i]]$theta <- NULL
    design$scenarios[[i]]$omega <- NULL
    design$scenarios[[i]]$sigma <- NULL
    design$scenarios[[i]]$model <- NULL
  }
  old_hash <- .lity_hash(design$model)
  design$model <- model
  design$endpoints <- .lity_endpoints_from_model(model, design$endpoints)
  design$alternative_models <- list()
  design$prior_fim <- NULL
  design$id <- .lity_id("design")
  history <- design$metadata$model_history %||% list()
  history[[length(history) + 1L]] <- list(
    changed_at = .lity_now(), previous_hash = old_hash,
    model_hash = .lity_hash(model), provenance = provenance,
    compatibility_warnings = compatibility$warnings
  )
  design$metadata$model_provenance <- provenance
  design$metadata$model_history <- history
  validation <- lity_validate(design)
  if (!validation$valid) {
    .lity_stop("The selected model is incompatible with the current design: ",
               paste(validation$errors, collapse = "; "))
  }
  design
}
