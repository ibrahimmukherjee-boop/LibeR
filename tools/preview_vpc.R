source(file.path("tools", "validation-runtime.R"))
.libPaths(c(liber_validation_library_path(getwd()), .libPaths()))
library(LibeRation)

times <- c(0.5, 1, 2, 4, 8, 12)
observed <- data.frame(
  BIN = paste0("bin", seq_along(times)), TIME = times, N = 30,
  Q5 = c(0.7, 3, 8, 6, 1.1, 0.5),
  Q50 = c(3, 18, 32, 24, 9, 4),
  Q95 = c(15, 90, 140, 105, 44, 22)
)
simulated <- data.frame(BIN = observed$BIN, TIME = times)
for (name in c("Q5", "Q50", "Q95")) {
  simulated[[paste0(name, "_median")]] <- observed[[name]] * c(.9, 1.05, 1, .95, 1.05, 1)
  simulated[[paste0(name, "_lo")]] <- simulated[[paste0(name, "_median")]] * .55
  simulated[[paste0(name, "_hi")]] <- simulated[[paste0(name, "_median")]] * 1.65
}
set.seed(17)
points <- do.call(rbind, lapply(seq_along(times), function(index) data.frame(
  TIME = times[[index]], DV = exp(stats::rnorm(30, log(observed$Q50[[index]]), .85))
)))
vpc <- structure(list(
  observed = observed, simulated = simulated, points = points,
  nsim = 200L, pc_correct = FALSE, stratify = "SEX",
  stratified = list(
    list(
      level = "Female",
      observed = transform(observed, Q5 = Q5 * 0.82, Q50 = Q50 * 0.82, Q95 = Q95 * 0.82),
      simulated = transform(
        simulated,
        Q5_median = Q5_median * 0.82, Q5_lo = Q5_lo * 0.82, Q5_hi = Q5_hi * 0.82,
        Q50_median = Q50_median * 0.82, Q50_lo = Q50_lo * 0.82, Q50_hi = Q50_hi * 0.82,
        Q95_median = Q95_median * 0.82, Q95_lo = Q95_lo * 0.82, Q95_hi = Q95_hi * 0.82
      ),
      points = transform(points, DV = DV * 0.82)
    ),
    list(
      level = "Male",
      observed = transform(observed, Q5 = Q5 * 1.18, Q50 = Q50 * 1.18, Q95 = Q95 * 1.18),
      simulated = transform(
        simulated,
        Q5_median = Q5_median * 1.18, Q5_lo = Q5_lo * 1.18, Q5_hi = Q5_hi * 1.18,
        Q50_median = Q50_median * 1.18, Q50_lo = Q50_lo * 1.18, Q50_hi = Q50_hi * 1.18,
        Q95_median = Q95_median * 1.18, Q95_lo = Q95_lo * 1.18, Q95_hi = Q95_hi * 1.18
      ),
      points = transform(points, DV = DV * 1.18)
    )
  )
), class = "nm_vpc")

ui <- shiny::fluidPage(liberWorkbenchOutput("workbench", height = "100vh"))
server <- function(input, output, session) {
  output$workbench <- renderLiberWorkbench(liber_workbench(
    diagnostics = list(vpc = vpc), height = "100vh"
  ))
}
shiny::runApp(shiny::shinyApp(ui, server), host = "127.0.0.1", port = 8766,
              launch.browser = FALSE)
