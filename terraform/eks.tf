# EKS cluster + Spot managed node group.
#
# No Helm, no ingress controller, no aws-auth editing:
#   * EKS grants the IAM principal that creates the cluster system:masters.
#   * EKS enrolls the managed node group's IAM role automatically.
#   * The ALB reaches pods through a fixed NodePort Service (see k8s/20-service.yaml),
#     so the only Kubernetes API caller is scripts/k8s-bootstrap.sh.

locals {
  cluster_name = "${var.project_name}-eks"

  # EKS-managed ASGs are not reconciled by EKS, so attaching the node group's
  # ASG to the ALB target group is stable. Unknown at plan time, resolved at
  # apply once the node group exists.
  node_autoscaling_group = try(tolist(aws_eks_node_group.app.resources)[0].autoscaling_groups[0].name, null)
}

# ---------------------------------------------------------------------------
# Control plane IAM
# ---------------------------------------------------------------------------
resource "aws_iam_role" "eks_cluster" {
  name = "${var.project_name}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })

  tags = { Name = "${var.project_name}-eks-cluster-role" }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ---------------------------------------------------------------------------
# Worker node IAM (ECR pull + CNI + log archive uploads)
# ---------------------------------------------------------------------------
resource "aws_iam_role" "eks_node" {
  name = "${var.project_name}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = { Name = "${var.project_name}-eks-node-role" }
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Pods inherit the node role, so the log-archive CronJob in the cluster can
# write to the existing S3 bucket without static credentials.
resource "aws_iam_policy" "node_log_archive" {
  name = "${var.project_name}-eks-node-log-archive"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
      Resource = [aws_s3_bucket.logs.arn, "${aws_s3_bucket.logs.arn}/*"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node_log_archive" {
  role       = aws_iam_role.eks_node.name
  policy_arn = aws_iam_policy.node_log_archive.arn
}

# ---------------------------------------------------------------------------
# Cluster
# ---------------------------------------------------------------------------
resource "aws_eks_cluster" "app" {
  name     = local.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.eks_cluster.arn

  # API_AND_CONFIG_MAP keeps the legacy auth path available and is the least
  # surprising mode for a university lab.
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids              = aws_subnet.public[*].id
    endpoint_public_access  = true
    endpoint_private_access = true
  }

  tags = { Name = local.cluster_name }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}

# ---------------------------------------------------------------------------
# Node launch template
# ---------------------------------------------------------------------------
# Nodes carry the EKS-managed cluster security group (so kubelet <-> control
# plane traffic is already allowed) plus the lab node security group that opens
# NodePort 30080 to the ALB and SSH to the operator.
resource "aws_launch_template" "nodes" {
  name_prefix = "${var.project_name}-node-"
  key_name    = var.ssh_key_name

  vpc_security_group_ids = [
    aws_eks_cluster.app.vpc_config[0].cluster_security_group_id,
    aws_security_group.eks_nodes.id,
  ]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-spot-node"
      # Matches the dynamic inventory's eks_nodes group (ansible/inventory).
      Role    = "eks-node"
      Project = var.project_name
      Lab     = "true"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Spot managed node group
# ---------------------------------------------------------------------------
resource "aws_eks_node_group" "app" {
  cluster_name    = aws_eks_cluster.app.name
  node_group_name = "${var.project_name}-spot"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = aws_subnet.public[*].id

  # 70-90% cheaper than on-demand for a lab that lives a few hours.
  capacity_type  = "SPOT"
  instance_types = var.node_instance_types
  # Pin the EKS-optimized AL2023 AMI: the Ansible node patch playbook drives
  # dnf on an Amazon Linux 2023 node (ec2-user) and does not guess the OS.
  ami_type = "AL2023_x86_64_STANDARD"
  # Volume size comes from the launch template's block device mapping.

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    role      = "app"
    lifecycle = "spot"
  }

  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }

  tags = { Name = "${var.project_name}-spot-node" }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
  ]
}
