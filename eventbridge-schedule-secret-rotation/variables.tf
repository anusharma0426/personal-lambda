variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID. Used to scope the EventBridge PutEvents IAM permission."
  type        = string
}

variable "name_prefix" {
  description = "Prefix applied to all resource names."
  type        = string
  default     = "demo"
}

variable "environment" {
  description = "Environment name used for tagging (e.g. dev, sit, uat, prod)."
  type        = string
  default     = "dev"
}

variable "secret_name" {
  description = "Name of the Secrets Manager secret to create and rotate."
  type        = string
  default     = "secret-rotation-demo-secret"
}

variable "rotation_schedule" {
  description = "EventBridge schedule expression for triggering rotation. Defaults to every hour. Examples: 'rate(1 hour)', 'cron(0 0/1 * * ? *)'."
  type        = string
  default     = "rate(1 hour)"
}

# --------------------------------------------------------------------------
# VPC — optional, set vpc_id to enable private deployment
# --------------------------------------------------------------------------
variable "vpc_id" {
  description = "VPC ID to deploy Lambda into for private network isolation. Set to null (default) to run Lambda outside a VPC."
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "List of private subnet IDs for Lambda ENIs. Required when vpc_id is set."
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "Security group IDs for the Lambda function. If empty and vpc_id is set, a default egress-only SG is created automatically."
  type        = list(string)
  default     = []
}

variable "enable_vpc_endpoints" {
  description = "Create VPC Interface Endpoints for secretsmanager, logs and scheduler so Lambda can reach AWS APIs without a NAT gateway."
  type        = bool
  default     = false
}
