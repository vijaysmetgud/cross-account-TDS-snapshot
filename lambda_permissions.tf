module "sqs_lambda_permission_delete_snapshot" {
  source = "./modules/lambda_permission"
  providers = {
    aws = aws.account_a
  }

  statement_id = "AllowExecutionFromSQSDelete"
  lambda_arn   = module.lambda_delete_snapshot.lambda_function_arn
  principal    = "sqs.amazonaws.com"
  source_arn   = module.delete_shared_snapshot_queue.queue_arn
}
