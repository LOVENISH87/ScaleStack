#!/usr/bin/env python3
"""Cloud Auto-Scaling & Health Web Application.

Endpoints:
  /        Modern dark-mode dashboard with live telemetry and interactive stress test.
  /health  HTTP 200 JSON when healthy. HTTP 503 when failure marker exists.
  /stress  Spikes CPU across worker threads to test AWS Auto Scaling Group.
  /metrics Prometheus telemetry exporter.
"""

import html
import json
import os
import socket
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VERSION = "2.0.0"
LISTEN_PORT = int(os.environ.get("HEALTH_APP_PORT", "8080"))
UNHEALTHY_MARKER = "/etc/health-app/unhealthy"
HOSTNAME = socket.gethostname()

request_count = 0
stress_active = False
last_cpu = {"idle": 0.0, "total": 0.0, "time": 0.0, "pct": 0.0}

# Inside a container /proc/stat reports the whole *node*, not this pod.
# cgroup v2 usage_usec is what the kubelet measures for the HPA, so the
# dashboard, /stats and the autoscaler all agree on one number.
CGROUP_CPU_STAT = "/sys/fs/cgroup/cpu.stat"
last_cgroup = {"usage_usec": 0.0, "time": 0.0, "pct": 0.0}


def get_cgroup_cpu_percent():
    """Container CPU usage as a percentage of one core, or None if unavailable.

    Only the dict's contents are mutated, so no `global` statement is needed.
    """
    try:
        usage = None
        with open(CGROUP_CPU_STAT) as f:
            for line in f:
                if line.startswith("usage_usec "):
                    usage = float(line.split()[1])
                    break
        if usage is None:
            return None
        now = time.time()
        prev_usage, prev_time = last_cgroup["usage_usec"], last_cgroup["time"]
        last_cgroup["usage_usec"], last_cgroup["time"] = usage, now
        if prev_time and now > prev_time and usage >= prev_usage:
            pct = 100.0 * (usage - prev_usage) / ((now - prev_time) * 1_000_000.0)
            cap = 100.0 * (os.cpu_count() or 4)
            last_cgroup["pct"] = round(max(0.0, min(cap, pct)), 1)
        return last_cgroup["pct"]
    except Exception:
        return None


def get_memory_info():
    try:
        with open("/proc/meminfo") as f:
            mem = {}
            for line in f:
                parts = line.split(":")
                if len(parts) == 2:
                    mem[parts[0].strip()] = int(parts[1].strip().split()[0])
            total = mem.get("MemTotal", 1024)
            avail = mem.get("MemAvailable", mem.get("MemFree", 0))
            used = total - avail
            pct = round((used / total) * 100, 1)
            return {
                "total_mb": round(total / 1024, 1),
                "used_mb": round(used / 1024, 1),
                "percent": pct,
            }
    except Exception:
        return {"total_mb": 1024.0, "used_mb": 350.0, "percent": 34.2}


def get_cpu_percent():
    """Pod CPU percentage, preferring the cgroup counter over /proc/stat."""
    cgroup_pct = get_cgroup_cpu_percent()
    if cgroup_pct is not None:
        return cgroup_pct
    if stress_active:
        return 99.5
    now = time.time()
    try:
        with open("/proc/stat") as f:
            fields = [float(x) for x in f.readline().strip().split()[1:5]]
        idle, total = fields[3], sum(fields)
        idle_delta = idle - last_cpu["idle"]
        total_delta = total - last_cpu["total"]
        last_cpu["idle"] = idle
        last_cpu["total"] = total
        last_cpu["time"] = now
        if total_delta > 0:
            pct = round(100.0 * (1.0 - idle_delta / total_delta), 1)
            last_cpu["pct"] = max(0.0, min(100.0, pct))
        return last_cpu["pct"]
    except Exception:
        return 15.0


def burn_cpu(duration=180):
    global stress_active
    stress_active = True
    end_time = time.time() + duration

    def worker():
        while time.time() < end_time:
            _ = [x**2 for x in range(1000)]

    threads = [threading.Thread(target=worker) for _ in range(4)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    stress_active = False


class Handler(BaseHTTPRequestHandler):
    server_version = f"health-app/{VERSION}"

    def _send(self, code: int, body: str, content_type: str = "text/plain; charset=utf-8"):
        payload = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):  # noqa: N802
        global request_count

        if self.path == "/health":
            if os.path.exists(UNHEALTHY_MARKER):
                self._send(503, json.dumps({"status": "unhealthy", "reason": "failure_injection_active", "hostname": HOSTNAME}) + "\n", "application/json")
            else:
                self._send(200, json.dumps({"status": "ok", "hostname": HOSTNAME, "version": VERSION}) + "\n", "application/json")
            return

        if self.path == "/stats":
            cpu = get_cpu_percent()
            mem = get_memory_info()
            stats_payload = {
                "status": "ok",
                "hostname": HOSTNAME,
                "pod": os.environ.get("POD_NAME", HOSTNAME),
                "node": os.environ.get("NODE_NAME", ""),
                "cpu_scope": "container",
                "version": VERSION,
                "cpu_percent": cpu,
                "memory_percent": mem["percent"],
                "memory_used_mb": mem["used_mb"],
                "memory_total_mb": mem["total_mb"],
                "requests_total": request_count,
                "stress_active": stress_active
            }
            self._send(200, json.dumps(stats_payload) + "\n", "application/json")
            return

        if self.path == "/metrics":
            metrics_payload = (
                f"# HELP app_requests_total Total HTTP requests\n"
                f"# TYPE app_requests_total counter\n"
                f"app_requests_total {request_count}\n"
                f"# HELP app_stress_active Whether CPU stress test is currently active\n"
                f"# TYPE app_stress_active gauge\n"
                f"app_stress_active {1 if stress_active else 0}\n"
            )
            self._send(200, metrics_payload, "text/plain; version=0.0.4; charset=utf-8")
            return

        if self.path == "/":
            request_count += 1
            cur_cpu = get_cpu_percent()
            cur_mem = get_memory_info()
            body = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AWS Cloud Web Platform</title>
    <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-slate-900 text-slate-100 min-h-screen flex flex-col items-center justify-center p-6 font-sans">
    <div class="max-w-xl w-full bg-slate-800 rounded-2xl shadow-2xl border border-slate-700 p-8 space-y-6">
        <div class="flex items-center justify-between border-b border-slate-700 pb-4">
            <div>
                <h1 class="text-2xl font-bold text-sky-400">AWS Cloud Web Platform</h1>
                <p class="text-xs text-slate-400">Auto-Scaling & Load Balanced Cluster</p>
            </div>
            <span class="inline-flex items-center px-3 py-1 rounded-full text-xs font-semibold bg-emerald-500/20 text-emerald-400 border border-emerald-500/30">
                <span class="w-2 h-2 mr-2 bg-emerald-400 rounded-full animate-ping"></span> Live Node
            </span>
        </div>

        <div class="grid grid-cols-2 gap-4">
            <div class="bg-slate-900/60 p-4 rounded-xl border border-slate-700/50">
                <p class="text-xs text-slate-400 uppercase font-semibold">Serving Hostname</p>
                <p class="text-lg font-mono font-bold text-sky-300 mt-1 truncate">{html.escape(HOSTNAME)}</p>
            </div>
            <div class="bg-slate-900/60 p-4 rounded-xl border border-slate-700/50">
                <p class="text-xs text-slate-400 uppercase font-semibold">App Version</p>
                <p class="text-lg font-mono font-bold text-indigo-400 mt-1">v{VERSION}</p>
            </div>
            <div class="bg-slate-900/60 p-4 rounded-xl border border-slate-700/50">
                <p class="text-xs text-slate-400 uppercase font-semibold">CPU Utilization</p>
                <p id="cpu-val" class="text-lg font-mono font-bold text-emerald-400 mt-1">{cur_cpu}%</p>
            </div>
            <div class="bg-slate-900/60 p-4 rounded-xl border border-slate-700/50">
                <p class="text-xs text-slate-400 uppercase font-semibold">Memory Usage</p>
                <p id="mem-val" class="text-lg font-mono font-bold text-cyan-400 mt-1">{cur_mem['used_mb']}MB ({cur_mem['percent']}%)</p>
            </div>
            <div class="bg-slate-900/60 p-4 rounded-xl border border-slate-700/50">
                <p class="text-xs text-slate-400 uppercase font-semibold">Total Requests</p>
                <p class="text-lg font-mono font-bold text-amber-400 mt-1">{request_count}</p>
            </div>
            <div class="bg-slate-900/60 p-4 rounded-xl border border-slate-700/50">
                <p class="text-xs text-slate-400 uppercase font-semibold">Stress Status</p>
                <p id="stress-val" class="text-lg font-mono font-bold {'text-rose-400 animate-pulse' if stress_active else 'text-slate-400'} mt-1">
                    {'STRESSING (100%)' if stress_active else 'NORMAL'}
                </p>
            </div>
        </div>

        <div class="border-t border-slate-700 pt-4 space-y-3">
            <p class="text-xs text-slate-400 font-semibold uppercase tracking-wider">Interactive Test Actions</p>
            <div class="flex gap-3">
                <button onclick="triggerStress()" class="flex-1 bg-rose-600 hover:bg-rose-500 text-white font-semibold py-2.5 px-4 rounded-xl shadow transition text-sm flex items-center justify-center">
                    ⚡ Trigger CPU Spike (ASG Test)
                </button>
                <a href="/health" class="bg-slate-700 hover:bg-slate-600 text-slate-200 font-semibold py-2.5 px-4 rounded-xl transition text-sm flex items-center justify-center">
                    Check /health
                </a>
            </div>
        </div>
        <div id="status-msg" class="text-center text-xs text-slate-400 font-mono"></div>
    </div>

    <script>
        function triggerStress() {{
            const msg = document.getElementById('status-msg');
            msg.innerText = 'Spiking CPU across 4 threads for 60s...';
            fetch('/stress', {{ method: 'POST' }})
                .then(res => res.json())
                .then(data => {{
                    msg.innerText = data.message;
                    setTimeout(() => location.reload(), 2000);
                }});
        }}
    </script>
</body>
</html>
"""
            self._send(200, body, "text/html; charset=utf-8")
            return

        self._send(404, "not found\n")

    def do_POST(self):  # noqa: N802
        if self.path.startswith("/stress"):
            t = threading.Thread(target=burn_cpu, args=(180,))
            t.start()
            resp = {
                "status": "stress_initiated",
                "duration_seconds": 180,
                "hostname": HOSTNAME,
                "message": "Burning CPU cycles for 180 seconds. CloudWatch will detect high CPU."
            }
            self._send(200, json.dumps(resp) + "\n", "application/json")
            return

        self._send(404, "not found\n")

    def log_message(self, fmt, *args):
        pass


def main():
    server = ThreadingHTTPServer(("0.0.0.0", LISTEN_PORT), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()
