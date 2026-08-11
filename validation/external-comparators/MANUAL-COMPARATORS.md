# Manual and licensed comparator campaign

This register describes validations that cannot be truthfully completed by the
portable open-source CI environment. A missing licence, runtime, deployment, or
independent evidence file is recorded as `not-run`, never as agreement.

## NONMEM

- Use `validation/nonmem/run-validation.R --run` with the intended NONMEM
  installation and PsN `execute` on `PATH`.
- NONMEM 7.6 directly covers ADVAN1-15 and ADVAN18 in the current campaign.
  ADVAN16/17 additionally require the separately licensed RADAR5NM extension;
  when it is absent, their direct controls are retained as `not-run` and their
  dynamics are compared with equivalent ADVAN18 controls.
- Retain control streams, data hashes, NONMEM version/build, command line,
  listing/table outputs, LibeR source identity, tolerances, and the generated
  LibeR provenance bundle.

## MonolixSuite

- Re-run the matched baseline and advanced population fixtures already used
  for NONMEM/nlmixr2, including estimated variance, correlated OMEGA, IOV,
  M3/M4 BLQ, mixtures, priors, and time-varying covariates. Add combinations
  only where parameterisations can be made identical.
- For stochastic algorithms, run repeated seeds and compare bias, empirical
  dispersion, convergence frequency, and interval coverage rather than one
  finite-sample objective.
- Export a machine-readable result table; do not automate a licensed GUI or
  redistribute proprietary binaries.

## Pumas

- Use an independently reviewed Julia script and locked project manifest.
- Separate population estimation/Bayesian comparisons from
  `Pumas.OptimalDesign` comparisons.
- Record whether objective constants, variance transforms, priors, and
  censoring conventions are identical before declaring a numerical tolerance.

## NONMEM 7.6 ADVAN16/17 with RADAR5NM

- Re-run the checked-in ADVAN16/17 controls on an installation with the
  optional RADAR5NM licence extension.
- Retain the direct result alongside the existing ADVAN18 equivalent-delay and
  ADVAN15 equilibrium-component comparisons.
- Never convert licence rejection into agreement; it remains explicit
  capability evidence with status `not-run`.

## Deployment qualification

- Run the k6 and ZAP harness from `validation/liberties/deployment/` against an
  authorised disposable environment with the production reverse proxy,
  storage key, service account, filesystem namespace, cgroup/container policy,
  and resource ceilings enabled.
- Add restart-under-load, worker termination, disk-full, payload/result-limit,
  token-expiry/rotation, cross-tenant, backup/restore, and audit-retention
  campaigns.
- Commission independent penetration testing and map evidence to the selected
  OWASP ASVS level. Neither a ZAP baseline nor an environment variable is proof
  of hostile-code containment.

## Evidence acceptance

Every imported result must identify the comparator product and version, input
hashes, execution command/configuration, random seeds, hardware/OS where
relevant, declared estimand, parameter transforms, tolerances, and reviewer.
The evidence should remain immutable alongside the corresponding LibeR commit
and package versions.
