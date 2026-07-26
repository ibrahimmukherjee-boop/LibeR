# Deterministic matched population fixtures shared by the LibeRation and
# nlmixr2 lanes. No fitted value from either engine is used to create them.

nlmixr2_population_data <- function(n = 24L, correlated = FALSE,
                                    covariate = FALSE) {
  times <- c(0, .5, 1, 2, 4, 8, 12)
  z1 <- as.numeric(scale(stats::qnorm((seq_len(n) - .5) / n)))
  z2 <- as.numeric(scale(sin(seq_len(n) * 1.73)))
  eta1 <- sqrt(.12) * z1
  eta2 <- if (correlated) {
    sqrt(.18) * (.45 * z1 + sqrt(1 - .45^2) * z2)
  } else {
    rep(0, n)
  }
  weight <- seq(48, 96, length.out = n)
  do.call(rbind, lapply(seq_len(n), function(id) {
    clearance <- 2 * if (covariate) (weight[[id]] / 70)^.65 else 1
    clearance <- clearance * exp(eta1[[id]])
    volume <- 20 * exp(eta2[[id]])
    prediction <- 100 / volume *
      exp(-clearance / volume * times[-1L])
    residual <- .15 * sin(id * 2.31 + seq_along(prediction) * 1.17)
    data.frame(
      ID = id, TIME = times,
      EVID = c(1L, rep(0L, length(prediction))),
      AMT = c(100, rep(0, length(prediction))), CMT = 1L,
      DV = c(NA, prediction + residual),
      MDV = c(1L, rep(0L, length(prediction))),
      WT = weight[[id]]
    )
  }))
}

nlmixr2_iov_data <- function(n = 20L) {
  standardized <- as.numeric(scale(
    stats::qnorm((seq_len(n) - .5) / n)
  ))
  do.call(rbind, lapply(seq_len(n), function(id) {
    eta <- sqrt(.08) * standardized[[id]]
    kappa <- sqrt(.04) * c(sin(id * 1.37), cos(id * 1.11))
    times <- c(0, 1, 4, 8, 24, 25, 28, 32)
    evid <- as.integer(times %in% c(0, 24))
    amount <- 0
    last_time <- 0
    observation <- rep(NA_real_, length(times))
    for (row in seq_along(times)) {
      occasion <- if (times[[row]] < 24) 1L else 2L
      clearance <- 2 * exp(eta + kappa[[occasion]])
      amount <- amount * exp(
        -clearance / 20 * (times[[row]] - last_time)
      )
      if (evid[[row]] == 1L) amount <- amount + 100
      if (evid[[row]] == 0L) {
        observation[[row]] <- amount / 20 +
          .15 * sin(id * 2.07 + row * 1.21)
      }
      last_time <- times[[row]]
    }
    data.frame(
      ID = id, TIME = times, EVID = evid,
      AMT = ifelse(evid == 1L, 100, 0), CMT = 1L,
      DV = observation, MDV = evid,
      OCC = ifelse(times < 24, 1L, 2L)
    )
  }))
}

nlmixr2_blq_data <- function(method = c("m3", "m4"), n = 24L) {
  method <- match.arg(method)
  data <- nlmixr2_population_data(n)
  data$CENS <- 0L
  data$LLOQ <- 1.8
  censored <- data$MDV == 0L & data$DV < data$LLOQ
  data$CENS[censored] <- 1L
  data$DV[censored] <- data$LLOQ[censored]
  if (identical(method, "m4")) data$LIMIT <- 0
  data
}

nlmixr2_timevarying_data <- function(n = 24L) {
  times <- c(.5, 1, 2, 4, 8, 12)
  standardized <- as.numeric(scale(
    stats::qnorm((seq_len(n) - .5) / n)
  ))
  do.call(rbind, lapply(seq_len(n), function(id) {
    weight <- seq(52, 90, length.out = n)[[id]] +
      4 * sin(times / 3 + id * .37)
    eta <- sqrt(.1) * standardized[[id]]
    clearance <- 2 * exp(.7 * (weight - 70) / 20 + eta)
    prediction <- 100 / 20 * exp(-clearance / 20 * times)
    data.frame(
      ID = id, TIME = times, EVID = 0L, AMT = 0, CMT = 1L,
      DV = prediction +
        .12 * sin(id * 1.91 + seq_along(times) * 1.31),
      MDV = 0L, WT = weight
    )
  }))
}

nlmixr2_mixture_data <- function(n = 30L) {
  do.call(rbind, lapply(seq_len(n), function(id) {
    component <- if (id <= 19L) 1L else 2L
    center <- c(1.2, 4.1)[[component]]
    observation <- center +
      .25 * sin(id * 1.41 + seq_len(4L) * 1.13)
    data.frame(
      ID = id, TIME = seq_len(4L), EVID = 0L, AMT = 0,
      CMT = 1L, DV = observation, MDV = 0L
    )
  }))
}

nlmixr2_prior_data <- function() {
  values <- c(2.1, 2.3, 2.4, 2.2, 2.5)
  data.frame(
    ID = seq_along(values), TIME = 0, EVID = 0L, AMT = 0,
    CMT = 1L, DV = values, MDV = 0L
  )
}
