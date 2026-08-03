# LibeRties systemd versus callr executor benchmark

Run: 2026-08-03T09:53:03.616Z<br>
Profile: `quick`<br>
R: R version 4.1.2 (2021-11-01)<br>
Kernel: 6.6.87.2-microsoft-standard-WSL2+

Each observation is a new R worker. Both executors use the same typed job,
durable queue, encrypted storage, installed libraries, result verification,
and parent polling interval. Executor order alternates within each pair.
The core time is LibeRation's internal fit time and is available only for
the estimation workload.

| workload | metric | callr_median_seconds | systemd_median_seconds | systemd_minus_callr_seconds | systemd_percent_change |
| --- | --- | --- | --- | --- | --- |
| tiny_simulation | total_seconds | 0.2995 | 0.4350 | 0.1355 | 45.2421 |
| tiny_simulation | worker_seconds | 0.0920 | 0.0820 | -0.0100 | -10.8696 |
| dense_simulation | total_seconds | 0.8000 | 0.9580 | 0.1580 | 19.7500 |
| dense_simulation | worker_seconds | 0.5560 | 0.5790 | 0.0230 | 4.1367 |
| focei_estimation | total_seconds | 0.5795 | 0.7455 | 0.1660 | 28.6454 |
| focei_estimation | worker_seconds | 0.3790 | 0.3810 | 0.0020 | 0.5277 |
| focei_estimation | engine_core_seconds | 0.3010 | 0.2995 | -0.0015 | -0.4983 |

Positive differences mean systemd was slower; negative differences mean it
was faster in this sample. Small sub-second differences should be interpreted
as startup/polling noise unless they are stable across repetitions. These are
descriptive local WSL measurements, not a cross-machine performance claim.
