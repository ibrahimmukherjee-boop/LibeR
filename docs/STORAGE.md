# LibeR storage layout

The source checkout is intentionally kept separate from application data,
regenerable development caches, project records, and cleanup review material.
The default Windows layout is:

| Location | Purpose | Back up? |
|---|---|---|
| `Documents/LibeR` | Git source checkout and the default LibeRation workspace | Source is in Git; back up `workspace` |
| `Documents/LibeR-data` | LibeRary catalogue, encrypted LibeRator patient workspaces, LibeRtAD benchmark results, downloaded documents, and retained research corpora | Yes |
| `Documents/LibeR-dev-cache` | Validation libraries, hosted-deployment libraries, external tools, installer stages, and downloads | No; reproducible |
| `Documents/LibeR-project-records` | Reviews, audit spreadsheets, relocation manifests, and other development records | Yes |
| `Documents/LibeR-cleanup-review` | Quarantined generated or duplicate material awaiting manual deletion | Until reviewed |

`LIBER_DEV_CACHE` overrides the development-cache root.
`LIBERARY_HOME` overrides the LibeRary repository. Existing users with
`Documents/LibeR/library` continue to use that legacy location when the new
default does not yet exist.

Historical package archives remain under `releases/`, which is deliberately
excluded from Git. `releases/INDEX.csv` and `releases/SHA256SUMS` identify the
retained files by location, size, and digest.

No automated cleanup command deletes application data. Generated files are
first moved to a dated quarantine directory with CSV manifests so that they can
be inspected before manual deletion.
