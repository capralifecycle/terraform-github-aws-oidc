variable "github" {
  description = "The GitHub configuration used for configuring the OIDC provider."
  type = object({
    owner        = string
    repo         = string
    trunk_branch = string
  })
}

variable "tfstate_config" {
  description = "The Terraform state backend configuration, to which the provider will provide access."
  type = object({
    bucket_name = string
    state_files = list(string)
  })
}


variable "name_prefix" {
  description = "The name prefix used for the resources created by this module."
  type        = string
}

variable "read_policy_document" {
  description = "The IAM policy document for the reader role assumed from non-trunk branch workflows."
  type = object({
    Version = string
    Statement = list(object({
      Effect   = string
      Action   = list(string)
      Resource = string
    }))
  })
}

variable "admin_policy_document" {
  description = "The IAM policy document for the admin role assumed from trunk branch workflows."
  type = object({
    Version = string
    Statement = list(object({
      Effect   = string
      Action   = list(string)
      Resource = string
    }))
  })
}
