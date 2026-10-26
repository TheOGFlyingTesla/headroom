#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_EXECUTABLE="$ROOT_DIR/dist/Headroom.app/Contents/MacOS/Headroom"
INSTALLED_EXECUTABLE="$HOME/Applications/Headroom.app/Contents/MacOS/Headroom"

# Match complete executable paths, never just a process name.
app_pids() {
    /bin/ps -axo pid=,comm= | while read -r candidate_pid candidate_executable; do
        if [[ "$candidate_executable" == "$BUILD_EXECUTABLE" || "$candidate_executable" == "$INSTALLED_EXECUTABLE" ]]; then
            printf '%s\n' "$candidate_pid"
        fi
    done
}

TASK_PIDS="$(app_pids)"
for task_pid in $TASK_PIDS; do
    # Graceful termination lets Headroom stop its owned helper.
    if ! kill -TERM "$task_pid" 2>/dev/null && kill -0 "$task_pid" 2>/dev/null; then
        echo 'Could not stop the existing Headroom app.' >&2
        exit 1
    fi
done
for attempt in {1..30}; do
    [[ -n "$(app_pids)" ]] || exit 0
    sleep 0.1
done
echo 'Headroom is still running; stopping the requested operation.' >&2
exit 1
