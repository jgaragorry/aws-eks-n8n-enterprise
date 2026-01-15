remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket         = "eks-gitops-platform-tfstate-533267117128"
    key            = "n8n-ent/${path_relative_to_include()}/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "eks-gitops-platform-tflock"
  }
}

inputs = {
  account_id  = "533267117128"
  aws_region  = "us-east-1"
}
