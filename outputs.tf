output "managed_private_endpoints" {
  description = "A map of managed private endpoints. The map key is the supplied input to var.managed_private_endpoints. The map value is the entire azurerm_grafana_managed_private_endpoint resource."
  value       = azurerm_dashboard_grafana_managed_private_endpoint.this
}

output "name" {
  description = "The Name of the Dashboard Grafana."
  value       = azurerm_dashboard_grafana.this.name
}

output "private_endpoints" {
  description = <<DESCRIPTION
  A map of the private endpoints created.
  DESCRIPTION
  value       = var.private_endpoints_manage_dns_zone_group ? azurerm_private_endpoint.this_managed_dns_zone_groups : azurerm_private_endpoint.this_unmanaged_dns_zone_groups
}

output "resource" {
  description = "The Dashboard Grafana resource."
  value       = azurerm_dashboard_grafana.this
}

output "resource_id" {
  description = "The ID of the Dashboard Grafana."
  value       = azurerm_dashboard_grafana.this.id
}
