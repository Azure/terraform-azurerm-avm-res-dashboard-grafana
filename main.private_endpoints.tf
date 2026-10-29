resource "azapi_resource" "private_endpoints" {
  for_each = local.private_endpoints

  location               = coalesce(each.value.location, azapi_resource.this.location)
  name                   = module.avm_interfaces_private_endpoints[each.key].private_endpoints_azapi[each.key].name
  parent_id              = local.private_endpoint_parent_ids[each.key]
  type                   = var.resource_types.network_private_endpoints
  body                   = module.avm_interfaces_private_endpoints[each.key].private_endpoints_azapi[each.key].body
  ignore_body_changes    = length(var.ignore_body_changes.network_private_endpoints) > 0 ? var.ignore_body_changes.network_private_endpoints : null
  response_export_values = ["properties.networkInterfaces"]
  retry                  = var.retry
  tags                   = each.value.tags

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

resource "azapi_resource" "private_dns_zone_groups" {
  for_each = {
    for k, v in local.private_endpoints : k => module.avm_interfaces_private_endpoints[k].private_dns_zone_groups_azapi[k]
    if var.private_endpoints_manage_dns_zone_group && length(v.private_dns_zone_resource_ids) > 0
  }

  name                   = each.value.name
  parent_id              = azapi_resource.private_endpoints[each.key].id
  type                   = var.resource_types.network_private_endpoints_private_dns_zone_groups
  body                   = each.value.body
  ignore_body_changes    = length(var.ignore_body_changes.network_private_endpoints_private_dns_zone_groups) > 0 ? var.ignore_body_changes.network_private_endpoints_private_dns_zone_groups : null
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
