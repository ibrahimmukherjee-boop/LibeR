test_that("persistent tape returns exact gradient and Hessian", {
  model <- ad_compile(
    "Y = (X - 1)^2 + 3 * Z^2 + X * Z",
    inputs = c("X", "Z"), outputs = "Y",
    at = c(X = 2, Z = -1), wrt = c("X", "Z")
  )
  expect_equal(unname(model$value(c(X = 2, Z = -1))), 2)
  expect_equal(unname(model$gradient(c(X = 2, Z = -1))), c(1, -4), tolerance = 1e-12)
  expect_equal(
    unname(model$hessian(c(X = 2, Z = -1))),
    matrix(c(2, 1, 1, 6), 2, 2), tolerance = 1e-12
  )
})

test_that("program evaluation can use non-taped fixed inputs", {
  model <- ad_compile("Y = A * X + B", inputs = c("A", "X", "B"), outputs = "Y")
  expect_equal(unname(model$value(c(A = 2, X = 4, B = 1), taped = FALSE)), 9)
  model$record(c(A = 2, X = 4, B = 1), wrt = "X", outputs = "Y")
  expect_equal(unname(model$gradient(c(X = 10))), 2)
})

test_that("non-active inputs are reusable CppAD dynamic parameters", {
  model <- ad_compile(
    "Y = X^P + P^X",
    inputs = c("X", "P"), outputs = "Y",
    at = c(X = 2, P = 0), wrt = "X"
  )

  expect_identical(model$dynamic, "P")
  expect_equal(model$tape_info()$dynamic_independent, 1)

  model$set_dynamic(c(P = 3))
  expect_equal(unname(model$value(c(X = 2))), 17, tolerance = 1e-12)
  expect_equal(
    unname(model$gradient(c(X = 2))),
    12 + 9 * log(3), tolerance = 1e-11
  )
  expect_equal(
    unname(model$hessian(c(X = 2))),
    matrix(12 + 9 * log(3)^2, 1, 1), tolerance = 1e-10
  )

  # Named full points can update dynamics and evaluate active inputs in one call.
  expect_equal(unname(model$value(c(X = 2, P = 4))), 32, tolerance = 1e-12)
  expect_equal(unname(model$dynamic_values), 4)
})

test_that("data-driven conditionals retain derivatives of the selected branch", {
  code <- paste(
    "LEFT = X^2",
    "RIGHT = exp(X)",
    "Y = ifelse(DV == 0, LEFT, RIGHT)",
    sep = "\n"
  )
  model <- ad_compile(
    code, inputs = c("X", "DV"), outputs = "Y",
    at = c(X = 2, DV = 0), wrt = "X"
  )

  expect_equal(unname(model$gradient(c(X = 3, DV = 0))), 6,
               tolerance = 1e-12)
  expect_equal(unname(model$gradient(c(X = 3, DV = 1))), exp(3),
               tolerance = 1e-12)
})

test_that("static conditionals return the selected AD expression, not its recording value", {
  code <- paste(
    "LT = ifelse(0 < 1, X^2, exp(X))",
    "LE = ifelse(1 <= 1, X^2, exp(X))",
    "GT = ifelse(2 > 1, X^2, exp(X))",
    "GE = ifelse(1 >= 1, X^2, exp(X))",
    "EQ = ifelse(1 == 1, X^2, exp(X))",
    "NE = ifelse(0 != 1, X^2, exp(X))",
    "EQ_FALSE = ifelse(0 == 1, exp(X), X^2)",
    sep = "\n"
  )
  for (optimize in c(FALSE, TRUE)) {
    model <- ad_compile(
      code, inputs = "X", at = c(X = 2), wrt = "X",
      optimize = optimize
    )
    expect_equal(unname(model$value(c(X = 3))), rep(9, 7),
                 tolerance = 1e-12)
    expect_equal(unname(model$jacobian(c(X = 3))), matrix(6, 7, 1),
                 tolerance = 1e-12)
  }
})

test_that("Jacobian evaluation selects multi-direction and subgraph kernels", {
  dense_code <- paste0(
    "Y", seq_len(20), " = X", seq_len(20), "^2 + X1"
  )
  dense <- ad_compile(
    paste(dense_code, collapse = "\n"),
    inputs = paste0("X", seq_len(20)),
    at = setNames(seq_len(20) / 10, paste0("X", seq_len(20))),
    wrt = paste0("X", seq_len(20))
  )
  dense$jacobian(setNames(seq_len(20) / 5, paste0("X", seq_len(20))))
  expect_identical(dense$tape_info()$derivative_strategy, "multi-forward")

  input_names <- paste0("X", seq_len(32))
  sparse_code <- paste0(
    "Y", seq_len(128), " = ", input_names[(seq_len(128) - 1L) %% 32L + 1L],
    "^2"
  )
  sparse <- ad_compile(
    paste(sparse_code, collapse = "\n"), inputs = input_names,
    at = setNames(rep(2, 32), input_names), wrt = input_names
  )
  jacobian <- sparse$jacobian(setNames(rep(3, 32), input_names))
  expected <- matrix(0, nrow = 128, ncol = 32)
  expected[cbind(seq_len(128), (seq_len(128) - 1L) %% 32L + 1L)] <- 6
  expect_identical(sparse$tape_info()$derivative_strategy, "subgraph-reverse")
  expect_equal(sparse$tape_info()$jacobian_nonzeros, 128)
  expect_equal(sum(jacobian != 0), 128)
  expect_equal(unname(jacobian), expected, tolerance = 1e-12)
})

test_that("nonsmooth operations expose their recorded branch convention", {
  absolute <- ad_compile(
    "Y = abs(X)", inputs = "X", outputs = "Y",
    at = c(X = 1), wrt = "X"
  )
  expect_equal(unname(absolute$gradient(c(X = 2))), 1)
  expect_equal(unname(absolute$gradient(c(X = -2))), -1)
  expect_equal(unname(absolute$gradient(c(X = 0))), 0)
  expect_equal(unname(absolute$hessian(c(X = 0))), matrix(0, 1, 1))

  branch <- ad_compile(
    "Y = ifelse(X < 0, X^2, X^3)", inputs = "X", outputs = "Y",
    at = c(X = -1), wrt = "X"
  )
  expect_equal(unname(branch$hessian(c(X = -2))), matrix(2, 1, 1))
  expect_equal(unname(branch$hessian(c(X = 2))), matrix(12, 1, 1))
  # At the comparison boundary the false branch is selected by the declared
  # strict inequality; this is a branch derivative, not a smoothness claim.
  expect_equal(unname(branch$gradient(c(X = 0))), 0)
  expect_equal(unname(branch$hessian(c(X = 0))), matrix(0, 1, 1))

  minimum <- ad_compile(
    "Y = min(X, Z)", inputs = c("X", "Z"), outputs = "Y",
    at = c(X = 1, Z = 2), wrt = c("X", "Z")
  )
  expect_equal(unname(minimum$gradient(c(X = 1, Z = 2))), c(1, 0))
  expect_equal(unname(minimum$gradient(c(X = 2, Z = 1))), c(0, 1))
})

test_that("Hessian evaluation selects and reuses the measured sparse pattern", {
  inputs <- paste0("X", seq_len(40))
  terms <- paste0("T", seq_len(40), " = ", inputs, "^2")
  code <- paste(
    c(terms, paste0("Y = ", paste0("T", seq_len(40), collapse = " + "))),
    collapse = "\n"
  )
  point <- setNames(seq_len(40) / 10, inputs)
  model <- ad_compile(
    code, inputs = inputs, outputs = "Y",
    at = point, wrt = inputs
  )

  first <- model$hessian(point)
  second <- model$hessian(point + 0.1)
  info <- model$tape_info()

  expect_equal(first, diag(2, 40), tolerance = 1e-12, ignore_attr = TRUE)
  expect_equal(second, first, tolerance = 1e-12)
  expect_identical(info$hessian_strategy, "sparse-colored")
  expect_equal(info$hessian_nonzeros, 40)
  expect_lte(info$hessian_sweeps, 2)

  small <- ad_compile(
    "Y = X1^2 + X2^2", inputs = c("X1", "X2"), outputs = "Y",
    at = c(X1 = 1, X2 = 2), wrt = c("X1", "X2")
  )
  small$hessian(c(X1 = 1, X2 = 2))
  expect_identical(small$tape_info()$hessian_strategy, "dense-directional")
})

test_that("optimized CppAD graph caches reconstruct without retaping", {
  model <- ad_compile(
    "Y = X^P + P^X", inputs = c("X", "P"), outputs = "Y",
    at = c(X = 2, P = 0), wrt = "X"
  )
  path <- tempfile(fileext = ".rds")
  on.exit(unlink(path), add = TRUE)
  model$save_tape(path)
  restored <- ad_load_tape(path)
  restored$set_dynamic(c(P = 3))
  expect_equal(restored$value(c(X = 2)), c(Y = 17), tolerance = 1e-12)
  expect_equal(restored$gradient(c(X = 2)), 12 + 9 * log(3),
               tolerance = 1e-11, ignore_attr = TRUE)
})

test_that("graph caches enforce their IR semantics and input contract", {
  square <- ad_compile(
    "Y = X^2 + P", inputs = c("X", "P"), outputs = "Y",
    at = c(X = 2, P = 1), wrt = "X"
  )
  cube <- ad_compile(
    "Y = X^3 + P", inputs = c("X", "P"), outputs = "Y",
    at = c(X = 2, P = 1), wrt = "X"
  )
  path <- tempfile(fileext = ".rds")
  on.exit(unlink(path), add = TRUE)

  cache <- square$tape_cache()
  expect_identical(cache$version, 2L)
  cache$graph_json <- cube$tape_cache()$graph_json
  saveRDS(cache, path)
  expect_error(ad_load_tape(path), "not semantically consistent")

  cache <- square$tape_cache()
  cache$domain <- c("X", "P")
  saveRDS(cache, path)
  expect_error(ad_load_tape(path), "domain/dynamic contract")
})

test_that("checkpoint prototypes are exact and nested-AD safe", {
  probe <- ad_checkpoint_probe(repetitions = 8L, evaluations = 5L)
  for (case in probe[c("advan1", "matrix2")]) {
    expect_true(case$nested_ad_safe)
    expect_lt(case$max_value_difference, 1e-12)
    expect_lt(case$max_jacobian_difference, 1e-10)
    expect_true(is.finite(case$checkpoint_microseconds))
    expect_true(is.finite(case$direct_microseconds))
    expect_gt(case$checkpoint_operations, 0)
  }
})

test_that("failed recordings do not poison the next tape on the thread", {
  expect_true(LibeRtAD:::.libertad_recording_recovery_probe())
})

test_that("engine reports the bundled CppAD provenance", {
  info <- ad_engine_info()

  expect_identical(info$backend, "CppAD (bundled by LibeRtAD)")
  expect_identical(info$cppad_version, "cppad-20260000.0")
  expect_identical(
    info$cppad_source_commit,
    "5d51b2aa6d6874c8d561da298a90b3721550d45d"
  )
  expect_identical(info$eigen_version, "5.0.1")
  expect_identical(
    info$eigen_source_commit,
    "bc3b39870ecb690a623a3f49149a358b95c5781d"
  )
})
