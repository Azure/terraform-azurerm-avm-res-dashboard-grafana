resource "azapi_resource" "this" {
  location  = var.location
  name      = var.name
  parent_id = var.parent_id
  type      = var.resource_types.dashboard_grafana_managed_private_endpoints
  body = {
    properties = {
      groupIds                  = var.group_ids
      privateLinkResourceId     = var.private_link_resource_id
      privateLinkResourceRegion = var.private_link_resource_region
      privateLinkServiceUrl     = var.private_link_service_url
      requestMessage            = var.request_message
    }
  }
  ignore_body_changes  = length(var.ignore_body_changes.dashboard_grafana_managed_private_endpoints) > 0 ? var.ignore_body_changes.dashboard_grafana_managed_private_endpoints : null
  ignore_null_property = true
  # Every property can only be set at creation.
  replace_triggers_refs = [
    "properties.groupIds",
    "properties.privateLinkResourceId",
    "properties.privateLinkResourceRegion",
    "properties.privateLinkServiceUrl",
    "properties.requestMessage",
  ]
  response_export_values = [
    "properties.connectionState",
    "properties.privateLinkServicePrivateIP",
  ]
  retry = var.retry
  tags  = var.tags

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
