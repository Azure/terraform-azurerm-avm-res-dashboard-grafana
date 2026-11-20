output "connection_status" {
  description = "The status of the Private Link connection, e.g. `Pending` until the owner of the target resource approves it, then `Approved`."
  value       = try(azapi_resource.this.output.properties.connectionState.status, null)
}

output "name" {
  description = "The name of the managed private endpoint."
  value       = azapi_resource.this.name
}

output "private_ip_address" {
  description = "The private IP address of the Private Link service behind the managed private endpoint."
  value       = try(azapi_resource.this.output.properties.privateLinkServicePrivateIP, null)
}

output "resource_id" {
  description = "The resource ID of the managed private endpoint."
  value       = azapi_resource.this.id
}
