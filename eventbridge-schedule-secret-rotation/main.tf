locals {
  lambda_src_path = "${path.module}/src"
  lambda_zip_path = "${path.module}/.build/rotation_lambda.zip"
  # effective_sg_ids resolved later after aws_security_group.lambda is declared
}

# --------------------------------------------------------------------------
# Secrets Manager — demo secret
# --------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "this" {
  name        = var.secret_name
  description = "Secret Rotation Demo secret"

  tags = {
    Name        = var.secret_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_secretsmanager_secret_version" "initial" {
  secret_id     = aws_secretsmanager_secret.this.id
  secret_string = jsonencode({ value = "initial_value" })

  lifecycle {
    # Rotation lambda will update this; ignore drift after first deploy
    ignore_changes = [secret_string]
  }
}

# --------------------------------------------------------------------------
# Lambda — package source and deploy
# --------------------------------------------------------------------------
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = local.lambda_src_path
  output_path = local.lambda_zip_path
}

resource "aws_iam_role" "lambda" {
  name = "${var.name_prefix}-secret-rotator-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach VPC execution policy when Lambda runs inside a VPC
resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  count      = var.vpc_id != null ? 1 : 0
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "lambda_secrets" {
  name = "${var.name_prefix}-secret-rotator-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecretsManagerAccess"
        Effect = "Allow"
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecretVersionStage"
        ]
        Resource = [aws_secretsmanager_secret.this.arn]
      },
      {
        Sid      = "EventBusPublish"
        Effect   = "Allow"
        Action   = ["events:PutEvents"]
        Resource = ["arn:aws:events:${var.aws_region}:${var.aws_account_id}:event-bus/default"]
      }
    ]
  })
}

# Auto-created security group (egress-only HTTPS) when vpc_id is set and no SGs are provided
resource "aws_security_group" "lambda" {
  count       = var.vpc_id != null && length(var.security_group_ids) == 0 ? 1 : 0
  name        = "${var.name_prefix}-secret-rotation-lambda-sg"
  description = "Secret rotation Lambda - egress HTTPS only"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS to AWS APIs (or VPC endpoints)"
  }

  tags = {
    Name        = "${var.name_prefix}-secret-rotation-lambda-sg"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

locals {
  effective_sg_ids = var.vpc_id != null ? (
    length(var.security_group_ids) > 0 ? var.security_group_ids : [aws_security_group.lambda[0].id]
  ) : []
}

resource "aws_lambda_function" "rotation" {
  function_name    = "${var.name_prefix}-secret-rotation"
  description      = "Rotates Secrets Manager secrets on an EventBridge schedule"
  role             = aws_iam_role.lambda.arn
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  handler          = "rotation_lambda.lambda_handler"
  runtime          = "python3.12"
  timeout          = 120

  environment {
    variables = {
      SECRET_ID = aws_secretsmanager_secret.this.arn
    }
  }

  # VPC placement — only active when vpc_id is provided
  dynamic "vpc_config" {
    for_each = var.vpc_id != null ? [1] : []
    content {
      subnet_ids         = var.subnet_ids
      security_group_ids = local.effective_sg_ids
    }
  }

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# --------------------------------------------------------------------------
# VPC Endpoints — optional, removes need for NAT in fully private subnets
# --------------------------------------------------------------------------
resource "aws_vpc_endpoint" "secretsmanager" {
  count               = var.vpc_id != null && var.enable_vpc_endpoints ? 1 : 0
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = local.effective_sg_ids
  private_dns_enabled = true

  tags = {
    Name        = "${var.name_prefix}-vpce-secretsmanager"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_vpc_endpoint" "logs" {
  count               = var.vpc_id != null && var.enable_vpc_endpoints ? 1 : 0
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = local.effective_sg_ids
  private_dns_enabled = true

  tags = {
    Name        = "${var.name_prefix}-vpce-logs"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_vpc_endpoint" "scheduler" {
  count               = var.vpc_id != null && var.enable_vpc_endpoints ? 1 : 0
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.scheduler"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = local.effective_sg_ids
  private_dns_enabled = true

  tags = {
    Name        = "${var.name_prefix}-vpce-scheduler"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_lambda_permission" "allow_scheduler" {
  statement_id  = "AllowEventBridgeScheduler"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rotation.function_name
  principal     = "scheduler.amazonaws.com"
  source_arn    = aws_scheduler_schedule.rotation.arn
}

# --------------------------------------------------------------------------
# EventBridge Scheduler
# --------------------------------------------------------------------------
resource "aws_iam_role" "scheduler" {
  name = "${var.name_prefix}-secret-rotation-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_role_policy" "scheduler_invoke" {
  name = "${var.name_prefix}-secret-rotation-scheduler-policy"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "InvokeLambda"
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = [aws_lambda_function.rotation.arn]
    }]
  })
}

resource "aws_scheduler_schedule" "rotation" {
  name        = "${var.name_prefix}-secret-rotation-schedule"
  description = "Triggers secret rotation Lambda on the configured schedule"

  schedule_expression = var.rotation_schedule

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.rotation.arn
    role_arn = aws_iam_role.scheduler.arn

    retry_policy {
      maximum_retry_attempts       = 0
      maximum_event_age_in_seconds = 300
    }
  }
}
