# Native `terraform test` suite. Uses mock providers so it runs with no AWS
# credentials and produces no real infrastructure. Run with `make test`.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }

  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/mock"
    }
  }
}

mock_provider "tls" {
  mock_data "tls_certificate" {
    defaults = {
      certificates = [
        { sha1_fingerprint = "1111111111111111111111111111111111111111" },
        { sha1_fingerprint = "2222222222222222222222222222222222222222" },
      ]
    }
  }
}

variables {
  name_prefix = "demo-app"
  github = {
    owner        = "example-org"
    repo         = "demo-repo"
    trunk_branch = "main"
  }
  tfstate_config = {
    bucket_name = "example-tfstate-bucket"
    state_files = ["terraform/demo-app/terraform.tfstate"]
  }
  read_policy_document = {
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = "arn:aws:s3:::example-data-bucket/*"
    }]
  }
  admin_policy_document = {
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject"]
      Resource = "arn:aws:s3:::example-data-bucket/*"
    }]
  }
}

run "creates_prefixed_roles" {
  command = plan

  assert {
    condition     = aws_iam_role.admin.name == "gha-demo-app-admin"
    error_message = "Admin role name should be prefixed with gha-<name_prefix>."
  }

  assert {
    condition     = aws_iam_role.read.name == "gha-demo-app-read"
    error_message = "Reader role name should be prefixed with gha-<name_prefix>."
  }

  assert {
    condition     = aws_iam_policy.terraform_state_management.name == "gha-demo-app-tfstate-mgmt"
    error_message = "State-management policy name should be prefixed with gha-<name_prefix>."
  }
}

run "registers_oidc_thumbprint" {
  command = plan

  assert {
    condition     = length(aws_iam_openid_connect_provider.github.thumbprint_list) == 1
    error_message = "The OIDC provider should register the leaf certificate thumbprint."
  }
}

run "trunk_branch_can_only_assume_admin_role" {
  # apply (against mocks) so the provider-normalized trust policy is resolved.
  command = apply

  # The admin trust policy must be scoped to the trunk branch ref.
  assert {
    condition     = strcontains(aws_iam_role.admin.assume_role_policy, "repo:example-org/demo-repo:ref:refs/heads/main")
    error_message = "Admin role trust policy must be scoped to the trunk branch."
  }

  # The reader trust policy must explicitly exclude the trunk branch.
  assert {
    condition     = strcontains(aws_iam_role.read.assume_role_policy, "StringNotLike")
    error_message = "Reader role must exclude the trunk branch via StringNotLike."
  }
}

run "default_session_duration_is_one_hour" {
  command = plan

  assert {
    condition     = aws_iam_role.admin.max_session_duration == 3600
    error_message = "Default max_session_duration should be 3600 seconds."
  }
}

run "rejects_name_prefix_exceeding_iam_role_limit" {
  command = plan

  variables {
    name_prefix = "this-name-prefix-is-far-too-long-to-fit-within-the-iam-role-name-limit"
  }

  expect_failures = [var.name_prefix]
}

run "rejects_empty_state_files" {
  command = plan

  variables {
    tfstate_config = {
      bucket_name = "example-tfstate-bucket"
      state_files = []
    }
  }

  expect_failures = [var.tfstate_config]
}
