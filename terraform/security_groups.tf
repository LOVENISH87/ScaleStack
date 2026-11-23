# ALB: HTTP from the internet (demo only). Nothing else.
# Egress is limited to the NodePort the Kubernetes Service binds.
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Internet-facing ALB for the lab. HTTP only."
  vpc_id      = aws_vpc.lab.id

  ingress {
    description = "HTTP from the internet for the demo"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "To worker nodes on the app NodePort"
    from_port   = var.app_node_port
    to_port     = var.app_node_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = { Name = "${var.project_name}-alb-sg" }
}

# EKS worker nodes: no public HTTP. The app NodePort is reachable only from the
# ALB. SSH only from the operator CIDR (Ansible node patching).
# kube-proxy needs node-to-node traffic within the group, hence the self rule.
resource "aws_security_group" "eks_nodes" {
  name        = "${var.project_name}-eks-nodes-sg"
  description = "EKS worker nodes. NodePort from the ALB only; SSH from operator CIDR."
  vpc_id      = aws_vpc.lab.id

  ingress {
    description     = "Application traffic from the ALB only"
    from_port       = var.app_node_port
    to_port         = var.app_node_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description = "Node-to-node pod networking and kube-proxy"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  ingress {
    description = "SSH from the operator CIDR only (Ansible node patching)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.operator_cidr]
  }

  egress {
    description = "Outbound for ECR pulls, package updates and AWS APIs"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-eks-nodes-sg" }
}
