# WSL scheduler test harness

This directory provisions disposable single-node scheduler environments for
testing the LibeRties Slurm and Grid Engine adapters before deployment to a
real Linux cluster. It is a development harness, not a production cluster
configuration.

Tested WSL distribution: Ubuntu 22.04 with systemd enabled. The local hostname
is `liber-wsl`; the OCS installer refreshes its WSL virtual-network address at
boot because Grid Engine correctly rejects a cluster hostname that resolves to
loopback.

Run the setup from an elevated PowerShell terminal:

```powershell
wsl.exe -d Nvidia_SDKM_Ubuntu_22.04_JetPack_7.2 -u root -- `
  bash /mnt/c/Users/svdijkman.DESKTOP-4OG10M4/Documents/LibeR/LibeRties/tools/wsl-scheduler-test/configure-slurm-single-node.sh
wsl.exe -d Nvidia_SDKM_Ubuntu_22.04_JetPack_7.2 -u root -- `
  bash /mnt/c/Users/svdijkman.DESKTOP-4OG10M4/Documents/LibeR/LibeRties/tools/wsl-scheduler-test/install-ocs-single-node.sh
wsl.exe -d Nvidia_SDKM_Ubuntu_22.04_JetPack_7.2 -u root -- `
  bash /mnt/c/Users/svdijkman.DESKTOP-4OG10M4/Documents/LibeR/LibeRties/tools/wsl-scheduler-test/configure-ocs-single-node.sh
```

Then run the real LibeRties smoke suite:

```powershell
wsl.exe -d Nvidia_SDKM_Ubuntu_22.04_JetPack_7.2 -u root -- `
  bash /mnt/c/Users/svdijkman.DESKTOP-4OG10M4/Documents/LibeR/LibeRties/tools/wsl-scheduler-test/run-wsl-scheduler-smokes.sh
```

The suite installs the current LibeRties source in WSL and, for each scheduler,
submits a two-core ADVAN1 simulation, reconstructs the durable queue supervisor,
checks the numerical result and terminal accounting, and cancels a second job.
Use `check-wsl-schedulers.sh` for a non-submitting health check after restart.

Ubuntu Jammy's packaged Grid Engine 8.1.9 qmaster crashes while loading its
spool (Launchpad bug 2002055). The harness therefore installs the maintained
Open Cluster Scheduler 9.1.4 release in `/opt/ocs`; it exposes the compatible
`qsub`, `qstat`, `qacct`, and `qdel` interfaces used by LibeRties and does not
replace Ubuntu system libraries. Managed wrappers in `/usr/local/bin` load the
correct OCS cell and ports, so the default `ls_grid_engine_executor()` command
discovery also works in non-login R processes.

## Windows client through a two-hop SSH tunnel

The optional ProxyJump campaign exercises the complete route used by a local
LibeRation GUI rather than calling the WSL API directly:

```text
Windows LibeRation -> gateway SSH -> target SSH -> loopback LibeRties API
                    -> Grid Engine or Slurm -> durable result
```

Create a disposable Ed25519 key, then pass its mounted `.pub` path to
`configure-ssh-proxyjump-test.sh`. The script installs OpenSSH Server when
needed but disables the distribution's normal port-22 service. It starts two
non-boot-persistent test daemons: a forwarding-only gateway on port 2222 and a
loopback-only target on port 2223. Only the target may forward to the two test
APIs on ports 8000 and 8001.

Keep `run-ssh-tunnel-test-servers.sh <mounted-runtime-directory>` running in
one elevated terminal, then invoke `run-liberties-ssh-client-smoke.R` from
Windows with a library containing the current LibeRation and LibeRties source,
the private-key path, and the same runtime directory. For each scheduler the
client submits through the two SSH hops, stops its local tunnel while the job
runs, reconnects, downloads and checks the result, and asserts that no
duplicate job was created.

Finish by creating `<mounted-runtime-directory>/stop` and running
`stop-ssh-proxyjump-test.sh` as root. The latter stops both SSH services and
empties the authorized-key file; delete the disposable private key and token
files on Windows. This harness is intentionally isolated and is not a template
for a production SSH service.

The same disposable gateway and destination also exercise the daemon-free
direct scheduler route. With current LibeRation and LibeRties packages loaded
on Windows and installed in WSL, run:

```powershell
Rscript LibeRties/tools/wsl-scheduler-test/run-liberties-direct-ssh-client-smoke.R `
  <disposable-private-key>
```

The smoke submits one ADVAN1 simulation to each scheduler through ProxyJump,
allows the one-shot SSH connection to disappear, then reconnects to recover
status and the checksum-validated numerical result without duplication.
