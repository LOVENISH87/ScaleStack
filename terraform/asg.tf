# IAM Role & Instance Profile for EC2 App Instances (S3, ECR & SSM access)
resource "aws_iam_role" "app_instance" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "s3_ecr_access" {
  name = "${var.project_name}-s3-ecr-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.logs.arn,
          "${aws_s3_bucket.logs.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags",
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "app_s3_ecr" {
  role       = aws_iam_role.app_instance.name
  policy_arn = aws_iam_policy.s3_ecr_access.arn
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.project_name}-instance-profile"
  role = aws_iam_role.app_instance.name
}

# Launch Template for Auto Scaling Group
resource "aws_launch_template" "app" {
  name_prefix   = "${var.project_name}-lt-"
  image_id      = data.aws_ami.ubuntu_2404.id
  instance_type = var.app_instance_type
  key_name      = var.ssh_key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.app.id]
  }

  # Requirement #5: Secondary EBS Volume (10GB) for persistent data
  block_device_mappings {
    device_name = "/dev/sdf"
    ebs {
      volume_size           = 10
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  # Bootstrap instance: self-naming, prerequisites, and deploy application service
  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -euo pipefail

    # Install prerequisites & AWS CLI for self-naming
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y python3 curl awscli

    TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || true)
    INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "")
    REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "ap-south-1")

    # Determine unique sequential name: Server-One, Server-Two, Server-Three, Server-Four
    ASSIGNED_NAME="Server-One"
    if [ -n "$INSTANCE_ID" ] && [ -n "$REGION" ]; then
      EXISTING_NAMES=$(aws ec2 describe-instances --region "$REGION" \
        --filters "Name=tag:Role,Values=app" "Name=instance-state-name,Values=running,pending" \
        --query "Reservations[].Instances[].Tags[?Key=='Name'].Value[]" --output text 2>/dev/null || true)

      for NUM in One Two Three Four Five Six; do
        if ! echo "$EXISTING_NAMES" | grep -qw "Server-$NUM"; then
          ASSIGNED_NAME="Server-$NUM"
          break
        fi
      done

      # Tag itself directly in AWS EC2 Console so the Name column shows Server-One, Server-Two, etc.
      aws ec2 create-tags --region "$REGION" --resources "$INSTANCE_ID" --tags "Key=Name,Value=$ASSIGNED_NAME" 2>/dev/null || true
    fi

    hostnamectl set-hostname "$ASSIGNED_NAME"

    # Configure application user and directories
    id -u healthapp &>/dev/null || useradd -r -s /usr/sbin/nologin -d /nonexistent healthapp
    mkdir -p /opt/health-app /etc/health-app
    chown healthapp:healthapp /etc/health-app

    # Deploy application code directly so new workers serve the app immediately
    echo "${filebase64("${path.module}/../app/health_app.py")}" | base64 -d > /opt/health-app/health_app.py
    chmod 0755 /opt/health-app/health_app.py
    chown root:root /opt/health-app/health_app.py

    # Deploy systemd unit
    cat <<'SVCEOF' > /etc/systemd/system/health-app.service
    [Unit]
    Description=Health-gated patching lab demo application
    After=network.target

    [Service]
    Type=simple
    User=healthapp
    Group=healthapp
    Environment=HEALTH_APP_PORT=8080
    ExecStart=/usr/bin/python3 /opt/health-app/health_app.py
    Restart=always
    RestartSec=2
    NoNewPrivileges=true
    ProtectSystem=strict
    ReadWritePaths=/etc/health-app

    [Install]
    WantedBy=multi-user.target
    SVCEOF

    # Start and enable application service
    systemctl daemon-reload
    systemctl enable --now health-app
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = "Server-Worker"
      Role    = "app"
      Project = var.project_name
      Lab     = "true"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name    = "Server-Worker-Volume"
      Project = var.project_name
      Lab     = "true"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Requirement #1: Auto Scaling Group (ASG) behind ALB (Starts with 2 instances, scales up to 4)
resource "aws_autoscaling_group" "app" {
  name_prefix         = "${var.project_name}-asg-"
  min_size            = 2
  max_size            = 4
  desired_capacity    = 2
  vpc_zone_identifier = aws_subnet.public[*].id
  target_group_arns   = [aws_lb_target_group.app.arn]

  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "Server-Worker"
    propagate_at_launch = true
  }

  tag {
    key                 = "Role"
    value               = "app"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = var.project_name
    propagate_at_launch = true
  }

  tag {
    key                 = "Lab"
    value               = "true"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity]
  }
}

# Requirement #1: Target Tracking Policy (Scale Out when CPU > 60%)
resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                   = "${var.project_name}-cpu-scaling"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value     = 60.0
    disable_scale_in = false
  }
}

# Discover active worker instances launched by ASG for Terraform outputs and Ansible
data "aws_instances" "app_workers" {
  instance_tags = {
    Role    = "app"
    Project = var.project_name
  }

  instance_state_names = ["running", "pending"]

  depends_on = [aws_autoscaling_group.app]
}
