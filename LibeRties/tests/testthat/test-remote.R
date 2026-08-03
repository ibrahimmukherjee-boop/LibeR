test_that("HTTP router exposes the typed contract without an RDS upload route", {
  skip_if_not_installed("plumber")
  root <- tempfile("server-")
  server <- ls_server(root)
  router <- ls_api(server)
  expect_s3_class(router, "Plumber")
  printed <- paste(capture.output(print(router)), collapse = "\n")
  expect_match(printed, "/jobs")
  expect_false(grepl("rds", printed, ignore.case = TRUE))
})

test_that("remote client validates its connection settings", {
  expect_error(ls_remote("not-a-url", "token"), "invalid")
  client <- ls_remote("https://example.test/", "token", timeout = 5)
  expect_equal(client$url, "https://example.test")
  expect_equal(client$timeout, 5)
})

test_that("HTTP routes enforce their complete read/write authorization matrix", {
  skip_if_not_installed("httpuv")
  skip_if_not_installed("callr")
  root <- tempfile("http-authz-")
  on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)
  reader <- ls_user_create(root, "reader", scopes = "jobs:read")
  writer <- ls_user_create(root, "writer", scopes = "jobs:write")
  full <- ls_user_create(root, "full", scopes = c("jobs:read", "jobs:write"))
  port <- httpuv::randomPort()
  process <- callr::r_bg(
    function(root, port, libraries) {
      .libPaths(libraries)
      LibeRties::ls_run_api(
        root, host = "127.0.0.1", port = port,
        max_workers_per_user = 1L, quiet = TRUE
      )
    },
    args = list(root, port, .libPaths()), libpath = .libPaths(), supervise = TRUE
  )
  on.exit(if (process$is_alive()) process$kill(), add = TRUE)
  base <- paste0("http://127.0.0.1:", port)
  deadline <- Sys.time() + 15
  repeat {
    ready <- tryCatch({
      httr2::req_perform(httr2::request(paste0(base, "/v1/health")))
      TRUE
    }, error = function(error) FALSE)
    if (ready) break
    if (Sys.time() >= deadline) {
      fail(paste("HTTP API did not start", paste(process$read_error_lines(), collapse = "\n")))
    }
    Sys.sleep(0.05)
  }
  request <- function(method, path, token = NULL, body = NULL) {
    value <- httr2::request(paste0(base, path))
    if (!is.null(token)) {
      value <- httr2::req_headers(value, Authorization = paste("Bearer", token))
    }
    value <- httr2::req_method(value, method)
    if (!is.null(body)) value <- httr2::req_body_json(value, body, auto_unbox = TRUE)
    value <- httr2::req_error(value, is_error = function(response) FALSE)
    httr2::req_perform(value, error_call = NULL)
  }
  status <- function(...) httr2::resp_status(request(...))
  skip_if_not_installed("LibeRation")
  model <- LibeRation::nm_model(
    INPUT = c("ID", "TIME", "EVID", "AMT"), ADVAN = 1,
    PRED = "CL=THETA(1); V=THETA(2); S1=V", ERROR = "Y=F",
    THETAS = data.frame(THETA = 1:2, Value = c(2, 20))
  )
  wire <- ls_job_to_wire(ls_job(
    "simulate", model = model,
    data = data.frame(ID = 1, TIME = 0, EVID = 0L, AMT = 0)
  ))

  expect_equal(status("GET", "/v1/jobs"), 401L)
  expect_equal(status("POST", "/v1/jobs", reader$token, list(not = "a job")), 401L)
  expect_equal(status("DELETE", "/v1/jobs/unknown", reader$token), 401L)
  expect_equal(status("GET", "/v1/jobs", writer$token), 401L)
  expect_equal(status("GET", "/v1/jobs/unknown", writer$token), 401L)
  expect_equal(status("GET", "/v1/jobs/unknown/result", writer$token), 401L)
  expect_equal(status("GET", "/v1/jobs/unknown/logs", writer$token), 401L)
  expect_equal(status("GET", "/v1/jobs", reader$token), 200L)
  expect_equal(status("POST", "/v1/jobs", writer$token, wire), 200L)

  response <- request("POST", "/v1/jobs", full$token, wire)
  id <- httr2::resp_body_json(response, simplifyVector = TRUE)$id
  expect_equal(status("GET", "/v1/jobs", full$token), 200L)
  expect_equal(status("GET", paste0("/v1/jobs/", id), full$token), 200L)
  expect_equal(status("GET", paste0("/v1/jobs/", id, "/logs"), full$token), 200L)
  expect_true(status("GET", paste0("/v1/jobs/", id, "/result"), full$token) %in%
                c(200L, 409L))
  expect_equal(status("DELETE", paste0("/v1/jobs/", id), full$token), 200L)
})
