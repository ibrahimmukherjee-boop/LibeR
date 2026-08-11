# LibeRation estimation and RADAR-family optimisation review

Date: 2026-08-06

## Scope

This review traced the current population estimators from the R coordinator to
the subject and population C++ tapes, with particular attention to BAYES,
SAEM/IMP, and the clean-room Radau IIA paths used by ADVAN16 and ADVAN17. It
also separates conservative reference numerics from opt-in LibeR-specific
accelerations so matched NONMEM work remains reproducible.

## Changes implemented

### Batched Bayesian ETA sweeps

The BAYES sampler previously evaluated one full-population objective tape for
every single-subject ETA proposal. A sweep over N subjects therefore repeated
approximately N subjects of work N times. Subject ETA proposals are now sent
through the existing batched conditional-subject C++ Metropolis kernel. This
preserves the same conditional independence factorisation, proposal covariance,
Metropolis ratio, parameter priors, and transformed-parameter Jacobian while
reducing the ETA sweep from quadratic to linear subject scaling.

Parallel workers now also return their current subject objective values. This
allows the sampler to update the joint log posterior without a redundant full
population evaluation after the sweep. Iteration logging uses the batched
conditional CppAD gradient and includes parameter-prior contributions.

### Persistent stochastic state and grouped proposal factors

The sampler now carries the exact conditional objective value of every
subject alongside its ETA state. At a fixed population-parameter point, a
Metropolis sweep therefore replays each subject tape only for the candidate;
the current value is a cache lookup. Accepted candidates replace both the ETA
and its objective value atomically. Population proposals similarly retain the
per-subject values returned by their already-required evaluation. This does
not change the Markov transition, random-number stream, or seeded result.

Proposal covariance roots are cached by exact OMEGA value and random-effect
design. Subjects with the same design share one Cholesky factor; heterogeneous
IOV or general random-effect layouts receive one factor per distinct design.
The fixed-ETA SAEM objective also has an optimized native aggregate that sums
the value and exact gradient in C++, avoiding allocation and transfer of an
N-subject by P-parameter gradient matrix. The compatibility policy retains
the established subject-order reduction. BAYES now also reports an
autocorrelation-adjusted effective sample size for every population parameter,
so performance can be judged by effective draws per second rather than raw
iterations alone. R-hat remains unavailable for its single chain; users who
need multichain diagnostics should use HMC/NUTS.

On the standard 100-subject, 800-record matched-control workload (one warm-up,
three measured fresh processes, fit only), the median core times changed as
follows:

| Method | NONMEM core | Previous optimized core | Current compatibility | Current optimized | LibeR/NONMEM core ratio | Seeded result |
|---|---:|---:|---:|---:|---:|---|
| SAEM | 3.42 s | 3.16 s | 2.04 s | 2.07 s | 0.61 | identical |
| BAYES | 22.41 s | 17.26 s | 5.02 s | 5.27 s | 0.24 | identical |

The BAYES reduction removes about 300,000 redundant current-state tape
evaluations from the standard 3,000-iteration/100-subject run. Fresh-process
end-to-end medians were 7.81 versus 2.61 seconds for NONMEM/LibeR SAEM and
26.99 versus 5.82 seconds for NONMEM/LibeR BAYES. The two LibeR policy timings
overlap at this scale because the dominant improvement is arithmetic-neutral
and is therefore safe for both paths.

Those measurements deliberately used the established SAEM random-walk and
BAYES isotropic proposal kernels. They therefore did **not** include f-SAEM or
adaptive population BAYES. A subsequent optimized-policy pass added both as
separate, auditable kernels:

- f-SAEM uses a periodically refreshed conditional Laplace approximation as
  an independent multivariate Gaussian proposal and includes the exact
  independent Metropolis-Hastings proposal-density ratio. Previous modes warm
  start later refreshes. The implementation follows the algorithmic account in
  [Karimi, Lavielle and Moulines](https://arxiv.org/abs/1910.12222); it is not
  the distinct mini-batch SAEM algorithm.
- Adaptive BAYES learns the full transformed population-parameter proposal
  covariance during burn-in, uses a diminishing scale update towards the
  0.44/0.234 scalar/multivariate acceptance targets, and freezes the proposal
  before retained sampling. It follows the adaptive-Metropolis construction of
  [Haario, Saksman and Tamminen](https://doi.org/10.2307/3318737).
- Both kernels use one persistent C++ subject collection: dynamic inputs are
  installed once and tape pointers and point buffers survive across iterations.
  BAYES additionally compiles population-prior targets/constants once and
  updates its log posterior by the exact ETA-sweep delta rather than
  reevaluating unchanged prior/Jacobian terms.

A second pass moved the complete eligible optimized-BAYES coordinator into
that persistent collection. Parameter decoding, prior and transformation-
Jacobian evaluation, population proposal generation, Welford covariance
adaptation, OMEGA factor caching, conditional ETA sweeps, and retained-chain
assembly now remain in C++. MU-referenced, expanded-IOV, ODE, parallel, and
iteration-printing cases automatically retain the general R coordinator.

The same pass made the f-SAEM proposal builder reuse the mature optimized
Laplace conditional-mode policy: scale-aware convergence, Newton-displacement
acceptance near flat optima, warm starts, bounded restart from the latest
finite mode, curvature evaluation only after mode acceptance, and bounded
positive-definite repair. A random mixture with an exact OMEGA-scaled
random-walk rescue kernel improves tail and secondary-mode exploration.
Population movement and poor independence acceptance can trigger an early
proposal refresh. The non-persistent implementation now applies the same
independence density ratio on PSOCK workers and across guarded ODE retaping.

Fresh-process standard-profile results (100 subjects, 800 records, one warm-up,
three measured processes, no covariance) were:

| Comparison | Kernel | Core | End-to-end | Acceptance | Worst ESS | Median ESS |
|---|---|---:|---:|---:|---:|---:|
| BAYES | isotropic | 1.33 s | 1.80 s | 0.285 | 24.6 | 26.0 |
| BAYES | adaptive Metropolis | 1.37 s | 1.89 s | 0.231 | 46.5 | 67.0 |
| two-ETA SAEM | random walk | 2.41 s | 2.86 s | 0.299 | n/a | n/a |
| two-ETA SAEM | f-SAEM, refresh 25 | 2.84 s | 3.33 s | 0.706 | n/a | n/a |

Adaptive BAYES therefore costs about 3% core time but yields 1.83 times the
worst-parameter ESS per second and 2.50 times median ESS per second in this
matched run. f-SAEM costs 18% more raw core time but produces approximately
twice as many accepted proposals per second; because those proposals are
independent Laplace draws rather than adjacent random-walk moves, acceptance
understates its mixing advantage. Multiple-seed accuracy/convergence studies
remain necessary before treating either one-scenario result as a universal
performance guarantee.

Using the identical saved 100-subject fixtures and controls after the second
pass (one warm-up, three measured fresh processes) gave:

| Comparison | Previous core | Current core | Previous end-to-end | Current end-to-end | Current acceptance / ESS |
|---|---:|---:|---:|---:|---|
| BAYES adaptive Metropolis | 1.37 s | 0.69 s | 1.89 s | 1.20 s | outer 0.231; worst ESS 46.5; median ESS 67.0 |
| two-ETA f-SAEM | 2.84 s | 2.64 s | 3.33 s | 3.16 s | ETA 0.777 |

Thus the native BAYES coordinator reduced core time by about 50% without
changing the seeded chain or its ESS in this fixture. Reusing the optimized
Laplace proposal path reduced f-SAEM core time by about 7%; its robust mixture
also increased total ETA acceptance in this run. These are focused local
measurements, not claims about every model topology.

`liber_optimized` now selects adaptive BAYES automatically and selects f-SAEM
automatically for models with at least two ETAs. Stable serial analytical
models use the persistent all-C++ proposal path; ODE and PSOCK models use the
guarded general path.
Explicit `outer_kernel = "isotropic"` and `saem_kernel = "random_walk"`
retain direct comparators. `nonmem_compatibility` continues to select only the
established kernels and rejects explicit optimized-kernel requests.

### ADVAN16/17 Radau IIA policy

The Radau implementation uses two independently derived optimisations without
using or inspecting proprietary RADAR5 source code:

1. Both numerical policies cache delayed history/algebraic values for repeated right-hand-side
   evaluations at the same collocation time. The minimum-delay contract means
   these values belong entirely to accepted history and do not depend on the
   current collocation state.
2. The `liber_optimized` policy additionally reuses a step-start Jacobian and
   its coupled Radau Newton factorisation
   across the step's corrections. The AD path records the corresponding
   differentiable linear inverse once and subsequently uses matrix-vector
   products.

`nonmem_compatibility` retains the earlier conservative three-stage Jacobian
path while benefiting from the arithmetic-neutral accepted-history cache, and
remains the default. ADVAN18 remains the fixed-step RK4
method-of-steps implementation; the Radau policy is only used for ADVAN16/17.

## Focused development measurements

These are local single-process microbenchmarks on eight subjects and seven
post-dose times, not a replacement for the paired NONMEM benchmark. Medians
were taken over seven simulation calls and three fresh compile/derivative calls.

| Scenario | Operation | Compatibility | LibeR optimised | Speed-up |
|---|---:|---:|---:|---:|
| ADVAN16 Radau DDE | simulation | 0.06 s | 0.05 s | 1.20x |
| ADVAN16 Radau DDE | compile + derivatives | 0.36 s | 0.22 s | 1.64x |
| ADVAN17 Radau DDAE | simulation | 0.65 s | 0.41 s | 1.59x |
| ADVAN17 Radau DDAE | compile + derivatives | 1.18 s | 0.74 s | 1.59x |

Across the focused equivalence cases, the largest absolute prediction
difference between policies was `1.31e-13`, and the largest CppAD Jacobian
difference was `9.77e-13`.

## Remaining opportunities

- Extend the all-C++ BAYES coordinator itself to general random-effect blocks,
  IOV, MU-specialized proposals, guarded ODE retaping, and PSOCK workers. Those
  paths already work through the general coordinator; native support is now a
  speed opportunity rather than a coverage gap.
- Evaluate optional Student-t and multi-mode f-SAEM proposal families as
  explicitly selected research kernels. The exact rescue mixture already
  addresses the principal tail-sticking risk without introducing another
  tuning dimension into the default algorithm.
- Continue structural tape sharing for subjects with the same event topology;
  dynamic observation/covariate data are the main remaining startup and memory
  opportunity in large studies.
- Evaluate a real-valued Radau eigentransform only as a separate clean-room
  algorithmic project. It can reduce the coupled linear algebra further, but it
  requires substantially more numerical validation than the factorisation reuse
  implemented here.

The matched NONMEM benchmark explicitly records and defaults to
`nonmem_compatibility`. It accepts `--numerical-mode=liber_optimized` for a
separate optimisation experiment without silently changing the reference track.
