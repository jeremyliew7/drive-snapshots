# Contributing

Use PowerShell 7.2+ and a modern browser; Node 18+ is needed only for development tests. No package installation is required.

1. Keep changes focused and explain their observable effect.
2. Run `./tests/smoke.ps1` and `node --test tests/viewer.test.cjs`.
3. For viewer changes, run `./scripts/build-demo.ps1` and open `demo/index.html`. Check import, comparison, folder navigation, playback, and narrow-window layout.
4. Update both READMEs when commands or behavior change.
5. Inspect the staged diff and file list. Use synthetic fixtures, never real paths or inventories, in public reports and screenshots.

Preserve read-only scanning and legacy CSV support. Include a regression test for arithmetic, traversal, serialization, or parsing changes. New cleanup integrations must separate planning from execution and explain their recovery behavior. See AGENTS.md for agent workflows.

When reporting a bug, include OS, PowerShell/browser version, expected and actual behavior, and a small synthetic reproduction. Do not attach real inventories or machine configuration. For potential data exposure issues, avoid posting private data; use the repository host's private security reporting feature if enabled.
