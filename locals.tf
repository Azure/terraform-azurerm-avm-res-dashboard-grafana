locals {
  # Azure returns the whole catalog of a Grafana diagnostic setting: the log entries sent, then the other category groups
  # (or, when logs are selected by category or not at all, the other categories) and AllMetrics, all disabled. Sending
  # them explicitly, in that order, avoids a perpetual diff. Catalog from the diagnosticSettingsCategories API.
  diagnostic_catalog = concat(
    [for g in ["allLogs", "audit"] : { category = null, categoryGroup = g }],
    [for c in ["GrafanaLoginEvents", "GrafanaUsageInsightsEvents", "GrafanaAlertAuthFailure"] : { category = c, categoryGroup = null }],
  )
  diagnostic_metric_categories = ["AllMetrics"]
  diagnostic_retention_off     = { days = 0, enabled = false }
  # `logAnalyticsDestinationType` is not supported for Microsoft.Dashboard/grafana diagnostic settings and does not
  # round-trip, so it is not sent even though the standard interface carries it.
  # The utility module returns a null name when none is set, which AzAPI rejects.
  diagnostic_settings = {
    for k, v in module.avm_interfaces.diagnostic_settings_azapi_v2 : k => merge(v, {
      name = coalesce(v.name, "diag-${var.name}")
      body = merge(v.body, {
        properties = merge(
          { for pk, pv in v.body.properties : pk => pv if pk != "logAnalyticsDestinationType" },
          {
            logs = concat(local.diagnostic_settings_sent[k].logs, [
              for e in local.diagnostic_catalog : merge(e, { enabled = false, retentionPolicy = local.diagnostic_retention_off })
              if(e.categoryGroup != null) == local.diagnostic_settings_sent[k].by_group && !contains(local.diagnostic_settings_sent[k].log_keys, coalesce(e.categoryGroup, e.category))
            ])
            metrics = concat(local.diagnostic_settings_sent[k].metrics, [
              for m in local.diagnostic_metric_categories : { category = m, enabled = false, retentionPolicy = local.diagnostic_retention_off }
              if !contains([for x in local.diagnostic_settings_sent[k].metrics : x.category], m)
            ])
          }
        )
      })
    })
  }
  diagnostic_settings_sent = {
    for k, v in module.avm_interfaces.diagnostic_settings_azapi_v2 : k => {
      logs     = v.body.properties.logs == null ? [] : v.body.properties.logs
      metrics  = v.body.properties.metrics == null ? [] : v.body.properties.metrics
      by_group = anytrue([for l in coalesce(v.body.properties.logs, []) : l.categoryGroup != null])
      log_keys = [for l in coalesce(v.body.properties.logs, []) : coalesce(l.categoryGroup, l.category)]
    }
  }
  grafana_configurations = {
    security = {
      csrfAlwaysCheck = var.grafana_configurations.security_csrf_always_check
    }
    smtp = var.grafana_configurations.smtp == null ? null : {
      enabled        = var.grafana_configurations.smtp.enabled
      fromAddress    = var.grafana_configurations.smtp.from_address
      fromName       = var.grafana_configurations.smtp.from_name
      host           = var.grafana_configurations.smtp.host
      skipVerify     = var.grafana_configurations.smtp.skip_verify
      startTLSPolicy = var.grafana_configurations.smtp.start_tls_policy
      user           = var.grafana_configurations.smtp.user
    }
    snapshots = {
      externalEnabled = var.grafana_configurations.snapshots_external_enabled
    }
    unifiedAlertingScreenshots = {
      captureEnabled = var.grafana_configurations.unified_alerting_screenshots_capture_enabled
    }
    users = {
      editorsCanAdmin = var.grafana_configurations.users_editors_can_admin
      viewersCanEdit  = var.grafana_configurations.users_viewers_can_edit
    }
  }
}

locals {
  # Public access is closed by default as soon as the workspace has a private endpoint to be reached through.
  public_network_access_enabled = var.public_network_access_enabled != null ? var.public_network_access_enabled : length(var.private_endpoints) == 0
}

locals {
  private_endpoint_locks = {
    for k, v in module.avm_interfaces_private_endpoints : k => v.lock_private_endpoint_azapi[k]
    if local.private_endpoints[k].lock != null
  }
  private_endpoint_parent_ids = {
    for k, v in var.private_endpoints : k => coalesce(v.resource_group_name, var.parent_id)
  }
  private_endpoint_role_assignments = {
    for item in flatten([
      for parent_value in module.avm_interfaces_private_endpoints : [
        for child_key, child_value in parent_value.role_assignments_private_endpoint_azapi : {
          child_key   = child_key
          child_value = child_value
        }
      ]
    ]) : item.child_key => item.child_value
  }
  # Defaults are derived per map key: the utility module's generated names depend only on the workspace, so two
  # unnamed endpoints would collide. Tags and the workspace lock apply to endpoints unless overridden; a lock kind of
  # `None` opts an endpoint out of the workspace lock.
  private_endpoints = {
    for k, v in var.private_endpoints : k => merge(v, {
      lock                            = v.lock == null ? var.lock : (v.lock.kind == "None" ? null : v.lock)
      name                            = coalesce(v.name, "pep-${var.name}-${k}")
      network_interface_name          = coalesce(v.network_interface_name, "nic-${coalesce(v.name, "pep-${var.name}-${k}")}")
      private_service_connection_name = coalesce(v.private_service_connection_name, "pse-${var.name}-${k}")
      subresource_name                = coalesce(v.subresource_name, "grafana")
      tags                            = v.tags != null ? v.tags : var.tags
    })
  }
}
