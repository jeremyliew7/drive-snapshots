---
name: snapshot-growth
description: Compare existing directory snapshots to explain where storage grew or shrank and identify coverage-related uncertainty.
---

Read README.md for the schema and caveats. Select snapshots for the user's root and interval; verify root, reported depth, and available coverage information. Timestamped filenames provide ordering, not proof of unchanged scan settings.

Join rows by full path (case-insensitive Windows paths, case-sensitive POSIX paths). Compute latest minus baseline SizeBytes. Missing rows are newly observed or not observed, never proven creation/deletion. Flag Unreadable and Incomplete; legacy files cannot establish descendant coverage.

Start with root delta and immediate children, then drill into the largest changes. Avoid counting a recursive parent and its children in an aggregate. Explain renames and scope changes as alternative causes when relevant. Do not assert duplicates, stale files, or safe deletion from folder sizes alone. Keep private paths in local outputs only; use the synthetic demo for public examples.
