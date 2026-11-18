# Health-Gated Server Patching (Learning Lab)

> **For learning in infrastructure you own only. The failure injection is for
> this lab. Never use this project to patch arbitrary or production systems.**

A disposable AWS lab that demonstrates safe, gradual patching of a three-server
web application behind an Application Load Balancer. Ansible patches one server
at a time: it removes the server from the load balancer, patches and reboots it,
verifies it with a fresh health check, and only then returns it to service.
If any server fails verification, the rollout stops immediately, the failed
server stays out of the target group, and the remaining servers are not touched.

## Architecture

```
                Internet
                   |
              +----v----+        HTTP /health, /
              |   ALB   |  (internet-facing, port 80)
              +----+----+  target group: health-gated-patching-tg
                   | HTTP :8080
     +-------------+-------------+
     |             |             |
 +---v---+    +----v---+    +----v---+
 | app-1 |    | app-2  |    | app-3  |   Ubuntu 24.04, health-app on :8080
 +-------+    +--------+    +--------+   SSH from your CIDR only; no public HTTP

 +-------------+
 | Nagios Core |  checks: ALB /health + /, per-app HTTP/SSH/disk/load
 +-------------+  web UI + SSH from your CIDR only
```

- **Terraform** creates/destroys the lab (VPC, ALB, target group, 3 app
  servers, 1 Nagios server, security groups).
- **Ansible** bootstraps the lab and runs the ordered patch workflow.
- **Puppet** owns the application baseline on each app server: required
  packages, the systemd unit, enabling and running the service. Puppet does
  **not** upgrade OS packages; Ansible owns package patching.
- **Nagios Core** continuously monitors the ALB and the app servers. Nagios is
  an independent monitoring system; the immediate per-server rollout gate is
  Ansible's fresh health check (a Nagios check result can lag behind).
- **AWS ALB** routes requests to healthy targets and supports deregister /
  drain / re-register per server.

## Repository layout

```
terraform/    Terraform config (VPC, ALB, target group, instances, SGs, outputs)
ansible/      ansible.cfg, dynamic AWS inventory (tag-filtered to this lab),
              group_vars, and playbooks: bootstrap, patch, configure_nagios,
              failure_demo. Roles: app, puppet_baseline, nagios, patch_report.
puppet/       Application baseline manifest (puppet/manifests/app.pp)
app/          The demo HTTP application + systemd unit + its own README
```

Note: Ansible group/host vars live in `ansible/inventory/group_vars/`
(Ansible loads group_vars adjacent to the inventory file).

## Prerequisites

- An AWS account you own, with permission to create VPC/EC2/ALB resources.
- An AWS EC2 key pair in your region.
- Locally: Terraform >= 1.5, Ansible (>= 2.15), AWS CLI v2, Python 3, `curl`.
  Collections: `amazon.aws` and `community.general` (see `ansible/requirements.yml`).
  The dynamic inventory plugin also needs `boto3`/`botocore` on the control
  machine, e.g. `pip install boto3 botocore`.
- Your public IP address (for `operator_cidr`) — SSH to every lab instance is
  restricted to it, and the Nagios web UI is reachable from it only.

## Configure AWS credentials locally (never commit them)

```bash
# Option A: aws configure (writes ~/.aws/credentials, chmod 600)
aws configure

# Option B: environment variables
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...

export AWS_REGION=us-east-1          # used by Terraform, Ansible, aws CLI
export PROJECT_NAME=health-gated-patching   # optional, this is the default
```

Do not put credentials in any file inside this repository. `.gitignore` covers
state files, tfvars and key material — keep it that way.

Create `terraform/terraform.tfvars` (gitignored) from the example and set your
region, operator CIDR and key pair:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# edit: operator_cidr = "<your-public-ip>/32", ssh_key_name = "<your-keypair>"
```

`operator_cidr` must never be `0.0.0.0/0` (Terraform validates this).

SSH from Ansible: the playbooks connect with your SSH key. Either add a
`Host` stanza for the lab instance IPs to `~/.ssh/config` (recommended, since
they change only when you re-apply), or export:

```bash
export ANSIBLE_SSH_ARGS='-o IdentityFile=/path/to/your-key.pem -o IdentitiesOnly=yes'
```

## Validate and plan Terraform

```bash
cd terraform
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan            # review before applying; costs real money
```

## Create the infrastructure (costs money; destroy when done)

```bash
cd terraform
terraform apply           # type 'yes' to create
terraform output          # alb_url, target_group_arn, IPs, instance IDs
```

Expected monthly cost (us-east-1, t3.micro x4 + ALB, Nov 2026, on-demand):
~4 × $7.60 + ALB ~$16–22 + minor data transfer ≈ **$50/month** if left running.
Actual cost varies. **Destroy the lab when you are done** (see below).

## Bootstrap and configure

```bash
cd ansible

# one-time: install required collections
ansible-galaxy collection install -r requirements.yml

# connectivity check
ansible-inventory --graph
ansible all -m ping

# 1. bootstrap app servers (deploy app + puppet baseline + local health verify)
ansible-playbook playbooks/bootstrap.yml

# 2. configure Nagios (password is required and never committed)
ansible-playbook playbooks/configure_nagios.yml \
  -e nagios_admin_password='<choose-a-strong-password>' \
  -e nagios_alert_email='you@example.com'
```

Access:

- Application: `http://$(cd ../terraform && terraform output -raw alb_dns_name)/`
  - `/health` returns HTTP 200
  - `/` shows the hostname + application version of whichever instance served you
- Nagios: Ubuntu's nagios4 package restricts the web UI and cgi-bin/cmd.cgi
  to private IP ranges by default (see `/etc/nagios4/apache2.conf`), so the
  supported way to view it is an SSH tunnel from your operator machine:

  ```bash
  ssh -N -L 8099:127.0.0.1:80 -i /path/to/your-key.pem ubuntu@<nagios_public_ip>
  # then open http://127.0.0.1:8099/nagios4/
  ```

  The lab security group also allows port 80 from your operator CIDR, but the
  packaged Apache config only grants the UI on loopback/RFC1918 addresses.
  The digest-protected `cmd.cgi` uses realm `Nagios4`, user `nagiosadmin` and
  the password you passed (`RoY…`-style, only if you kept the generated one).
- ALB and app checks via Nagios: see Hosts/Services views.

## Non-destructive patch preview (no changes made)

```bash
cd ansible
ansible-playbook playbooks/patch.yml --check \
  -e confirm_patch=true \
  -e target_group_arn=$(terraform -chdir=../terraform output -raw target_group_arn)
```

Check mode previews the tasks without deregistering targets or upgrading
packages (read-only AWS queries still run).

## Run the confirmed patch workflow

```bash
cd ansible
ansible-playbook playbooks/patch.yml \
  -e confirm_patch=true \
  -e target_group_arn=$(terraform -chdir=../terraform output -raw target_group_arn)
```

What happens per server (strictly serial, one at a time):

1. `confirm_patch=true` is required; the target group ARN is required.
2. The server is verified to be a member of the Terraform-managed target group.
3. The server is recorded `in_progress` in `patch-report-<timestamp>.json`.
4. The server is deregistered from the target group; Ansible waits until the
   ALB reports state `unused` (drain complete, ~15s deregistration delay).
5. `apt-get dist-upgrade` is applied.
6. The server reboots **only if** `/var/run/reboot-required` exists.
7. Ansible waits for SSH (up to 600s), then runs a *fresh* health check
   (`curl http://127.0.0.1:8080/health` over SSH — the app port is not
   publicly reachable by design).
8. The server is re-registered and Ansible waits until the ALB reports it
   `healthy` before moving on.
9. The server is recorded `patched`.

If any step fails, the rollout halts immediately: the failed server is **not**
re-registered, remaining servers are **not** patched, and a report of
`patched` / `failed` / `not_attempted` servers plus the failed step and error
details is printed (and saved in `patch-report-<timestamp>.json`).

This workflow **does not roll back OS package updates**. It stops safely and
reports; recovery is an operator action.

The application stays available through the ALB during patching because at
most one of three targets is out of rotation at any time.

## Failure demonstration (opt-in, lab only)

```bash
cd ansible

# pick one app server from the inventory
APP_HOST=$(ansible-inventory --graph app_servers | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)

# 1. inject failure: /health now returns 503 (marker file, no reboot needed)
ansible-playbook playbooks/failure_demo.yml --limit "$APP_HOST" \
  -e confirm_failure_injection=true \
  -e failure_demo_target="$APP_HOST" \
  -e failure_demo_action=inject

# 2. run the patch workflow — it will drain, patch, reboot, then FAIL the
#    health check on that server and HALT. The server stays out of the ALB.
ansible-playbook playbooks/patch.yml \
  -e confirm_patch=true \
  -e target_group_arn=$(terraform -chdir=../terraform output -raw target_group_arn)

# 3. verify: the failed server is not in the target group; later servers untouched
aws elbv2 describe-target-health \
  --target-group-arn "$(terraform -chdir=../terraform output -raw target_group_arn)" \
  --region "$AWS_REGION"
cat ../patch-report-*.json

# 4. restore health and re-run the workflow to complete the rollout
ansible-playbook playbooks/failure_demo.yml --limit "$APP_HOST" \
  -e confirm_failure_injection=true \
  -e failure_demo_target="$APP_HOST" \
  -e failure_demo_action=restore

ansible-playbook playbooks/patch.yml \
  -e confirm_patch=true \
  -e target_group_arn=$(terraform -chdir=../terraform output -raw target_group_arn)
```

To recover a server left out of rotation after a failed run: fix the cause
(e.g. disk full, bad package), restore or remove `/etc/health-app/unhealthy`,
confirm `curl http://127.0.0.1:8080/health` returns 200 from the server, then
re-run `playbooks/patch.yml` — it will patch and re-add it.

## Nagios checks

`configure_nagios.yml` installs Nagios Core 4 and monitoring plugins and
renders `/etc/nagios4/conf.d/health-gated-patching.cfg` with:

- Host + service checks for the ALB: `/health` and `/` (HTTP 200 expected)
- Per app server: HTTP health on `:8080`, SSH on port 22, disk `/` (warn 20% /
  crit 10%), load (warn 2 / crit 4)
- A `lab_admin` contact (email via `nagios_alert_email`) grouped into
  `lab_admins`; alerts name the failing host/service and include check output.
  Note: delivery requires a working MTA on the Nagios server — the lab uses
  `bsd-mailx`; without an MTA, alerts are visible in the web UI only.
- All monitoring traffic flows only from the Nagios security group (least
  privilege): HTTP `:8080` and SSH `:22` to app servers, operator-only web UI.
  The role enables `a2enmod cgid` (required for the CGI status pages), writes a
  Digest-authenticated `cmd.cgi` user (realm `Nagios4`), and removes the distro
  default `Swap Usage` check (t3.micro has no swap and would always alert).

Nagios can lag several minutes behind reality. The rollout gate is always
Ansible's fresh health check, never a Nagios result.

## Destroy everything and verify cleanup

```bash
cd terraform
terraform destroy    # type 'yes'
terraform show       # should print no resources
aws elbv2 describe-load-balancers --region "$AWS_REGION"   # lab ALB gone?
aws ec2 describe-instances --region "$AWS_REGION" \
  --filters Name=tag:Project,Values=health-gated-patching \
           Name=instance-state-name,Values=running,pending,stopping \
  # no lab instances remain
```

## Cost warning

This lab creates billable resources (ALB, EC2, EBS). Run `terraform destroy`
as soon as you finish; otherwise expect roughly $50/month (us-east-1, on-demand
prices as of Nov 2026). Unused EC2 capacity is billed hourly regardless of
whether the app is idle.

## Security notes / constraints enforced

- SSH to all instances only from `operator_cidr`; Terraform rejects
  `operator_cidr = 0.0.0.0/0`. Nothing else is exposed to the internet.
- App servers have **no** public HTTP ingress. Traffic reaches them only from
  the ALB SG (app port) or the Nagios SG (health check port and SSH).
- No credentials in the repo; `.gitignore` excludes keys, tfvars, state,
  plans, generated reports and Ansible artifacts.
- All lab resources carry `Project=health-gated-patching`, `Lab=true` tags.
- Failure injection requires `confirm_failure_injection=true`, one explicit
  target in the tag-filtered inventory, and is never enabled by default.
- The patch playbook requires `confirm_patch=true`; there is no way to enable
  patching "by default".
- No CI workflow in this repository can or should patch AWS infrastructure.

## Limitations (by design)

- No automatic rollback of OS updates. Stopping safely is the mitigation;
  restoring a bad server is an operator action.
- Distribution upgrades can trigger different reboot behavior per host; the
  playbook reboots only when `/var/run/reboot-required` exists.
- Single-AZ-per-subnet layout is minimal (2 public subnets across 2 AZs; ALB
  is the only cross-AZ component). This is a learning lab, not HA guidance.

## Validation

```bash
cd terraform && terraform init -backend=false && terraform validate && terraform fmt -check -recursive
cd ../ansible && ansible-playbook --syntax-check playbooks/bootstrap.yml playbooks/patch.yml playbooks/configure_nagios.yml playbooks/failure_demo.yml
```
