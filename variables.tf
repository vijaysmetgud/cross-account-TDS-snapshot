variable "region" {
  description = "AWS Region"
  type        = string
  default     = "eu-central-1"
}
# Define your root-level variables here

variable "db_instance_id" {
  description = "RDS DB instance ID for the source DB"
  type        = string
}

variable "target_account_id" {
  description = "AWS Account ID to share the snapshot with"
  type        = string
}

variable "temp_kms_key_arn" {
  description = "KMS key ARN from Account B for temporary encryption"
  type        = string
}

variable "cross_share_queue_url" {
  description = "SQS queue URL in Account A to notify Account B"
  type        = string
}

variable "delete_snapshot_queue_url" {
  description = "SQS queue URL used by the delete-shared-snapshot Lambda"
  type        = string
}

variable "target_kms_key_arn" {
  description = "Target KMS key ARN in Account A for final snapshot encryption"
  type        = string
}
