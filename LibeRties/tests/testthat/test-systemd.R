test_that("systemd maps a multi-core job to a whole-cgroup quota", {
  executor <- ls_systemd_executor(
    service_user = "liberties", max_cores_per_job = 8L,
    tasks_per_core = 12L, min_tasks = 32L,
    systemd_run = "/usr/bin/systemd-run",
    systemctl = "/usr/bin/systemctl", live_preflight = FALSE
  )
  job <- structure(list(
    type = "estimate", arguments = list(n_cores = 4L)
  ), class = "liber_job")
  metadata <- list(
    user = "alice", id = "job-1",
    limits = list(max_runtime_seconds = 600, max_memory_mb = 2048)
  )
  local_mocked_bindings(
    .ls_systemd_path = function(value, what) as.character(value),
    .package = "LibeRties"
  )
  profile <- LibeRties:::.ls_systemd_properties(
    executor, job, metadata, "/srv/liberties/job-1",
    "/opt/liber/library", "/opt/liber/liberties-systemd-worker.R"
  )

  expect_identical(profile$cores, 4L)
  expect_identical(profile$tasks, 48L)
  expect_true("CPUQuota=400%" %in% profile$properties)
  expect_true("TasksMax=48" %in% profile$properties)
  expect_true("Slice=liberties-workers.slice" %in% profile$properties)
  expect_true("OOMPolicy=kill" %in% profile$properties)
  expect_true("PrivateUsers=yes" %in% profile$properties)
  expect_true("PrivateNetwork=yes" %in% profile$properties)
  expect_true("KillMode=control-group" %in% profile$properties)
  expect_true("BindPaths=/srv/liberties/job-1:/tmp/liberties-job" %in%
                profile$properties)
  expect_true("ReadWritePaths=/tmp/liberties-job" %in% profile$properties)
  expect_true(any(startsWith(
    profile$properties, "StandardOutput=append:/srv/liberties/job-1/"
  )))
})

test_that("only explicit literature tasks receive network access", {
  executor <- ls_systemd_executor(
    service_user = "liberties", max_cores_per_job = 2L,
    systemd_run = "/usr/bin/systemd-run",
    systemctl = "/usr/bin/systemctl", live_preflight = FALSE
  )
  metadata <- list(
    user = "alice", id = "job-2",
    limits = list(max_runtime_seconds = 600, max_memory_mb = 2048)
  )
  local_mocked_bindings(
    .ls_systemd_path = function(value, what) as.character(value),
    .package = "LibeRties"
  )
  profile <- LibeRties:::.ls_systemd_properties(
    executor,
    structure(list(type = "library_assess", arguments = list()),
              class = "liber_job"),
    metadata, "/srv/liberties/job-2", "/opt/liber/library",
    "/opt/liber/liberties-systemd-worker.R"
  )
  expect_true("PrivateNetwork=no" %in% profile$properties)
})

test_that("queue records systemd launch provenance and requested cores", {
  root <- tempfile("liberties-systemd-queue-")
  on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)
  executor <- ls_systemd_executor(
    service_user = "liberties", max_cores_per_job = 8L,
    systemd_run = "/usr/bin/systemd-run",
    systemctl = "/usr/bin/systemctl", live_preflight = FALSE
  )
  process <- list(
    is_alive = function() TRUE,
    get_pid = function() NA_integer_,
    get_exit_status = function() NA_integer_,
    kill_tree = function() TRUE,
    kill = function() TRUE
  )
  local_mocked_bindings(
    .ls_systemd_start = function(executor, job, metadata, job_dir,
                                 library_paths) {
      list(
        process = process, unit = "liberties-job-test.service",
        cores = 4L, tasks = 64L, profile = "network-isolated-compute"
      )
    },
    .package = "LibeRties"
  )
  queue <- ls_local_queue(root, executor = executor)
  job <- ls_job(
    "simulate", structure(list(), class = "nm_model"),
    data.frame(ID = 1, TIME = 0), arguments = list(n_cores = 4L)
  )
  id <- queue$submit(job)
  status <- queue$status(id)

  expect_identical(queue$isolation, "systemd-transient-service")
  expect_identical(status$executor, "systemd")
  expect_identical(status$requested_cores, 4L)
  expect_identical(status$tasks_max, 64L)
  expect_identical(status$systemd_unit, "liberties-job-test.service")
  expect_identical(status$systemd_profile, "network-isolated-compute")
})

test_that("systemd core ceilings reject oversized jobs before persistence", {
  root <- tempfile("liberties-systemd-limit-")
  on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)
  executor <- ls_systemd_executor(
    service_user = "liberties", max_cores_per_job = 2L,
    systemd_run = "/usr/bin/systemd-run",
    systemctl = "/usr/bin/systemctl", live_preflight = FALSE
  )
  queue <- ls_local_queue(root, executor = executor)
  job <- ls_job(
    "simulate", structure(list(), class = "nm_model"),
    data.frame(ID = 1, TIME = 0), arguments = list(n_cores = 4L)
  )
  expect_error(queue$submit(job, start = FALSE), "requests 4 cores")
  expect_equal(nrow(queue$list()), 0L)
})

test_that("production preflight uses systemd executor attestation", {
  root <- tempfile("liberties-systemd-preflight-")
  on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)
  executor <- ls_systemd_executor(
    service_user = "liberties", systemd_run = "/usr/bin/systemd-run",
    systemctl = "/usr/bin/systemctl", live_preflight = FALSE
  )
  local_mocked_bindings(
    .ls_systemd_preflight = function(executor, live = executor$live_preflight) {
      list(
        active = TRUE, provider = "systemd-transient-service",
        evidence = "verified by test harness", issues = character()
      )
    },
    .package = "LibeRties"
  )
  report <- ls_server_preflight(
    root, policy = ls_security_policy(
      production = TRUE, require_storage_encryption = FALSE
    ), executor = executor
  )
  expect_true(report$ready)
  expect_identical(report$executor, "systemd")
  expect_identical(report$os_isolation, "systemd-transient-service")
})

test_that("workers can read storage keys from systemd credentials", {
  credentials <- tempfile("liberties-credentials-")
  dir.create(credentials)
  on.exit(unlink(credentials, recursive = TRUE, force = TRUE), add = TRUE)
  key <- ls_generate_storage_key()
  writeLines(key, file.path(credentials, "liberties-storage-key"))
  old_directory <- Sys.getenv("CREDENTIALS_DIRECTORY", unset = NA_character_)
  old_key <- Sys.getenv("LIBERTIES_STORAGE_KEY", unset = NA_character_)
  on.exit({
    if (is.na(old_directory)) Sys.unsetenv("CREDENTIALS_DIRECTORY") else
      Sys.setenv(CREDENTIALS_DIRECTORY = old_directory)
    if (is.na(old_key)) Sys.unsetenv("LIBERTIES_STORAGE_KEY") else
      Sys.setenv(LIBERTIES_STORAGE_KEY = old_key)
  }, add = TRUE)
  Sys.setenv(CREDENTIALS_DIRECTORY = credentials)
  Sys.unsetenv("LIBERTIES_STORAGE_KEY")
  old_option <- getOption("LibeRties.storage_key")
  on.exit(options(LibeRties.storage_key = old_option), add = TRUE)
  options(LibeRties.storage_key = "")

  expect_length(LibeRties:::.ls_storage_key(required = TRUE), 32L)
})

test_that("the standard production API cannot fall back to subprocesses", {
  expect_error(
    ls_run_api(
      tempfile("liberties-no-production-subprocess-"),
      production = TRUE, executor = NULL
    ),
    "requires the native Linux systemd executor"
  )
})
