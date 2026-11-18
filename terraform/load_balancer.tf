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

resource "aws_lb_target_group" "app" {
  name        = "${var.project_name}-tg"
  port        = var.app_port
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

# Route /nagios* through the ALB so campus firewalls (Sophos) cannot block it!
resource "aws_lb_target_group" "nagios" {
  name        = "nagios-monitoring-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.lab.id
  target_type = "instance"

  health_check {
    enabled  = true
    path     = "/nagios4/"
    matcher  = "200,301,302,401"
    interval = 15
    timeout  = 5
  }

  tags = {
    Name    = "nagios-monitoring-tg"
    Project = var.project_name
  }
}

resource "aws_lb_target_group_attachment" "nagios" {
  target_group_arn = aws_lb_target_group.nagios.arn
  target_id        = aws_instance.nagios.id
  port             = 80
}

resource "aws_lb_listener_rule" "nagios" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nagios.arn
  }

  condition {
    path_pattern {
      values = ["/nagios*", "/nagios4*"]
    }
  }
}
