# Estimator conformance remediation — 10 August 2026

## Scope and claim boundary

This remediation covers the estimators whose preceding implementation audit
did not return an unqualified **Correct** verdict: ITS, GQ, IMP, SAEM/f-SAEM,
NUTS, NPML, and NPAG. The deterministic FO, FOCE, FOCEI, Laplace, BAYES, and
static HMC implementations were not redefined by this work.

`nonmem_compatibility` means that the public estimator identity, update
equations, relevant control interpretation, and matched numerical behaviour
are aligned with the documented NONMEM method. It does not claim the same
proprietary implementation, random-number stream, stopping decisions, or
bitwise output. `liber_optimized` preserves the estimator's target and
defining recurrence while permitting different, explicitly reported proposal,
batching, cache, and optimization strategies.

## Remediation summary

| Method | Previous concern | Corrected implementation | Compatibility/optimization boundary |
|---|---|---|---|
| ITS | The implementation behaved like conditional-Gaussian quadrature EM, which is not NONMEM ITS. | Each iteration now finds conditional modes, estimates first-order conditional covariance, updates THETA/SIGMA at the modes, and updates OMEGA from the mean conditional second moment `eta_hat eta_hat' + Var(eta \| y)`. | Compatibility defaults to one approximate population optimizer step per cycle. Optimized mode may solve that same fixed-mode M-step more completely; it does not change the ITS approximation. |
| IMP | A direct optimization of one finite common-random-number marginal approximation was labelled IMP. | Default IMP is importance-sampling Monte-Carlo EM: every E-step obtains normalized importance weights and the M-step optimizes their fixed complete-data expectation with its exact CppAD gradient. | New independent E-step samples are used in both policies. The old finite-CRN marginal optimizer remains available only as the explicitly named `imp_algorithm = "marginal_ml"` alternative. Optimized batching and mode caching do not change the MCEM target. |
| GQ | The adaptive-node score omitted derivatives of node movement, yet could determine the returned optimum. | GQ is explicitly described as finite tensor/Smolyak Gauss–Hermite integration. Compatibility optimizes the complete finite-grid objective without claiming a node-movement derivative. | Optimized mode may use the normalized quadrature score as a search direction, but always finishes with a derivative-free refinement of the complete adaptive-grid objective before returning the estimate. |
| SAEM | The running state could be interpreted as an average of sampled objectives rather than the canonical auxiliary function. | The engine retains the complete-data auxiliary function through a Robbins–Monro recurrence and performs the M-step against that retained state. Sufficient-statistic OMEGA/SIGMA updates are checked against the same recurrence. | Compatibility retains the random-walk Metropolis kernel and NONMEM-aligned schedule. Optimized f-SAEM changes only the invariant Metropolis proposal (including proposal-density correction and a rescue mixture), not the posterior target or SA recurrence. |
| NUTS | The earlier dynamic HMC path was closer to classic slice NUTS and lacked several modern Stan-family mechanics. | Optimized NUTS now has multinomial progressive trajectory selection, generalized U-turn termination using accumulated momentum and both endpoint velocities, dual-averaged step size, robust bounded initialization, three-stage warmup, regularized diagonal/dense/block metrics, and E-BFMI. | Compatibility retains the established classic-slice and diagonal-metric defaults. The optimized sampler is **Stan-aligned, not Stan-identical**: it does not claim Stan Services identity, Stan's complete transform library, or bitwise-equivalent adaptation. |
| NPML | A fast weight solver risked obscuring the fixed-support NPML identity. | NPML is explicitly a constrained maximum-likelihood fit over a fixed user/initial ETA support. The compatibility EM solver and optimized interior/KKT solver are tested against the same mixture likelihood. | The optimized solver changes numerical solution strategy only. Population-parameter alternation is reported separately and is not silently included in the NPML name. |
| NPAG | The name could imply reproduction of one proprietary NPAG implementation. | The implementation is explicitly qualified as adaptive-grid nonparametric maximum likelihood: it expands/prunes support and re-solves the same constrained mixture likelihood. | Optimized native likelihood grids and weight solves preserve that objective. No claim of algorithmic identity to a proprietary NPAG program is made. |

## Evidence

The focused estimator unit suites cover the fixed-expectation CppAD gradient,
ITS conditional moments, finite GQ integral, IMP MCEM state, SAEM
Robbins–Monro recurrence, compatibility/optimized objective invariance,
nonparametric solver equivalence, native/R sampler agreement, multinomial
selection, and generalized U-turn criterion.

The release-profile independent plus matched-NONMEM campaign is retained under
`validation/estimation-methods/results/20260810-algorithm-conformance-nonmem-release/`.
It passed every declared check for all 13 estimators. On that fixture, ITS
estimated THETA1 as 2.1076395 versus NONMEM's 2.10254 (absolute difference
0.0050995), and the maximum ETA1 difference was 0.0022823. GQ differed from
the independently integrated marginal optimum by 2.39e-7, IMP by 0.00393,
and SAEM by 0.01417. Optimized NUTS had R-hat 1.0195, bulk ESS 393.5, no
divergences, and a posterior-mean difference of 0.00534 from the independently
normalized posterior. Broader multi-parameter and structural scenarios remain
necessary for production qualification.

The optimized-policy release-profile campaign is retained under
`validation/estimation-methods/results/20260810-algorithm-conformance-optimized-release-v2/`.
All applicable independent-reference checks passed; its NONMEM rows are
deliberately `not-run` because NONMEM comparison qualifies the compatibility
policy. Optimized NUTS differed from the independent posterior by 0.01570 in
the mean and 0.00268 in the SD, with R-hat 1.0074, bulk ESS 462.9, and no
divergences.

## Follow-on hardening (11 August 2026)

The seven remaining audit qualifications were addressed without redefining an
estimator target:

| # | Finding | Resolution |
|---:|---|---|
| 1 | Final conditional-mode failure could be reported only diagnostically. | Deterministic nested estimators now reject the population estimate if any final subject mode is non-converged. |
| 2 | NPML support could be pruned despite the fixed-support estimator name. | NPML now retains every initial/user support point. A nonzero pruning threshold is ignored with a warning. |
| 3 | NPAG pruning lacked an explicit likelihood acceptance guard. | Every proposed support reduction is followed by weight re-optimization and is accepted only if the mixture log likelihood does not decrease beyond numerical tolerance. |
| 4 | Bayesian reported objectives could be mistaken for likelihood OFVs. | BAYES/HMC/NUTS scores carry a machine-readable non-comparable posterior-objective type; AIC, BIC, and likelihood-ratio deltas are suppressed in favour of WAIC/PSIS-LOO. |
| 5 | SAEM replicas were ranked by stochastic auxiliary histories. | Sequential replicas are now ranked by one shared-seed, normalized marginal importance-sampling score. |
| 6 | Accelerated/support-compressed SAEM could retain an unqualified SAEM label. | Fits explicitly report canonical SAEM, accelerated SAEM, accelerated f-SAEM, or support-pruned approximate accelerated SAEM according to their finite execution policy. |
| 7 | Conformance evidence was concentrated on a compact one-parameter fixture. | The executable matrix now covers all 13 public estimators across correlated ETAs, covariates, combined error, posterior geometry, multidimensional nonparametric supports, IOV, ODEs, BLQ, compiled user likelihoods, and near-boundary parameters under each applicable numerical policy. |

The expanded matrix exposed and led to correction of a zero-random-effect IMP
Fisher-proposal edge case. These checks increase internal conformance evidence;
they do not expand the external-validation claim beyond the separately recorded
NONMEM and independent-comparator campaigns.

## Further NUTS opportunities

Dense and block metrics, three-stage warmup, bounded initialization, and
E-BFMI were added after the original audit. Remaining opportunities are mainly
operational: parallel-chain execution, richer warmup telemetry, automated
reparameterization advice, and broader external comparison against CmdStan on
correlated, funnel-like, ODE, and IOV posteriors. These additions improve
diagnosis and throughput but are not required for algorithmic NUTS correctness.
