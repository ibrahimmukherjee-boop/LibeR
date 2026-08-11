args <- commandArgs(trailingOnly = TRUE)

option_value <- function(name, default = NULL) {
  prefix <- paste0("--", name, "=")
  value <- args[startsWith(args, prefix)]
  if (!length(value)) default else sub(prefix, "", tail(value, 1L), fixed = TRUE)
}

compatibility_dir <- normalizePath(
  option_value("compatibility"), winslash = "/", mustWork = TRUE
)
optimized_dir <- normalizePath(
  option_value("optimized"), winslash = "/", mustWork = TRUE
)
output_dir <- normalizePath(
  option_value("output"), winslash = "/", mustWork = FALSE
)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

read_summary <- function(directory) {
  utils::read.csv(
    file.path(directory, "summary.csv"), stringsAsFactors = FALSE,
    check.names = FALSE
  )
}
compatibility <- read_summary(compatibility_dir)
optimized <- read_summary(optimized_dir)
optimized$engine[optimized$engine == "LibeRation"] <- "LibeRation optimized"
compatibility$engine[compatibility$engine == "LibeRation"] <-
  "LibeRation compatibility"
combined <- rbind(compatibility, optimized)

engine_order <- c(
  "NONMEM", "LibeRation compatibility", "LibeRation optimized", "nlmixr2"
)
method_order <- c(
  "FO", "FOCE", "FOCEI", "LAPLACE", "ITS", "IMP", "SAEM", "BAYES",
  "SIMULATION"
)

lookup <- function(engine, method, column) {
  row <- combined[combined$engine == engine & combined$method == method, , drop = FALSE]
  if (nrow(row) != 1L) NA_real_ else as.numeric(row[[column]][[1L]])
}

timing <- do.call(rbind, lapply(method_order, function(method) {
  row <- data.frame(
    workload = if (method == "SIMULATION") "simulation" else "estimation",
    method = method, stringsAsFactors = FALSE
  )
  for (engine in engine_order) {
    prefix <- switch(
      engine,
      NONMEM = "nonmem",
      `LibeRation compatibility` = "liberation_compatibility",
      `LibeRation optimized` = "liberation_optimized",
      nlmixr2 = "nlmixr2"
    )
    row[[paste0(prefix, "_end_to_end_seconds")]] <- lookup(
      engine, method, "median_end_to_end_seconds"
    )
    row[[paste0(prefix, "_core_seconds")]] <- lookup(
      engine, method, "median_core_seconds"
    )
  }
  row
}))
utils::write.csv(
  timing, file.path(output_dir, "full-benchmark-timing.csv"),
  row.names = FALSE, na = ""
)

ratios <- do.call(rbind, lapply(method_order, function(method) {
  nonmem_end <- lookup("NONMEM", method, "median_end_to_end_seconds")
  nonmem_core <- lookup("NONMEM", method, "median_core_seconds")
  do.call(rbind, lapply(engine_order[-1L], function(engine) data.frame(
    method = method, engine = engine,
    end_to_end_ratio_nonmem_over_engine = nonmem_end /
      lookup(engine, method, "median_end_to_end_seconds"),
    core_ratio_nonmem_over_engine = nonmem_core /
      lookup(engine, method, "median_core_seconds"),
    stringsAsFactors = FALSE
  )))
}))
utils::write.csv(
  ratios, file.path(output_dir, "full-benchmark-ratios.csv"),
  row.names = FALSE, na = ""
)

present_methods <- method_order[vapply(method_order, function(method) {
  any(vapply(engine_order, function(engine) {
    is.finite(lookup(engine, method, "median_end_to_end_seconds"))
  }, logical(1)))
}, logical(1))]
focused_stochastic <- identical(present_methods, c("SAEM", "BAYES"))
benchmark_title <- if (focused_stochastic) {
  "SAEM and BAYES matched-control speed benchmark"
} else {
  "Full matched-control estimation and simulation benchmark"
}

write_plot <- function(path, device = c("png", "svg")) {
  device <- match.arg(device)
  if (device == "png") {
    grDevices::png(path, width = 2400L, height = 1350L, res = 180L)
  } else {
    grDevices::svg(path, width = 13.333, height = 7.5, pointsize = 11)
  }
  on.exit(grDevices::dev.off(), add = TRUE)
  old <- graphics::par(no.readonly = TRUE)
  on.exit(graphics::par(old), add = TRUE)
  graphics::par(
    mfrow = c(1L, 2L), mar = c(5.5, 7.4, 4.2, 1.0),
    oma = c(5.6, 0, 4.0, 0), las = 1, family = "sans",
    fg = "#2B3036", col.axis = "#2B3036", col.lab = "#2B3036",
    col.main = "#1F252B"
  )
  colours <- c(
    NONMEM = "#355C7D",
    `LibeRation compatibility` = "#2A9D8F",
    `LibeRation optimized` = "#67B99A",
    nlmixr2 = "#D08C3F"
  )
  display_methods <- rev(present_methods)
  draw_panel <- function(column, title) {
    values <- matrix(
      NA_real_, nrow = length(engine_order), ncol = length(display_methods),
      dimnames = list(engine_order, display_methods)
    )
    for (engine in engine_order) for (method in display_methods) {
      values[engine, method] <- lookup(engine, method, column)
    }
    positive <- values[is.finite(values) & values > 0]
    limits <- c(max(0.02, min(positive) / 1.8), max(positive) * 1.45)
    graphics::barplot(
      values, beside = TRUE, horiz = TRUE, log = "x", xlim = limits,
      col = colours[engine_order], border = NA, names.arg = display_methods,
      xlab = "Elapsed time (seconds, logarithmic scale)", main = title,
      cex.names = 0.84, cex.axis = 0.82, cex.lab = 0.9
    )
    graphics::box(col = "#A7AFB7")
  }
  draw_panel("median_end_to_end_seconds", "End-to-end time")
  draw_panel("median_core_seconds", "Core time")
  graphics::par(
    fig = c(0, 1, 0, 1), new = TRUE,
    mar = rep(0, 4), oma = rep(0, 4)
  )
  graphics::plot.new()
  graphics::text(
    0.5, 0.975, benchmark_title, cex = 1.25, font = 2,
    col = "#1F252B"
  )
  graphics::legend(
    "bottom", inset = c(0, 0.052), xpd = NA, horiz = TRUE,
    legend = engine_order, fill = colours[engine_order],
    border = NA, bty = "n", cex = 0.84
  )
  graphics::text(
    0.5, 0.018,
    paste(
      "Standard profile: 100 subjects, 800 records; covariance requested;",
      "median of 3 fresh processes. Blank bars indicate not run/no valid result."
    ),
    cex = 0.76, col = "#59636D"
  )
  invisible(TRUE)
}
write_plot(file.path(output_dir, "full-benchmark-timing.png"), "png")
write_plot(file.path(output_dir, "full-benchmark-timing.svg"), "svg")

markdown_table <- function(frame, digits = 3L) {
  display <- frame
  numeric <- vapply(display, is.numeric, logical(1))
  display[numeric] <- lapply(display[numeric], function(value) {
    ifelse(
      is.finite(value), formatC(value, digits = digits, format = "f"),
      "not run"
    )
  })
  names(display) <- c(
    "Workload", "Method", "NONMEM E2E", "NONMEM core",
    "LibeR compatibility E2E", "LibeR compatibility core",
    "LibeR optimized E2E", "LibeR optimized core",
    "nlmixr2 E2E", "nlmixr2 core"
  )
  c(
    paste0("| ", paste(names(display), collapse = " | "), " |"),
    paste0("| ", paste(rep("---", ncol(display)), collapse = " | "), " |"),
    apply(display, 1L, function(row) {
      paste0("| ", paste(row, collapse = " | "), " |")
    })
  )
}

report <- c(
  paste0("# ", benchmark_title), "",
  "Standard ADVAN1/TRANS2 IV-bolus fixture with 100 subjects and 800 records. Covariance was requested for applicable estimation methods. Values are medians of three measured fresh-process runs after one unmeasured warm-up.", "",
  "Core time excludes LibeRation context/tape initialization. NONMEM uses reported estimation plus covariance time when available and otherwise total CPU time. nlmixr2 core is the complete estimator call, including estimator-internal compilation/preparation and covariance because stable separate timers are not exposed.", "",
  markdown_table(timing[timing$method %in% present_methods, , drop = FALSE]), "",
  "## Comparator coverage note", "",
  if (focused_stochastic) {
    "SAEM completed in all three engines. BAYES has no exact nlmixr2 mapping in this harness, so that cell is intentionally blank rather than replaced by a different method."
  } else {
    "FO, FOCE, FOCEI, Laplace, SAEM, and simulation completed. ITS and BAYES have no exact nlmixr2 mapping in this harness. nlmixr2 IMP was excluded after a bounded warm-up exceeded five minutes without returning and reproduced the previously observed singular-repair/non-completion behaviour; its cell is marked as not run rather than reported as zero or replaced with another method."
  }, "",
  paste0("- Compatibility source: `", compatibility_dir, "`."),
  paste0("- Optimized source: `", optimized_dir, "`."), ""
)
writeLines(report, file.path(output_dir, "REPORT.md"), useBytes = TRUE)

cat("Combined report:", file.path(output_dir, "REPORT.md"), "\n")
