# Access to the Grafana workspace itself (Grafana Admin / Editor / Viewer for users, groups and pipelines).
resource "azapi_resource" "role_assignments" {
  for_each = module.avm_interfaces.role_assignments_azapi

  name                 = each.value.name
  parent_id            = azapi_resource.this.id
  type                 = var.resource_types.authorization_role_assignments
  body                 = each.value.body
  ignore_body_changes  = length(var.ignore_body_changes.authorization_role_assignments) > 0 ? var.ignore_body_changes.authorization_role_assignments : null
  ignore_null_property = true
  # Role assignments cannot be updated in place (RoleAssignmentUpdateNotPermitted): replace them when the principal or
  # role changes, including when a recreated workspace gets a new identity whose ID is only known after apply.
  replace_triggers_external_values = {
    principal_id       = each.value.body.properties.principalId
    role_definition_id = each.value.body.properties.roleDefinitionId
  }
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

resource "azapi_resource" "private_endpoint_role_assignments" {
  for_each = local.private_endpoint_role_assignments

  name                 = each.value.name
  parent_id            = azapi_resource.private_endpoints[each.value.pe_key].id
  type                 = var.resource_types.authorization_role_assignments
  body                 = each.value.body
  ignore_body_changes  = length(var.ignore_body_changes.authorization_role_assignments) > 0 ? var.ignore_body_changes.authorization_role_assignments : null
  ignore_null_property = true
  # Role assignments cannot be updated in place (RoleAssignmentUpdateNotPermitted): replace them when the principal or
  # role changes, including when a recreated workspace gets a new identity whose ID is only known after apply.
  replace_triggers_external_values = {
    principal_id       = each.value.body.properties.principalId
    role_definition_id = each.value.body.properties.roleDefinitionId
  }
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
