resource "aws_lb" "app" {
  name               = "ScaleStack-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name    = "ScaleStack-alb"
    Project = var.project_name
  }
}

resource "aws_lb_target_group" "app" {
  name        = "ScaleStack-tg"
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
    Name    = "ScaleStack-tg"
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
