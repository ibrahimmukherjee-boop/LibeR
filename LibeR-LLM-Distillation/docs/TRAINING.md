# Training protocol

## 1. Establish a baseline

Run `doctor`, preserve its report, and run the evaluation prompts against the
untuned student. The evaluation command repeats this baseline immediately before
testing the adapter, but an early run is useful for refining rubrics.

## 2. Build a curriculum

The categories in `configs/default.yaml` should be balanced across:

- code generation and correction;
- model structure and parameterisation;
- estimation and uncertainty;
- diagnostics and interpretation;
- simulation and workflow;
- failure analysis;
- evidence boundaries and refusal to invent unavailable results.

Start with high-confidence LibeR documentation and tested examples. Add broader
pharmacometrics sources only after their rights and expected contribution are
clear. More synthetic rows are not automatically better.

## 3. Generate and adjudicate

The teacher first proposes questions with exact evidence, then answers them in a
second call. The judge sees the original passage, question, answer and evidence.
It may repair the answer, but a repaired answer must still pass exact-evidence
and policy checks.

Using the same model as author and judge can preserve systematic mistakes. The
default uses two installed Qwen sizes, and critical evaluation can use the 27B
teacher again. A small human gold set should eventually remain completely
outside generation.

## 4. SFT

The default is two epochs of QLoRA. Monitor training and validation loss,
gradient norm and token accuracy. Stop if validation loss worsens consistently.
Do not tune on the held-out evaluation prompts.

## 5. Optional preference training

DPO is disabled until there is enough evidence that SFT alone produces a
specific, reproducible style or calibration problem. When enabled, rejected
answers contain a named defect and are screened for unsafe content. Keep DPO
learning rates substantially below SFT learning rates.

## 6. Evaluation and release gate

Evaluation contains:

- fixed capability/safety prompts with required and forbidden concepts;
- held-out questions grouped by source document;
- base-versus-tuned regression detection;
- optional Qwen teacher scoring.

Before a public or clinical-facing release, add manually authored gold questions,
code-execution checks for generated R/C++ snippets, calibration tests, red-team
prompts, and external pharmacometric review. A teacher judge is useful triage,
not independent scientific validation.
