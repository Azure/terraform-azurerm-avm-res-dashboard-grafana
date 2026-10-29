resource "azapi_resource" "diagnostic_settings" {
  for_each = local.diagnostic_settings

  name                   = each.value.name
  parent_id              = azapi_resource.this.id
  type                   = var.resource_types.insights_diagnostic_settings
  body                   = each.value.body
  ignore_body_changes    = length(var.ignore_body_changes.insights_diagnostic_settings) > 0 ? var.ignore_body_changes.insights_diagnostic_settings : null
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
}
