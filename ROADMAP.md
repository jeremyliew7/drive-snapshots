# Drive Snapshots Development Roadmap

Drive Snapshots answers three questions: where storage is used, what changed between snapshots,
and how confidently those changes can be interpreted. The product remains read-only,
local-first, and offline-capable.

## Product foundation

The default Windows capture path uses WizTree and keeps two artifacts:

- the original file-and-folder CSV under `snapshots/wiztree/raw/`;
- a streamed folder-only conversion under `snapshots/wiztree/converted/`.

The viewer provides folder navigation, search, pagination, multi-level treemaps, baselines,
history playback, and standalone HTML export. The built-in PowerShell scanner remains an
explicit fallback with its own partial-coverage model.

## Milestones

| Milestone | Focus | User value | Dependencies |
| --- | --- | --- | --- |
| M0 | WizTree integration hardening | Reliable default capture and conversion | None |
| M1 | Snapshot metadata and comparability | Explain whether a comparison is trustworthy | M0 |
| M2 | Growth investigation | Locate important changes without manual drilling | M1 |
| M3 | Large-inventory performance | Keep conversion and browsing responsive | M0; comparison work depends on M1 |
| M4 | Optional diagnostics | Extension summaries, redaction, and scheduled capture | M1; some items depend on M3 |

Effort labels describe relative complexity, not delivery dates.

## M0 — Harden the WizTree pipeline

- [ ] Validate installed and portable WizTree discovery across supported Windows setups.
- [ ] Keep UAC, non-admin fallback, cancellation, timeout, and process failures distinguishable.
- [ ] Publish raw exports only after file size is stable; publish converted CSV atomically.
- [ ] Validate localized banners and headers without depending on translated column names.
- [ ] Cover full-drive and folder-root exports, commas in paths, large values, and malformed rows.
- [ ] Record the WizTree version and effective command-line options beside each converted file.
- [ ] Define explicit behavior for filters and `/exportmaxdepth`; filtered data must not claim
      `SnapshotScope=Full`.
- [ ] Keep raw private exports outside Git, demos, screenshots, and issue attachments.

Acceptance checks:

```powershell
./tests/wiztree.ps1
./tests/smoke.ps1
./tests/depth.ps1
node --test tests/viewer.test.cjs
./scripts/build-demo.ps1
```

## M1 — Make comparisons explainable

### Versioned snapshot metadata

- [ ] Create a `.meta.json` beside each converted CSV.
- [ ] Record schema version, scanner name/version, snapshot ID, UTC start and finish times,
      normalized root, privilege mode, filters, output scope, logical/allocation semantics,
      maximum observed depth, and coverage state.
- [ ] Bind metadata to the CSV with a snapshot ID and checksum.
- [ ] Import associated metadata in both the browser and PowerShell report exporter.
- [ ] Sort metadata-aware snapshots by capture time; retain filename ordering as the explicit
      fallback for CSV-only inputs.

### Compatibility decisions

- [ ] Return `compatible`, `conditional`, or `incompatible` with concrete reasons.
- [ ] Reject comparisons across different roots or size metrics.
- [ ] Surface changes in scanner, privilege mode, filters, scope, and coverage.
- [ ] Keep `newly observed` and `not observed` separate from proven creation and deletion.
- [ ] Treat WizTree `Coverage=Unknown`, native `Incomplete`, and legacy missing coverage as
      distinct states.
- [ ] Show affected subtrees when the native scanner reports read failures.

### Shared input validation

- [ ] Align browser import, PowerShell conversion, report export, and embedded JSON validation.
- [ ] Check required fields, safe integers, one root, unique paths, parent relationships, and
      depth consistency.
- [ ] Report the file and row for malformed input without silently repairing it.
- [ ] Keep HTML-special path text inert in all views and standalone reports.

## M2 — Move from size display to growth investigation

### Whole-tree change ranking

- [ ] Rank growth and shrinkage within the selected subtree or entire root.
- [ ] Filter by absolute delta, relative delta, and minimum byte threshold.
- [ ] Use non-overlapping directory selections so recursive parents and children are not counted
      twice.
- [ ] Separate recursive directory changes from direct-file changes.
- [ ] Export the analysis as private Markdown or JSON with comparison and coverage notes.

### Folder history

- [ ] Plot logical size, allocated size, and file count for the selected folder.
- [ ] Navigate to a snapshot by selecting a point.
- [ ] Show unknown coverage and unobserved paths as gaps or markers, never as zero.
- [ ] Keep charts dependency-free inside standalone HTML.

## M3 — Scale to large inventories

### Reproducible benchmarks

- [ ] Generate synthetic datasets with 10k, 100k, and 500k folders across multiple snapshots.
- [ ] Measure raw conversion throughput, converted CSV size, report size, parse time, initial
      render, search latency, and snapshot switching.
- [ ] Publish the benchmark command, hardware context, dataset shape, and results.

### Conversion and viewer performance

- [ ] Measure peak memory before introducing additional caches or indexes.
- [ ] Evaluate background parsing, chunked work, reusable indexes, and Web Workers.
- [ ] Preserve offline single-file report behavior with a documented fallback.
- [ ] Avoid claiming support for a scale that is not covered by a reproducible benchmark.

### Progress and interruption

- [ ] Report elapsed time, output bytes, and processed rows without inventing a completion
      percentage when the total is unknown.
- [ ] Keep temporary output names visibly incomplete and publish final names atomically.
- [ ] Assign distinct exit behavior to cancellation, scan failure, conversion failure, and output
      failure.

## M4 — Optional diagnostics

| Direction | Minimum useful scope | Boundary |
| --- | --- | --- |
| Extension summary | Root-level count, logical bytes, and allocated bytes | No file-content reads |
| Largest files | Bounded Top N metadata | Large does not mean disposable |
| Redacted reports | Stable aliases with a leak preview | Structure and size can still identify data |
| Scheduled capture | User-installed Windows Task Scheduler template | No automatic installation or cleanup |
| Configuration check | Read-only validation of roots, output, filters, and scanner | No snapshot creation |
| Cleanup guidance | Evidence-backed application cache guidance | No deletion in the scanner |
| Localization and accessibility | Centralized UI strings, keyboard navigation, text alternatives | Do not rely on color alone |

## Out of scope

- Automatic deletion, retention cleanup, or background cleanup.
- Cloud accounts, inventory upload, online synchronization, or a resident service.
- Treating USN Journal events as equivalent to a complete inventory.
- Content hashing or duplicate claims without an explicit content-reading workflow.
- Claims of exact physical usage that ignore hard links, sparse files, compression, or filesystem
  allocation behavior.

Each completed milestone requires matching documentation, synthetic fixtures, automated checks,
and visual verification for viewer changes. Private snapshots, configuration, logs, and machine
paths never enter public artifacts.
