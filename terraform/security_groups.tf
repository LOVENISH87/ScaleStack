# ALB: HTTP from the internet (demo only). Nothing else.
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
    description = "To app servers on the app port"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "To Nagios on port 80"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = { Name = "${var.project_name}-alb-sg" }
}

# App servers: no direct public HTTP. App port only from ALB SG (and the
# Nagios SG for monitoring). SSH only from the operator CIDR.
resource "aws_security_group" "app" {
  name        = "${var.project_name}-app-sg"
  description = "Application servers. No public HTTP; SSH from operator CIDR only."
  vpc_id      = aws_vpc.lab.id

  ingress {
    description     = "App traffic from the ALB only"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "HTTP health checks from Nagios only"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.nagios.id]
  }

  ingress {
    description     = "SSH from the Nagios server for check_by_ssh-style probes (optional)"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.nagios.id]
  }

  ingress {
    description = "SSH from the operator CIDR only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.operator_cidr]
  }

  egress {
    description = "Outbound for OS package updates and AWS APIs"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-app-sg" }
}

# Nagios: SSH from the operator CIDR only. Can reach app servers and the
# ALB for checks; nothing else may reach its web UI except the operator.
resource "aws_security_group" "nagios" {
  name        = "${var.project_name}-nagios-sg"
  description = "Nagios Core server. Web UI and SSH from operator CIDR only."
  vpc_id      = aws_vpc.lab.id

  ingress {
    description     = "Nagios web UI from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description = "Nagios web UI from anywhere (authenticated with nagiosadmin password)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from the operator CIDR only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.operator_cidr]
  }

  egress {
    description = "Outbound for checks, package updates and AWS APIs"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-nagios-sg" }
}
