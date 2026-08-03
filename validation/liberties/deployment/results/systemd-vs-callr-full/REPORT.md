# LibeRties systemd versus callr executor benchmark

Run: 2026-08-03T09:58:27.798Z<br>
Profile: `full`<br>
R: R version 4.1.2 (2021-11-01)<br>
Kernel: 6.6.87.2-microsoft-standard-WSL2+

Each observation is a new R worker. Both executors use the same typed job,
durable queue, encrypted storage, installed libraries, result verification,
and parent polling interval. Executor order alternates within each pair.
The core time is LibeRation's internal fit time and is available only for
the estimation workload.

| workload | metric | callr_median_seconds | systemd_median_seconds | difference_of_medians_seconds | paired_median_difference_seconds | paired_mean_difference_seconds | paired_minimum_difference_seconds | paired_maximum_difference_seconds | systemd_percent_change |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| tiny_simulation | total_seconds | 0.3015 | 0.4525 | 0.1510 | 0.1475 | 0.1389 | 0.0820 | 0.1890 | 50.0829 |
| tiny_simulation | worker_seconds | 0.0875 | 0.0865 | -0.0010 | 0.0000 | 0.0000 | -0.0090 | 0.0100 | -1.1428 |
| dense_simulation | total_seconds | 0.8065 | 0.9520 | 0.1455 | 0.1605 | 0.1540 | 0.0980 | 0.1900 | 18.0409 |
| dense_simulation | worker_seconds | 0.5545 | 0.5650 | 0.0105 | 0.0185 | 0.0123 | -0.0350 | 0.0460 | 1.8935 |
| focei_estimation | total_seconds | 0.6560 | 0.7940 | 0.1380 | 0.1305 | 0.1153 | 0.0150 | 0.1850 | 21.0366 |
| focei_estimation | worker_seconds | 0.4190 | 0.4160 | -0.0030 | 0.0055 | -0.0197 | -0.1110 | 0.0210 | -0.7160 |
| focei_estimation | engine_core_seconds | 0.3315 | 0.3205 | -0.0110 | -0.0065 | -0.0163 | -0.0820 | 0.0300 | -3.3183 |
| long_focei_estimation | total_seconds | 1.5670 | 1.7555 | 0.1885 | 0.2055 | 0.1773 | 0.0550 | 0.2690 | 12.0294 |
| long_focei_estimation | worker_seconds | 1.3195 | 1.3525 | 0.0330 | 0.0330 | 0.0232 | -0.0680 | 0.1280 | 2.5010 |
| long_focei_estimation | engine_core_seconds | 1.2205 | 1.2570 | 0.0365 | 0.0310 | 0.0218 | -0.0630 | 0.1010 | 2.9906 |

Positive differences mean systemd was slower; negative differences mean it
was faster in this sample. Small sub-second differences should be interpreted
as startup/polling noise unless they are stable across repetitions. These are
descriptive local WSL measurements, not a cross-machine performance claim.
