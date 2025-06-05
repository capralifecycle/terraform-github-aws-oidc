locals {

  name_prefix = "demo-app"

  github_config = {
    owner        = "example-org"
    repo         = "demo-repo"
    trunk_branch = "main"
  }

  tfstate_config = {
    bucket_name = "example-tfstate-bucket"
    state_files = [
      "terraform/demo-app/terraform.tfstate"
    ]
  }

  read_policy_document = {
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "arn:aws:s3:::example-data-bucket/*"
      }
    ]
  }

  admin_policy_document = {
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "arn:aws:s3:::example-data-bucket/*"
      }
    ]
  }
}

module "github_aws_oidc" {
  source                = "../../."
  name_prefix           = local.name_prefix
  github                = local.github_config
  tfstate_config        = local.tfstate_config
  admin_policy_document = local.admin_policy_document
  read_policy_document  = local.read_policy_document
}
