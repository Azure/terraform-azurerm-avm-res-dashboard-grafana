terraform {
  required_version = ">= 1.11, < 2.0"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}

provider "azapi" {}

module "regions" {
  source  = "Azure/avm-utl-regions/azurerm"
  version = "0.13.0"

  location         = var.location
  enable_telemetry = var.enable_telemetry
  is_recommended   = true
}

locals {
  # Azure Managed Grafana is not offered in every region.
  grafana_regions = [for r in module.regions.regions : r.name if contains(["australiaeast", "eastus", "eastus2", "northeurope", "swedencentral", "uksouth", "westeurope", "westus3"], r.name)]
}

resource "random_integer" "region_index" {
  max = length(local.grafana_regions) - 1
  min = 0
}

module "naming" {
  source  = "Azure/avm-utl-naming/azure"
  version = "0.2.0"
}

data "azapi_client_config" "current" {}

resource "azapi_resource" "resource_group" {
  location               = local.grafana_regions[random_integer.region_index.result]
  name                   = module.naming.names.resource_group.name_unique
  parent_id              = "/subscriptions/${data.azapi_client_config.current.subscription_id}"
  type                   = "Microsoft.Resources/resourceGroups@2024-11-01"
  response_export_values = []
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azapi_resource" "user_assigned_identity" {
  location               = azapi_resource.resource_group.location
  name                   = "id-grafana-${random_string.suffix.result}"
  parent_id              = azapi_resource.resource_group.id
  type                   = "Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31"
  response_export_values = []
}

module "test" {
  source = "../../"

  location         = azapi_resource.resource_group.location
  name             = substr(module.naming.names.grafana.name_unique, 0, 23)
  parent_id        = azapi_resource.resource_group.id
  enable_telemetry = var.enable_telemetry
  # Azure Managed Grafana accepts a single identity: this one replaces the system-assigned identity.
  managed_identities = {
    user_assigned_resource_ids = [azapi_resource.user_assigned_identity.id]
  }
}
