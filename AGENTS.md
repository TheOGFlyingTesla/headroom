# Headroom

Read README.md before changing behavior. Keep this app small and native. Never start a Codex model turn to retrieve account usage. Never read, print, or copy credential files. Preserve the documented app-server integration and unknown/stale states.

- Build and run: `./script/build_and_run.sh --verify`.
- Inspect UI: `./script/build_and_run.sh --preview`. This opens the same card in a regular window for accessibility tooling. Command-Shift-H exercises the actual status-item popover. Normal launches show only the menu bar item.
- Focused tests: `swift test`.
- Live data check: `.build/debug/Headroom --probe`.
- Measure a settled normal launch: `python3 script/measure_idle.py`. Include all owned helper processes when reporting cost.
- GUI startup must remain synchronous. Asynchronous data requests run after AppKit owns the event loop.
- Do not add continuous animations, directory scans, third-party packages, or faster network polling without a concrete need.
- For floating-card drag changes, verify actual origin changes: `python3 script/check_drag.py record /tmp/headroom-drag.json`, perform a real UI drag, then `python3 script/check_drag.py verify /tmp/headroom-drag.json`. Unchanged AX text or the existence of a saved frame is not movement evidence. Cover the header and readings separately, and check that close still works.
- Use the weekly duration, not a hardcoded primary/secondary assumption. Missing data is not zero usage.
- Local app bundles are ad-hoc signed. Distribution requires a separate signing/notarization decision.
