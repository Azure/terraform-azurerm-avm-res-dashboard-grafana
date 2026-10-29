resource "azapi_resource" "lock" {
  count = var.lock != null ? 1 : 0

  name                   = coalesce(module.avm_interfaces.lock_azapi.name, "lock-${azapi_resource.this.name}")
  parent_id              = azapi_resource.this.id
  type                   = var.resource_types.authorization_locks
  body                   = module.avm_interfaces.lock_azapi.body
  ignore_body_changes    = length(var.ignore_body_changes.authorization_locks) > 0 ? var.ignore_body_changes.authorization_locks : null
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

  depends_on = [
    azapi_resource.role_assignments,
    azapi_resource.diagnostic_settings,
    azapi_resource.private_endpoints,
    azapi_resource.private_dns_zone_groups,
    azapi_resource.private_endpoint_role_assignments,
    azapi_resource.private_endpoint_locks,
    azapi_resource_action.refresh_managed_private_endpoints,
    module.managed_private_endpoint,
  ]
}

resource "azapi_resource" "private_endpoint_locks" {
  for_each = local.private_endpoint_locks

  name      = coalesce(each.value.name, "lock-${each.value.body.properties.level}")
  parent_id = azapi_resource.private_endpoints[each.key].id
  type      = var.resource_types.authorization_locks
  body = merge(each.value.body, {
    properties = {
      for k, v in each.value.body.properties : k => v
      if k != "notes" || v != null
    }
  })
  ignore_body_changes    = length(var.ignore_body_changes.authorization_locks) > 0 ? var.ignore_body_changes.authorization_locks : null
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

  depends_on = [
    azapi_resource.private_dns_zone_groups,
    azapi_resource.private_endpoint_role_assignments,
  ]
}
