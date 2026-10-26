# Security

Please report vulnerabilities through **Security > Report a vulnerability** on this repository. Include the affected version, steps to reproduce, and expected impact. Keep credentials and account data out of reports, screenshots, and public issues.

## Trust and data

Headroom runs with your macOS user account's permissions. It launches an installed Codex CLI from one of three fixed locations and exchanges JSON over private standard-input/output pipes. Headroom requests account rate limits; it does not start model turns or accept commands from helper output.

The CLI owns authentication, account selection, network requests, and its own configuration and storage. Only install Codex from a source you trust. Headroom does not provide a sandbox around the CLI or verify its publisher signature.

Headroom keeps account responses in memory and displays quota and disk summaries in its interface, tooltips, and accessibility labels. Its optional `--probe` command prints those summaries to your terminal. It does not read credential files or log account responses or window coordinates. Preferences store the menu bar display choice and floating-panel position.

Build and installation scripts run locally without administrator privileges. The local bundle uses ad-hoc signing, which checks bundle integrity and does not establish a verified publisher. This repository provides source builds; it does not include a notarized binary release.

## Scope

The first public version was reviewed for subprocess execution, JSON parsing, account-data handling, local persistence, logging, installation scripts, and accidental source disclosure. A redacted secret scan was also run. No reportable vulnerabilities were identified in that review. This is not a guarantee against future issues, and it does not cover the installed Codex CLI or its upstream services.
