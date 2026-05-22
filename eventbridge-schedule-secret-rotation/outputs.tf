output "secret_arn" {
  description = "ARN of the demo Secrets Manager secret."
  value       = aws_secretsmanager_secret.this.arn
}

output "rotation_lambda_arn" {
  description = "ARN of the secret rotation Lambda function."
  value       = aws_lambda_function.rotation.arn
}

output "rotation_lambda_name" {
  description = "Name of the secret rotation Lambda function."
  value       = aws_lambda_function.rotation.function_name
}

output "scheduler_arn" {
  description = "ARN of the EventBridge schedule."
  value       = aws_scheduler_schedule.rotation.arn
}

output "rotation_schedule" {
  description = "Schedule expression in use for rotation."
  value       = var.rotation_schedule
}

output "lambda_security_group_id" {
  description = "ID of the auto-created Lambda security group. Empty string when vpc_id is null or security_group_ids were provided."
  value       = length(aws_security_group.lambda) > 0 ? aws_security_group.lambda[0].id : ""
}

output "vpc_endpoint_secretsmanager_id" {
  description = "ID of the secretsmanager VPC endpoint. Empty string when not created."
  value       = length(aws_vpc_endpoint.secretsmanager) > 0 ? aws_vpc_endpoint.secretsmanager[0].id : ""
}
