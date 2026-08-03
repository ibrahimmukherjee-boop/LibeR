# LibeRties systemd deployment

LibeRties uses **transient systemd user services** as its built-in production
worker boundary. This keeps the API and workers under a dedicated non-root
Linux account and avoids giving an R process authority over the system service
manager. It requires systemd as PID 1, a unified cgroup-v2 hierarchy, and a
persistent systemd user manager.

Windows operators must provide that environment through WSL 2 with systemd
enabled. macOS operators must provide a Linux systemd VM or host themselves.
LibeRties deliberately does not install or emulate systemd on either OS.

For WSL, install `dbus-user-session` as well as R and the compiler toolchain.
`systemctl --user` may appear healthy while `systemd-run --user` still fails
with `Failed to connect to bus` when `/run/user/<uid>/bus` is absent. Verify the
actual transient-service boundary before installing LibeRties:

```sh
sudo apt-get install dbus-user-session r-base r-base-dev build-essential
systemctl --user daemon-reload
systemctl --user start dbus.socket
test -S "/run/user/$(id -u)/bus"
systemd-run --user --wait --collect --property=PrivateUsers=yes \
  --property=PrivateNetwork=yes --property=MemoryMax=64M /usr/bin/true
```

Use `loginctl enable-linger <service-account>` so the user manager survives
logout. An SDK/vendor WSL distribution can be used for local validation, but a
plain, maintained Ubuntu distribution and a dedicated non-root `liberties`
account are preferable for a persistent service.

## 1. Provision a dedicated account

Run these administrative commands on the Linux host, adapting paths to local
policy:

```sh
sudo useradd --create-home --shell /bin/bash liberties
sudo loginctl enable-linger liberties
sudo install -d -o liberties -g liberties -m 0700 /srv/liberties
sudo install -d -o liberties -g liberties -m 0700 /srv/liberties-secrets
```

Install R and the compatible LibeR package stack for this account. Do not use
the account for interactive browsing, email, or unrelated services. Package,
queue, and credential paths used by the executor must not contain whitespace
or a colon because they become systemd bind-mount specifications.

## 2. Provision the storage key

Generate the key once in R:

```r
LibeRties::ls_generate_storage_key()
```

Store the returned 64-character value as
`/srv/liberties-secrets/storage-key`, owned by `liberties` with mode `0600`.
Do not put it in an environment variable, command line, repository, or unit
file. The API unit and each transient worker receive it through systemd's
`LoadCredential=` mechanism. The API uses the credential to read the encrypted
registry and queue; a worker receives only its own temporary credential mount.

## 3. Install the API user service

Locate the installed examples from R:

```r
system.file("systemd", "liberties-api.service.example", package = "LibeRties")
system.file("systemd", "liberties-api.R", package = "LibeRties")
```

As the `liberties` account, copy the API example to
`~/.config/systemd/user/liberties-api.service` and
`liberties-workers.slice.example` to
`~/.config/systemd/user/liberties-workers.slice`. Replace the `ExecStart` path
with the second path above and adapt the storage root, credential path, worker
count, trusted reverse-proxy addresses, and optional aggregate slice ceilings.
Then run:

```sh
systemctl --user daemon-reload
systemctl --user enable --now liberties-workers.slice
systemctl --user enable --now liberties-api.service
systemctl --user status liberties-api.service
```

Keep the API on loopback or a private interface and terminate HTTPS at a
maintained reverse proxy. `LIBERTIES_BEHIND_TLS_PROXY=true` is an operator
attestation; configure the proxy itself to enforce TLS and request-size/time
limits. Only list an address in `LIBERTIES_TRUSTED_PROXIES` when that immediate
peer overwrites, rather than appends to, client forwarding headers.

## 4. Verify production preflight

The API calls the equivalent of:

```r
executor <- ls_systemd_executor(
  max_cores_per_job = 16L,
  storage_credential = "/srv/liberties-secrets/storage-key"
)
ls_server_preflight(
  "/srv/liberties", host = "127.0.0.1", behind_tls_proxy = TRUE,
  policy = ls_security_policy(production = TRUE),
  executor = executor, strict = TRUE
)
```

Preflight fails unless systemd is PID 1, cgroup v2 is present, both systemd
clients exist, the current account matches the configured service account, the
storage credential is available, and a short live transient sandbox completes.
Inspect API logs with:

```sh
journalctl --user -u liberties-api.service
```

## Multi-core behaviour

Systemd limits the **whole job cgroup**, not each R process to one core. A job
requesting `n_cores = 4` receives `CPUQuota=400%`; `TasksMax` is set above four
to accommodate the R parent, PSOCK/FORK children, and native runtime threads.
All descendants remain in the unit because `KillMode=control-group` is used.
LibeRation's existing multi-core estimators and simulations therefore retain
their parallel execution, while the job cannot consume more aggregate CPU than
its allocation. Numerical libraries remain one-threaded per R process to avoid
nested oversubscription. All workers also sit below
`liberties-workers.slice`; its optional aggregate CPU/memory/task ceilings
protect the host across simultaneous users without changing how cores are
shared within an individual job.

## Worker boundary

Each compute job receives `PrivateUsers=yes`, a strict read-only host view, a
hidden home directory, private temporary/dev/proc views, no new privileges, no
capabilities, one writable bind-mounted job directory, and read-only R package
libraries. Compute jobs receive `PrivateNetwork=yes`; this still permits local
loopback communication used by PSOCK workers but not host or internet access.
For portable rootless user services, the job directory is mounted at
`/tmp/liberties-job` inside the unit's private `/tmp`. LibeRties deliberately
does not use a new destination directly below `/run`, because unprivileged user
managers cannot create that bind target on every kernel, including WSL 2.
Only the explicitly typed LibeRary literature jobs use the host network.
`MemoryMax`, `MemorySwapMax=0`, `TasksMax`, `CPUQuota`, and `RuntimeMaxSec` are
hard cgroup/service controls. The durable queue additionally records resource
usage, checks total CPU time, recovers live unit handles after API restarts, and
cancels the complete control group.

The trusted-local subprocess backend remains available on every supported R
platform. It is convenient for a single user but is intentionally rejected as
the standard production isolation boundary.
