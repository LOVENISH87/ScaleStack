variable "aws_region" {
  description = "AWS region for the lab, e.g. ap-south-1."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project tag used to identify and tear down all lab resources."
  type        = string
  default     = "scalestack"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "project_name must be lowercase letters, digits and hyphens."
  }
}

variable "operator_cidr" {
  description = "CIDR allowed to SSH to EKS worker nodes (your public IP /32). Never 0.0.0.0/0."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.operator_cidr)) && var.operator_cidr != "0.0.0.0/0"
    error_message = "operator_cidr must be a valid CIDR block and must not be 0.0.0.0/0."
  }
}

variable "ssh_key_name" {
  description = "Name of an existing AWS EC2 key pair, used by Ansible to patch worker nodes."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the lab VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Two public subnet CIDRs, one per AZ."
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24"]
}

variable "kubernetes_version" {
  description = "EKS control plane version. Must be in standard support to stay cheap."
  type        = string
  default     = "1.35"
}

variable "node_instance_types" {
  description = "Spot instance types for the EKS managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of worker nodes."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of worker nodes the cluster autoscaler headroom allows."
  type        = number
  default     = 4
}

variable "app_port" {
  description = "Port the demo application listens on inside the container."
  type        = number
  default     = 8080
}

variable "app_node_port" {
  description = "Fixed NodePort the Kubernetes Service binds; the ALB target group points here."
  type        = number
  default     = 30080
}

variable "nagios_node_port" {
  description = "Fixed NodePort the Nagios Service binds; the ALB path rule forwards here."
  type        = number
  default     = 30081

  validation {
    condition     = var.nagios_node_port >= 30000 && var.nagios_node_port <= 32767
    error_message = "nagios_node_port must be a valid NodePort (30000-32767)."
  }
}

variable "app_health_check_path" {
  description = "HTTP path used by the ALB target group health check."
  type        = string
  default     = "/health"
}
