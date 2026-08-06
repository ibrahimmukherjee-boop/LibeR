test_that("direct scheduler requests are checksummed and configure durable storage", {
  root <- tempfile("direct-scheduler-")
  key <- paste(rep("ab", 32L), collapse = "")
  payload <- list(
    schema = "liberties.direct-scheduler", version = 1L,
    operation = "authenticate", storage_key = key,
    config = list(
      backend = "slurm", queue_name = "test", root = root,
      user = "local", max_workers = 2L, max_cores_per_job = 4L
    )
  )
  result <- LibeRties:::.ls_direct_dispatch(payload)
  expect_identical(result$backend, "slurm")
  expect_identical(result$queue_name, "test")
  expect_true(file.exists(file.path(root, ".storage-key")))
  expect_identical(
    LibeRties:::.ls_direct_scheduler_config(payload$config)$limits$max_concurrent_jobs,
    2L
  )
  if (.Platform$OS.type != "windows") {
    expect_identical(bitwAnd(as.integer(file.info(file.path(root, ".storage-key"))$mode),
                             as.octmode("077")), 0L)
  }

  payload_json <- jsonlite::toJSON(payload, auto_unbox = TRUE, null = "null", force = TRUE)
  request <- list(
    schema = "liberties.ssh.request", version = 1L,
    payload_json = as.character(payload_json),
    sha256 = unname(paste0(openssl::sha256(charToRaw(as.character(payload_json)))))
  )
  expect_identical(
    LibeRties:::.ls_direct_request_unpack(request)$operation,
    "authenticate"
  )
  request$sha256 <- paste(rep("0", 64L), collapse = "")
  expect_error(LibeRties:::.ls_direct_request_unpack(request), "checksum mismatch")
})

test_that("direct scheduler CLI emits a bounded response envelope", {
  root <- tempfile("direct-scheduler-cli-")
  key <- paste(rep("cd", 32L), collapse = "")
  payload <- list(
    schema = "liberties.direct-scheduler", version = 1L,
    operation = "authenticate", storage_key = key,
    config = list(backend = "grid_engine", queue_name = "test", root = root,
                  user = "local", max_workers = 1L, max_cores_per_job = 2L)
  )
  payload_json <- as.character(jsonlite::toJSON(
    payload, auto_unbox = TRUE, null = "null", force = TRUE
  ))
  request <- jsonlite::toJSON(list(
    schema = "liberties.ssh.request", version = 1L,
    payload_json = payload_json,
    sha256 = unname(paste0(openssl::sha256(charToRaw(payload_json))))
  ), auto_unbox = TRUE, null = "null", force = TRUE)
  input <- rawConnection(charToRaw(as.character(request)), open = "rb")
  lines <- character()
  output <- textConnection("lines", open = "w", local = TRUE)
  on.exit({
    try(close(input), silent = TRUE)
    try(close(output), silent = TRUE)
  }, add = TRUE)
  ls_direct_scheduler_cli(input = input, output = output)
  close(output)
  expect_true("LIBERTIES_SSH_RESPONSE_BEGIN" %in% lines)
  expect_true("LIBERTIES_SSH_RESPONSE_END" %in% lines)
  encoded <- lines[which(lines == "LIBERTIES_SSH_RESPONSE_BEGIN") + 1L]
  envelope <- jsonlite::fromJSON(encoded, simplifyVector = FALSE)
  expect_identical(envelope$schema, "liberties.ssh.response")
})

test_that("direct scheduler rejects unsafe scheduler routing values", {
  key <- paste(rep("ef", 32L), collapse = "")
  expect_error(LibeRties:::.ls_direct_dispatch(list(
    schema = "liberties.direct-scheduler", version = 1L,
    operation = "authenticate", storage_key = key,
    config = list(
      backend = "slurm", queue_name = "test", root = tempfile(), user = "local",
      partition = "normal; touch /tmp/no", max_workers = 1L, max_cores_per_job = 1L
    )
  )), "unsupported scheduler characters")
})
