---
name: snapshot-capture
description: Generate new read-only directory or drive snapshots using the project scanner, including initial configuration, optional Windows elevation, and coverage verification. Use for capturing or refreshing snapshots, not merely viewing existing reports.
---

Read the repository README.md for current scanner parameters and CSV semantics. Use the existing drive-snapshot.ps1; do not implement a second scanner.

## Select scope and settings

Use the user's requested roots and overrides, otherwise reuse the existing snapshot.config.json (or their selected -Config). If neither identifies the roots, ask which drives or directories to scan; do not guess a system drive or scan every mounted volume. Reuse settings already authorized in the conversation without reconfirmation.

Check that PowerShell 7.2+ is available and each root exists as a real directory, not a file or link. Relative scan/output paths resolve beside the configuration file. MaxDepth limits reported rows, not traversal cost; a whole-drive scan may take considerable time.

For a one-off request, pass overrides without modifying saved configuration. For requested initial setup, supply known values non-interactively to -Init, then run the scanner: initialization alone does not capture a snapshot. Use the default snapshots output directory if the user has no output preference. Do not overwrite an existing configuration or change unrelated settings.

## Capture

Run from the repository root; substitute the user's actual paths:

```powershell
# Capture with existing settings.
./drive-snapshot.ps1

# One-off capture, preserving saved settings.
./drive-snapshot.ps1 -Path 'D:\Projects' -MaxDepth 4

# First-time setup when requested, followed by capture.
./drive-snapshot.ps1 -Init -Path 'D:\Projects' -OutDirRoot 'snapshots' -MaxDepth 5
./drive-snapshot.ps1

# Explicitly requested Windows administrator scan.
./drive-snapshot.ps1 -Path 'C:\' -Elevate
```

Use -Elevate when the user has requested or already authorized administrator scanning. Otherwise use ordinary permissions; for system roots, explain that -Elevate can improve coverage. Do not automatically retry a partial scan with elevation. Respect UAC cancellation and report child-process failure. Even administrator access cannot guarantee complete coverage. Do not change ACLs, ownership, or security settings to make a production scan succeed.

Preserve the configured output exclusion and existing history. Wait for completion, using the available process/session mechanism for long scans; do not start duplicate scans because a tool yielded early. If interrupted or failed after some roots finish, distinguish completed roots from remaining ones.

## Verify and deliver

For each requested root, locate the CSV and matching log from this run. In an elevated invocation, the child's console output may not be visible: use the resolved output directory, run start time, and root row to identify new files rather than assuming success from a launch.

Check that the CSV has exactly one depth-0 row for the intended root, inspect its SizeBytes, FileCount, and Incomplete, and read the log for read failures and privilege status. Do not treat a pre-existing file or a zero process exit alone as proof of a fresh capture. Report partial coverage as a lower bound, including failures below the reported depth; never describe inaccessible data as empty.

Return local links to the generated files and a concise completion/coverage summary for each root. Keep local inventory and configuration out of Git; verify ignore coverage for custom output locations inside the repository. Capture does not authorize deleting files, publishing inventories, or adding scheduled scans. If visualization was also requested, use the snapshot-report workflow with these exact output files.
