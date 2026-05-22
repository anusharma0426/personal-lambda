# EventBridge Schedule → Secrets Manager Rotation (Terraform)

Terraform conversion of the AWS Serverless Pattern [eventbridge-schedule-secret-rotation-cdk](https://github.com/aws-samples/serverless-patterns/tree/main/eventbridge-schedule-secret-rotation-cdk).

## Architecture

```
EventBridge Scheduler (cron/rate)
        │
        ▼  (InvokeFunction)
  Lambda Function  ──▶  Secrets Manager
  (rotation_lambda)      (AWSPENDING → AWSCURRENT rotation)
```

## Resources created

| Resource | Description |
|---|---|
| `aws_secretsmanager_secret` | Demo secret to rotate |
| `aws_secretsmanager_secret_version` | Initial secret value |
| `aws_lambda_function` | Rotation handler (Python 3.12) |
| `aws_iam_role` (lambda) | Lambda execution role |
| `aws_iam_role_policy` (lambda) | Inline — SecretsManager + EventBridge perms |
| `aws_iam_role_policy_attachment` | AWSLambdaBasicExecutionRole managed policy |
| `aws_lambda_permission` | Allow EventBridge Scheduler to invoke Lambda |
| `aws_scheduler_schedule` | Hourly EventBridge schedule (flexible_time_window=OFF) |
| `aws_iam_role` (scheduler) | Scheduler execution role |
| `aws_iam_role_policy` (scheduler) | Inline — lambda:InvokeFunction |

## How rotation works

1. **createSecret** — generates a new secret value tagged `AWSPENDING`
2. **setSecret** — applies the pending value to the service (extend this for real DB/API rotation)
3. **testSecret** — validates the pending secret works (extend as needed)
4. **finishSecret** — promotes `AWSPENDING` to `AWSCURRENT`, demotes old version

## Prerequisites

- Terraform >= 1.5
- AWS provider >= 5.40 (required for `aws_scheduler_schedule`)
- AWS credentials configured

## Deploy

```bash
cd eventbridge-schedule-secret-rotation

cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your aws_region, aws_account_id, etc.

terraform init
terraform plan
terraform apply
```

## Customise rotation logic

Edit `src/rotation_lambda.py`:
- `set_secret()` — write the new credential to your target service
- `test_secret()` — verify the pending credential works

## Destroy

```bash
terraform destroy
```
