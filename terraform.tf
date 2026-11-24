terraform {
  # 1.11 is required for the write-only `sensitive_body` argument fed by the ephemeral `smtp_password` input.
  required_version = ">= 1.11, < 2.0"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
  }
}
