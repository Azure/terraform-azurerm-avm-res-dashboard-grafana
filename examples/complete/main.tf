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
  # Regions where Azure Managed Grafana supports zone redundancy, per "Reliability in Azure Managed Grafana" on Microsoft Learn.
  grafana_regions = [
    for r in module.regions.regions : r.name
    if contains(["australiaeast", "eastasia", "eastus", "northeurope", "southcentralus", "westus3"], r.name)
  ]
  location = local.grafana_regions[random_integer.region_index.result]
}

resource "random_integer" "region_index" {
  max = length(local.grafana_regions) - 1
  min = 0
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

module "naming" {
  source  = "Azure/avm-utl-naming/azure"
  version = "0.2.0"
}

data "azapi_client_config" "current" {}

resource "azapi_resource" "resource_group" {
  location               = local.location
  name                   = module.naming.names.resource_group.name_unique
  parent_id              = "/subscriptions/${data.azapi_client_config.current.subscription_id}"
  type                   = "Microsoft.Resources/resourceGroups@2024-11-01"
  response_export_values = []
}

resource "azapi_resource" "log_analytics_workspace" {
  location  = azapi_resource.resource_group.location
  name      = module.naming.names.operational_insights_workspace.name_unique
  parent_id = azapi_resource.resource_group.id
  type      = "Microsoft.OperationalInsights/workspaces@2023-09-01"
  body = {
    properties = {
      retentionInDays = 30
      sku = {
        name = "PerGB2018"
      }
    }
  }
  response_export_values = []
}

# Managed Prometheus, linked to Grafana and reached through a managed private endpoint.
resource "azapi_resource" "monitor_workspace" {
  location               = azapi_resource.resource_group.location
  name                   = "amw-${random_string.suffix.result}"
  parent_id              = azapi_resource.resource_group.id
  type                   = "Microsoft.Monitor/accounts@2023-04-03"
  body                   = {}
  response_export_values = []
}

resource "azapi_resource" "virtual_network" {
  location  = azapi_resource.resource_group.location
  name      = module.naming.names.virtual_network.name_unique
  parent_id = azapi_resource.resource_group.id
  type      = "Microsoft.Network/virtualNetworks@2024-05-01"
  body = {
    properties = {
      addressSpace = {
        addressPrefixes = ["10.10.0.0/16"]
      }
      subnets = [
        {
          name = "snet-private-endpoints"
          properties = {
            addressPrefix = "10.10.0.0/24"
          }
        }
      ]
    }
  }
  response_export_values = []
}

resource "azapi_resource" "private_dns_zone" {
  location               = "global"
  name                   = "privatelink.grafana.azure.com"
  parent_id              = azapi_resource.resource_group.id
  type                   = "Microsoft.Network/privateDnsZones@2024-06-01"
  response_export_values = []
  # On destroy, Azure can still report the deleted virtual network link as a nested resource for a while
  # (409 CannotDeleteResource, seen in an end-to-end run). Retry until it is gone.
  retry = {
    error_message_regex = ["CannotDeleteResource"]
  }
}

resource "azapi_resource" "private_dns_zone_link" {
  location  = "global"
  name      = "link-${azapi_resource.virtual_network.name}"
  parent_id = azapi_resource.private_dns_zone.id
  type      = "Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01"
  body = {
    properties = {
      registrationEnabled = false
      virtualNetwork = {
        id = azapi_resource.virtual_network.id
      }
    }
  }
  response_export_values = []
}

module "test" {
  source = "../../"

  location  = azapi_resource.resource_group.location
  name      = substr(module.naming.names.grafana.name_unique, 0, 23)
  parent_id = azapi_resource.resource_group.id
  azure_monitor_workspace_integrations = {
    prometheus = {
      resource_id = azapi_resource.monitor_workspace.id
    }
  }
  diagnostic_settings = {
    log_analytics = {
      name                  = "diag-grafana"
      logs                  = [{ category_group = "allLogs" }]
      workspace_resource_id = azapi_resource.log_analytics_workspace.id
    }
  }
  enable_telemetry = var.enable_telemetry
  # CanNotDelete rather than ReadOnly: a ReadOnly lock would also block updates and the managed private endpoint refresh.
  lock = {
    kind = "CanNotDelete"
  }
  managed_identities = {
    system_assigned = true
  }
  # The owner of the Azure Monitor workspace approves the connection; afterwards, change
  # `managed_private_endpoints_refresh_trigger` so that Grafana starts using the endpoint.
  managed_private_endpoints = {
    prometheus = {
      name                         = "mpe-prometheus"
      private_link_resource_id     = azapi_resource.monitor_workspace.id
      private_link_resource_region = azapi_resource.resource_group.location
      group_ids                    = ["prometheusMetrics"]
      request_message              = "Azure Managed Grafana access to managed Prometheus"
    }
  }
  private_endpoints = {
    grafana = {
      subnet_resource_id            = "${azapi_resource.virtual_network.id}/subnets/snet-private-endpoints"
      private_dns_zone_resource_ids = [azapi_resource.private_dns_zone.id]
      role_assignments = {
        deployer_reader = {
          principal_id               = data.azapi_client_config.current.object_id
          role_definition_id_or_name = "Reader"
        }
      }
    }
  }
  public_network_access_enabled = false
  role_assignments = {
    deployer = {
      principal_id               = data.azapi_client_config.current.object_id
      role_definition_id_or_name = "Grafana Admin"
    }
  }
  tags = {
    scenario = "complete"
  }
  zone_redundancy_enabled = true

  depends_on = [azapi_resource.private_dns_zone_link]
}

# Data-source access is granted by whoever owns the data source, not by the Grafana module. Here the Azure Monitor
# workspace belongs to the example, so the example grants Grafana's identity `Monitoring Data Reader` on it; with an
# AVM module for the workspace, pass the same principal through that module's `role_assignments` input instead.
data "azapi_resource_list" "monitoring_data_reader" {
  parent_id = azapi_resource.monitor_workspace.id
  type      = "Microsoft.Authorization/roleDefinitions@2022-04-01"
  response_export_values = {
    id = "value[?properties.roleName == 'Monitoring Data Reader'].id | [0]"
  }
}

resource "random_uuid" "grafana_monitoring_data_reader" {}

resource "azapi_resource" "grafana_monitoring_data_reader" {
  name      = random_uuid.grafana_monitoring_data_reader.result
  parent_id = azapi_resource.monitor_workspace.id
  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  body = {
    properties = {
      principalId      = module.test.system_assigned_mi_principal_id
      principalType    = "ServicePrincipal"
      roleDefinitionId = data.azapi_resource_list.monitoring_data_reader.output.id
    }
  }
  response_export_values = []
}
