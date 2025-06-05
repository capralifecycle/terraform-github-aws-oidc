locals {
  repo_with_owner = "${var.github.owner}/${var.github.repo}"
  audience        = format("sts.%v", data.aws_partition.this.dns_suffix)
}


data "aws_partition" "this" {}
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  client_id_list  = ["https://github.com/${var.github.owner}", local.audience]
  thumbprint_list = toset([data.tls_certificate.github.certificates[0].sha1_fingerprint])
  url             = "https://token.actions.githubusercontent.com"
}

#
# Terraform S3 State permissions
#
# These permissions are required for the GitHub Actions workflow to manage the
# Terraform state (state and lockfile) in the S3 backend.
#
resource "aws_iam_policy" "terraform_state_management" {
  name        = "gha-${var.name_prefix}-tfstate-mgmt"
  description = "Permissions required to manage the Terraform S3 backend state and lockfile."
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = "s3:ListBucket",
        Resource = "arn:aws:s3:::${var.tfstate_config.bucket_name}",
        Condition = {
          StringLike = {
            "s3:prefix" = [
              for state_file in var.tfstate_config.state_files : "${state_file}*"
            ]
          }
        }
      },
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ],
        Resource = [
          for state_file in var.tfstate_config.state_files :
          "arn:aws:s3:::${var.tfstate_config.bucket_name}/${state_file}"
        ]

      },
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ],
        Resource = [
          for state_file in var.tfstate_config.state_files :
          "arn:aws:s3:::${var.tfstate_config.bucket_name}/${state_file}.tflock"
        ]
      }
    ]
  })
}

#
# Admin role
#
# The admin role is assumed by the GitHub Actions runner in trunk branch workflow runs,
# and allows for full access to the remote resources specified by the user.
#
resource "aws_iam_role" "admin" {
  name                 = "gha-${var.name_prefix}-admin"
  description          = "Full access for trunk branch deployment"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = "sts:AssumeRoleWithWebIdentity",
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        },
        Condition = {
          "StringLike" = {
            "token.actions.githubusercontent.com:sub" = "repo:${local.repo_with_owner}:ref:refs/heads/${var.github.trunk_branch}"
          },
          "StringEquals" = {
            "token.actions.githubusercontent.com:aud" = local.audience
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "admin_tfstate_mgmt" {
  role       = aws_iam_role.admin.name
  policy_arn = aws_iam_policy.terraform_state_management.arn
}

resource "aws_iam_role_policy" "admin" {
  role   = aws_iam_role.admin.name
  policy = jsonencode(var.admin_policy_document)
}

#
# Reader role
#
# The reader role is assumed by the GitHub Actions runner in non-trunk branch workflow runs.
# The role is used for restrictive access to the remote resources specified by the user,
# and allows for inspecting and planning changes, but not applying them.
#
resource "aws_iam_role" "read" {
  name                 = "gha-${var.name_prefix}-read"
  description          = "Read-only access for non-trunk branches"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = "sts:AssumeRoleWithWebIdentity",
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        },
        Condition = {
          "StringLike" = {
            "token.actions.githubusercontent.com:sub" = [
              "repo:${local.repo_with_owner}:ref:refs/heads/*",
              "repo:${local.repo_with_owner}:pull_request"
            ]
          },
          "StringNotLike" = {
            "token.actions.githubusercontent.com:sub" = "repo:${local.repo_with_owner}:ref:refs/heads/${var.github.trunk_branch}"
          },
          "StringEquals" = {
            "token.actions.githubusercontent.com:aud" = local.audience
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "reader_tfstate_mgmt" {
  role       = aws_iam_role.read.name
  policy_arn = aws_iam_policy.terraform_state_management.arn
}

resource "aws_iam_role_policy" "reader" {
  role   = aws_iam_role.read.name
  policy = jsonencode(var.read_policy_document)
}

