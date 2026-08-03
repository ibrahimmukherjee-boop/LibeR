# LibeR algorithm inventory and final pre-1.0 gap review

Review date: 2026-07-31
Repository baseline: `0.9.0-research-beta.11`

## Executive assessment

LibeR already contains a broader modelling and estimation surface than most
single pharmacometric applications. No fundamental classical population PK/PD
engine family is obviously absent. The principal pre-1.0 workflow gaps
identified by this review—MU referencing, sampling importance resampling,
first-class reproducible model comparison, Bayesian PPC/WAIC/PSIS-LOO, and
broader bootstrap designs—have now been implemented.

The principal NCA gap has now been addressed with an independent native C++
engine and external `ncar`/`NonCompart` comparison. BA/BE, dose
proportionality, and specialised NCA workflows remain clinical-pharmacology
items for 1.1.

## 1. Current algorithm surface

### LibeRtAD

- direct CppAD/Eigen automatic differentiation;
- scalar/vector values, gradients, Jacobians, and Hessians;
- sparse Jacobian/Hessian paths and graph optimization;
- dynamic parameters and structural tape sharing;
- tape validity guards and automatic retaping;
- persistent portable graph caches with dependency provenance;
- Gauss-Hermite and sparse Smolyak quadrature; and
- derivative and performance benchmarking.

### LibeRation: propagation and model specification

- ADVAN1-14, analytical compartmental kernels, matrix exponentials, explicit
  and stiff ODEs, Michaelis-Menten elimination, and equilibrium DAE paths;
- bolus, oral, infusion, modelled rate/duration, multiple dosing, and analytical
  or nonlinear periodic steady state;
- editable `$PK/$PRED`, `$DES`, `$ERROR`, and likelihood configuration;
- R-like and restricted C++ model expressions;
- nonlinear elimination, transit/parallel absorption, parent-metabolite,
  effect-compartment, indirect-response, tumour-growth, and TMDD templates;
- SDE, DDE, index-1 DAE, QSP reaction networks, and immutable learned/hybrid
  components within declared experimental envelopes; and
- linear, EKF, UKF, particle, and switching state-space propagation.

### LibeRation: population estimation

- FO, FOCE, FOCEI, Laplace, ITS, GQ, IMP, SAEM, BAYES, HMC, NUTS, NPML, and
  NPAG;
- sequential/multi-stage estimation with compatible warm starts;
- conditional individual fitting and empirical Bayes estimates;
- exact or score-based gradients according to estimator;
- native C++ HMC/NUTS trajectories and batched population kernels;
- diagonal and full OMEGA, IOV, nested/crossed random effects, priors, mixtures,
  and time-varying covariates; and
- additive, proportional, combined, lognormal, correlated-endpoint, AR(1), and
  ARMA residual structures.

### LibeRation: outcome and latent-state models

- Bernoulli, binomial, categorical, ordinal, Poisson, negative-binomial,
  zero-inflated, and hurdle likelihoods;
- TTE, recurrent-event, and competing-risk likelihoods;
- observed Markov and arbitrary-state continuous-time Markov models;
- HMM, continuous-time HMM, HSMM, factorial HMM, filtering, retrospective
  smoothing, and Viterbi decoding; and
- Gaussian and nonlinear state-space models with particle likelihoods.

### LibeRation: uncertainty, diagnostics, and workflows

- Hessian/R, OPG/S, sandwich covariance, fallback, eigenvalue, and
  condition-number diagnostics;
- standard errors, relative standard errors, parameter correlations, EBE
  tables, and ETA shrinkage;
- subject/cluster-level stratified and parametric bootstrap, profile
  likelihood, and sampling importance resampling;
- posterior predictive checks, subject-marginal WAIC and PSIS-LOO;
- serializable model comparisons with AIC/BIC weights, explicitly declared
  nested LRTs, boundary warnings, and optional bootstrap calibration;
- SCM with nested re-estimation and likelihood-ratio thresholds;
- PRED/IPRED, RES/IRES/WRES/IWRES/CWRES, VPC, prediction-corrected VPC, NPDE,
  NPC, and specialised categorical/count/TTE/recurrent/competing-risk VPCs;
- simulation, output-column discovery, reporting, model comparison display,
  NONMEM control-stream import/export, and visual model/report builders; and
- durable project/version/run/diagnostic storage.

### LibeRality

- population-FO Fisher information;
- D-, A-, Ds-, E-, c-, L-, Bayesian, robust, maximin/minimax, compound,
  model-discrimination, prediction, power, RSE, utility, burden, cost,
  precision-probability, target, correct-dose, model-average, and Pareto
  criteria;
- discrete and continuous design optimisation, constraints, robustness,
  scenarios, trial simulation, and operating characteristics; and
- PopED/PFIM external-validation infrastructure.

### LibeRator

- longitudinal patient evidence;
- missing/intermittent covariate handling;
- sequential individual-parameter updating;
- endpoint libraries for AED, ATG, and beta-lactam examples;
- candidate-regimen generation, endpoint-aware optimisation, and prospective
  prediction; and
- auditable research/teaching workspaces.

### LibeRary and LibeRties

- literature discovery, abstract triage, document parsing, deliberative
  text/vision extraction, adjudication, provenance, catalogue qualification,
  reference-corpus benchmarking, and LibeRation import;
- typed local/remote jobs and results, queue durability, cancellation/recovery,
  authentication, quotas, audit logs, and administrative workflows.

## 2. Missing or insufficiently first-class capabilities

### Priority 0: resolve before 1.0 scope freeze

#### A. MU modelling / MU referencing

**Status:** implemented as serializable `nm_mu` metadata, generated editable
model code, subject-level covariate validation, model-contract v4, NONMEM
control-stream round-tripping, symbolic affine/link classification, bounded
vectorized/cached GLS SAEM updates, closed-form-only M-steps,
Metropolis-corrected BAYES MU blocks, and MU-preserving IMP mode warm starts.
Subject-varying MU designs receive an exact finite-CRN IMP refinement. Unsafe
or non-identifiable structures fall back with an explicit fit diagnostic.

**Why it matters:** MU referencing is an expected NONMEM compatibility feature
and can materially improve EM/SAEM/BAYES updates and model portability.

**Qualification:** paired conventional/MU and external MU-referenced NONMEM
FOCEI/IMP/SAEM controls now compare population/individual estimates,
fresh-process and core runtime, and LibeRation specialization telemetry. The
100-subject, three-repeat standard campaign passed all 33 preregistered
estimate/ETA checks. The generalized matrix also passes scenarios with two
ETAs, estimated diagonal or correlated OMEGA, estimated SIGMA, and an
estimated weight relationship. Vectorized GLS and the closed-form-only M-step
reduced the standard specialized SAEM core time from 3.76 to approximately
1.92 seconds across three measured runs. The remaining product integration is
to let SCM/GUI generators produce common log-normal MU covariate relationships
automatically.

#### B. Sampling importance resampling (SIR)

**Status:** implemented through `nm_sir()` using a heavy-tailed covariance
proposal, the exact population objective, normalized weights, ESS diagnostics,
and systematic resampling.

**Why it matters:** SIR is commonly used when asymptotic covariance is
ill-conditioned or asymmetric and a full bootstrap/profile campaign is too
expensive.

**Recommendation:** add proposal selection from covariance/sandwich/bootstrap,
importance weighting, adaptive proposal inflation, effective sample size,
resampling, convergence diagnostics, and reproducible local/remote execution.

#### C. First-class statistical model comparison

**Status:** implemented through the serializable `nm_model_comparison`
contract, `nm_compare()`, durable fingerprints/provenance, information
criteria and weights, explicitly declared nested LRTs, boundary warnings, and
optional parametric-bootstrap calibration.

**Why it matters:** a typical modeller needs a reproducible table containing
OFV, parameter count, AIC/BIC, nested likelihood-ratio tests, boundary warnings,
predictive diagnostics, and the exact compared run provenance.

**Recommendation:** add a serializable comparison result with:

- nested-model LRT and degrees-of-freedom validation;
- warnings for boundary and mixture cases where ordinary chi-square inference
  is invalid;
- optional parametric-bootstrap LRT;
- AIC, BIC, delta metrics, and model weights; and
- links to diagnostic and validation evidence.

#### D. Bayesian model checking and comparison

**Status:** implemented. HMC/NUTS report split R-hat, ESS, divergences,
tree-depth diagnostics, and traces. `nm_log_lik()` retains subject-pointwise
conditional or population-marginal predictive densities, `nm_ppc()` provides
population or conditional posterior predictive checks, and `nm_waic()` and
`nm_psis_loo()` provide predictive comparison with pointwise evidence and
Pareto-k diagnostics.

**Why it matters:** sampler convergence does not establish model adequacy.

**Recommendation:** add posterior predictive simulation/checks, pointwise
log-likelihood retention, WAIC, PSIS-LOO with Pareto-k diagnostics, and
graphical predictive summaries. If this is not implemented, describe Bayesian
estimation as supported but Bayesian model comparison as experimental.

#### E. Broader uncertainty resampling controls

**Status:** `nm_bootstrap()` now provides subject- or cluster-level
nonparametric resampling, optional subject/cluster strata, and parametric
simulation from the fitted model. Replicate seeds, failed fits, design
metadata, fitted samples, and intervals are retained.

**Remaining refinement:** add explicit occasion-level and case-residual
resampling where scientifically appropriate, BCa intervals, and queue-native
checkpoint/resume for very large campaigns.

### Priority 1: highly valuable, but may be scheduled for 1.1

#### F. Noncompartmental analysis

**Status:** implemented in LibeRation 0.10.0 and consumed by LibeRality and
LibeRator.

**Why it matters:** NCA is an everyday clinical-pharmacology and
pharmacometric workflow for AUC, Cmax, Tmax, terminal half-life, accumulation,
dose proportionality, and exposure summaries.

The first-class `nm_nca()` module now provides:

- linear-up/log-down and selectable trapezoidal rules;
- auditable terminal-phase selection and sensitivity analysis;
- single/multiple-dose and partial-AUC support;
- dose normalisation and dosing-interval exposure summaries;
- tabular/graphical reporting in LibeRality simulations; and
- executable validation and fallback against `ncar`/`NonCompart`.

Specialised sparse/composite, urine, and regulatory reporting workflows remain
future extensions and must not be inferred from the core NCA API.

#### G. Bioequivalence and dose-proportionality workflows

**Status:** not found as dedicated workflows.

**Recommendation:** after NCA, add conventional average bioequivalence,
replicate-design/reference-scaled analysis where applicable, food-effect,
dose-proportionality, and exposure-summary reporting. Treat this as
clinical-pharmacology functionality rather than part of the population engine.

#### H. Individual conditional-distribution task

**Status:** conditional modes, Hessian uncertainty, and full population
Bayesian sampling exist, but a dedicated Monolix-like task for conditional
means/medians and draws for each individual is not clearly first-class.

**Recommendation:** add reproducible individual posterior draws or quadrature
summaries, conditional mean/median/mode comparison, uncertainty intervals, and
simulation based on those draws.

#### I. Case-deletion and influence diagnostics

**Status:** not found as an explicit workflow.

**Recommendation:** add subject/cluster influence, case-deletion OFV and
parameter change, ETA influence, leverage-style diagnostics, and a queueable
jackknife. This is especially useful when sparse influential subjects determine
a covariate effect.

#### J. Cross-validation and predictive model ranking

**Status:** no general K-fold, leave-one-subject/cluster-out, or predictive
scoring workflow was found.

**Recommendation:** add grouped cross-validation with log predictive density,
RMSE/MAE where suitable, calibration, and task-aware scoring for continuous and
non-Gaussian outcomes.

### Priority 2: useful extensions rather than essential omissions

- non-normal parametric random-effect distributions beyond transformations of
  normal ETA and the existing NPML/NPAG alternatives;
- model averaging/ensembles in LibeRation rather than only design criteria;
- adaptive/higher-order SDE solvers and broader parameter-recovery campaigns;
- sparse large-scale DAE/PBPK/QSP factorization and adjoint sensitivities;
- PDE/spatial and agent-based simulation interfaces;
- automated dropout/adherence/protocol-deviation scenario libraries;
- richer causal/exposure-response estimands; and
- dedicated model-based meta-analysis workflows.

These should not delay 1.0 unless promoted into the first-class release scope.

## 3. Qualification gaps rather than algorithm gaps

Several important remaining items are not missing algorithms:

- broad simulation-estimation bias and coverage studies;
- large-state, large-ETA, thousands-of-subject scaling;
- full external qualification of verified and experimental families;
- ADVAN14 comparison with a NONMEM version that provides ADVAN14;
- formal stationarity diagnostics for SAEM;
- boundary-aware variance-component inference;
- complete per-phase optimizer timing and telemetry;
- independent deployment security testing; and
- external real-project use by people who did not design the software.

These are central 1.0 gates even though they add little visible functionality.

## 4. Recommended pre-1.0 decision

The recommended scope decision is:

1. qualify the implemented MU referencing, SIR, first-class model comparison,
   Bayesian predictive checking, and richer bootstrap controls before
   `1.0.0-rc.1`;
2. qualify the new native NCA and its independent comparison fixtures before
   making it part of the 1.0 supported surface;
3. retain bioequivalence and specialised clinical-pharmacology workflows as
   leading 1.1 roadmap items;
4. retain experimental advanced numerical families without allowing them to
   delay the supported classical and latent-state release; and
5. spend the majority of remaining pre-1.0 effort on independent validation,
   failure recovery, usability, security, and real-project qualification.
