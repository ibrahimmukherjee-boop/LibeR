test_that("fixed-shape matrix IR evaluates core statistical operations", {
  ir <- ad_matrix_ir(
    inputs = list(A = c(2, 2), b = c(2, 1)),
    operations = list(
      ad_matrix_op("L", "cholesky", x = "A"),
      ad_matrix_op("x", "solve", a = "A", b = "b", method = "spd"),
      ad_matrix_op("ld", "logdet", x = "A"),
      ad_matrix_op("q", "quadratic_form", a = "A", x = "b")
    ),
    outputs = c("L", "x", "ld", "q")
  )
  expect_s3_class(ir, "libertad_matrix_ir")
  expect_identical(ir$inputs$A$shape, c(2L, 2L))
  at <- list(A = matrix(c(4, 1, 1, 3), 2), b = matrix(c(2, -1), 2, 1))
  model <- ad_matrix_compile(ir, at = at, wrt = c("A", "b"))
  value <- model$value(at)
  expect_equal(value$L, t(chol(at$A)), tolerance = 1e-11)
  expect_equal(value$x, solve(at$A, at$b), tolerance = 1e-11)
  expect_equal(drop(value$ld), as.numeric(determinant(at$A, logarithm = TRUE)$modulus), tolerance = 1e-11)
  expect_equal(drop(value$q), drop(crossprod(at$b, at$A %*% at$b)), tolerance = 1e-11)
})

test_that("matrix gradients retain public element labels", {
  ir <- ad_matrix_ir(
    inputs = list(A = c(2, 2), b = c(2, 1)),
    operations = list(ad_matrix_op("q", "quadratic_form", a = "A", x = "b")),
    outputs = "q"
  )
  at <- list(A = matrix(c(4, 1, 1, 3), 2), b = matrix(c(2, -1), 2, 1))
  model <- ad_matrix_compile(ir, at = at, wrt = "b")
  gradient <- model$gradient(at)
  expect_equal(unname(gradient), drop(2 * at$A %*% at$b), tolerance = 1e-11)
  expect_equal(names(gradient), c("b[1,1]", "b[2,1]"))
  expect_equal(unname(model$hessian(at)), 2 * at$A, tolerance = 1e-11)
  model$jacobian(at)
  expect_lte(model$tape_info()$jacobian_nonzeros, 2L)
})

test_that("matrix exponential and covariance construction use fixed paths", {
  ir <- ad_matrix_ir(
    inputs = list(K = c(2, 2), raw = c(2, 2)),
    operations = list(
      ad_matrix_op("E", "matrix_exp", x = "K", order = 22L, scaling = 3L),
      ad_matrix_op("Omega", "covariance", x = "raw", log_diagonal = TRUE)
    ),
    outputs = c("E", "Omega")
  )
  raw <- matrix(c(log(2), 0.3, 99, log(1.5)), 2, 2)
  at <- list(K = diag(c(0.2, -0.4)), raw = raw)
  value <- ad_matrix_compile(ir, at = at)$value(at)
  expect_equal(value$E, diag(exp(c(0.2, -0.4))), tolerance = 1e-10)
  lower <- matrix(c(2, 0.3, 0, 1.5), 2, 2)
  expect_equal(value$Omega, lower %*% t(lower), tolerance = 1e-11)
  expect_match(ir$contracts$E$path, "fixed-order")
})

test_that("matrix IR and optimized tape caches round trip", {
  ir <- ad_matrix_ir(
    inputs = list(A = c(2, 2), b = c(2, 1)),
    operations = list(ad_matrix_op("x", "solve", a = "A", b = "b", method = "no_pivot")),
    outputs = "x"
  )
  at <- list(A = matrix(c(3, 1, 2, 4), 2), b = matrix(c(1, 2), 2, 1))
  reconstructed <- unserialize(serialize(ir, NULL))
  expect_equal(ad_matrix_compile(reconstructed, at = at)$value(at)$x, solve(at$A, at$b), tolerance = 1e-11)
  path <- tempfile(fileext = ".rds")
  on.exit(unlink(path), add = TRUE)
  model <- ad_matrix_compile(ir, at = at)
  model$save_tape(path)
  loaded <- ad_matrix_load_tape(path)
  expect_equal(loaded$value(at)$x, model$value(at)$x, tolerance = 1e-12)
})

test_that("matrix API rejects dynamic shapes and ambiguous decompositions", {
  expect_error(ad_matrix_ir(list(A = c(2, NA)), list(ad_matrix_op("T", "transpose", x = "A"))), "fixed shape")
  expect_error(
    ad_matrix_ir(list(A = c(2, 2)), list(ad_matrix_op("U", "svd", x = "A"))),
    "Unsupported matrix operation"
  )
  expect_true(all(c("matrix_exp", "logdet", "covariance") %in% ad_matrix_supported()$operations))
})
