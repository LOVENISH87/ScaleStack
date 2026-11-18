# Lab application

A deliberately tiny HTTP service used to demonstrate the maintenance
workflow. It is not meant to be a real application.

- `GET /` — HTML page showing the server hostname and application version.
- `GET /health` — HTTP 200 when healthy. Returns HTTP 503 while the
  failure-injection marker file `/etc/health-app/unhealthy` exists.
- Listens on TCP 8080 as the unprivileged `healthapp` user.
- Managed as the `health-app.service` systemd unit. Puppet (not Ansible)
  owns the service lifecycle: see `puppet/manifests/app.pp`.
- `health_app.py` is deployed to `/opt/health-app/health_app.py` by the
  Ansible `app` role (`ansible/roles/app`).

Failure injection (returning 503 from `/health`) is done only by
`ansible/playbooks/failure_demo.yml` and always requires the explicit
`confirm_failure_injection=true` variable. It is never enabled by default.
The marker file is created/removed on demand and is never managed by Puppet,
so the rollback path never fights the configuration management layer.
