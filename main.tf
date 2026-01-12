resource "azurerm_dashboard_grafana" "this" {
  grafana_major_version                  = var.grafana_major_version
  location                               = var.location
  name                                   = var.name
  resource_group_name                    = var.resource_group_name
  api_key_enabled                        = var.api_key_enabled
  auto_generated_domain_name_label_scope = var.auto_generated_domain_name_label_scope
  deterministic_outbound_ip_enabled      = var.deterministic_outbound_ip_enabled
  public_network_access_enabled          = var.public_network_access_enabled
  sku                                    = var.sku
  tags                                   = var.tags
  zone_redundancy_enabled                = var.zone_redundancy_enabled

  dynamic "azure_monitor_workspace_integrations" {
    for_each = var.azure_monitor_workspace_integrations

    content {
      resource_id = azure_monitor_workspace_integrations.value
    }
  }
  dynamic "identity" {
    for_each = (var.managed_identities.system_assigned || length(var.managed_identities.user_assigned_resource_ids) > 0) ? { this = var.managed_identities } : {}

    content {
      type         = identity.value.system_assigned && length(identity.value.user_assigned_resource_ids) > 0 ? "SystemAssigned, UserAssigned" : length(identity.value.user_assigned_resource_ids) > 0 ? "UserAssigned" : "SystemAssigned"
      identity_ids = identity.value.user_assigned_resource_ids
    }
  }
  dynamic "smtp" {
    for_each = var.smtp == null ? [] : [var.smtp]

    content {
      from_address              = smtp.value.from_address
      host                      = smtp.value.host
      password                  = smtp.value.password
      start_tls_policy          = smtp.value.start_tls_policy
      user                      = smtp.value.user
      enabled                   = smtp.value.enabled
      from_name                 = smtp.value.from_name
      verification_skip_enabled = smtp.value.verification_skip_enabled
    }
  }
}

resource "azurerm_dashboard_grafana_managed_private_endpoint" "this" {
  for_each = var.managed_private_endpoints

  grafana_id                   = azurerm_dashboard_grafana.this.id
  location                     = each.value.location != null ? each.value.location : var.location
  name                         = each.value.name != null ? each.value.name : substr(replace("mpe-${var.name}", "/[^a-zA-Z0-9-]/", ""), 0, 20)
  private_link_resource_id     = each.value.private_link_resource_id
  group_ids                    = each.value.group_ids
  private_link_resource_region = each.value.private_link_resource_region != null ? each.value.private_link_resource_region : var.location # Is this required?
  tags                         = var.tags
}

# TODO: auto-approve: https://github.com/hashicorp/terraform-provider-azurerm/issues/23950#issuecomment-2035109970

# required AVM resources interfaces
resource "azurerm_management_lock" "this" {
  count = var.lock != null ? 1 : 0

  lock_level = var.lock.kind
  name       = coalesce(var.lock.name, "lock-${var.lock.kind}")
  scope      = azurerm_dashboard_grafana.this.id
  notes      = var.lock.kind == "CanNotDelete" ? "Cannot delete the resource or its child resources." : "Cannot delete or modify the resource or its child resources."
}

resource "azurerm_role_assignment" "this" {
  for_each = var.role_assignments

  principal_id                           = each.value.principal_id
  scope                                  = azurerm_dashboard_grafana.this.id
  condition                              = each.value.condition
  condition_version                      = each.value.condition_version
  delegated_managed_identity_resource_id = each.value.delegated_managed_identity_resource_id
  role_definition_id                     = strcontains(lower(each.value.role_definition_id_or_name), lower(local.role_definition_resource_substring)) ? each.value.role_definition_id_or_name : null
  role_definition_name                   = strcontains(lower(each.value.role_definition_id_or_name), lower(local.role_definition_resource_substring)) ? null : each.value.role_definition_id_or_name
  skip_service_principal_aad_check       = each.value.skip_service_principal_aad_check
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  for_each = var.diagnostic_settings

  name                           = each.value.name != null ? each.value.name : "diag-${var.name}"
  target_resource_id             = azurerm_dashboard_grafana.this.id
  eventhub_authorization_rule_id = each.value.event_hub_authorization_rule_resource_id
  eventhub_name                  = each.value.event_hub_name
  log_analytics_destination_type = each.value.log_analytics_destination_type
  log_analytics_workspace_id     = each.value.workspace_resource_id
  partner_solution_id            = each.value.marketplace_partner_resource_id
  storage_account_id             = each.value.storage_account_resource_id

  dynamic "enabled_log" {
    for_each = each.value.log_categories

    content {
      category = enabled_log.value
    }
  }
  dynamic "enabled_log" {
    for_each = each.value.log_groups

    content {
      category_group = enabled_log.value
    }
  }
  dynamic "metric" {
    for_each = each.value.metric_categories

    content {
      category = metric.value
    }
  }
}

