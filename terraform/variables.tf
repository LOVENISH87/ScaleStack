variable "aws_region" {
  description = "AWS region for the lab, e.g. us-east-1."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project tag used to identify and tear down all lab resources."
  type        = string
  default     = "health-gated-patching"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "project_name must be lowercase letters, digits and hyphens."
  }
}

variable "operator_cidr" {
  description = "CIDR allowed to SSH to lab instances (your public IP /32). Never 0.0.0.0/0."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.operator_cidr)) && var.operator_cidr != "0.0.0.0/0"
    error_message = "operator_cidr must be a valid CIDR block and must not be 0.0.0.0/0."
  }
}

variable "ssh_key_name" {
  description = "Name of an existing AWS EC2 key pair used for SSH access."
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

variable "app_instance_type" {
  description = "Instance type for the three application servers."
  type        = string
  default     = "t3.micro"
}

variable "nagios_instance_type" {
  description = "Instance type for the Nagios Core server."
  type        = string
  default     = "t3.micro"
}

variable "app_port" {
  description = "Port the demo application listens on."
  type        = number
  default     = 8080
}

variable "app_health_check_path" {
  description = "HTTP path used by the ALB target group health check."
  type        = string
  default     = "/health"
}
