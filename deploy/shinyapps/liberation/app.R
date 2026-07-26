options(shiny.maxRequestSize = 50 * 1024^2)

library(LibeRation)

# shinyapps.io filesystems are ephemeral. Each browser session therefore gets
# an isolated demonstration workspace, and computational work runs in-process.
liber_gui(
  workspace = file.path(tempdir(), "LibeRation-shinyapps"),
  queue = FALSE,
  session_workspace = TRUE,
  allow_ollama = FALSE,
  launch.browser = NULL
)
