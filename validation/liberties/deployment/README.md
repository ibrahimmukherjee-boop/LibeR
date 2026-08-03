# LibeRties deployment verification

These checks exercise a **running, disposable LibeRties API**. They supplement
the package tests for tenant separation, typed-wire rejection, durable restart
recovery, quotas, log redaction, rate limiting, and production preflight. They
do not certify a deployment or prove that hostile code is contained.

## Systemd versus trusted-local callr performance

`benchmark-executors.R` submits identical encrypted jobs through the durable
queue using the trusted-local `callr` subprocess and the production systemd
executor. It records fresh-process end-to-end time, queue/start latency, worker
wall time, result retrieval, resource telemetry, and LibeRation's internal core
fit time when available. Executor order alternates within every pair and an
unrecorded warm-up is used to reduce page-cache bias.

Run it inside the configured Linux/systemd environment:

```sh
export R_LIBS_USER=/home/liberties/R/library
export LIBERTIES_SYSTEMD_STORAGE_CREDENTIAL=/srv/liberties-secrets/storage-key
export LIBERTIES_EXECUTOR_BENCHMARK_OUTPUT=/tmp/liberties-executor-benchmark
Rscript validation/liberties/deployment/benchmark-executors.R
```

Set `LIBERTIES_EXECUTOR_BENCHMARK_PROFILE=quick` for a shorter smoke benchmark.
The full profile is intended for reporting. It creates a fresh R process for
every measurement but does not flush the operating-system page cache, matching
normal server operation after startup.

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

## Native systemd worker smoke test

On the intended Linux/WSL systemd host, point to the same protected storage-key
file used by the API and run a real two-core simulation inside the production
executor:

```text
LIBERTIES_SYSTEMD_STORAGE_CREDENTIAL=/srv/liberties-secrets/storage-key \
Rscript validation/liberties/deployment/run-systemd-smoke.R
```

Set `LIBERTIES_SYSTEMD_EVIDENCE` to retain the JSON evidence outside the
temporary queue. The test performs strict live preflight, starts a transient
systemd user service, exercises PSOCK parallelism with `n_cores=2`, retrieves
and validates its result, and checks that the unit/profile/core/task provenance
was durably recorded. It intentionally fails on Windows and macOS rather than
pretending to validate a non-systemd substitute.
