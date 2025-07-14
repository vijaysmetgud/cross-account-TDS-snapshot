provider "aws" {
  alias   = "account_a"
  region  = var.region
  profile = "account-a"
}

provider "aws" {
  alias   = "account_b"
  region  = var.region
  profile = "account-b"
}
# Define your AWS providers here
