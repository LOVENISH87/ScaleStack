# ScaleStack — EKS Autoscaling & Health-Gated Patching (Learning Lab)

> **For learning in infrastructure you own only.** The failure and stress paths
> are for this lab. Never point them at production systems.

A disposable AWS lab for INT333 (Advanced Configuration Management). A small
web application runs on **EKS** with **Spot worker nodes**, scales itself with an
**HPA at 40% CPU**, is fronted by an **Application Load Balancer**, reports live
telemetry on `/stats`, and is monitored by a **containerized Nagios Core**.
A serial Ansible workflow patches the worker nodes one at a time
(**cordon → drain → patch → reboot → uncordon**) so the application stays
available throughout.

Everything is created and destroyed with Terraform; nothing bills while
`terraform destroy` has run.

## What the lab demonstrates

| Concern | Implementation |
| --- | --- |
| Orchestration | EKS 1.35 control plane, managed **Spot** node group (`t3.medium`) |
| Autoscaling | HPA v2, min 2 / max 6 replicas, target **40% CPU** of the pod request |
| Load balancing | ALB (port 80) → instance target group → fixed **NodePort 30080** |
| Zero-downtime rollout | RollingUpdate `maxUnavailable: 0`, readiness + liveness probes, PodDisruptionBudget `maxUnavailable: 1` |
| Telemetry | `/stats` reads cgroup v2 `cpu.stat`, so it reports **pod** CPU — the same number the HPA uses |
| Monitoring | Nagios Core 4 **as a pod**, UI path-routed by the same ALB at `/nagios/` |
| Patching | Ansible: cordon, drain (PDB respected), `dnf`/`apt` upgrade, reboot if needed, uncordon, wait Ready |
| Cost control | Spot capacity, 2 nodes, single NAT-free VPC, `terraform destroy` as the last step |

## Architecture

```
                        Internet
                           |
                    +------v------+
                    |     ALB     |  :80  (one listener, two target groups)
                    +--+-------+--+
          default      |       |      /nagios, /nagios/*
             +---------+       +---------+
             |                           |
   HTTP :30080 (NodePort)      HTTP :30081 (NodePort)
             |                           |
+------------v---------------------------v-------------+
|  EKS managed Spot node group (2 x t3.medium, AL2023)  |
|                                                      |
|  scalestack-web Deployment (2..6 pods)               |
|    - HPA 40% CPU   - PDB maxUnavailable 1             |
|    - probes on /health                               |
|                                                      |
|  scalestack-nagios Deployment (1 pod)                |
+------------------------------------------------------+
             |                        |
      ECR image pulls          S3 log bucket (+ Lambda log processor)

  Control plane: EKS 1.35, public + private endpoint
  SSH :22 to nodes only from operator_cidr (Ansible patching)
```

Design choices worth knowing before you read the code:

- **No Helm, no AWS Load Balancer Controller, no `aws-auth` editing.** The ALB
  uses *instance* targets on a fixed NodePort, and the node group's ASG is
  attached to the target groups with `aws_autoscaling_attachment`. EKS does not
  reconcile that attachment, so it is stable.
- **No Kubernetes provider in Terraform.** The IAM principal that runs
  `terraform apply` creates the cluster and therefore gets `system:masters`, and
  EKS enrolls the managed node group's role automatically. `kubectl` work starts
  from `scripts/k8s-bootstrap.sh`, not from Terraform.
- **Nagios is a pod, not a host.** Its config is rendered at container start
  from the ALB DNS name, and its UI rides the existing ALB under `/nagios/`.

## Repository layout

```
terraform/    VPC, ALB + target groups + listener rule, EKS cluster, Spot node
              group, ECR, S3, Lambda, security groups, outputs
k8s/          00-namespace, 10-deployment, 20-service, 30-hpa, 40-pdb,
              50-nagios, 60-log-archive
nagios/       Nagios image: Dockerfile, entrypoint, Apache config, object config
log-archive/  CronJob image + script that ships pod logs to S3
app/          Demo HTTP application (stdlib only), Dockerfile
scripts/      k8s-bootstrap.sh, kind-smoke-test.sh, kind-config.yaml
ansible/      inventory (tag-filtered AWS dynamic inventory), group_vars,
              playbooks/patch.yml, roles/patch_report
lambda/       S3 log processor function source
puppet/       EC2-era Puppet baseline (course artifact, unused on EKS)
diagrams/     Architecture diagrams
```

## Prerequisites

- An AWS account you own, with permission to create VPC, EC2, EKS, IAM, ALB,
  ECR, S3 and Lambda resources.
- An EC2 key pair in your region (Ansible uses it to reach the worker nodes).
- Locally: Terraform >= 1.5, AWS CLI v2, `kubectl` (1.31+), Docker, `curl`,
  Python 3, Ansible >= 2.15 with `amazon.aws` (`ansible-galaxy collection
  install -r ansible/requirements.yml`) and `boto3`/`botocore` for the dynamic
  inventory.
- Your public IP for `operator_cidr` — SSH to nodes and nothing else is exposed.

Terraform and Ansible both read the standard AWS credential chain. Never put
credentials, `terraform.tfvars`, keys or state in the repository; `.gitignore`
already excludes them.

```bash
export AWS_REGION=ap-south-1
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# edit: operator_cidr = "<your-public-ip>/32", ssh_key_name = "<your-keypair>"
```

`operator_cidr` cannot be `0.0.0.0/0` (Terraform validates this). Confirm
`kubernetes_version` is still in **EKS standard support** in your region, or you
pay extended-support pricing:

```bash
aws eks describe-cluster-versions --region "$AWS_REGION" \
  --query 'clusterVersions[?clusterVersion==`1.35`].{version:clusterVersion,status:status}'
```

## 1. Create the infrastructure

```bash
cd terraform
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan      # 34-40 resources on a fresh account
terraform apply
```

Outputs used below: `cluster_name`, `alb_dns_name`, `nagios_url`,
`ecr_repository_url`, `kubeconfig_command`.

## 2. Build and push the two images

`terraform/ecr.tf` creates one repository; both images are tags of it.

```bash
cd terraform
REPO=$(terraform output -raw ecr_repository_url)
REGISTRY=${REPO%%/*}
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

docker build -t "$REPO:v1" ../app
docker push "$REPO:v1"

docker build -t "$REPO:nagios" ../nagios
docker push "$REPO:nagios"

docker build -t "$REPO:log-archive" ../log-archive
docker push "$REPO:log-archive"
```

## 3. Deploy to the cluster

```bash
IMAGE_URI="$REPO:v1" \
NAGIOS_IMAGE_URI="$REPO:nagios" \
LOG_ARCHIVE_IMAGE_URI="$REPO:log-archive" \
NAGIOS_ADMIN_PASSWORD='<choose-a-strong-password>' \
  ../scripts/k8s-bootstrap.sh
```

The script points `kubectl` at the cluster, creates the namespace and the
Nagios ConfigMap/Secret, applies `k8s/`, sets both images, installs
**metrics-server** (EKS does not ship it, and without it the HPA stays at
`<unknown>/40%`), and waits for the HPA to report CPU.

The Nagios password is passed as an environment variable and stored only as a
Kubernetes Secret. It is never written into the repository.

## 4. Verify autoscaling at 40%

```bash
ALB=$(terraform -chdir=terraform output -raw alb_dns_name)

curl -s "http://$ALB/health"      # {"status": "ok", ...}
curl -s "http://$ALB/stats"       # pod CPU%, pod name, node name

kubectl -n scalestack get hpa scalestack-web -w
```

In a second terminal, push load into the pods:

```bash
for _ in $(seq 1 12); do curl -s -X POST "http://$ALB/stress" >/dev/null; done
```

Each `POST /stress` burns CPU for 180 s. Watch the HPA: utilisation crosses
40%, `REPLICAS` climbs toward 6, and the new pods go Ready within a couple of
seconds (small stdlib image, `initialDelaySeconds: 1` readiness probe). After
the stress ends, scale-down stabilises at 2 replicas within ~60 s.

## 5. Nagios UI

```
http://<alb_dns_name>/nagios/     user: nagiosadmin   password: NAGIOS_ADMIN_PASSWORD
```

The ALB forwards `/nagios`, `/nagios/*` to NodePort 30081 (`priority 10` listener
rule); everything else goes to the app. The pod checks:

- the ALB: `/health` and `/` (HTTP 200 expected)
- the in-cluster Service `scalestack-web.scalestack.svc.cluster.local`: `/health`
- pod CPU and pod memory via `check_system_metrics.py` (INT333 Practical 8),
  reading `/stats` from the application

Notes: alerts are **UI-only** (the image ships no MTA), and Nagios history lives
in the pod, so a restart clears it. The target group health check uses the
unauthenticated `/healthz` endpoint, so digest auth never breaks it.

## 6. Health-gated node patching

```bash
cd ansible
ansible-inventory --graph          # -> eks_nodes: the Spot worker nodes
ansible-playbook playbooks/patch.yml -e confirm_patch=true
```

Preview without changing anything:

```bash
ansible-playbook playbooks/patch.yml --check -e confirm_patch=true
```

Per node, strictly serial (`serial: 1`, `any_errors_fatal: true`):

1. `confirm_patch=true` is required; `kubectl` must work on the controller.
2. The node is resolved from this instance's IP via `kubectl get nodes -o wide`,
   and the play refuses to touch a node it cannot identify.
3. `kubectl cordon` — no new pods land here.
4. `kubectl drain --ignore-daemonsets --delete-emptydir-data --timeout=300s` —
   this **respects the PodDisruptionBudget** (`maxUnavailable: 1`), so only one
   application pod leaves at a time and the other replica keeps serving.
5. `dnf -y upgrade` on AL2023 (`apt-get dist-upgrade` if the node is Debian).
6. Reboot only if required: a newer kernel than `uname -r` (AL2023) or
   `/var/run/reboot-required` (apt).
7. Wait for SSH, then `kubectl uncordon`, `kubectl wait node --for=condition=Ready`,
   and `kubectl rollout status deployment/scalestack-web`.
8. Record the node as `patched` in `patch-report.json`.

If any step fails the rollout **halts immediately**: the node is left
**cordoned** (so nothing new is scheduled on a half-patched node), remaining
nodes are **not** patched, and the report lists the failed step and details.
Recovery is an operator action — finish the patch or replace the node, then
`kubectl uncordon <node>`. There is no automatic rollback of package updates.

The node-side work deliberately uses Ansible's `raw` module: the EKS AL2023 AMI
is assumed, but the play does not depend on a Python interpreter being present,
and `raw` also survives the reboot boundary.

> **Caveat that matters for the write-up:** patching node packages in place is
> the teaching path here. The *supported* production approach is to build a new
> AMI / node group version and let the managed node group roll nodes, which is
> what EKS expects. In-place `dnf upgrade` drifts from the managed AMI until the
> node is replaced.

## 7. Log archiving

The CronJob `scalestack-log-archive` runs every 15 minutes on one node. It reads
that node's kubelet log directory (`/var/log/pods`, mounted read-only as a
hostPath), tars the `scalestack_*` log files touched in the last hour, and
uploads one object per run:

```
s3://<bucket>/logs/<node-name>/<UTC timestamp>.tar.gz
```

That key matches the bucket notification (`prefix logs/`, `suffix .tar.gz`), so
every upload invokes the `scalestack-s3-log-processor` Lambda. Credentials are
the node's IAM role (`s3:PutObject` on this bucket only) — no static keys — and
the launch template's `http_put_response_hop_limit = 2` is what lets a pod reach
the instance metadata service to pick that role up.

Run one immediately and follow it:

```bash
kubectl -n scalestack create job --from=cronjob/scalestack-log-archive log-archive-now
kubectl -n scalestack logs job/log-archive-now -f

BUCKET=$(terraform -chdir=terraform output -raw s3_bucket_name)
aws s3 ls "s3://$BUCKET/logs/" --recursive
aws logs tail "/aws/lambda/$(terraform -chdir=terraform output -raw lambda_function_name)" --follow
```

Inspect an archive without downloading it:

```bash
aws s3 cp "s3://$BUCKET/logs/<node>/<timestamp>.tar.gz" - | tar -tzf -
```

Archiving is best-effort by design: it ships what the kubelet still has on disk
inside the window, so logs rotated away before a run are not recovered.

## Cost

Roughly **$0.15/hour** in `ap-south-1` (Nov 2026, prices change — check the
current pricing page):

| Item | Estimate |
| --- | --- |
| EKS control plane | $0.10/hr (standard support — no extended-support fee) |
| 2 × Spot `t3.medium` | ~$0.025/hr |
| ALB + minimal LCU | ~$0.03/hr |
| EBS 2 × 20 GB gp3 | ~$0.006/hr |

A 2–3 hour evaluation is about **$0.30–$0.45**, dominated by the control plane.
The HPA can raise pods to 6, but they fit inside the two nodes, so pod count
does not add EC2 cost.

If Spot capacity is constrained in your AZ, widen the types:

```hcl
node_instance_types = ["t3.medium", "t3a.medium", "t3.large"]
```

## Destroy everything

```bash
cd terraform
terraform destroy        # type 'yes'

aws eks list-clusters --region "$AWS_REGION"
aws elbv2 describe-load-balancers --region "$AWS_REGION" \
  --query 'LoadBalancers[?contains(LoadBalancerName, `scalestack`)]'
aws ec2 describe-instances --region "$AWS_REGION" \
  --filters Name=tag:Project,Values=scalestack \
            Name=instance-state-name,Values=running,pending,stopping \
  --query 'Reservations[].Instances[].InstanceId'
```

All three should come back empty. Billing after a clean destroy is zero: there
is no NAT gateway, no idle EC2, and the EKS control plane is deleted with the
cluster.

## Security notes

- Nothing is reachable from the internet except the ALB on port 80.
- Worker nodes accept the app only on NodePort 30080 and Nagios only on 30081,
  and both only from the ALB security group. SSH is limited to `operator_cidr`.
- Pods run non-root with `readOnlyRootFilesystem`, all capabilities dropped and
  `RuntimeDefault` seccomp; the Nagios appliance pod is the documented exception
  (Apache needs root to bind port 80 and setuid to `www-data`).
- App containers are pinned by image tag at deploy time; no floating `latest` in
  the cluster manifests.
- The Nagios password exists only as a Kubernetes Secret and in the operator's
  shell history — pass it from a password manager, not from a file in the repo.
- No credentials, keys, tfvars, state files or generated reports are tracked in
  git.
- `confirm_patch=true` is required; there is no default-on patching, and no CI
  workflow in this repository patches infrastructure.

## Limitations (by design)

- Single-AZ-per-subnet layout, public subnets only, no NAT gateway. This is a
  learning lab, not an HA reference.
- No ingress controller / AWS Load Balancer Controller: a node that is drained
  temporarily loses its NodePort listener, but the ALB target group removes it
  from rotation, so requests still succeed.
- Nagios alerts are UI-only and history is not persisted.
- `/stats` reports container CPU (what the HPA measures) but **node-level
  memory** from `/proc/meminfo`; a pod-scoped memory value from cgroup
  `memory.current` is a known gap.
- `puppet/` is the original EC2/Puppet app baseline. Nothing on EKS runs it, so
  it is kept as a course artifact rather than as enforcement; the workload
  baseline is the manifests plus the image.
- There is no in-cluster failure-injection endpoint. In EKS the health gate is
  the readiness probe and `kubectl rollout status`; the old `/health` marker
  file needs a writable `/etc/health-app` that the hardened pod does not have.
- Log archives are per-node and per-window, not a complete audit trail: the
  CronJob has no persistent state and the Lambda only records object metadata.

## Validation

```bash
cd terraform && terraform init -backend=false && terraform validate \
  && terraform fmt -check -recursive

bash -n scripts/k8s-bootstrap.sh scripts/kind-smoke-test.sh \
           nagios/entrypoint.sh log-archive/archive_pod_logs.sh

python3 -m py_compile app/health_app.py nagios/check_system_metrics.py
pip install flake8 && flake8 app/ nagios/ lambda/          # config: .flake8

# Manifest schema check, offline (no cluster, no credentials)
kubeconform -strict -summary -ignore-missing-schemas k8s/

cd ../ansible && ansible-playbook --syntax-check playbooks/patch.yml

# Manifests + HPA behaviour without spending money (1-CPU Docker VM needs ~4 CPUs
# for the control plane and metrics-server to fit):
WITH_NAGIOS=1 scripts/kind-smoke-test.sh
```
