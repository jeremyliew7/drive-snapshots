---
name: snapshot-report
description: Build an offline HTML report from existing snapshots or regenerate the public synthetic demonstration.
---

For a private report, use export-report.ps1 with an explicit CSV list and an output under reports/. Select the intended root and history, avoiding unrelated inventories. Open the resulting HTML and verify totals, root, baseline, and coverage status. Embedded paths are private data; report creation is not permission to upload or publish.

For public demo work, run scripts/build-demo.ps1, which generates invented data without scanning the machine. Do not use local snapshots as fixture input. After viewer changes, regenerate demo/index.html and check drill-down, comparison, and history playback.

Use README.md for current command syntax. Ensure imported filenames remain text and embedded JSON cannot close its script element. A standalone report must include styles, code, and data without external network dependencies.
