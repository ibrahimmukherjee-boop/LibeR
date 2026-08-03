# Interpretation: systemd versus trusted-local callr

Date: 2026-08-03<br>
Environment: WSL2, Linux 6.6.87.2, R 4.1.2<br>
Packages: LibeRties 0.7.7, LibeRation 0.9.8, LibeRtAD 0.7.13

## Result

The production systemd boundary adds a small, predominantly fixed job-launch
cost. It did not demonstrate a material penalty inside the LibeRation numerical
engine in this single-worker benchmark.

| Workload | Pairs | callr end-to-end median | systemd end-to-end median | Paired median systemd overhead | Paired median worker difference | Paired median core-fit difference |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Tiny one-subject simulation | 10 | 0.302 s | 0.453 s | +0.148 s | 0.000 s | n/a |
| Dense 100-subject, two-core simulation | 6 | 0.807 s | 0.952 s | +0.161 s | +0.019 s | n/a |
| 100-subject FOCEI | 4 | 0.656 s | 0.794 s | +0.131 s | +0.006 s | -0.007 s |
| 500-subject FOCEI | 6 | 1.567 s | 1.756 s | +0.206 s | +0.033 s | +0.031 s |

Every paired callr/systemd run produced the same rounded scientific result
signature. The dense simulation exercised two requested cores under
`CPUQuota=200%`; systemd did not serialize it onto one core.

The paired mean worker-time 95% t-intervals all included zero:

- Tiny simulation: -0.004 to +0.004 seconds.
- Dense simulation: -0.016 to +0.041 seconds.
- 100-subject FOCEI: -0.118 to +0.078 seconds.
- 500-subject FOCEI: -0.050 to +0.097 seconds.

The core-fit intervals also included zero: -0.092 to +0.060 seconds for the
100-subject fit and -0.040 to +0.084 seconds for the 500-subject fit. The
observations therefore support a launch-cost effect, not a demonstrated
numerical-throughput effect.

## Practical meaning

The percentage penalty appears large only because every measured workload was
shorter than two seconds. A fixed 0.15-0.20 second launch cost is approximately
2% for a 10-second job, 0.3% for a one-minute job, and 0.03% for a ten-minute
job. Normal pharmacometric estimation, diagnostics, bootstrap, simulation, or
optimal-design jobs should therefore receive the isolation benefits at
negligible relative cost.

For a workload made of thousands of sub-second tasks, submit a typed batch as
one sandboxed job or let a worker process an approved chunk internally. Do not
remove the systemd boundary merely to save launch latency. The enforced
`CPUQuota` can intentionally slow a job that requests fewer cores than it
actually tries to consume, or that starts undeclared nested BLAS/OpenMP
threads; this is resource-policy enforcement rather than systemd computational
overhead.

## Limits and next gate

This is a local WSL2, single-active-worker benchmark with warm operating-system
page caches. It is not a production-Linux or concurrent-load claim. Before a
production qualification candidate, repeat the harness on the intended Linux
server and add paired 1/4/8/16-worker throughput and tail-latency runs. Those
tests should monitor aggregate cgroup CPU throttling, memory pressure, worker
slice limits, queue latency, and p95/p99 completion time.
