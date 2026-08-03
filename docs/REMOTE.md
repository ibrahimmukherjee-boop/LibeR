# Remote execution

LibeRties provides the same durable queue behind local and authenticated HTTP
interfaces. A remote user cannot select a filesystem namespace: every job
operation derives the tenant from a 256-bit bearer token. Only a SHA-256 token
digest is stored in the server registry.

## Start a development server

```r
library(LibeRties)

root <- "D:/liberties-data"
user <- ls_user_create(
  root,
  "alice",
  limits = list(max_concurrent_jobs = 2L, max_queued_jobs = 20L),
  scopes = c("jobs:read", "jobs:write"),
  expires = Sys.time() + 90 * 24 * 3600
)

# Store user$token in a secret manager; it is shown only at creation.
Sys.setenv(LIBERTIES_STORAGE_KEY = ls_generate_storage_key())
ls_server_preflight(root, "127.0.0.1")
ls_run_api(root, host = "127.0.0.1", port = 8000L, production = FALSE)
```

Connect from the modelling workstation:

```r
remote <- ls_remote(
  "https://liberties.example.org",
  Sys.getenv("LIBERTIES_TOKEN")
)

id <- remote$submit(ls_job("simulate", model, data))
remote$status(id)
result <- remote$result(id)
```

LibeRary triage, parsing, text extraction, PDF-vision extraction, assessment,
and adjudication can use the same queue through `library_job()`. PDF or parsed
text transfer requires explicit confirmation. The remote worker must have
LibeRary, Docling plus its PDF dependencies, and the selected LLM provider
credentials installed/configured. Credentials are read from the server
environment and are not included in the job payload.

The typed literature job names are `library_triage`, `library_parse`,
`library_index`, `library_dual_extract`, `library_assess`, and
`library_adjudicate`. A worker stores temporary document bundles inside its
job-specific directory and returns structured results; it never publishes into
the client's catalogue implicitly.

The LibeRation Jobs tab stores remote client definitions, the selected queue,
and the bearer token in `<workspace>/.liberation/client-settings.rds`. This file
is outside the package library, is written atomically, and is restricted to the
current user (`0600`) on POSIX systems. On Windows, the shared durability layer
replaces inherited access with an ACL granting full access only to the current
user SID, SYSTEM, and local Administrators. Set
`options(LibeR.strict_windows_acl = TRUE)` for deployments that must fail a
write when this ACL cannot be applied. Authenticated encryption remains the
primary at-rest control for sensitive workspaces. Editing a
remote without entering a replacement token retains the existing token. Remove
the queue from the Jobs tab to remove its saved client definition.

The local queue itself is stored in `<workspace>/.jobs`. LibeRation loads that
history before the first workbench render and polls it once the browser session
is ready, so queued, running, and completed work is visible after restarting R.
Server-side users and job history remain under `LIBERTIES_ROOT` (or
`options(LibeRties.root = ...)`); package installation directories are never
used for durable state.

The repository smoke test starts a loopback server, submits an ADVAN1 job, and
retrieves its C++ result:

```r
Rscript tools/smoke-remote.R
```

## Security boundary

- The public API accepts `liber.job.wire/2` JSON (and reads version 1 only for
  migration compatibility). It has no RDS upload or arbitrary-code endpoint.
- The receiver recompiles semantic model text with `nm_model()` and does not
  trust client-provided expression IR.
- Payloads cannot contain functions, calls, environments, weak references, or
  external pointers.
- Job and result files use SHA-256 integrity digests. When
  `LIBERTIES_STORAGE_KEY` is configured, internal RDS metadata, payloads, and
  results are additionally authenticated-encrypted at rest.
- User identifiers and job identifiers are validated path components, and all
  API operations derive the user from the bearer token.
- Scoped, optionally expiring bearer tokens and request throttling constrain
  access; user/token administration is retained in a hash-chained audit log.
- Forwarded client addresses are ignored unless the immediate peer is in the
  policy's exact/CIDR `trusted_proxies` allowlist. Rate-limit identities are
  pruned every minute and capped by `max_rate_limit_keys`.
- Queue, payload, result-download, storage, wall-time, CPU-time, complete
  process-tree size, and resident memory limits are enforced per tenant and
  recorded in job provenance.
- Metadata updates are lock-protected state transitions, so cancellation or a
  resource failure cannot be overwritten by a late worker completion.
- API responses disable caching and framing. Cross-origin access is not enabled
  by default.
- Remote logs redact common bearer/API-key/password/email forms and enforce
  line/byte response ceilings. With encrypted storage, plaintext live streams
  are sealed into authenticated encrypted archives when a job becomes terminal.

For a remote deployment, keep the R service on a private/loopback interface and
terminate TLS at a maintained reverse proxy. Production mode uses a transient
systemd user service for every job and fails closed unless a live sandbox can
be created. The worker receives a private user/mount/process view, a private
network namespace for compute work, its one writable job directory, read-only
R/package libraries, and cgroup-v2 CPU, task, memory, and wall-time limits.
`KillMode=control-group` also makes cancellation and restart recovery apply to
all parallel child workers rather than only the parent R PID.

Use a dedicated non-root Linux account and enable its systemd user manager at
boot. Windows deployments must run the service inside WSL 2 with systemd;
macOS deployments must supply their own Linux systemd environment. LibeRties
does not install or emulate systemd on either host. Full setup is documented in
[SYSTEMD.md](SYSTEMD.md).

Example proxy-aware policy:

```r
policy <- ls_security_policy(
  production = TRUE,
  trusted_proxies = c("127.0.0.1", "10.20.0.0/16"),
  requests_per_minute = 120,
  max_rate_limit_keys = 10000
)
ls_run_api(
  root, host = "127.0.0.1", behind_tls_proxy = TRUE,
  policy = policy,
  executor = ls_systemd_executor(
    max_cores_per_job = 16L,
    storage_credential = "/var/lib/liberties/secrets/storage-key"
  )
)
```

An `isolation_probe` remains available for deployment-specific attestation,
but is no longer needed for the standard systemd production backend.
