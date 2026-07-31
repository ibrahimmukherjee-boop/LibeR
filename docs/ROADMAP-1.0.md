# LibeR 1.0 release roadmap

Status: proposed
Roadmap baseline: 2026-07-26
Current ecosystem release: `0.9.0-research-beta.10`

Post-1.0 clinical-pharmacology functionality is tracked separately in
[`ROADMAP-1.1.md`](ROADMAP-1.1.md). Core NCA is now a candidate 1.0 capability;
BA/BE, dose proportionality, and specialised NCA workflows remain out of scope.

## 1. Release definition

LibeR 1.0 is a coordinated, research-grade and production-quality release for
academic, teaching, and pharmaceutical research workflows. Version 1.0 defines
a stable public API, stable workspace and wire contracts, a documented support
boundary, and independently supported scientific claims.

Version 1.0 does **not** by itself qualify LibeR for autonomous clinical use,
regulated clinical decision support, or regulatory submission. Those uses
require separate intended-use, quality-system, risk-management, validation, and
governance programmes.

The 1.0 release contract is:

- stable and documented R APIs, model contracts, workspaces, and job/result
  schemas;
- forward migration of supported pre-1.0 projects and server state;
- independently validated first-class numerical capabilities;
- reproducible results within declared numerical and platform tolerances;
- supported Windows, Linux, and macOS installations;
- reliable local and remote execution;
- explicit `validated`, `verified`, `experimental`, and `not qualified`
  evidence language; and
- semantic-versioning and deprecation policies for subsequent 1.x releases.

References:

- Semantic Versioning 2.0.0: https://semver.org/
- ISO/IEC 25010:2023 product quality model:
  https://www.iso.org/standard/78176.html
- NIST Secure Software Development Framework:
  https://csrc.nist.gov/pubs/sp/800/218/final
- OWASP Application Security Verification Standard:
  https://owasp.org/www-project-application-security-verification-standard/
- WCAG 2.2: https://www.w3.org/TR/WCAG22/

## 2. Scope freeze and support tiers

Before the validation campaign, every capability in
`LibeRation/inst/ecosystem/support-matrix.csv` must be assigned to one of the
following release classes:

1. **Supported**: included in the 1.0 compatibility promise and independently
   validated.
2. **Experimental**: opt-in, clearly labelled, and outside the 1.0 numerical
   compatibility guarantee.
3. **Not qualified**: present only for research into a future release and not
   promoted as an operational capability.

Every capability that is currently `verified` must either obtain independent
validation evidence, retain an experimental label, or be removed from the
first-class interface. New major model families are frozen once the 1.0 scope
is approved.

The following boundaries remain explicit:

- LibeRator is for research and teaching until separately clinically qualified.
- LibeRary extractions require human review and are not machine-qualified
  evidence.
- large/general SDE, DDE, DAE, QSP, PBPK, and hybrid models may remain
  experimental where the validated numerical envelope is narrower;
- hostile-code isolation requires operating-system, container, or virtual
  machine controls outside an ordinary R subprocess; and
- regulatory-submission readiness is a later programme.

## 3. Scientific validation programme

### 3.1 Mandatory validation matrix

Exercise all scientifically valid combinations of:

- ADVAN1-14 and their supported TRANS parameterisations;
- bolus, oral, infusion, multiple-dose, ADDL, lagged, and steady-state events
  where structurally meaningful;
- one-, two-, three-, general linear, ODE, stiff ODE, nonlinear elimination,
  and equilibrium DAE models;
- FO, FOCE, FOCEI, Laplace, ITS, GQ, IMP, SAEM, BAYES, HMC, NUTS, NPML, and
  NPAG estimation;
- covariance, empirical Bayes/posthoc estimates, simulations, and diagnostics;
- diagonal/full OMEGA, IOV, nested/crossed effects, mixtures, priors,
  time-varying covariates, BLQ, and correlated endpoints; and
- continuous, categorical, count, event-time, competing-risk, Markov, HMM,
  state-space, SDE, DDE, DAE, QSP, and optimal-design workflows within their
  declared supported scopes.

Do not use a mechanically complete Cartesian product containing invalid
combinations. Fully enumerate high-risk interactions such as steady state,
infusions, stiff solvers, retaping, covariance, mixtures, BLQ, correlated
variance structures, and stochastic estimation. Use a documented pairwise
covering design for lower-risk interactions.

### 3.2 Independent references

Use the most appropriate independent implementation or analytic result:

- NONMEM/PsN for classical PK/PD, estimation, covariance, and compatible
  likelihood models;
- nlmixr2/rxode2 and Monolix, where available;
- Stan/Torsten for Bayesian and selected likelihood models;
- PopED and PFIM for optimal design;
- KFAS, hmmTMB, pomp, bssm, deSolve, and Julia SciML for specialised numerical
  families; and
- independently derived closed-form, exhaustive-enumeration, conservation,
  convergence, and Monte Carlo references where no universal comparator
  exists.

The expected result and tolerance for every definitive fixture must be approved
before its result is examined.

### 3.3 Initial numerical acceptance thresholds

These are default protocol thresholds, to be tightened or adapted per fixture
before execution:

- closed-form predictions: absolute or relative error at most `1e-8`;
- ODE/DDE/DAE predictions: at most `1e-5`, or a declared
  solver-tolerance-scaled limit;
- AD gradients: relative error at most `1e-5` at differentiable,
  well-conditioned points;
- Hessians: relative error at most `1e-4`;
- deterministic estimation: the same likelihood basin and parameter
  differences at most 2% or 0.1 reference standard errors;
- normalized objective difference: at most `1e-4` per observation, unless a
  scientifically justified method-specific threshold is preregistered; and
- stochastic estimation/simulation: bias, coverage, quantiles, and diagnostics
  within preregistered Monte Carlo confidence bounds rather than seed-identical
  output.

Targets:

- at least 50 deterministic canonical fixtures;
- at least 20 stochastic/calibration fixtures, normally with 500-1,000
  replications;
- at least 15 real-project reanalyses;
- at least 1,000 ordinary end-to-end jobs during the pilot; and
- at least 10,000 synthetic queue jobs for load, recovery, and durability
  testing.

## 4. Real-life pilot

The pilot must include:

1. oral one-compartment sparse PK;
2. IV bolus and infusion PK;
3. two- and three-compartment PK;
4. multiple dosing and steady state;
5. nonlinear elimination or TMDD;
6. ODE-based indirect-response or disease-progression PD;
7. covariate modelling and SCM;
8. IOV, correlated OMEGA, and combined residual error;
9. BLQ observations;
10. categorical or count modelling;
11. TTE or recurrent-event modelling;
12. Markov and HMM modelling;
13. Bayesian estimation;
14. PopED/PFIM-matched optimal design; and
15. multi-user remote execution, interruption, restart, and recovery.

At least five projects must come from independent external users rather than
being constructed around known LibeR strengths. At least three must be blinded
reanalyses of completed studies, comparing scientific conclusions as well as
numerical output.

The environment matrix includes:

- Windows local execution;
- at least two independently administered Linux server installations;
- multiple browsers and display sizes;
- clean installations and upgrades from the current beta;
- interrupted network connections and restarted workers/servers; and
- backup restoration into a clean installation.

No directly identifying patient information is entered into the pilot
workbook. Public, synthetic, or appropriately de-identified data must be used.

## 5. People and testing effort

Recommended participation:

| Role | People | Target hours |
|---|---:|---:|
| Release lead/product owner | 1 | 300 |
| Independent senior pharmacometricians | 2 | 360 |
| Numerical methods/C++ reviewer | 1 | 160 |
| Security/deployment reviewer | 1 | 120 |
| R/Shiny/accessibility QA reviewers | 1-2 | 160 |
| Documentation/onboarding reviewer | 1 | 80 |
| External pilot users | 18 | 360 |
| **Total** | **22-26** | **approximately 1,540** |

The 18 external users should preferably include six Master's-level/new users,
six PhD/postdoctoral or academic modellers, and six experienced industry
pharmacometricians. Reserve an additional 600-1,000 engineering hours for
defect investigation and remediation.

A reduced minimum programme is 12 independent participants and 900 testing
hours, but it provides materially lower confidence and should be disclosed as
such.

## 6. Engineering quality gates

### 6.1 Correctness and compatibility

- `R CMD check` passes for every package on Windows, Linux, and macOS with no
  errors, warnings, or unexplained notes.
- Current, previous, and development R releases are exercised.
- GCC, Clang, and current Windows Rtools are exercised.
- Cross-package model, workspace, job, and result contracts pass from an
  isolated installation.
- Workspace and wire migrations are tested forward, interrupted, resumed, and
  rolled back.
- Every exported function is documented and has at least one executable test.

### 6.2 Test depth

- at least 80% line coverage overall;
- at least 90% coverage of numerical contracts, migrations, authentication,
  and queue-state transitions;
- mutation score at least 70% overall and 80% for critical contracts;
- AddressSanitizer/UndefinedBehaviorSanitizer and memory-leak campaigns for C++;
- property-based tests of event handling, serialization, and numerical
  invariants;
- parser, upload, and job-contract fuzzing; and
- no unresolved race, corruption, cancellation, or duplicate-submission defect.

Coverage is evidence of exercised code, not a substitute for independent
scientific validation.

### 6.3 Performance and user experience

- no unexplained median performance regression above 10% on the canonical
  benchmark suite;
- common local UI interactions respond within 200 ms;
- long-running operations do not block the complete browser interface;
- the GUI is checked in current and previous Chrome, Edge, Firefox, and Safari;
- WCAG 2.2 AA is met, including keyboard access, visible focus, contrast,
  accessible dialogs, and alternatives to drag-only interactions;
- at least 90% completion of ordinary usability tasks;
- 100% completion of destructive-confirmation and recovery tasks; and
- median System Usability Scale score at least 80.

### 6.4 Security and supply chain

- development practices are mapped to NIST SSDF;
- remotely exposed applications are assessed against OWASP ASVS 5.0 Level 2
  where applicable;
- an independent penetration test receives 40-80 hours;
- no known critical or high-severity vulnerability remains;
- secrets, dependencies, licences, and vulnerabilities are scanned;
- a software bill of materials, SHA-256 checksums, and build provenance are
  published; and
- TLS, authentication, authorization, tenant separation, quotas, audit logs,
  backup, restore, and incident response are tested.

### 6.5 Operational resilience

- a 72-hour server soak completes without state corruption or lost jobs;
- cancellation, duplicate submission, worker crash, server restart, network
  interruption, storage pressure, and partial-result handling are exercised;
- a backup is restored into a clean deployment;
- the release can be rolled back without losing supported workspaces; and
- installation, upgrade, diagnostic bundle creation, and uninstallation are
  documented and tested.

## 7. Release sequence

| Phase | Duration | Exit output |
|---|---:|---|
| Scope and API freeze | 2 weeks | Approved support matrix and acceptance protocol |
| Scientific matrix expansion | 6-8 weeks | Complete automated validation evidence |
| Engineering/security hardening | 6 weeks, overlapping | Coverage, sanitizers, security, and performance gates |
| External pilot | 8-12 weeks | Real projects, usability evidence, and issue log |
| `1.0.0-rc.1` | 2-3 weeks | Feature-complete candidate |
| `1.0.0-rc.2` | 2-3 weeks | Fixes and documentation only |
| Quiet period | 14-30 days | No new severe defect |
| `1.0.0` | 1 week | Signed coordinated release |

The expected calendar duration is 7-9 months, depending on the remediation
load found during independent testing.

## 8. Release governance and final decision

The release-readiness group contains at least:

- the release lead;
- one independent senior pharmacometrician;
- one numerical-methods reviewer; and
- one security/operations reviewer.

LibeR 1.0 is released only when:

- 100% of the mandatory first-class matrix passes;
- no Severity 1 or Severity 2 defect remains open;
- no critical or high security issue remains;
- the pilot has run for 30 consecutive days without a new Severity 1 or
  Severity 2 defect;
- external usability and real-project thresholds pass;
- upgrade, rollback, backup, and recovery tests pass;
- manuals, vignettes, examples, and support claims match the release;
- two consecutive clean full release builds pass; and
- all four release-readiness roles sign off.

No single reviewer may override a failed scientific or security gate. A failed
gate is fixed, narrowed out of the supported scope, or carried into a new
release candidate with an explicit decision record.
