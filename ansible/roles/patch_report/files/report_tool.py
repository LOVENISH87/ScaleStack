#!/usr/bin/env python3
"""Tiny JSON report helper for the patch workflow.

Usage:
  report_tool.py init <report_file> <run_id>
  report_tool.py append <report_file>            # event JSON read from $PATCH_EVENT
  report_tool.py summary <report_file> <expected_csv>

The report file is a JSON object:
  {"run_id": "...", "events": [ {server, status, step, details, time}, ... ]}
"""

import csv
import json
import os
import sys
import datetime


def load(path):
    with open(path) as fh:
        return json.load(fh)


def save(path, doc):
    with open(path, "w") as fh:
        json.dump(doc, fh, indent=2)


def cmd_init(path, run_id):
    if os.path.exists(path):
        stamp = datetime.datetime.now().strftime("%Y%m%dT%H%M%S")
        backup = f"{path}.bak-{stamp}"
        os.replace(path, backup)
        print(f"existing report moved to: {backup}")
    save(path, {"run_id": run_id, "events": []})
    print(f"report initialized: {path} (run_id={run_id})")


def cmd_append(path):
    event = json.loads(os.environ["PATCH_EVENT"])
    doc = load(path)
    doc["events"].append(event)
    save(path, doc)
    print(f"recorded: {event['server']} -> {event['status']}"
          + (f" (step: {event.get('step')})" if event.get("step") else ""))


def cmd_summary(path, expected_csv):
    doc = load(path)
    expected = [h for h in next(csv.reader([expected_csv])) if h]
    latest = {}
    order = []
    for ev in doc["events"]:
        server = ev["server"]
        if server not in latest:
            order.append(server)
        latest[server] = ev

    patched = [s for s, e in latest.items() if e["status"] == "patched"]
    failed = [s for s, e in latest.items() if e["status"] == "failed"]
    in_progress = [s for s, e in latest.items() if e["status"] == "in_progress"]
    not_attempted = [s for s in expected if s not in latest]

    summary = {
        "run_id": doc["run_id"],
        "patched": patched,
        "failed": failed,
        "in_progress": in_progress,
        "not_attempted": not_attempted,
        "events": doc["events"],
    }

    print("=" * 70)
    print(f"PATCH RUN REPORT  run_id={doc['run_id']}")
    print("=" * 70)
    print(f"patched       ({len(patched)}): {', '.join(patched) or '-'}")
    print(f"failed        ({len(failed)}): {', '.join(failed) or '-'}")
    print(f"in_progress   ({len(in_progress)}): {', '.join(in_progress) or '-'}")
    print(f"not attempted ({len(not_attempted)}): {', '.join(not_attempted) or '-'}")
    for s, e in latest.items():
        if e["status"] == "failed":
            print(f"FAILED server={s} step={e.get('step')} details={e.get('details')}")
    print("=" * 70)
    print("Summary JSON:")
    print(json.dumps(summary, indent=2))


def main():
    if len(sys.argv) < 3:
        sys.exit("usage: report_tool.py init|append|summary ...")
    cmd = sys.argv[1]
    if cmd == "init":
        cmd_init(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else
                 datetime.datetime.now().strftime("%Y%m%dT%H%M%S"))
    elif cmd == "append":
        cmd_append(sys.argv[2])
    elif cmd == "summary":
        cmd_summary(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "")
    else:
        sys.exit(f"unknown command: {cmd}")


if __name__ == "__main__":
    main()
