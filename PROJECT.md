# PROJECT.md — ScaleStack (EKS autoscaling & health-gated patching lab)

## Goal

A disposable AWS lab that shows safe, gradual maintenance of a containerized
web application: **EKS** with **Spot worker nodes**, an **HPA at 40% CPU**, an
**ALB** in front, **Nagios** monitoring as a pod, and an Ansible workflow that
patches worker nodes one at a time behind a health gate. Built for learning in
infrastructure you own.

## Success criteria

1. The application serves continuously while nodes are patched one at a time
   (`serial: 1`, `any_errors_fatal: true`), using cordon → drain → patch →
   reboot → uncordon, with the PodDisruptionBudget respected during drain.
2. A node is only returned to service after `kubectl wait node --for=Condition=Ready`
   and a successful `kubectl rollout status` of the application Deployment.
3. A node that fails to come back healthy halts the rollout, is left **cordoned**,
   and is never silently returned to rotation; recovery is manual.
4. The HPA scales from 2 to 6 replicas at 40% average CPU utilisation of the pod
   request, and back down after the load ends.
5. No request fails with 502/503 during a scale-out or a single-node drain.
6. `terraform destroy` leaves no billable resources (no NAT gateway, no idle
   EC2, no EKS control plane, no ALB, no EBS volumes).
7. Reports list `patched`, `failed`, `in_progress` and `not_attempted` nodes with
   the failed step and details.

## Component responsibilities

| Component | Owns | Does NOT own |
|---|---|---|
| Terraform | VPC, subnets, ALB + target groups + path rule, EKS cluster, Spot node group, ECR, S3, Lambda, security groups, outputs | Workload deployment, node package state |
| Kubernetes manifests (`k8s/`) | Namespace, Deployment (probes, security context, resources), NodePort Services, HPA, PDB, Nagios pod | Node configuration, image builds |
| `scripts/k8s-bootstrap.sh` | kubeconfig, namespace, Nagios ConfigMap/Secret, manifests, image pinning, metrics-server | Cluster creation, IAM |
| Ansible (`playbooks/patch.yml`) | Cordon/drain/patch/reboot/uncordon of nodes, rollout gate, patch reports | Creating infrastructure, container builds |
| Nagios (pod) | Independent monitoring: ALB `/health` and `/`, in-cluster Service health, pod CPU/memory via `/stats` | Rollout gating — the gate is `kubectl rollout status`, not a Nagios result |
| ALB | Routing to healthy instance targets, `/nagios*` path rule, target drain on NodePort 30080/30081 | Health semantics beyond HTTP 200 |

## Failure model

Node patch failure: halt the rollout, leave the failed node cordoned (its pods
already rescheduled onto the other node), do not touch remaining nodes, print
and persist the report. OS package updates are **not** rolled back
automatically.

Workload failure: the readiness probe fails, the pod leaves the Service
endpoints, the ALB target group drops it, and `kubectl rollout status` reports
the Deployment as stalled, which halts the node patch.

## Design constraints worth stating in the report

- No Helm, no AWS Load Balancer Controller and no `aws-auth` editing: the ALB
  uses **instance** targets on fixed NodePorts, and the managed node group's ASG
  is attached to the target groups with `aws_autoscaling_attachment`.
- No Kubernetes provider in Terraform: the IAM principal that creates the
  cluster receives `system:masters`, and EKS enrolls the managed node group role
  automatically.
- Worker nodes run the EKS-optimized **AL2023** AMI (`ami_type` pinned), so the
  node play drives `dnf`; it also handles Debian/Ubuntu nodes via apt.
- In-place node patching is the teaching path. Production EKS expects a new AMI
  / node group version and a managed rolling replacement; in-place upgrades
  drift from the managed AMI until the node is replaced.
- Nagios alerts are UI-only (no MTA in the image) and its history is per-pod.

## Safety constraints

- Patching requires `confirm_patch=true`; there is no default-on patching.
- SSH to nodes only from `operator_cidr`; Terraform rejects `0.0.0.0/0`.
- Nodes accept NodePort traffic only from the ALB security group.
- Terraform rejects an invalid NodePort range for either service.
- The Nagios password is passed as an environment variable at bootstrap time and
  stored only as a Kubernetes Secret; nothing secret is committed.
- No CI workflow patches AWS: CI validates and, when explicitly enabled with
  repository variables, builds images and rolls the Deployment.
