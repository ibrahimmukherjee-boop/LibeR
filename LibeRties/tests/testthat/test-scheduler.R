test_that("scheduler constructors validate site configuration", {
  slurm <- ls_slurm_executor(
    partition = "compute", account = "pharmacometrics",
    max_cores_per_job = 16L,
    submit = "sbatch", query = "squeue", accounting = "sacct", cancel = "scancel"
  )
  expect_s3_class(slurm, "liberties_scheduler_executor")
  expect_identical(slurm$type, "slurm")
  expect_identical(slurm$partition, "compute")

  grid <- ls_grid_engine_executor(
    parallel_environment = "smp", tmpfs_mb = 10240L,
    submit = "qsub", query = "qstat", accounting = "qacct", cancel = "qdel"
  )
  expect_s3_class(grid, "liberties_scheduler_executor")
  expect_identical(grid$type, "grid_engine")
  expect_true(grid$memory_per_core)
  expect_identical(grid$tmpfs_mb, 10240L)

  expect_error(
    ls_slurm_executor(
      partition = "bad\nvalue", submit = "sbatch", query = "squeue",
      accounting = "sacct", cancel = "scancel"
    ), "single-line"
  )
  expect_error(
    ls_grid_engine_executor(
      memory_resource = "mem;bad", submit = "qsub", query = "qstat",
      accounting = "qacct", cancel = "qdel"
    ), "resource name"
  )
})

test_that("Slurm submission maps LibeRties resource limits", {
  captured <- new.env(parent = emptyenv())
  executor <- ls_slurm_executor(
    partition = "cpu", account = "acct", qos = "normal",
    max_cores_per_job = 8L,
    submit = "sbatch", query = "squeue", accounting = "sacct", cancel = "scancel"
  )
  job <- structure(list(type = "estimate", arguments = list(n_cores = 4L)),
                   class = "liber_job")
  metadata <- list(
    user = "alice", id = "job-1",
    limits = list(max_runtime_seconds = 3661, max_memory_mb = 4096)
  )
  job_dir <- tempfile("liberties-slurm-job-")
  dir.create(job_dir)
  on.exit(unlink(job_dir, recursive = TRUE, force = TRUE), add = TRUE)
  local_mocked_bindings(
    .ls_scheduler_run = function(command, args, timeout) {
      captured$command <- command
      captured$args <- args
      list(status = 0L, stdout = "12345;cluster\n", stderr = "")
    },
    .package = "LibeRties"
  )
  launch <- LibeRties:::.ls_slurm_start(
    executor, job, metadata, job_dir, .libPaths()
  )

  expect_identical(launch$scheduler_job_id, "12345")
  expect_identical(launch$cores, 4L)
  expect_true("--cpus-per-task=4" %in% captured$args)
  expect_true("--mem=4096M" %in% captured$args)
  expect_true("--time=01:01:01" %in% captured$args)
  expect_true("--partition=cpu" %in% captured$args)
  expect_true("--account=acct" %in% captured$args)
  expect_true("--export=NONE" %in% captured$args)
  expect_true(file.exists(launch$script))
  script <- readLines(launch$script, warn = FALSE)
  expect_true(any(grepl("R_ENVIRON_USER", script, fixed = TRUE)))
  expect_false(any(grepl("LIBERTIES_STORAGE_KEY=", script, fixed = TRUE)))
})

test_that("Grid Engine submission matches Myriad resource semantics", {
  captured <- new.env(parent = emptyenv())
  executor <- ls_grid_engine_executor(
    queue = "all.q", project = "AllUsers", tmpfs_mb = 15360L,
    max_cores_per_job = 36L,
    submit = "qsub", query = "qstat", accounting = "qacct", cancel = "qdel"
  )
  job <- structure(list(type = "simulate", arguments = list(n_cores = 4L)),
                   class = "liber_job")
  metadata <- list(
    user = "alice", id = "job-2",
    limits = list(max_runtime_seconds = 600, max_memory_mb = 8192)
  )
  job_dir <- tempfile("liberties-grid-job-")
  dir.create(job_dir)
  on.exit(unlink(job_dir, recursive = TRUE, force = TRUE), add = TRUE)
  local_mocked_bindings(
    .ls_scheduler_run = function(command, args, timeout) {
      captured$args <- args
      list(status = 0L, stdout = "9876\n", stderr = "")
    },
    .package = "LibeRties"
  )
  launch <- LibeRties:::.ls_grid_engine_start(
    executor, job, metadata, job_dir, .libPaths()
  )

  expect_identical(launch$scheduler_job_id, "9876")
  expect_true(all(c("-pe", "smp", "4") %in% captured$args))
  resource <- captured$args[[which(captured$args == "-l") + 1L]]
  expect_match(resource, "h_rt=00:10:00", fixed = TRUE)
  expect_match(resource, "mem=2048M", fixed = TRUE)
  expect_match(resource, "tmpfs=15360M", fixed = TRUE)
  expect_true(all(c("-q", "all.q", "-P", "AllUsers") %in% captured$args))
})

test_that("scheduler status adapters distinguish active and accounted jobs", {
  expect_equal(LibeRties:::.ls_scheduler_memory_mb("0.000"), 0)
  expect_equal(LibeRties:::.ls_scheduler_memory_mb("512M"), 512)

  slurm <- ls_slurm_executor(
    submit = "sbatch", query = "squeue", accounting = "sacct", cancel = "scancel"
  )
  local_mocked_bindings(
    .ls_scheduler_run = function(command, args, timeout) {
      if (identical(command, "squeue")) {
        return(list(status = 0L, stdout = "", stderr = ""))
      }
      list(
        status = 0L,
        stdout = "123|COMPLETED|0:0|12|00:00:20|512M\n", stderr = ""
      )
    },
    .package = "LibeRties"
  )
  status <- LibeRties:::.ls_slurm_status(slurm, "123", .ls_now())
  expect_false(status$active)
  expect_identical(status$exit_status, 0L)
  expect_equal(status$usage$memory_mb, 512)
  expect_equal(status$usage$cpu_seconds, 20)

  grid <- ls_grid_engine_executor(
    submit = "qsub", query = "qstat", accounting = "qacct", cancel = "qdel"
  )
  local_mocked_bindings(
    .ls_scheduler_run = function(command, args, timeout) {
      if (identical(command, "qstat")) {
        return(list(status = 1L, stdout = "", stderr = "Following jobs do not exist"))
      }
      list(
        status = 0L,
        stdout = paste(
          "exit_status 0", "failed 0", "cpu 18.5", "ru_wallclock 22",
          "maxvmem 1.5G", sep = "\n"
        ), stderr = ""
      )
    },
    .package = "LibeRties"
  )
  status <- LibeRties:::.ls_grid_engine_status(grid, "456", .ls_now())
  expect_false(status$active)
  expect_identical(status$state, "COMPLETED")
  expect_equal(status$usage$memory_mb, 1536)
  expect_equal(status$usage$cpu_seconds, 18.5)
})

test_that("Slurm completion falls back to bounded scontrol history", {
  slurm <- ls_slurm_executor(
    submit = "sbatch", query = "squeue", accounting = "sacct",
    control = "scontrol", cancel = "scancel"
  )
  local_mocked_bindings(
    .ls_scheduler_run = function(command, args, timeout) {
      if (identical(command, "squeue")) {
        return(list(status = 0L, stdout = "", stderr = ""))
      }
      if (identical(command, "sacct")) {
        return(list(
          status = 1L, stdout = "",
          stderr = "Slurm accounting storage is disabled"
        ))
      }
      list(
        status = 0L,
        stdout = paste(
          "JobId=12 JobState=COMPLETED ExitCode=0:0",
          "RunTime=00:00:07 Partition=debug"
        ), stderr = ""
      )
    },
    .package = "LibeRties"
  )
  status <- LibeRties:::.ls_slurm_status(slurm, "12", .ls_now())
  expect_false(status$active)
  expect_identical(status$state, "COMPLETED")
  expect_identical(status$exit_status, 0L)
  expect_equal(status$usage$elapsed_seconds, 7)
  expect_match(status$detail, "scontrol")
})

test_that("queue records scheduler provenance and recovers pending allocations", {
  root <- tempfile("liberties-scheduler-queue-")
  on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)
  executor <- ls_grid_engine_executor(
    max_cores_per_job = 8L,
    submit = "qsub", query = "qstat", accounting = "qacct", cancel = "qdel"
  )
  cancelled <- new.env(parent = emptyenv())
  cancelled$value <- FALSE
  process <- list(
    is_alive = function() TRUE,
    get_pid = function() NA_integer_,
    get_exit_status = function() NA_integer_,
    resource_usage = function() list(memory_mb = 0, cpu_seconds = 0, elapsed_seconds = 0),
    kill_tree = function() { cancelled$value <- TRUE; TRUE },
    kill = function() { cancelled$value <- TRUE; TRUE }
  )
  local_mocked_bindings(
    .ls_scheduler_start = function(executor, job, metadata, job_dir, library_paths) {
      list(
        process = process, scheduler_job_id = "54321",
        scheduler_backend = "grid_engine", scheduler_queue = "",
        profile = "slots=2;memory_per_core=2048M", cores = 2L,
        script_sha256 = paste(rep("a", 64), collapse = "")
      )
    },
    .ls_executor_process = function(executor, metadata) process,
    .package = "LibeRties"
  )
  queue <- ls_local_queue(root, executor = executor, max_workers = 2L)
  job <- ls_job(
    "simulate", structure(list(), class = "nm_model"),
    data.frame(ID = 1, TIME = 0), arguments = list(n_cores = 2L)
  )
  id <- queue$submit(job)
  metadata <- queue$status(id)
  expect_identical(metadata$executor, "grid_engine")
  expect_identical(metadata$scheduler_job_id, "54321")
  expect_identical(metadata$requested_cores, 2L)
  expect_identical(queue$isolation, "grid-engine-scheduled-worker")

  restarted <- ls_local_queue(root, executor = executor, max_workers = 2L)
  restarted$poll(start = FALSE)
  expect_true(exists(paste("local", id, sep = "::"), envir = restarted$processes))
  expect_true(restarted$cancel(id))
  expect_true(cancelled$value)
  expect_identical(restarted$status(id)$status, "cancelled")
})

test_that("recovery never resubmits a durable job through a different scheduler", {
  root <- tempfile("liberties-scheduler-mismatch-")
  on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)
  grid <- ls_grid_engine_executor(
    submit = "qsub", query = "qstat", accounting = "qacct", cancel = "qdel"
  )
  process <- list(
    is_alive = function() TRUE,
    get_pid = function() NA_integer_,
    get_exit_status = function() NA_integer_,
    resource_usage = function() list(memory_mb = 0, cpu_seconds = 0, elapsed_seconds = 0),
    kill_tree = function() TRUE,
    kill = function() TRUE
  )
  launches <- 0L
  local_mocked_bindings(
    .ls_scheduler_start = function(executor, job, metadata, job_dir, library_paths) {
      launches <<- launches + 1L
      list(
        process = process, scheduler_job_id = "65432",
        scheduler_backend = "grid_engine", scheduler_queue = "",
        profile = "slots=1", cores = 1L,
        script_sha256 = paste(rep("b", 64), collapse = "")
      )
    },
    .ls_executor_process = function(executor, metadata) process,
    .package = "LibeRties"
  )
  queue <- ls_local_queue(root, executor = grid)
  job <- ls_job(
    "simulate", structure(list(), class = "nm_model"),
    data.frame(ID = 1, TIME = 0)
  )
  id <- queue$submit(job)
  expect_identical(launches, 1L)

  slurm <- ls_slurm_executor(
    submit = "sbatch", query = "squeue", accounting = "sacct", cancel = "scancel"
  )
  reopened <- ls_local_queue(root, executor = slurm)
  reopened$poll(start = TRUE)
  metadata <- reopened$status(id)
  expect_identical(launches, 1L)
  expect_identical(metadata$status, "queued")
  expect_identical(metadata$scheduler_state, "RECOVERY_EXECUTOR_MISMATCH")
  expect_match(metadata$error, "will not resubmit or falsely fail")
  expect_true(dir.exists(file.path(
    root, "users", "local", "jobs", id, ".claimed"
  )))
})

test_that("scheduler workers can read a protected storage-key file", {
  key_file <- tempfile("liberties-scheduler-key-")
  writeLines(ls_generate_storage_key(), key_file)
  on.exit(unlink(key_file, force = TRUE), add = TRUE)
  old_file <- Sys.getenv("LIBERTIES_STORAGE_KEY_FILE", unset = NA_character_)
  old_key <- Sys.getenv("LIBERTIES_STORAGE_KEY", unset = NA_character_)
  old_option <- getOption("LibeRties.storage_key")
  on.exit({
    if (is.na(old_file)) Sys.unsetenv("LIBERTIES_STORAGE_KEY_FILE") else
      Sys.setenv(LIBERTIES_STORAGE_KEY_FILE = old_file)
    if (is.na(old_key)) Sys.unsetenv("LIBERTIES_STORAGE_KEY") else
      Sys.setenv(LIBERTIES_STORAGE_KEY = old_key)
    options(LibeRties.storage_key = old_option)
  }, add = TRUE)
  Sys.setenv(LIBERTIES_STORAGE_KEY_FILE = key_file)
  Sys.unsetenv("LIBERTIES_STORAGE_KEY")
  options(LibeRties.storage_key = "")
  expect_length(LibeRties:::.ls_storage_key(required = TRUE), 32L)
})

test_that("production scheduler use requires independent isolation evidence", {
  root <- tempfile("liberties-scheduler-preflight-")
  on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)
  executor <- ls_slurm_executor(
    submit = "sbatch", query = "squeue", accounting = "sacct", cancel = "scancel"
  )
  local_mocked_bindings(
    .ls_scheduler_preflight = function(executor) list(
      active = FALSE, provider = "slurm-resource-scheduler",
      evidence = "validated scheduler commands", issues = character()
    ),
    .package = "LibeRties"
  )
  policy <- ls_security_policy(
    production = TRUE, require_storage_encryption = FALSE,
    require_os_isolation = TRUE
  )
  without_probe <- ls_server_preflight(
    root, policy = policy, executor = executor
  )
  expect_false(without_probe$ready)
  expect_match(without_probe$issues, "verifiable OS isolation")

  with_probe <- ls_server_preflight(
    root, policy = policy, executor = executor,
    isolation_probe = function() list(
      active = TRUE, provider = "site-container",
      evidence = "attested by the cluster deployment"
    )
  )
  expect_true(with_probe$ready)
  expect_identical(with_probe$os_isolation, "site-container")
})
