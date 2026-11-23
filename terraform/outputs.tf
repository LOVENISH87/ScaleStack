output "alb_dns_name" {
  description = "DNS name of the ScaleStack ALB (http://<alb_dns_name>/)."
  value       = aws_lb.app.dns_name
}

output "alb_url" {
  description = "Base URL of the ScaleStack application via the ALB."
  value       = "http://${aws_lb.app.dns_name}"
}

output "target_group_arn" {
  description = "ARN of the ALB target group the EKS node group is attached to."
  value       = aws_lb_target_group.app.arn
}

output "cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.app.name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = aws_eks_cluster.app.endpoint
}

output "kubeconfig_command" {
  description = "Run this to point kubectl at the cluster."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.app.name}"
}

output "node_group_name" {
  description = "EKS managed (Spot) node group name."
  value       = aws_eks_node_group.app.node_group_name
}

output "app_node_port" {
  description = "NodePort the Service binds and the ALB target group forwards to."
  value       = var.app_node_port
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for log backups."
  value       = aws_s3_bucket.logs.id
}

output "ecr_repository_url" {
  description = "URL of the ECR repository for Docker container images."
  value       = aws_ecr_repository.app.repository_url
}

output "lambda_function_name" {
  description = "Name of the S3 log processor Lambda function."
  value       = aws_lambda_function.s3_processor.function_name
}
