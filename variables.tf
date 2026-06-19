variable "github" {
  description = "The GitHub configuration used for configuring the OIDC provider."
  type = object({
    owner        = string
    repo         = string
    trunk_branch = string
  })

  validation {
    condition     = length(var.github.owner) > 0 && length(var.github.repo) > 0 && length(var.github.trunk_branch) > 0
    error_message = "github.owner, github.repo and github.trunk_branch must all be non-empty."
  }
}

variable "tfstate_config" {
  description = "The Terraform state backend configuration, to which the provider will provide access."
  type = object({
    bucket_name = string
    state_files = list(string)
  })

  validation {
    condition     = length(var.tfstate_config.bucket_name) >= 3 && length(var.tfstate_config.bucket_name) <= 63
    error_message = "tfstate_config.bucket_name must be a valid S3 bucket name (3-63 characters)."
  }

  validation {
    condition     = length(var.tfstate_config.state_files) > 0
    error_message = "tfstate_config.state_files must contain at least one state file path."
  }
}


variable "name_prefix" {
  description = "The name prefix used for the resources created by this module."
  type        = string

  validation {
    # "gha-<name_prefix>-admin" must stay within the 64-character IAM role name limit.
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.name_prefix)) && length(var.name_prefix) <= 54
    error_message = "name_prefix must contain only alphanumeric characters and hyphens, and be at most 54 characters."
  }
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

variable "max_session_duration" {
  description = "The maximum session duration (in seconds) for the admin and reader roles."
  type        = number
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "max_session_duration must be between 3600 and 43200 seconds (AWS IAM limits)."
  }
}

variable "tags" {
  description = "A map of tags to apply to all resources created by this module."
  type        = map(string)
  default     = {}
}
