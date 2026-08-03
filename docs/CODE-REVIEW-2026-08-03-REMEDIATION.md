# Post-review remediation record - 2026-08-03

This record closes the residual work identified in
`CODE-REVIEW-2026-08-03-VERIFICATION.md` and binds the behaviour changes to the
`0.9.0-research-beta.11` compatibility set.

## Residual findings closed

1. **Native pointer ownership:** LibeRtAD program/tape pointers are private R6
   state with a read-only `has_tape()` query and guarded semantic restoration.
   LibeRation's engine pointer is read-only.
2. **ADDL parity boundary:** every supported engine input is canonicalized by
   one ADDL materializer; the materialized dataset is marked; every native
   entry point rejects an unexpanded ADDL record. Expansion remains deliberate
   preprocessing rather than duplicated event logic in each C++ path.
3. **Extraction independence:** the default policy is `required`. Legacy
   booleans migrate to `required`/`preferred`; preferred same-model output is
   review-only and the gate decision is retained in provenance.
4. **Endpoint freshness:** MIC-dependent endpoints have a finite default age.
   Missing or stale evidence fails unless an actor supplies an explicit reason,
   which is retained with source evidence and assessment time.
5. **Marginal covariance:** GQ, IMP, and SAEM use estimator-specific observed
   marginal score information at the final fit instead of ordinary
   `optimHess`. Proposal adaptation is held fixed and that finite-sample
   convention is disclosed; it is not described as an exact fully adaptive
   marginal Hessian.
6. **Design approximation:** new LibeRality designs default to the externally
   cross-validated `fo_block` convention. Design schema version 2 stores the
   selection and migrates older saved designs deterministically.

Additional packaging work changed C++ implementation includes from `.ipp` to
portable `.h` names, removed namespace state from `.GlobalEnv`, corrected
optional dependency declarations, and made CI fail on every unexplained NOTE.

## Qualification completed

- Exact-version source installation on Windows/R 4.6.0: passed for all six
  packages.
- `R CMD check --as-cran`: five packages passed in the aggregate run;
  LibeRation's sole stale GUI-copy assertion was corrected and its complete
  rerun finished with 0 errors, 0 warnings, and the allowlisted Windows
  `-Wa,-mbig-obj` NOTE.
- Cross-package integration check: passed.
- Targeted pointer, ADDL, covariance, extraction-policy, endpoint-freshness,
  and design-migration suites: passed.
- Paired NONMEM estimation-method campaign, including all supported estimation
  methods: passed and complete.
- PopED 0.7.0 / PFIM 7.0.3 external design validation: all supported
  comparisons passed.
- Matrix-AD and covariance-repair smoke campaigns: passed.
- Ubuntu 22.04 / R 4.1.2 source build in WSL: passed.
- Strict production systemd preflight, encrypted two-core worker smoke, and
  eight-job concurrent queue campaign: passed. Retained JSON evidence is under
  `validation/liberties/deployment/results/`.

Real-browser tests were deliberately not run in this remediation pass in line
with the operator's instruction to stop the previously hanging bounded visual
checks. Non-browser hosted-GUI and server-construction tests remained active.

## Released compatibility identities

- LibeRtAD 0.8.0
- LibeRation 0.10.0
- LibeRary 0.8.0
- LibeRator 0.4.0
- LibeRality 0.3.0
- LibeRties 0.8.0

Breaking behaviours and caller actions are documented in
`MIGRATION-0.9.0-research-beta.11.md` and each package's NEWS file.
