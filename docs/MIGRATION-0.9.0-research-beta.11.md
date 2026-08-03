# Migration to 0.9.0-research-beta.11

This research-beta release deliberately replaces several silent degradations
with explicit contracts. Review the following items before moving an existing
workspace, automation, or server deployment to this compatibility set.

## Required caller changes

- **AD pointers are private.** Code that accessed `ADModel$tape_ptr`,
  `ADModel$program_ptr`, or assigned `NMEngine$pointer` must use the documented
  model/engine methods. Raw external-pointer replacement is no longer supported.
- **Outer finite-difference gradients are opt-in.** A non-finite AD gradient now
  stops estimation. `allow_fd_gradient = TRUE` is available only as an explicit,
  warned compatibility choice and is retained in derivative provenance.
- **ADDL is a canonical preprocessing contract.** All supported engine calls
  materialize ADDL records before native execution. A direct native call with
  non-zero ADDL now fails rather than silently interpreting a different event
  stream.
- **Covariance repair is opt-in.** A materially indefinite covariance matrix
  fails unless the caller selects and records a legitimate repair method.
- **Qualified clinical endpoints require attestation.** A `qualified` LibeRator
  endpoint needs issuer, reviewer, review time, evidence, scope, and an explicit
  research-use acknowledgement.
- **MIC evidence expires.** MIC-dependent endpoint evaluation rejects missing or
  stale evidence. An exceptional override must include an actor and rationale;
  the complete decision is written to the audit record.
- **Extraction independence is required by default.** LibeRary text and vision
  lanes must use distinct provider/model identities. Legacy `FALSE` settings
  migrate to `preferred`, which permits processing but makes same-model output
  review-only; select `off` only for explicitly exploratory work.
- **LibeRality defaults to `fo_block`.** New designs use the externally
  cross-validated FO block-diagonal information approximation. Version-1 saved
  designs migrate deterministically to that convention. Choose
  `full_gaussian` explicitly when its broader working approximation is intended.
- **Encrypted LibeRties stores reject plaintext records.** Migrate an existing
  plaintext queue before configuring a storage key. Production execution on
  Linux requires successful live systemd-isolation preflight; `callr` remains a
  local/research executor rather than a hostile-code sandbox.

## Covariance interpretation

FO, ITS, FOCE, FOCEI, and Laplace use the supported complete CppAD population-
objective Hessian. GQ, IMP, and SAEM use estimator-specific observed marginal
score information at the final fit with proposal adaptation held fixed. That
second result is a documented finite-sample information estimate; it is not
labelled as the exact Hessian of a fully adaptive marginal algorithm.

## Recommended upgrade sequence

Install the six package versions pinned by `ecosystem.json` together, restart R
to unload old namespaces, run `liber_doctor()`, and copy a production workspace
before its first write by the new stack. For LibeRties, run strict preflight in
the actual deployment environment rather than treating the WSL validation
evidence as an attestation for another host.
