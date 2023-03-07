provider "archive" {}

provider "aws" {
  region = "us-east-1"
}

data "aws_region" "current" {}

data "archive_file" "lambda" {
  type        = "zip"
  output_path = "lambda.zip"
  source_file = "${path.module}/../secrets-monitor/secrets_monitor/lambda_function.py"
}

data "aws_iam_policy" "lambda_basic_execution_role" {
  name = "AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "rotate_secrets" {
  statement {
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
      "secretsmanager:UpdateSecretVersionStage"
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/AllowMonitor"

      values = ["true"]
    }
  }
}

resource "aws_iam_role" "iam_for_lambda" {
  name               = "iam_for_lambda"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  inline_policy {
    name = "rotate-secrets"

    policy = data.aws_iam_policy_document.rotate_secrets.json
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution_role" {
  role       = aws_iam_role.iam_for_lambda.name
  policy_arn = data.aws_iam_policy.lambda_basic_execution_role.arn
}

resource "aws_lambda_function" "secrets_rotator" {
  function_name = "secrets-rotator"
  role          = aws_iam_role.iam_for_lambda.arn

  filename = data.archive_file.lambda.output_path
  handler  = "lambda_function.lambda_handler"

  runtime = "python3.9"

  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      SECRETS_MANAGER_ENDPOINT = "https://secretsmanager.${data.aws_region.current.name}.amazonaws.com"
    }
  }
}

resource "aws_lambda_permission" "allow_secretsmanager" {
  statement_id  = "AllowExecutionFromSecretsManager"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.secrets_rotator.function_name
  principal     = "secretsmanager.amazonaws.com"
}

resource "aws_secretsmanager_secret" "example" {
  name = "example"
  tags = {
    AllowMonitor = "true"
  }
}

resource "aws_secretsmanager_secret_rotation" "example" {
  secret_id           = aws_secretsmanager_secret.example.id
  rotation_lambda_arn = aws_lambda_function.secrets_rotator.arn

  rotation_rules {
    automatically_after_days = 90
  }
}
