# LibeRties deployment verification

These checks exercise a **running, disposable LibeRties API**. They supplement
the package tests for tenant separation, typed-wire rejection, durable restart
recovery, quotas, log redaction, rate limiting, and production preflight. They
do not certify a deployment or prove that hostile code is contained.

## Read-only k6 load test

Set the service URL and, optionally, a short-lived validation token:

```text
LIBERTIES_URL=http://127.0.0.1:8000
LIBERTIES_TOKEN=<short-lived token>
k6 run validation/liberties/deployment/k6.js
```

The default run performs health, authentication, job-list, response-header,
error-rate, and latency checks without changing server state. Tune
`LIBERTIES_VUS`, `LIBERTIES_DURATION`, and `LIBERTIES_P95_MS` for the deployment
under test.

Queue submission is deliberately opt-in. Create a non-sensitive typed wire
fixture, then run one submission per virtual user:

```text
Rscript validation/liberties/deployment/create-job-fixture.R --output=validation-job.json
LIBERTIES_ALLOW_SUBMIT=YES
LIBERTIES_JOB_FILE=validation-job.json
k6 run validation/liberties/deployment/k6.js
```

Use an isolated validation tenant with explicit queue/storage limits. Never use
a clinical or production tenant for destructive, saturation, restart, or
resource-exhaustion campaigns.

## OWASP ZAP baseline

The cross-platform R launcher uses the pinned ZAP 2.17.0 container and accepts
loopback targets only by default:

```text
Rscript validation/liberties/deployment/run-zap.R \
  --target=http://127.0.0.1:8000 \
  --output=validation/liberties/deployment/results/zap
```

It produces JSON and HTML reports. A non-loopback scan requires the explicit
`--allow-remote` flag because even passive crawling must be authorised by the
owner of the target. The baseline is unauthenticated and therefore validates
the public health/error surface and security headers; authenticated API
authorization, tenant isolation, and queue semantics remain covered by package
tests and the k6 token path. ZAP warnings are retained in evidence but are
non-fatal by default; use `--fail-on-warning` for a qualification candidate.

## CI

`.github/workflows/deployment-validation.yml` starts an ephemeral loopback
server, runs the read-only k6 contract, and performs the ZAP baseline. It uses
synthetic data, a disposable token, and an isolated temporary server root.
Deployment-specific load, restart, container-isolation, TLS, and penetration
tests must still be run in the intended Linux deployment environment.
