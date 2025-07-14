module "sns_topic_rds_snapshot_events" {
  source = "./modules/sns_topic"
  providers = {
    aws = aws.account_a
  }

  name = "rds-snapshot-events-topic"

  delivery_policy = jsonencode({
    http = {
      defaultHealthyRetryPolicy = {
        numRetries         = 3
        minDelayTarget     = 20
        maxDelayTarget     = 20
        numMaxDelayRetries = 0
        numMinDelayRetries = 0
        backoffFunction    = "linear"
      }
    }
  })
}


module "kms_key" {
  source      = "./modules/kms_key"
  description = "Key for encrypting RDS snapshots"
  providers = {
    aws = aws.account_a
  }
}

module "delete_shared_snapshot_queue" {
  source = "./modules/sqs_queue"
  providers = {
    aws = aws.account_a
  }

  name                       = "delete-shared-snapshot-queue"
  visibility_timeout_seconds = 630
  cross_account_arn          = "arn:aws:iam::423150264321:root" # Account B's ARN
}

module "cross_share_queue" {
  source = "./modules/sqs_queue"
  providers = {
    aws = aws.account_b
  }

  name                       = "cross-share-queue"
  visibility_timeout_seconds = 630
  cross_account_arn          = "arn:aws:iam::825169607534:root" # Account A root ARN
}

module "lambda_iam_role_a" {
  source = "./modules/iam_role_lambda"
  providers = {
    aws = aws.account_a
  }

  role_name       = "vijaylambdaRole"
  policy_name     = "LAMBDAPOLICY-ACCOUNTA"
  policy_document = file("${path.module}/policies/account_a_policy.json")
}

module "lambda_iam_role_b" {
  source = "./modules/iam_role_lambda"
  providers = {
    aws = aws.account_b
  }

  role_name       = "LAMBDAROLE-ACCOUNTB"
  policy_name     = "LAMBDAPOLICY-ACCOUNTB"
  policy_document = file("${path.module}/policies/account_b_policy.json")
}

module "lambda_share_snapshot" {
  source    = "./modules/lambda_function"
  providers = { aws = aws.account_a }

  function_name = "share-rds-snapshot"
  role_arn      = module.lambda_iam_role_a.role_arn
  handler       = "lambda_share_snapshot.lambda_handler"
  runtime       = "python3.12"
  filename      = "${path.module}/lambda_code/lambda_share_snapshot.zip"
  timeout       = 600
  environment_variables = {
    DB_INSTANCE_ID    = var.db_instance_id
    TARGET_ACCOUNT_ID = var.target_account_id
    TEMP_KEY_ARN      = var.temp_kms_key_arn
    SQS_QUEUE_URL     = var.cross_share_queue_url
  }
  depends_on = [module.lambda_iam_role_a]
}


module "sns_lambda_permission" {
  source = "./modules/lambda_permission"
  providers = {
    aws = aws.account_a
  }

  statement_id = "AllowExecutionFromSNS"
  lambda_arn   = module.lambda_share_snapshot.lambda_function_arn
  principal    = "sns.amazonaws.com"
  source_arn   = module.sns_topic_rds_snapshot_events.topic_arn
}

module "sqs_lambda_permission_b" {
  source = "./modules/lambda_permission"
  providers = {
    aws = aws.account_b
  }

  statement_id = "AllowExecutionFromSQS"
  lambda_arn   = module.lambda_copy_snapshot.lambda_function_arn
  principal    = "sqs.amazonaws.com"
  source_arn   = module.cross_share_queue.queue_arn
}

module "sns_to_lambda_subscription" {
  source = "./modules/sns_topic_subscription"
  providers = {
    aws = aws.account_a
  }

  topic_arn                    = module.sns_topic_rds_snapshot_events.topic_arn
  lambda_arn                   = module.lambda_share_snapshot.lambda_function_arn
  lambda_permission_dependency = module.sns_lambda_permission

  # filter_policy = jsonencode({
  #   event_source = ["db-instance"],
  #   event_id     = ["RDS-EVENT-0042"]
  # })
}

# resource "aws_sns_topic_subscription" "sns_to_lambda" {
#   provider   = aws.account_a
#   topic_arn  = module.sns_topic_rds_snapshot_events.topic_arn
#   protocol   = "lambda"
#   endpoint   = module.lambda_share_snapshot.lambda_function_arn
#   depends_on = [module.sns_lambda_permission]
# }

module "rds_event_subscription" {
  source = "./modules/rds_event_subscription"
  providers = {
    aws = aws.account_a
  }

  name                        = "rds-instance-backup-events-subscription"
  sns_topic                   = module.sns_topic_rds_snapshot_events.topic_arn
  source_type                 = "db-instance"
  event_categories            = ["backup"]
  enabled                     = true
  sns_subscription_dependency = module.sns_to_lambda_subscription
}


# resource "aws_db_event_subscription" "rds_event_subscription" {
#   provider         = aws.account_a
#   name             = "rds-snapshot-events-subscription"
#   sns_topic        = module.sns_topic_rds_snapshot_events.topic_arn
#   source_type      = "db-snapshot"
#   event_categories = ["creation"]
#   enabled          = true
#   depends_on       = [aws_sns_topic_subscription.sns_to_lambda]
# }


module "lambda_copy_snapshot" {
  source    = "./modules/lambda_function"
  providers = { aws = aws.account_b }

  function_name = "copy-rds-snapshot"
  role_arn      = module.lambda_iam_role_b.role_arn
  handler       = "lambda_copy_snapshot.lambda_handler"
  runtime       = "python3.12"
  filename      = "${path.module}/lambda_code/lambda_copy_snapshot.zip"
  timeout       = 600
  environment_variables = {
    TARGET_KMS_KEY_ID = var.target_kms_key_arn
  }
  depends_on = [module.lambda_iam_role_b]
}


module "event_source_mapping_copy" {
  source = "./modules/event_source_mapping"
  providers = {
    aws = aws.account_b
  }

  event_source_arn = module.cross_share_queue.queue_arn
  lambda_arn       = module.lambda_copy_snapshot.lambda_function_arn
  batch_size       = 1
  enabled          = true
}


module "lambda_delete_snapshot" {
  source    = "./modules/lambda_function"
  providers = { aws = aws.account_a }

  function_name = "delete-shared-snapshot"
  role_arn      = module.lambda_iam_role_a.role_arn
  handler       = "lambda_delete_snapshot.lambda_handler"
  runtime       = "python3.12"
  filename      = "${path.module}/lambda_code/lambda_delete_snapshot.zip"
  timeout       = 620
  environment_variables = {
    DELETE_SNAPSHOT_QUEUE_URL = var.delete_snapshot_queue_url
  }
  depends_on = [module.lambda_iam_role_a]
}

module "event_source_mapping_delete" {
  source = "./modules/event_source_mapping"
  providers = {
    aws = aws.account_a
  }

  event_source_arn = module.delete_shared_snapshot_queue.queue_arn
  lambda_arn       = module.lambda_delete_snapshot.lambda_function_arn
  batch_size       = 1
  enabled          = true
}


