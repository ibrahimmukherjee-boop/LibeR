source(file.path("tools", "validation-runtime.R"))
.libPaths(c(liber_validation_library_path(getwd()), .libPaths()))
library(LibeRation)

comparison <- structure(list(
  id = "preview-comparison",
  runs = data.frame(
    Run = c("FOCEI run", "SAEM run"), Method = c("FOCEI", "SAEM"),
    Objective = c(1023.4, 1017.8), Convergence = c(0L, 0L)
  ),
  gof = data.frame(
    Metric = c("OFV", "AIC", "BIC", "Population RMSE", "Individual RMSE"),
    `FOCEI run` = c(1023.4, 1039.4, 1070.2, 3.4, 1.8),
    `SAEM run` = c(1017.8, 1033.8, 1064.6, 3.1, 1.6), check.names = FALSE
  ),
  parameters = data.frame(
    Parameter = c("THETA1", "THETA2", "OMEGA1", "SIGMA1"),
    `FOCEI run` = c(1.02, 4.9, .12, .08), `FOCEI run SE` = c(.08, .5, .03, .01),
    `SAEM run` = c(.98, 5.1, .11, .075), `SAEM run SE` = c(.07, .45, .025, .009),
    check.names = FALSE
  )
), class = "liber_gui_comparison")

set.seed(21)
gof_rows <- data.frame(
  ID = rep(1:12, each = 6), TIME = rep(c(0.5, 1, 2, 4, 8, 12), 12)
)
gof_rows$IPRED <- 80 * exp(-0.22 * gof_rows$TIME) * exp(rnorm(nrow(gof_rows), 0, 0.12))
gof_rows$DV <- gof_rows$IPRED * exp(rnorm(nrow(gof_rows), 0, 0.16))
gof_rows$IWRES <- rnorm(nrow(gof_rows))
gof_rows$WRES <- 0.85 * gof_rows$IWRES + rnorm(nrow(gof_rows), 0, 0.2)
fit_plot <- function(scale = 1) list(
  available = TRUE, gof_loaded = TRUE,
  gof = LibeRation:::.liber_gui_rows(transform(
    gof_rows, DV = DV * scale, IPRED = IPRED * scale
  ))
)

vpc_observed <- data.frame(
  BIN = paste0("bin", 1:6), TIME = c(0.5, 1, 2, 4, 8, 12), N = 30,
  Q5 = c(2, 4, 7, 5, 2, 1), Q50 = c(16, 28, 36, 25, 10, 5),
  Q95 = c(70, 110, 145, 108, 48, 24)
)
vpc_simulated <- transform(
  vpc_observed[, c("BIN", "TIME")],
  Q5_median = vpc_observed$Q5, Q5_lo = vpc_observed$Q5 * .55, Q5_hi = vpc_observed$Q5 * 1.6,
  Q50_median = vpc_observed$Q50, Q50_lo = vpc_observed$Q50 * .75, Q50_hi = vpc_observed$Q50 * 1.28,
  Q95_median = vpc_observed$Q95, Q95_lo = vpc_observed$Q95 * .65, Q95_hi = vpc_observed$Q95 * 1.5
)
vpc_plot <- function(scale = 1) LibeRation:::.liber_gui_result(structure(list(
  observed = transform(vpc_observed, Q5 = Q5 * scale, Q50 = Q50 * scale, Q95 = Q95 * scale),
  simulated = transform(
    vpc_simulated,
    Q5_median = Q5_median * scale, Q5_lo = Q5_lo * scale, Q5_hi = Q5_hi * scale,
    Q50_median = Q50_median * scale, Q50_lo = Q50_lo * scale, Q50_hi = Q50_hi * scale,
    Q95_median = Q95_median * scale, Q95_lo = Q95_lo * scale, Q95_hi = Q95_hi * scale
  ),
  points = transform(gof_rows[, c("TIME", "DV")], DV = DV * scale),
  nsim = 200L, pc_correct = FALSE
), class = "nm_vpc"))

comparison$plots <- list(
  gof = list(
    list(label = "FOCEI run", fit = fit_plot(1)),
    list(label = "SAEM run", fit = fit_plot(0.96))
  ),
  vpc = list(
    list(label = "FOCEI run", result = vpc_plot(1)),
    list(label = "SAEM run", result = vpc_plot(0.96))
  )
)

ui <- shiny::fluidPage(liberWorkbenchOutput("workbench", height = "100vh"))
server <- function(input, output, session) {
  output$workbench <- renderLiberWorkbench(liber_workbench(
    result = comparison, height = "100vh"
  ))
}
shiny::runApp(shiny::shinyApp(ui, server), host = "127.0.0.1", port = 8767,
              launch.browser = FALSE)
