---
name: snapshot-capture
description: Generate read-only directory or drive snapshots with the project's default WizTree workflow, preserving raw CSV and producing viewer-ready data.
---

Read `README.md` and `.agents/skills/wiztree-csv-export/SKILL.md` before capture work.

## Default workflow

On Windows, use `wiztree-snapshot.ps1`. It runs WizTree, preserves the original export under
`snapshots/wiztree/raw/`, then streams folder rows into the Drive Snapshots schema under
`snapshots/wiztree/converted/`.

`drive-snapshot.ps1` is the paused built-in PowerShell scanner. Use it only when the user
explicitly asks for the native scanner or for cross-platform capture.

Use explicit roots when supplied. Otherwise, `wiztree-snapshot.ps1` may reuse `paths` and the
global `maxDepth` viewing preference from `snapshot.config.json`. Do not guess a system drive.
Do not overwrite configuration or existing snapshots.

```powershell
# Explicit drives or folders.
./wiztree-snapshot.ps1 -Target 'C:','D:'

# Reuse configured roots.
./wiztree-snapshot.ps1

# Slow directory walk without the administrator/MFT fast path.
./wiztree-snapshot.ps1 -Target 'D:\Projects' -NoAdmin

# Convert an existing raw export without rescanning.
./Convert-WizTreeCsv.ps1 -InputPath './snapshots/wiztree/raw/WizTree_example.csv'
```

WizTree requests administrator access by default for fast NTFS MFT scanning. Respect UAC
cancellation and report whether the exporter fell back to non-admin scanning. Do not change
ACLs, ownership, or security settings. A scan reads metadata and writes only its own output.

## Verification

For every requested root:

1. Verify the raw CSV exists, has a stable nonzero size, a WizTree banner, a localized header,
   and a first data row for the intended root.
2. Verify the converted CSV has exactly one depth-0 row and inspect `Path`, `SizeBytes`,
   `FileCount`, `Source`, and `Coverage`.
3. Keep the raw and converted files in their designated Git-ignored directories. Import the
   converted file into the viewer; never load a hundreds-of-megabytes raw file into a browser.

WizTree exports recursive folder totals and recursive file/folder counts. Its CSV does not carry
the built-in scanner's descendant read-failure propagation, so converted rows use
`Coverage=Unknown`. Never present that state as proven complete. Missing paths are unobserved,
not proven deleted, and recursive parent and child totals must not be summed.

If the user explicitly requests the native scanner, follow its configuration, elevation,
partial-coverage, CSV/log pairing, and root-row verification rules described in README.
