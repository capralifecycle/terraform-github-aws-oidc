locals {
  repo_with_owner = "${var.github.owner}/${var.github.repo}"
  audience        = format("sts.%v", data.aws_partition.this.dns_suffix)
  bucket_arn      = "arn:${data.aws_partition.this.partition}:s3:::${var.tfstate_config.bucket_name}"

  # GitHub Actions OIDC tokens carry the repository in the `sub` claim in one of two
  # formats: the original `owner/repo`, and an immutable one that appends the numeric
  # owner and repository IDs, `owner@1234/repo@5678`. Which one a repository gets
  # depends on a per-repository setting, so trust policies accept both until the
  # repository has opted in and `trust_legacy_subject_claim` is turned off.
  #
  # The IDs are required rather than wildcarded. Besides surviving a rename, this keeps
  # the pattern literal up to and including the repository name: an IAM `*` also
  # matches `/` and `:`, so a wildcard owner ID would let the pattern's trailing
  # `:ref:refs/heads/<branch>` be satisfied from elsewhere in the claim.
  #
  # https://github.blog/changelog/2026-04-23-immutable-subject-claims-for-github-actions-oidc-tokens/
  repo_claims = concat(
    var.github.trust_legacy_subject_claim ? [local.repo_with_owner] : [],
    ["${var.github.owner}@${var.github.owner_id}/${var.github.repo}@${var.github.repo_id}"],
  )

  trunk_subjects = [
    for repo in local.repo_claims : "repo:${repo}:ref:refs/heads/${var.github.trunk_branch}"
  ]
  any_branch_subjects = flatten([
    for repo in local.repo_claims : [
      "repo:${repo}:ref:refs/heads/*",
      "repo:${repo}:pull_request",
    ]
  ])
}


data "aws_partition" "this" {}
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  client_id_list  = ["https://github.com/${var.github.owner}", local.audience]
  thumbprint_list = toset([data.tls_certificate.github.certificates[0].sha1_fingerprint])
  url             = "https://token.actions.githubusercontent.com"
  tags            = var.tags
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
  tags        = var.tags
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = "s3:ListBucket",
        Resource = local.bucket_arn,
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
          "${local.bucket_arn}/${state_file}"
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
          "${local.bucket_arn}/${state_file}.tflock"
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
  max_session_duration = var.max_session_duration
  tags                 = var.tags
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
            "token.actions.githubusercontent.com:sub" = local.trunk_subjects
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
  max_session_duration = var.max_session_duration
  tags                 = var.tags
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
            "token.actions.githubusercontent.com:sub" = local.any_branch_subjects
          },
          # Listing every trunk-branch subject format is load-bearing: StringNotLike is
          # satisfied only when the claim matches none of the values, so a format missing
          # here would let trunk runs assume the reader role.
          "StringNotLike" = {
            "token.actions.githubusercontent.com:sub" = local.trunk_subjects
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

