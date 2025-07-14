terraform {
  backend "s3" {
    bucket         = "vijay-terraform-backend-bucket"       # ✅ Must exist
    key            = "state/project-root/terraform.tfstate" # ✅ Valid path
    region         = "eu-central-1"                         # ✅ Must match bucket region
    profile        = "account-a"                            # ✅ Matches AWS CLI profile
    encrypt        = true
    dynamodb_table = "vijay-terraform-locks" # ✅ Must exist in same region
  }
}
