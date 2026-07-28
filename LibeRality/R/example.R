#' A complete teaching example
#'
#' Creates a two-arm oral PK design with sampling-time and allocation variables,
#' parameter uncertainty, operational constraints, and representative criteria.
#' @return A list containing model, design, and criteria.
#' @examples
#' example <- lity_example()
#' result <- lity_evaluate(example$design, lity_criterion_D())
#' result$criterion
#' @export
lity_example <- function() {
  model <- LibeRation::nm_model(
    INPUT = c("ID", "TIME", "EVID", "AMT", "RATE", "CMT", "DV", "MDV", "DVID", "WT"),
    ADVAN = 2L, TRANS = 2L, DOSECMP = 1L, OBSCMP = 2L,
    PRED = paste(
      "KA=THETA(1)*exp(ETA(1))",
      "CL=THETA(2)*(WT/70)^0.75*exp(ETA(2))",
      "V=THETA(3)*(WT/70)*exp(ETA(3))",
      "S2=V", sep = ";"
    ),
    ERROR = "Y=F*(1+ERR(1))",
    THETAS = data.frame(THETA = 1:3, Value = c(1.2, 4, 35),
                        LOWER = c(0.05, 0.1, 1), UPPER = c(5, 20, 200)),
    OMEGAS = data.frame(OMEGA = 1:3, Value = c(0.20, 0.10, 0.15)),
    SIGMAS = data.frame(SIGMA = 1, Value = 0.15), COVARIATES = "WT"
  )
  attr(model, "name") <- "One-compartment oral PK"
  rich <- lity_arm(
    "Rich PK", lity_schedule(c(0.25, 0.5, 1, 2, 4, 8, 12, 24), dose = 500,
                              dose_cmt = 1, observation_cmt = 2, covariates = list(WT = 70)),
    size = 18, allocation = 0.3,
    costs = list(fixed = 3000, per_subject = 900, per_visit = 100, per_sample = 28, assay = 35),
    sample_volume = 3
  )
  sparse <- lity_arm(
    "Sparse PK", lity_schedule(c(1, 4, 12, 24), dose = 500,
                                dose_cmt = 1, observation_cmt = 2, covariates = list(WT = 70)),
    size = 42, allocation = 0.7,
    costs = list(fixed = 1500, per_subject = 550, per_visit = 80, per_sample = 28, assay = 35),
    sample_volume = 3
  )
  scenarios <- list(
    nominal = lity_scenario("Nominal", probability = 0.5),
    slow = lity_scenario("Slow clearance", theta = c(0.9, 2.8, 35), probability = 0.2),
    fast = lity_scenario("Fast clearance", theta = c(1.5, 6, 40), probability = 0.2),
    operational = lity_scenario("Operational loss", probability = 0.1,
                                 dropout = 0.1, adherence = 0.92, missed_sample = 0.08)
  )
  variables <- list(
    sparse_t1 = lity_variable("Sparse sample 1", "sampling_time", "Sparse PK", 1,
                              lower = 0.2, upper = 3),
    sparse_t2 = lity_variable("Sparse sample 2", "sampling_time", "Sparse PK", 2,
                              lower = 2, upper = 8),
    sparse_t3 = lity_variable("Sparse sample 3", "sampling_time", "Sparse PK", 3,
                              lower = 8, upper = 18),
    rich_size = lity_variable("Rich arm size", "arm_size", "Rich PK", type = "integer",
                              lower = 10, upper = 35),
    sparse_size = lity_variable("Sparse arm size", "arm_size", "Sparse PK", type = "integer",
                                lower = 25, upper = 70)
  )
  constraints <- list(
    separation = lity_constraint("At least 30 minutes between samples", "min_separation", 0.5),
    subjects = lity_constraint("At most 90 subjects", "total_subjects", 90),
    blood = lity_constraint("At most 30 mL per subject", "max_blood_volume", 30),
    budget = lity_constraint("Study budget", "total_cost", 100000)
  )
  design <- lity_design(
    model, arms = list(rich = rich, sparse = sparse),
    endpoints = list(pk = lity_endpoint("Plasma concentration", "continuous", dvid = 1)),
    scenarios = scenarios, variables = variables, constraints = constraints,
    name = "Oral PK population design",
    description = "Teaching design spanning rich and sparse sampling cohorts.",
    metadata = list(model_provenance = list(
      source = "Built-in", template = "teaching-oral-pk",
      label = "One-compartment oral PK",
      parameter_source = "template values"
    ))
  )
  criteria <- list(
    local_D = lity_criterion_D(name = "Local D-optimality"),
    robust_D = lity_criterion_robust(lity_criterion_D(), name = "Expected robust D-optimality"),
    max_rse = lity_criterion_rse(summary = "max", name = "Worst parameter RSE"),
    cost = lity_criterion_cost(name = "Total study cost")
  )
  list(model = model, design = design, criteria = criteria)
}
