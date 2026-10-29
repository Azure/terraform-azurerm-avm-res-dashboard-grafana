module "avm_interfaces" {
  source  = "Azure/avm-utl-interfaces/azure"
  version = "0.9.0"

  location               = var.location
  diagnostic_settings_v2 = var.diagnostic_settings
  enable_telemetry       = var.enable_telemetry
  lock                   = var.lock
  managed_identities     = var.managed_identities
  # The resource group is used to resolve role names to role definition IDs, so lookups do not wait for the workspace.
  role_assignment_definition_scope = var.parent_id
  role_assignments                 = var.role_assignments
}

module "avm_interfaces_private_endpoints" {
  source   = "Azure/avm-utl-interfaces/azure"
  version  = "0.9.0"
  for_each = local.private_endpoints

  location                                = var.location
  enable_telemetry                        = var.enable_telemetry
  private_endpoints                       = { (each.key) = each.value }
  private_endpoints_manage_dns_zone_group = var.private_endpoints_manage_dns_zone_group
  private_endpoints_scope                 = "${var.parent_id}/providers/Microsoft.Dashboard/grafana/${var.name}"
  role_assignment_definition_scope        = local.private_endpoint_parent_ids[each.key]
}
