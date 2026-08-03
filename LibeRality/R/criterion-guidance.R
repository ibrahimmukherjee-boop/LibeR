.lity_criterion_guidance <- function() {
  item <- function(type, label, group, summary, construction, strengths,
                   limitations, use_cases, requirements = "A valid design and model.") {
    list(
      type = type,
      label = label,
      group = group,
      summary = summary,
      construction = construction,
      strengths = strengths,
      limitations = limitations,
      useCases = use_cases,
      requirements = requirements,
      direction = .lity_default_direction(type)
    )
  }

  list(
    D = item(
      "D", "D-optimality", "Parameter precision",
      "Maximises overall joint parameter information.",
      "Maximises log det(F), where F is the expected Fisher information matrix. Geometrically, this minimises the volume of the joint parameter-confidence ellipsoid.",
      "Scale-efficient; balances precision across many correlated parameters; widely used and easy to compare between designs.",
      "Can hide one poorly estimated parameter; depends on the nominal model and parameterisation.",
      "General-purpose population PK/PD design and a strong default when all parameters matter."
    ),
    ED = item(
      "ED", "ED-optimality", "Uncertainty and robustness",
      "Maximises the expected determinant across uncertain parameter scenarios.",
      "Calculates det(F) for every declared parameter scenario and maximises E[det(F)]. LibeRality evaluates log E[det(F)] with a log-sum-exp calculation for numerical stability; this monotone transformation gives exactly the same optimum.",
      "Represents parameter uncertainty while rewarding designs that can be especially informative in plausible scenarios; it is a recognised robust-design criterion.",
      "The arithmetic expectation can be dominated by a small number of very large determinants and therefore offers less protection against poor scenarios than maximin or EID-style criteria.",
      "Population PK/PD studies with a defensible prior or discrete set of parameter scenarios where classical ED-optimality is required.",
      "At least one parameter scenario; several weighted scenarios are needed for it to differ from local D-optimality."
    ),
    A = item(
      "A", "A-optimality", "Parameter precision",
      "Minimises average parameter variance.",
      "Minimises trace(F^-1), optionally after applying parameter weights. The trace is the sum of approximate parameter variances.",
      "Directly rewards average precision; allows clinically important parameters to be weighted.",
      "Sensitive to parameter scale unless weights or transformations are chosen carefully; one very imprecise parameter may dominate.",
      "Designs where mean precision across a defined parameter set is more important than joint ellipsoid volume."
    ),
    E = item(
      "E", "E-optimality", "Parameter precision",
      "Protects the least-informed parameter combination.",
      "Maximises the smallest eigenvalue of F. The least precisely estimated linear combination of parameters therefore receives the most protection.",
      "Conservative; useful for preventing nearly unidentifiable directions.",
      "May sacrifice substantial average efficiency and can change abruptly when the limiting eigenvector changes.",
      "Identifiability-sensitive designs and models with strongly correlated parameters."
    ),
    Ds = item(
      "Ds", "Ds-optimality", "Parameter precision",
      "Maximises information for selected parameters while treating the rest as nuisance parameters.",
      "Uses the determinant of the Schur-complement information for the selected parameter subset, adjusting for correlation with nuisance parameters.",
      "Targets the parameters that drive the scientific question without pretending nuisance parameters are known.",
      "Requires a defensible parameter subset and can reduce precision for excluded parameters.",
      "Focused PK/PD questions such as exposure-response parameters or a treatment effect."
    ),
    c = item(
      "c", "c-optimality", "Parameter precision",
      "Minimises uncertainty for one chosen parameter contrast.",
      "Minimises c'F^-1c, the approximate variance of a specified linear contrast c of the model parameters.",
      "Highly efficient for a single estimand; has a clear statistical interpretation.",
      "Can produce poor precision for every direction not represented by c; the contrast must be supplied correctly.",
      "A primary treatment contrast, derived clearance contrast, or other prespecified estimand.",
      "A contrast vector aligned with the estimable parameters."
    ),
    L = item(
      "L", "L-optimality", "Parameter precision",
      "Minimises uncertainty for several chosen parameter contrasts.",
      "Minimises trace(L F^-1 L'), optionally with weights. Each row of L defines a contrast or derived linear estimand.",
      "Generalises c-optimality to multiple estimands and permits explicit scientific weighting.",
      "Requires a well-scaled contrast matrix; results reflect the chosen contrasts rather than global model precision.",
      "Several related treatment, exposure or biomarker contrasts.",
      "A contrast matrix with columns aligned to the estimable parameters."
    ),
    rse = item(
      "rse", "Weighted RSE", "Parameter precision",
      "Minimises a weighted summary of expected relative standard errors.",
      "Computes SE from diag(F^-1), divides by the absolute nominal parameter value, and minimises the selected weighted or mean percentage summary.",
      "Familiar to pharmacometricians and directly connected to precision targets.",
      "Unstable for parameters near zero and affected by parameterisation; correlations are summarised only indirectly.",
      "Protocols with explicit parameter-RSE expectations."
    ),
    max_rse = item(
      "max_rse", "Maximum RSE", "Parameter precision",
      "Minimises the worst expected parameter RSE.",
      "Computes expected parameter RSEs from F^-1 and minimises their maximum over the selected parameters.",
      "Prevents a single required parameter from being unacceptably imprecise.",
      "Conservative and potentially non-smooth when the worst parameter changes.",
      "Design requirements stated as an upper bound for every key parameter."
    ),
    prediction_variance = item(
      "prediction_variance", "Prediction variance", "Prediction and decision",
      "Minimises uncertainty in a specified model prediction.",
      "Uses the delta-method variance g'F^-1g, where g is the gradient of the prediction or derived quantity with respect to model parameters.",
      "Optimises what may matter clinically rather than every structural parameter.",
      "Applies locally around the nominal parameter values and requires a relevant prediction gradient.",
      "Exposure, concentration, response, or derived PK/PD prediction at a clinically important condition.",
      "A prediction-gradient vector aligned with the model parameters."
    ),
    bayesian = item(
      "bayesian", "Bayesian expected criterion", "Uncertainty and robustness",
      "Optimises average performance over prior parameter uncertainty.",
      "Evaluates a base criterion across parameter scenarios or prior draws and maximises or minimises its probability-weighted expectation.",
      "Less dependent on one nominal parameter vector; incorporates prior scientific uncertainty.",
      "Quality depends on the prior/scenarios and may favour average performance while tolerating a poor tail case.",
      "Early development, extrapolation, or any design with meaningful parameter uncertainty.",
      "Parameter scenarios or prior draws with defensible weights."
    ),
    robust = item(
      "robust", "Robust expected criterion", "Uncertainty and robustness",
      "Optimises weighted average performance across model and operational scenarios.",
      "Evaluates a base criterion for every declared scenario and combines the values using the scenario probabilities.",
      "Can jointly represent parameter, model, adherence, dropout and sampling uncertainty.",
      "Still an average-case criterion; rare but severe scenarios can be diluted by their weights.",
      "Operationally realistic designs and mixed plausible populations.",
      "Declared uncertainty scenarios with probabilities."
    ),
    minimax = item(
      "minimax", "Minimax loss", "Uncertainty and robustness",
      "Minimises the largest loss across scenarios.",
      "Calculates a loss-valued base criterion in each scenario and selects the design with the smallest worst-scenario loss.",
      "Strong protection against the most adverse declared scenario.",
      "Can be overly conservative and is sensitive to an implausible extreme scenario.",
      "High-consequence trials where a poor worst case is unacceptable.",
      "Multiple defensible scenarios and a loss-oriented base criterion."
    ),
    maximin = item(
      "maximin", "Maximin utility", "Uncertainty and robustness",
      "Maximises the smallest information or utility across scenarios.",
      "Evaluates a utility-valued base criterion in every scenario and maximises the worst achieved value.",
      "Transparent worst-case protection and useful when scenario probabilities are unreliable.",
      "May give up considerable expected performance to improve one limiting scenario.",
      "Robust designs with plausible but hard-to-weight scenarios.",
      "Multiple scenarios and a utility-oriented base criterion."
    ),
    model_average = item(
      "model_average", "Scenario-averaged information criterion", "Uncertainty and robustness",
      "Optimises a weighted average information matrix across declared parameter and operational scenarios.",
      "Combines scenario-specific FIMs using supplied scenario weights, then evaluates the selected base criterion on that average matrix.",
      "Reduces commitment to one local parameter or operating scenario while retaining one structural model.",
      "It is not structural-model averaging; averaging FIMs can also hide a poorly performing individual scenario.",
      "Parameter, covariate, adherence, or operating-scenario uncertainty within one model structure.",
      "One structural model with defensible scenarios and weights."
    ),
    precision_probability = item(
      "precision_probability", "Probability of adequate precision", "Prediction and decision",
      "Maximises the probability that precision targets are met.",
      "Across uncertainty scenarios or simulations, calculates the probability that selected parameter RSEs fall below a specified threshold.",
      "Maps directly to a go/no-go precision requirement and communicates easily.",
      "Threshold choice can make the objective abrupt and ignores improvements once the threshold is crossed.",
      "Protocols with explicit success criteria for parameter precision.",
      "A precision threshold and, preferably, uncertainty scenarios."
    ),
    T = item(
      "T", "T-optimal discrimination", "Model discrimination",
      "Maximises squared separation between competing model predictions.",
      "Maximises a variance-weighted distance between predictions from competing models over the proposed observations.",
      "Simple and effective for separating mean-response structures.",
      "May overemphasise large absolute differences and does not represent the complete observation distribution.",
      "Choosing sampling times that distinguish two mechanistic or structural models.",
      "At least two competing models."
    ),
    KL = item(
      "KL", "Kullback\u2013Leibler discrimination", "Model discrimination",
      "Maximises expected distributional separation between competing models.",
      "Maximises the expected log-likelihood ratio, or KL divergence, between the predictive distributions of competing models.",
      "Uses both mean and variability differences and has a direct information-theoretic interpretation.",
      "Directional and model-dependent; can be computationally heavier and sensitive to distributional assumptions.",
      "Discrimination when competing models imply different response distributions.",
      "At least two competing probabilistic models."
    ),
    model_discrimination = item(
      "model_discrimination", "General model discrimination", "Model discrimination",
      "Maximises a weighted separation across several competing models.",
      "Combines pairwise or reference-model prediction distances using supplied model and comparison weights.",
      "Supports more than two models and flexible scientific priorities.",
      "The result depends on the distance definition and weights and can be less immediately interpretable.",
      "Broad structural-model learning programmes.",
      "Competing models and comparison weights."
    ),
    power = item(
      "power", "Statistical power", "Hypothesis testing",
      "Maximises the probability of rejecting the null hypothesis for an assumed effect.",
      "Uses the contrast variance c'F^-1c and a normal approximation to calculate power at the chosen alpha, effect and sidedness.",
      "Directly aligned with a conventional inferential objective.",
      "Local and approximation-based; highly dependent on the assumed effect and model validity.",
      "Trials built around a prespecified model-based hypothesis.",
      "A parameter contrast, assumed effect, alpha and alternative."
    ),
    superiority = item(
      "superiority", "Superiority power", "Hypothesis testing",
      "Maximises power to demonstrate an effect exceeds a superiority margin.",
      "Calculates normal-approximation power for the selected contrast after subtracting the prespecified superiority margin.",
      "Direct connection to a superiority claim and its estimand.",
      "Sensitive to assumed effect, margin and asymptotic approximation.",
      "Model-based superiority objectives.",
      "A contrast, effect, margin, alpha and alternative."
    ),
    noninferiority = item(
      "noninferiority", "Non-inferiority power", "Hypothesis testing",
      "Maximises power to rule out an unacceptable loss relative to a margin.",
      "Calculates normal-approximation power for the selected contrast relative to the non-inferiority margin.",
      "Directly represents a non-inferiority decision.",
      "Requires strong clinical justification of the margin and careful sign/direction conventions.",
      "Exposure-response or treatment comparisons with a non-inferiority objective.",
      "A contrast, effect, non-inferiority margin, alpha and direction."
    ),
    correct_dose = item(
      "correct_dose", "Correct-dose selection", "Prediction and decision",
      "Maximises the probability of selecting the correct dose.",
      "Simulates trial outcomes under each scenario, applies the declared dose-selection rule, and estimates how often the intended dose is selected.",
      "Evaluates the actual programme decision rather than a surrogate precision metric.",
      "Simulation-intensive and only as credible as the decision rule, candidate doses and scenarios.",
      "Dose-ranging and seamless learning designs.",
      "Candidate doses, a target/selection rule and simulation settings."
    ),
    target_attainment = item(
      "target_attainment", "Target attainment", "Prediction and decision",
      "Maximises the probability that a clinical or exposure target is achieved.",
      "Simulates outcomes and estimates the proportion meeting the endpoint-specific target or target interval.",
      "Clinically interpretable and naturally supports nonlinear targets.",
      "May ignore how far misses fall outside the target and requires a justified target.",
      "Exposure, biomarker, efficacy or safety target designs.",
      "An endpoint target and simulation settings."
    ),
    expected_utility = item(
      "expected_utility", "Expected utility", "Prediction and decision",
      "Maximises the expected value of a declared benefit\u2013risk or decision utility.",
      "Maps simulated outcomes to a utility function and averages utility across posterior or scenario uncertainty.",
      "Can combine efficacy, safety, burden and cost in the same decision framework.",
      "Utility elicitation is subjective and should be transparent; complex utilities can be difficult to validate.",
      "Benefit\u2013risk optimisation and decision-focused trial design.",
      "A serialisable utility or loss definition and simulation settings."
    ),
    cost = item(
      "cost", "Total study cost", "Resources and multi-objective",
      "Minimises declared study cost.",
      "Sums fixed, per-subject, per-visit, per-sample and assay costs across all arms.",
      "Transparent and useful in constraints or multi-objective designs.",
      "Cost alone contains no information or clinical-quality requirement.",
      "Budget-constrained design or a component of a compound/Pareto objective.",
      "Arm-level cost definitions with meaningful units."
    ),
    burden = item(
      "burden", "Participant burden", "Resources and multi-objective",
      "Minimises a weighted summary of subjects, visits, samples and sample volume.",
      "Combines declared burden components using explicit weights.",
      "Makes participant burden visible and optimisable.",
      "Weights are value judgements and should not replace hard safety constraints.",
      "Paediatric, rare-disease and intensive-sampling designs.",
      "Burden-component weights and sample-volume information."
    ),
    compound = item(
      "compound", "Compound objective", "Resources and multi-objective",
      "Optimises a weighted, scaled combination of several criteria.",
      "Normalises component criteria to declared references/scales and combines them using explicit weights.",
      "Produces one practical ranking while representing several programme goals.",
      "Weights and scaling can hide trade-offs; results require sensitivity analysis.",
      "Balancing information, target attainment, cost and participant burden.",
      "Two or more criteria with defensible weights and scaling references."
    ),
    pareto = item(
      "pareto", "Pareto exploration", "Resources and multi-objective",
      "Identifies designs for which no objective can improve without worsening another.",
      "Evaluates multiple criteria without collapsing them into one score and retains the non-dominated design frontier.",
      "Makes trade-offs explicit and avoids arbitrary weights at the exploration stage.",
      "Returns a set rather than one answer; a later decision rule or human choice is required.",
      "Exploring information\u2013cost\u2013burden or efficacy\u2013safety trade-offs.",
      "At least two component criteria."
    )
  )
}
