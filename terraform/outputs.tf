output "alb_dns_name" {
  description = "DNS name of the lab ALB (http://<alb_dns_name>/)."
  value       = aws_lb.app.dns_name
}

output "alb_url" {
  description = "Base URL of the lab application via the ALB."
  value       = "http://${aws_lb.app.dns_name}"
}

output "target_group_arn" {
  description = "ARN of the ALB target group the app servers are registered with."
  value       = aws_lb_target_group.app.arn
}

output "app_instance_ids" {
  description = "Instance IDs of the three application servers, in order."
  value       = aws_instance.app[*].id
}

output "app_public_ips" {
  description = "Public IPs of the application servers (SSH from operator CIDR only)."
  value       = aws_instance.app[*].public_ip
}

output "app_private_ips" {
  description = "Private IPs of the application servers."
  value       = aws_instance.app[*].private_ip
}

output "nagios_public_ip" {
  description = "Public IP of the Nagios Core server (web UI and SSH from operator CIDR only)."
  value       = aws_instance.nagios.public_ip
}

output "nagios_private_ip" {
  description = "Private IP of the Nagios Core server."
  value       = aws_instance.nagios.private_ip
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for log backups."
  value       = aws_s3_bucket.logs.id
}

output "ecr_repository_url" {
  description = "URL of the ECR repository for Docker container images."
  value       = aws_ecr_repository.app.repository_url
}

output "asg_name" {
  description = "Name of the Auto Scaling Group."
  value       = aws_autoscaling_group.app.name
}

output "lambda_function_name" {
  description = "Name of the S3 log processor Lambda function."
  value       = aws_lambda_function.s3_processor.function_name
}
