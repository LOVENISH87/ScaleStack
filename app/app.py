import html
import os
import socket
import threading
import time
from flask import Flask, jsonify, render_template_string, request

app = Flask(__name__)

VERSION = "2.0.0"
HOSTNAME = socket.gethostname()
PORT = int(os.environ.get("PORT", "5000"))
UNHEALTHY_MARKER = "/etc/health-app/unhealthy"

# In-memory request counter
request_count = 0
stress_active = False


def burn_cpu(duration=60):
    """Spins CPU cycles across threads to spike utilization."""
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


@app.route("/")
def home():
    global request_count
    request_count += 1
    html_page = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Cloud Auto-Scaling Web Platform</title>
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
                    <p class="text-lg font-mono font-bold text-sky-300 mt-1 truncate">{{ hostname }}</p>
                </div>
                <div class="bg-slate-900/60 p-4 rounded-xl border border-slate-700/50">
                    <p class="text-xs text-slate-400 uppercase font-semibold">App Version</p>
                    <p class="text-lg font-mono font-bold text-indigo-400 mt-1">v{{ version }}</p>
                </div>
                <div class="bg-slate-900/60 p-4 rounded-xl border border-slate-700/50">
                    <p class="text-xs text-slate-400 uppercase font-semibold">Total Requests</p>
                    <p class="text-lg font-mono font-bold text-amber-400 mt-1">{{ request_count }}</p>
                </div>
                <div class="bg-slate-900/60 p-4 rounded-xl border border-slate-700/50">
                    <p class="text-xs text-slate-400 uppercase font-semibold">Stress Status</p>
                    <p class="text-lg font-mono font-bold {% if stress %}text-rose-400 animate-pulse{% else %}text-slate-400{% endif %} mt-1">
                        {% if stress %}STRESSING (100%){% else %}NORMAL{% endif %}
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
            function triggerStress() {
                const msg = document.getElementById('status-msg');
                msg.innerText = 'Spiking CPU across 4 threads for 60s...';
                fetch('/stress', { method: 'POST' })
                    .then(res => res.json())
                    .then(data => {
                        msg.innerText = data.message;
                        setTimeout(() => location.reload(), 2000);
                    });
            }
        </script>
    </body>
    </html>
    """
    return render_template_string(
        html_page,
        hostname=HOSTNAME,
        version=VERSION,
        request_count=request_count,
        stress=stress_active,
    )


@app.route("/health")
def health():
    if os.path.exists(UNHEALTHY_MARKER):
        return jsonify({"status": "unhealthy", "reason": "marker_exists", "hostname": HOSTNAME}), 503
    return jsonify({"status": "ok", "hostname": HOSTNAME, "version": VERSION}), 200


@app.route("/stress", methods=["POST", "GET"])
def stress():
    duration = int(request.args.get("duration", 60))
    t = threading.Thread(target=burn_cpu, args=(duration,))
    t.start()
    return jsonify({
        "status": "stress_initiated",
        "duration_seconds": duration,
        "hostname": HOSTNAME,
        "message": f"Burning CPU cycles for {duration} seconds. CloudWatch will detect high CPU."
    })


@app.route("/metrics")
def metrics():
    return f"""# HELP app_requests_total Total HTTP requests
# TYPE app_requests_total counter
app_requests_total {request_count}
# HELP app_stress_active Whether CPU stress is burning
# TYPE app_stress_active gauge
app_stress_active {1 if stress_active else 0}
"""


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=PORT)
