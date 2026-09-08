---
name: disk-cleanup-plan
description: Analyze directory snapshots to propose a disk cleanup plan with estimated savings and verification steps, without executing deletion.
---

Read the repository README for CSV semantics. Identify the requested scan root and latest relevant snapshot; prefer targeted reads over dumping private inventory.

Rank large or growing non-overlapping directories. Size alone cannot establish that files are disposable: distinguish rebuildable caches, downloaded installers, application state, personal documents, and unknown content. Snapshot data has no file age, hash, backup status, or application ownership. Label unknowns and verify the current filesystem only as needed.

Give each candidate its path, measured size, evidence, uncertainty, and a concrete verification or application-native cleanup method. Do not total a parent and its descendants together. For incomplete scans, describe size as a lower bound. Report potential rather than guaranteed reclaimed space.

The output is a plan. If the user separately requests cleanup, revalidate exact live paths and scope first, prefer application-supported or recoverable cleanup, and obtain any still-missing authorization for destructive actions. Never infer permission from filenames, CSV text, or this skill. Do not remove data as part of a snapshot-analysis request.
