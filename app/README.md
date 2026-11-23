# Lab application

The tiny HTTP service ScaleStack scales and patches. Stdlib only — no Flask,
no gunicorn, no pip install at build time.

- `GET /` — dashboard: pod hostname, version, live CPU/memory, request count.
- `GET /health` — 200 JSON when healthy (readiness/liveness probes and the ALB
  health check use this).
- `GET /stats` — JSON telemetry: `cpu_percent` (from cgroup v2 `cpu.stat`, so it
  matches what the HPA measures), `memory_percent`, `pod`, `node`, `cpu_scope`.
- `GET /metrics` — Prometheus text format.
- `POST /stress` — burns CPU for 180 s across 4 threads, to drive the HPA past
  its 40% target.

## Container contract

- Listens on `8080` (`HEALTH_APP_PORT`), non-root uid/gid `10001`.
- Reads `POD_NAME` and `NODE_NAME` from the Downward API for `/stats`.
- Runs with `readOnlyRootFilesystem: true`; only `/tmp` is writable.
- Image: `app/Dockerfile` (`python:3.12-slim`, ~124 MB).

## Health and failure

In the pod, health is owned by Kubernetes: the readiness probe fails on a
non-200 `/health`, the pod leaves the Service endpoints, and `kubectl rollout
status` reports the Deployment as not progressing. The Ansible node workflow
waits on that same rollout, so a pod that cannot come back healthy stops the
node patch instead of being silently returned to service.

`health_app.py` still honours the `/etc/health-app/unhealthy` marker file from
the original EC2/Puppet lab. Inside this container that path does not exist and
the root filesystem is read-only, so the marker cannot be created; the in-pod
equivalent is the readiness probe above.
