#!/usr/bin/env python3
"""Measure Headroom and only its descendants across a complete refresh cycle."""
import json
import subprocess
import time

def snapshot():
    rows = {}
    raw = subprocess.check_output(["ps", "-axo", "pid=,ppid=,time=,rss=,comm="], text=True)
    for line in raw.splitlines():
        fields = line.split(None, 4)
        if len(fields) != 5:
            continue
        pid, parent, cpu, rss, name = fields
        parts = cpu.split(":")
        seconds = 0.0
        for part in parts:
            seconds = seconds * 60 + float(part)
        rows[int(pid)] = dict(pid=int(pid), parent=int(parent), cpu_seconds=seconds,
                              rss_mib=int(rss) / 1024, name=name.rsplit("/", 1)[-1])
    roots = {pid for pid, row in rows.items() if row["name"] == "Headroom"}
    if len(roots) != 1:
        raise SystemExit("Launch exactly one Headroom app before measuring.")
    selected = set(roots)
    while True:
        children = {pid for pid, row in rows.items() if row["parent"] in selected}
        if children <= selected:
            break
        selected |= children
    return {pid: rows[pid] for pid in selected}

start = snapshot()
peak_rss = sum(row["rss_mib"] for row in start.values())
begin = time.monotonic()
for _ in range(7):
    time.sleep(10)
    end = snapshot()
    peak_rss = max(peak_rss, sum(row["rss_mib"] for row in end.values()))
if start.keys() != end.keys():
    raise SystemExit("Process tree changed during measurement; repeat after connection settles.")
elapsed = time.monotonic() - begin
cpu_seconds = sum(end[pid]["cpu_seconds"] - start[pid]["cpu_seconds"] for pid in start)
print(json.dumps(dict(duration_seconds=round(elapsed, 2), cpu_seconds=round(cpu_seconds, 3),
                      average_cpu_percent_one_core=round(cpu_seconds / elapsed * 100, 3),
                      peak_combined_rss_mib=round(peak_rss, 2),
                      processes=list(end.values())), indent=2))
