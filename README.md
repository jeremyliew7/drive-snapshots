![Drive Snapshots — Understand your storage](docs/banner.svg)

# Drive Snapshots

**Local disk inventory, offline visualization, and evidence-aware comparisons.**

[English](README.md) · [简体中文](README.zh-CN.md) · [Demo](demo/index.html) · [Roadmap](ROADMAP.md) · [Contributing](CONTRIBUTING.md) · [Agent guide](AGENTS.md)

Drive Snapshots uses WizTree as its default Windows scanner. It preserves the original WizTree
CSV, converts folder records into a compact directory snapshot, and opens that data in a
dependency-free browser viewer. Paths and inventory data stay on the local machine.

- Fast NTFS scans through WizTree's administrator/MFT mode.
- Searchable folder tree and area-proportional treemap.
- Baseline comparison and snapshot history playback.
- Standalone HTML reports that work offline.
- Explicit distinction between measured values and unknown coverage.

## Requirements

- Windows
- PowerShell 7.2 or later (`pwsh`)
- WizTree, installed or portable
- A modern browser for the viewer

WizTree is third-party software from Antibody Software. Its command-line options and CSV fields
are documented in the [official WizTree guide](https://diskanalyzer.com/guide).

## Quick start

```powershell
# Scan one or more drives or folders with WizTree.
./wiztree-snapshot.ps1 -Target 'C:','D:'

# Open viewer/index.html and import files from snapshots/wiztree/converted/.

# Bundle selected converted snapshots into one private offline report.
$files = (Get-ChildItem ./snapshots/wiztree/converted -Filter *.csv).FullName
./export-report.ps1 -Snapshot $files -Output ./reports/latest.html
```

`wiztree-snapshot.ps1` discovers `WizTree64.exe`, requests administrator access for the fast MFT
path, waits for a stable export, and converts it. Pass `-ExePath` when discovery does not find a
portable installation:

```powershell
./wiztree-snapshot.ps1 -Target 'C:' -ExePath 'C:\Tools\WizTree\WizTree64.exe'
```

Use `-NoAdmin` for WizTree's slower directory walk. Administrator access improves speed on NTFS
but does not make the export atomic or prove that every item is represented.

When `snapshot.config.json` exists, the command can reuse its `paths` and global `maxDepth`
viewing preference:

```powershell
./wiztree-snapshot.ps1
```

## Data flow

```text
WizTree scan
  -> snapshots/wiztree/raw/*.csv
  -> Convert-WizTreeCsv.ps1
  -> snapshots/wiztree/converted/*_folders.csv
  -> viewer/index.html or export-report.ps1
```

The raw CSV contains file and folder rows and can be hundreds of megabytes. Keep it as source
evidence; do not import it directly into the browser. The converter streams the file and emits
only folder rows, so it does not need to load the raw export into memory.

Convert an existing WizTree export without rescanning:

```powershell
./Convert-WizTreeCsv.ps1 `
  -InputPath './snapshots/wiztree/raw/WizTree_20260101090000.csv' `
  -ViewDepth 5
```

WizTree localizes its banner and header. The converter uses the documented fixed field positions
instead of matching English or Chinese column names.

## Snapshot semantics

The viewer-ready CSV contains these core fields:

| Column | Meaning |
| --- | --- |
| `Depth`, `Path` | Folder depth relative to the exported root and its absolute path. |
| `SizeBytes`, `SizeGiB` | Recursive logical size reported by WizTree. |
| `AllocatedBytes` | Recursive allocated size reported by WizTree. |
| `FileCount` | Recursive file count reported for the folder. |
| `DescendantDirCount` | Recursive descendant folder count reported by WizTree. |
| `SnapshotScope`, `ViewDepth` | Full folder export and the viewer's initial depth. |
| `Source` | `WizTree`. |
| `Coverage` | `Unknown`, because the WizTree CSV does not expose descendant read-failure propagation. |

Folder rows contain recursive totals. Do not add parent and child sizes together. A missing path
means it was not observed in that export; it does not prove deletion. Renames appear as one path
becoming unobserved and another becoming observed.

Logical size and allocated size answer different questions. The viewer uses logical size for its
treemap and comparisons. The converted CSV retains allocated size for separate analysis.

## Viewer and reports

Open `viewer/index.html`, choose **Import CSV snapshots**, and select one or more converted files.
The browser reads only the files selected by the user and uploads nothing. A new import replaces
the active dataset.

The folder tree is searchable and paginated. **Levels below folder** controls the tree and
treemap detail without changing the imported data. Select a baseline to inspect changes between
compatible snapshots of the same root.

`export-report.ps1` embeds selected snapshots, CSS, and JavaScript into one HTML file. Reports
contain full local paths and sizes; treat them as private inventory data.

The [demo](demo/index.html) contains fictional generated data only.

## Built-in scanner

`drive-snapshot.ps1`, `initialize-snapshots.ps1`, and `measure-snapshot-depth.ps1` remain available
as an explicit PowerShell fallback and for cross-platform development. They are not the default
capture path. Their CSV/log coverage model includes `Unreadable` and propagated `Incomplete`
fields, which are not interchangeable with WizTree's `Coverage=Unknown` state.

## Privacy and local data

The repository ignores private snapshots, reports, assessments, configuration, and generated
HTML. Only fictional demo data is allowlisted.

| Location | Purpose |
| --- | --- |
| `snapshots/wiztree/raw/` | Original WizTree CSV exports. |
| `snapshots/wiztree/converted/` | Compact viewer-ready folder snapshots. |
| `reports/` | Private standalone HTML reports. |
| `assessments/` | Built-in scanner depth assessments. |
| `backups/config/` | Configuration backups. |
| `snapshot.config.json` | Active private machine configuration. |

Before any commit or publication:

```powershell
git status --short
git ls-files
git check-ignore snapshots/wiztree/raw/example.csv reports/latest.html snapshot.config.json
```

The project never deletes scanned files. A large file or folder is not automatically a safe
cleanup target.

## Development

```powershell
./tests/wiztree.ps1
./tests/smoke.ps1
./tests/depth.ps1
node --test tests/viewer.test.cjs
./scripts/build-demo.ps1
```

The WizTree adapter and capture entry are PowerShell scripts. `viewer/` contains the offline UI,
`demo/` contains synthetic fixtures, and `.agents/skills/` contains capture, analysis, cleanup
planning, report, and WizTree export workflows.

## License

[MIT](LICENSE). WizTree is distributed separately under its own license.
