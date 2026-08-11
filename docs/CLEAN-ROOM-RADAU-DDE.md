# Clean-room Radau IIA DDE implementation

## Scope

LibeRation uses an independently written Radau IIA delay-equation path only
for ADVAN16 and ADVAN17, matching the NONMEM ADVAN families that select
RADAR5. ADVAN18 and LibeRation's general user-defined DDE path continue to use
the existing RK4 method-of-steps implementation. This restriction is tested
from the reported C++ propagation-kernel identity.

This is a clean-room mathematical implementation. No NONMEM, RADAR5, or other
vendor source file was downloaded, opened, copied, translated, linked, or used
as an implementation reference. The code was derived from published numerical
analysis and public user-facing descriptions, and its structure was designed
within LibeRation's existing C++/CppAD engine.

## Public mathematical basis

The solver uses the published three-stage Radau IIA collocation formula of
order five. Its nodes are

`c = ((4-sqrt(6))/10, (4+sqrt(6))/10, 1)`.

For each step, the three coupled stage states solve

`Y_i = y_n + h * sum_j A_ij f(t_n + c_j h, Y_j, history)`.

The final stage is the accepted endpoint because the method is stiffly
accurate. LibeRation solves the full coupled simplified-Newton system directly,
freezing and reusing its Jacobian within a step; it does not reproduce
RADAR5's implementation-specific transformations or internal linear algebra.
An independently derived order-three embedded formula,
obtained from the B(3) moment conditions with an explicit nonzero start-stage
weight, controls accepted and rejected steps. Past values are evaluated from
the integrated Lagrange polynomial through the three Radau stage derivatives.

Primary public references:

- N. Guglielmi and E. Hairer, *Implementing Radau IIA methods for stiff delay
  differential equations*, Computing 67 (2001), 1-12:
  <https://www.unige.ch/~hairer/preprints/radar5.pdf>
- N. Guglielmi and E. Hairer, *RADAR5 version 2 user guide*:
  <https://www.unige.ch/~hairer/manrad5-v2.pdf>

## LibeR-specific design

- Delay discontinuities caused by dose/event jumps are propagated and inserted
  into the integration mesh.
- A shared continuous mesh point uses the preceding collocation segment's
  stiffly accurate endpoint; explicit jumps retain distinct left and right
  limits.
- The maximum step is supplied by `nm_dde_config(step=...)`. Direct simulation
  adapts below this ceiling using `ODE_CONTROL` tolerances. A CppAD tape uses a
  fixed maximum-step replay mesh with recording-time Newton work whose
  convergence is certified at recording; this prevents estimator-driven
  retaping while retaining the same fifth-order stages and dense output.
- Stage equations, numerical Jacobian arithmetic, Newton linear solves, dense
  history evaluation, and accepted-step arithmetic all remain on the CppAD
  tape. Existing tape-path guards continue to cover parameter-dependent event
  paths, while non-finite replay output is rejected by the tape evaluator.
- ADVAN17 evaluates algebraic lag values through the differentiable index-1
  DAE Newton solve. It records at least one correction and fixes convergence
  work and pivot order at recording time rather than adding CompareOps.

## Compatibility statement

The mathematical method is in the same Radau IIA/RADAR5 family used by NONMEM
ADVAN16/17, but LibeRation does not claim binary or line-for-line equivalence
with the proprietary NONMEM integration or the authors' RADAR5 program.
Numerical equivalence is established with published equations, convergence and
gradient tests, and NONMEM comparisons where the installed NONMEM license
permits execution. A missing RADAR5NM license is reported as `not-run`, never
as a passing result.
