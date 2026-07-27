source(file.path("tools", "validation-runtime.R"))
.libPaths(c(liber_validation_library_path(getwd()), .libPaths()))
library(LibeRation)

model <- nm_model(
  INPUT = c("ID", "TIME", "EVID", "AMT", "DV"),
  ADVAN = 4, TRANS = 4, DOSECMP = 1, OBSCMP = 2,
  PRED = paste(
    "KA = THETA(1) * exp(ETA(1))",
    "CL = THETA(2) * exp(ETA(2))",
    "VC = THETA(3) * exp(ETA(3))",
    "Q = THETA(4)",
    "VP = THETA(5)",
    "S2 = VC",
    sep = "\n"
  ),
  ERROR = "Y = F * (1 + ERR(1)) + ERR(2)",
  THETAS = data.frame(THETA = 1:5, Value = c(1.2, 4, 35, 3, 70)),
  OMEGAS = data.frame(OMEGA = 1:3, Value = c(0.12, 0.08, 0.1)),
  SIGMAS = data.frame(SIGMA = 1:2, Value = c(0.04, 0.01))
)

data <- data.frame(
  ID = rep(1:12, each = 5),
  TIME = rep(c(0, 1, 2, 8, 24), 12),
  EVID = rep(c(1, 0, 0, 0, 0), 12),
  AMT = rep(c(100, 0, 0, 0, 0), 12),
  DV = NA_real_
)

app <- liber_gui(
  model, data,
  workspace = nm_workspace(file.path(tempdir(), "liber-gui-preview")),
  queue = FALSE,
  launch.browser = NULL
)
shiny::runApp(app, host = "127.0.0.1", port = 8765, launch.browser = FALSE)
