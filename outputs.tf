output "endpoint" {
  description = "The URL of the Grafana workspace, e.g. `https://<name>-<hash>.<region>.grafana.azure.com`."
  value       = azapi_resource.this.output.properties.endpoint
}

output "grafana_version" {
  description = "The full Grafana version currently running on the workspace."
  value       = try(azapi_resource.this.output.properties.grafanaVersion, null)
}

output "managed_private_endpoints" {
  description = "A map of the managed private endpoints created, keyed like `var.managed_private_endpoints`, with their resource ID and connection status."
  value = {
    for k, v in module.managed_private_endpoint : k => {
      resource_id       = v.resource_id
      connection_status = v.connection_status
    }
  }
}

output "name" {
  description = "The name of the Grafana workspace."
  value       = azapi_resource.this.name
}

output "outbound_ips" {
  description = "The outbound IPs of the workspace when `deterministic_outbound_ip_enabled` is `true`."
  value       = try(azapi_resource.this.output.properties.outboundIPs, [])
}

output "private_endpoints" {
  description = "A map of the private endpoints created, keyed like `var.private_endpoints`, with their resource ID and network interface IDs."
  value = {
    for k, v in azapi_resource.private_endpoints : k => {
      id                    = v.id
      network_interface_ids = v.output.properties.networkInterfaces[*].id
    }
  }
}

output "resource_id" {
  description = "The resource ID of the Grafana workspace."
  value       = azapi_resource.this.id
}

output "system_assigned_mi_principal_id" {
  description = "The principal ID of the system-assigned managed identity, or `null` when it is not enabled."
  value       = try(azapi_resource.this.identity[0].principal_id, null)
}
