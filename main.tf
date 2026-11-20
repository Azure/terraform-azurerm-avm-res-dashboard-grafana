resource "azapi_resource" "this" {
  location  = var.location
  name      = var.name
  parent_id = var.parent_id
  type      = var.resource_types.dashboard_grafana
  body = {
    sku = {
      name = var.sku
      size = var.sku_size
    }
    properties = {
      apiKey                  = var.api_key_enabled ? "Enabled" : "Disabled"
      deterministicOutboundIP = var.deterministic_outbound_ip_enabled ? "Enabled" : "Disabled"
      grafanaConfigurations   = local.grafana_configurations
      grafanaIntegrations = {
        azureMonitorWorkspaceIntegrations = [
          for v in values(var.azure_monitor_workspace_integrations) : {
            azureMonitorWorkspaceResourceId = v.resource_id
          }
        ]
      }
      grafanaMajorVersion = var.grafana_major_version
      grafanaPlugins      = length(var.grafana_plugins) == 0 ? null : { for p in var.grafana_plugins : p => {} }
      publicNetworkAccess = local.public_network_access_enabled ? "Enabled" : "Disabled"
      zoneRedundancy      = var.zone_redundancy_enabled ? "Enabled" : "Disabled"
    }
  }
  ignore_body_changes = length(var.ignore_body_changes.dashboard_grafana) > 0 ? var.ignore_body_changes.dashboard_grafana : null
  # Unset optional settings are omitted from the request instead of being sent as explicit nulls.
  ignore_null_property = true
  # Zone redundancy can only be chosen when the workspace is created.
  replace_triggers_refs = [
    "properties.zoneRedundancy",
  ]
  response_export_values = [
    "properties.endpoint",
    "properties.grafanaVersion",
    "properties.outboundIPs",
  ]
  retry = var.retry
  # Write-only and sent with every request: Azure rejects updates whose SMTP settings lack the password.
  sensitive_body = var.smtp_password == null ? null : {
    properties = {
      grafanaConfigurations = {
        smtp = {
          password = var.smtp_password
        }
      }
    }
  }
  tags = var.tags

  dynamic "identity" {
    for_each = module.avm_interfaces.managed_identities_azapi != null ? [module.avm_interfaces.managed_identities_azapi] : []

    content {
      type         = identity.value.type
      identity_ids = identity.value.identity_ids
    }
  }

  dynamic "timeouts" {
    for_each = var.timeouts == null ? [] : [var.timeouts]

    content {
      create = timeouts.value.create
      delete = timeouts.value.delete
      read   = timeouts.value.read
      update = timeouts.value.update
    }
  }

  lifecycle {
    precondition {
      condition     = !(var.managed_identities.system_assigned && length(var.managed_identities.user_assigned_resource_ids) > 0) && length(var.managed_identities.user_assigned_resource_ids) <= 1
      error_message = "Azure Managed Grafana supports a single identity: enable either the system-assigned identity or one user-assigned identity."
    }
    # Checked here rather than in the canonical `private_endpoints` declaration, which must stay verbatim.
    precondition {
      condition     = alltrue([for v in values(var.private_endpoints) : v.lock == null || contains(["CanNotDelete", "ReadOnly", "None"], try(v.lock.kind, ""))])
      error_message = "`private_endpoints[*].lock.kind` must be `CanNotDelete`, `ReadOnly`, or `None` (no lock on that endpoint)."
    }
    precondition {
      condition     = alltrue([for v in values(var.private_endpoints) : v.resource_group_name == null || can(provider::azapi::parse_resource_id("Microsoft.Resources/resourceGroups", v.resource_group_name))])
      error_message = "`private_endpoints[*].resource_group_name` must be a resource group resource ID."
    }
    precondition {
      condition = tonumber(var.grafana_major_version) < 12 || (
        var.grafana_configurations.security_csrf_always_check == null && var.grafana_configurations.users_editors_can_admin == null
      )
      error_message = "`grafana_configurations.security_csrf_always_check` and `users_editors_can_admin` are only supported up to Grafana 11; leave them unset for Grafana 12 and later."
    }
  }
}

# Grafana only routes traffic through a managed private endpoint after the workspace is refreshed, and the refresh has to
# follow the approval on the target resource. It runs when endpoints are added or removed, and when the trigger changes.
resource "terraform_data" "managed_private_endpoints_refresh" {
  count = length(var.managed_private_endpoints) > 0 ? 1 : 0

  triggers_replace = {
    endpoints = sort([for v in module.managed_private_endpoint : v.resource_id])
    trigger   = var.managed_private_endpoints_refresh_trigger
  }
}

resource "azapi_resource_action" "refresh_managed_private_endpoints" {
  count = length(var.managed_private_endpoints) > 0 ? 1 : 0

  action                 = "refreshManagedPrivateEndpoints"
  method                 = "POST"
  resource_id            = azapi_resource.this.id
  type                   = var.resource_types.dashboard_grafana
  response_export_values = []
  retry                  = var.retry

  dynamic "timeouts" {
    for_each = var.timeouts == null ? [] : [var.timeouts]

    content {
      create = timeouts.value.create
      delete = timeouts.value.delete
      read   = timeouts.value.read
      update = timeouts.value.update
    }
  }

  lifecycle {
    replace_triggered_by = [terraform_data.managed_private_endpoints_refresh[count.index]]
  }
}

# A rotated password alone makes no diff, so `smtp_password_version` pushes it.
resource "terraform_data" "smtp_password_version" {
  count = try(var.grafana_configurations.smtp.user, null) != null ? 1 : 0

  triggers_replace = var.smtp_password_version
}

resource "azapi_resource_action" "smtp_password" {
  count = try(var.grafana_configurations.smtp.user, null) != null ? 1 : 0

  method                 = "PATCH"
  resource_id            = azapi_resource.this.id
  type                   = var.resource_types.dashboard_grafana
  response_export_values = []
  retry                  = var.retry
  sensitive_body = {
    properties = {
      grafanaConfigurations = {
        smtp = {
          password = var.smtp_password
        }
      }
    }
  }

  dynamic "timeouts" {
    for_each = var.timeouts == null ? [] : [var.timeouts]

    content {
      create = timeouts.value.create
      delete = timeouts.value.delete
      read   = timeouts.value.read
      update = timeouts.value.update
    }
  }

  lifecycle {
    replace_triggered_by = [terraform_data.smtp_password_version[count.index]]
  }
}

module "managed_private_endpoint" {
  source   = "./modules/managed-private-endpoint"
  for_each = var.managed_private_endpoints

  group_ids                    = each.value.group_ids
  location                     = azapi_resource.this.location
  name                         = each.value.name
  parent_id                    = azapi_resource.this.id
  private_link_resource_id     = each.value.private_link_resource_id
  ignore_body_changes          = var.ignore_body_changes.dashboard_grafana_managed_private_endpoints
  private_link_resource_region = each.value.private_link_resource_region
  private_link_service_url     = each.value.private_link_service_url
  request_message              = each.value.request_message
  resource_types               = var.resource_types.dashboard_grafana_managed_private_endpoints
  retry                        = var.retry
  tags                         = var.tags
  timeouts                     = var.timeouts
}
