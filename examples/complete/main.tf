terraform {
  required_version = "~> 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "azurerm" {
  features {}
}


## Section to provide a random Azure region for the resource group
# This allows us to randomize the region for the resource group.
module "regions" {
  source  = "Azure/avm-utl-regions/azurerm"
  version = "0.9.3"
}

# This allows us to randomize the region for the resource group.
resource "random_integer" "region_index" {
  max = length(module.regions.regions) - 1
  min = 0
}
## End of section to provide a random Azure region for the resource group

# This ensures we have unique CAF compliant names for our resources.
module "naming" {
  source  = "Azure/naming/azurerm"
  version = "0.4.3"
}

# This is required for resource modules
resource "azurerm_resource_group" "this" {
  location = module.regions.regions[random_integer.region_index.result].name
  name     = module.naming.resource_group.name_unique
}

# Locals for configuration
locals {
  private_dns_zone_groups = {
    grafana = {
      grafana = "privatelink.grafana.azure.com"
    }
    monitor = {
      agentsvc       = "privatelink.agentsvc.azure-automation.net"
      monitor        = "privatelink.monitor.azure.com"
      oms_opinsights = "privatelink.oms.opinsights.azure.com"
      ods_opinsights = "privatelink.ods.opinsights.azure.com"
    }
    prometheus = {
      prometheus = "privatelink.${azurerm_resource_group.this.location}.prometheus.monitor.azure.com"
    }
    storage = {
      blob = "privatelink.blob.core.windows.net"
    }
  }

  private_dns_zones = merge([
    for group_key, zones in local.private_dns_zone_groups : {
      for zone_key, domain in zones : "${group_key}:${zone_key}" => domain
    }
  ]...)

  vnet_address_space = "10.0.0.0/16"

  tags = {
    source = "avm-res-dashboard-grafana/examples/complete"
  }
}

# Virtual Network
module "virtual_network" {
  source           = "Azure/avm-res-network-virtualnetwork/azurerm"
  version          = "0.16.0"
  enable_telemetry = var.enable_telemetry

  name      = module.naming.virtual_network.name_unique
  location  = azurerm_resource_group.this.location
  parent_id = azurerm_resource_group.this.id

  address_space = [local.vnet_address_space]

  subnets = {
    private_endpoints = {
      name             = "snet-pep"
      address_prefixes = [cidrsubnet(local.vnet_address_space, 8, 0)] # 10.0.0.0/24
    }
  }

  tags = local.tags
}

# Required Private DNS Zones
module "private_dns_zone" {
  for_each = local.private_dns_zones

  source           = "Azure/avm-res-network-privatednszone/azurerm"
  version          = "0.4.3"
  enable_telemetry = var.enable_telemetry

  domain_name = each.value
  parent_id   = azurerm_resource_group.this.id

  virtual_network_links = {
    vnetlink1 = {
      name   = "local-vnet-link"
      vnetid = module.virtual_network.resource_id
    }
  }

  tags = local.tags
}

# Azure Monitor Private Link Scope
resource "azurerm_monitor_private_link_scope" "this" {
  name                = "ampls-${module.naming.unique-seed}" # No output for AMPLS naming
  resource_group_name = azurerm_resource_group.this.name

  ingestion_access_mode = "PrivateOnly"
  query_access_mode     = "PrivateOnly"

  tags = local.tags
}

# Log Analytics Workspace for Diagnostics
module "log_analytics_workspace" {
  source           = "Azure/avm-res-operationalinsights-workspace/azurerm"
  version          = "0.5.1"
  enable_telemetry = var.enable_telemetry

  name                = module.naming.log_analytics_workspace.name_unique
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  log_analytics_workspace_identity = {
    type = "SystemAssigned"
  }

  monitor_private_link_scoped_resource = {
    ampls = {
      resource_id = azurerm_monitor_private_link_scope.this.id
    }
  }

  private_endpoints = {
    ampls = {
      name               = "pe-${azurerm_monitor_private_link_scope.this.name}"
      subnet_resource_id = module.virtual_network.subnets["private_endpoints"].resource_id

      private_dns_zone_resource_ids = [
        module.private_dns_zone["monitor:agentsvc"].resource_id,
        module.private_dns_zone["monitor:monitor"].resource_id,
        module.private_dns_zone["monitor:oms_opinsights"].resource_id,
        module.private_dns_zone["monitor:ods_opinsights"].resource_id,
        module.private_dns_zone["storage:blob"].resource_id,
      ]

      tags = local.tags
    }
  }

  tags = local.tags
}

# Azure Monitor Workspace for Integration
resource "azurerm_monitor_workspace" "this" {
  count = 2

  name                = "amw-${module.naming.unique-seed}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  public_network_access_enabled = false

  tags = local.tags
}

resource "azurerm_private_endpoint" "amw" {
  count = 2

  name                = "pe-${azurerm_monitor_workspace.this[count.index].name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  subnet_id = module.virtual_network.subnets["private_endpoints"].resource_id

  private_service_connection {
    name = "pse-${azurerm_monitor_workspace.this[count.index].name}"

    is_manual_connection           = false
    private_connection_resource_id = azurerm_monitor_workspace.this[count.index].id
    subresource_names              = ["prometheusMetrics"]
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [module.private_dns_zone["prometheus:prometheus"].resource_id]
  }

  tags = local.tags
}

resource "azurerm_monitor_diagnostic_setting" "amw" {
  count = 2

  name                       = "diag-${azurerm_monitor_workspace.this[count.index].name}"
  target_resource_id         = azurerm_monitor_workspace.this[count.index].id
  log_analytics_workspace_id = module.log_analytics_workspace.resource_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# Azure AD Group for assignment of Grafana Reader role
resource "azuread_group" "grafana_reader" {
  display_name     = "grafana-reader-${module.naming.unique-seed}"
  security_enabled = true
}

locals {
  grafana_identity = module.grafana.resource.identity[0].principal_id

  role_assignments = merge(
    {
      "amg:monitoring-reader:rg" = {
        principal_id         = local.grafana_identity
        role_definition_name = "Monitoring Reader"
        scope                = azurerm_resource_group.this.id
      }

      "amg:log-analytics-data-reader:law" = {
        principal_id         = local.grafana_identity
        role_definition_name = "Log Analytics Data Reader"
        scope                = module.log_analytics_workspace.resource_id
      }
    },
    {
      for idx, amw in azurerm_monitor_workspace.this : "amg:monitoring-data-reader:amw${idx}" => {
        principal_id         = local.grafana_identity
        role_definition_name = "Monitoring Data Reader"
        scope                = amw.id
      }
    }
  )
}

# Required role assignments for data access to grafana-connected resources
resource "azurerm_role_assignment" "this" {
  for_each = local.role_assignments

  principal_id         = each.value.principal_id
  role_definition_name = each.value.role_definition_name
  scope                = each.value.scope
}


# This is the module call
# Do not specify location here due to the randomization above.
# Leaving location as `null` will cause the module to use the resource group location
# with a data source.
module "test" {
  source = "../../"

  name                = module.naming.dashboard_grafana.name_unique
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  api_key_enabled               = true
  grafana_major_version         = "11"
  public_network_access_enabled = false

  azure_monitor_workspace_integrations = [
    for idx, amw in azurerm_monitor_workspace.this : amw.id
  ]

  managed_identities = {
    system_assigned = true
  }

  managed_private_endpoints = merge(
    {
      for idx, amw in azurerm_monitor_workspace.this : "amw${idx}" => {
        private_link_resource_id = amw.id
        group_ids                = ["prometheusMetrics"]
      }
    },
    {
      ampls = {
        private_link_resource_id = azurerm_monitor_private_link_scope.this.id
        group_ids                = ["azuremonitor"]
      }
    }
  )

  private_endpoints = {
    this = {
      subnet_id                     = module.virtual_network.subnets["private_endpoints"].resource_id
      private_dns_zone_resource_ids = [module.private_dns_zone["grafana:grafana"].resource_id]
    }
  }

  diagnostic_settings = {
    this = {
      workspace_resource_id = module.log_analytics_workspace.resource_id
    }
  }

  role_assignments = {
    "reader_group:grafana-reader" = {
      principal_id               = azuread_group.grafana_reader.object_id
      role_definition_id_or_name = "Grafana Reader"
    }
  }

  tags = local.tags
}
