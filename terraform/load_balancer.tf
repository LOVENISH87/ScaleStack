resource "aws_lb" "app" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name    = "${var.project_name}-alb"
    Project = var.project_name
  }
}

# Instance target group pointing at the fixed NodePort. Instances are the EKS
# managed node group's EC2 nodes, registered by the ASG attachment below, so no
# AWS Load Balancer Controller is required.
resource "aws_lb_target_group" "app" {
  name        = "${var.project_name}-tg"
  port        = var.app_node_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.lab.id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = var.app_health_check_path
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  deregistration_delay = "15"

  tags = {
    Name    = "${var.project_name}-tg"
    Project = var.project_name
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ---------------------------------------------------------------------------
# Nagios (containerized) behind the same listener under /nagios
# ---------------------------------------------------------------------------
resource "aws_lb_target_group" "nagios" {
  name        = "${var.project_name}-nagios-tg"
  port        = var.nagios_node_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.lab.id
  target_type = "instance"

  health_check {
    enabled = true
    # Unauthenticated static file, so the check never hits the digest login.
    path                = "/healthz"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  deregistration_delay = "15"

  tags = {
    Name    = "${var.project_name}-nagios-tg"
    Project = var.project_name
  }
}

# /nagios and /nagios/... win over the default app action. Exact patterns avoid
# swallowing app paths that merely start with the same letters.
resource "aws_lb_listener_rule" "nagios" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nagios.arn
  }

  condition {
    path_pattern {
      values = ["/nagios", "/nagios/*"]
    }
  }
}

resource "aws_autoscaling_attachment" "nagios_nodes" {
  autoscaling_group_name = local.node_autoscaling_group
  lb_target_group_arn    = aws_lb_target_group.nagios.arn
}

# Register every node of the managed node group with the target group.
# EKS does not reconcile ASG target groups, so this attachment is stable.
resource "aws_autoscaling_attachment" "app_nodes" {
  autoscaling_group_name = local.node_autoscaling_group
  lb_target_group_arn    = aws_lb_target_group.app.arn
}
