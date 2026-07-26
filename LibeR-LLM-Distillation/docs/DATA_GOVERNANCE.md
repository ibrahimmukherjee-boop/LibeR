# Data governance

## Source admission

A source is admitted only when `manifests/sources.yaml` records:

- a stable source identifier;
- the path and selection rules;
- its licence;
- whether it is owned, licensed, public domain, or used with permission;
- whether derived training rows may be redistributed.

The pipeline does not infer that paywalled, publicly visible, or technically
downloadable content is licensed for model training. That decision remains with
the dataset owner.

## Prohibited material

Do not ingest:

- patient-level or other personal data;
- secrets, tokens, passwords or private keys;
- proprietary material without a suitable licence or permission;
- ChatGPT/Codex responses as synthetic training targets;
- generated job outputs containing user data;
- local workspaces or run directories.

Generated answers are scanned for email addresses, phone-like strings and
absolute home paths. These checks reduce risk but are not a substitute for
reviewing a dataset before release.

## Provenance

Every accepted row retains source/document/chunk hashes, licence, rights basis,
teacher and judge identifiers, evidence spans and judge scores. The exact source
text is not placed in the SFT message body. It remains in the local work area so
an accepted answer can be audited.

## Redistribution

`dataset_audit.json` reports whether any retained rows came from
non-redistributable sources. Such a dataset must remain private. Publishing an
adapter or merged model may also engage source and base-model terms; obtain
appropriate legal review before external distribution or clinical use.

## Clinical boundary

The target assistant is for research and teaching. Training examples must not
teach it to issue unqualified patient-specific dosing instructions. Answers
should identify missing evidence, distinguish model diagnostics from clinical
judgement, and avoid fabricating model-run results.
