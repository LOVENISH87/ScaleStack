# PROJECT.md — Health-Gated Server Patching Lab

## Goal

Disposable lab demonstrating safe, gradual patching of a three-server web
application: Ansible patches one server at a time, gated on fresh health
checks, behind an AWS Application Load Balancer. Built for learning in
infrastructure you own.

## Success criteria

1. One server patched at a time; never two concurrently (`serial: 1`,
   `any_errors_fatal: true`).
2. Application stays available through the ALB during a run (at most one of
   three targets drained at any moment).
3. A patched server is verified (fresh local `/health` check over SSH) before
   being re-registered with the target group.
4. A failed health check stops the rollout immediately.
5. A report lists `patched`, `failed`, `in_progress`, and `not_attempted`
   servers plus the failed step and error details.
6. An unhealthy server is never silently re-added; recovery is manual.

## Component responsibilities

| Component | Owns | Does NOT own |
|---|---|---|
| Terraform | VPC, subnets, ALB, target group, EC2, security groups, outputs | OS configuration |
| Ansible | bootstrap, provisioning entry, ordered patch workflow (drain → patch → reboot → verify → re-add), reports, failure demo | app baseline enforcement |
| Puppet | app baseline: packages, systemd unit, service enabled + running | OS package upgrades, target-group operations |
| Nagios Core | independent monitoring: ALB, per-host HTTP/SSH/disk/load, alerts | rollout gating (Ansible's health check is the gate) |
| ALB | routing to healthy targets, per-target drain/register | health semantics (it only enforces HTTP 200 on /health) |

## Failure model

On any failure: halt, do not re-register the failed server, do not touch
remaining servers, report. Recovery = operator fixes the server, then re-runs
the playbook. OS updates are not rolled back automatically.

Failure injection (`failure_demo.yml`) creates `/etc/health-app/unhealthy`,
forcing HTTP 503 from `/health`. Opt-in only (`confirm_failure_injection=true`),
single explicit target, tag-filtered to this lab.

## Safety constraints

- Explicit confirmation variables required for patching and for injection.
- SSH restricted to `operator_cidr` everywhere; `0.0.0.0/0` rejected by
  Terraform validation for SSH.
- App servers expose no public HTTP.
- Secrets never in repo; tags `Project`/`Lab` identify all resources for
  teardown and for Ansible's dynamic inventory filter.
- No CI workflow that patches AWS.
