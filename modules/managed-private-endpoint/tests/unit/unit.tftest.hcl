mock_provider "azapi" {
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-grafana/providers/Microsoft.Dashboard/grafana/amg-test/managedPrivateEndpoints/mpe-amw"
      output = {
        properties = {
          connectionState = {
            status = "Approved"
          }
          privateLinkServicePrivateIP = "10.0.0.5"
        }
      }
    }
  }
}

variables {
  group_ids                = ["prometheusMetrics"]
  location                 = "westeurope"
  name                     = "mpe-amw"
  parent_id                = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-grafana/providers/Microsoft.Dashboard/grafana/amg-test"
  private_link_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mon/providers/Microsoft.Monitor/accounts/amw-test"
}

run "defaults" {
  command = apply

  assert {
    condition     = azapi_resource.this.type == "Microsoft.Dashboard/grafana/managedPrivateEndpoints@2025-08-01"
    error_message = "The submodule must default to the tested API version."
  }
  assert {
    condition     = azapi_resource.this.parent_id == var.parent_id
    error_message = "The managed private endpoint must be created under the Grafana workspace."
  }
  assert {
    condition     = azapi_resource.this.body.properties.groupIds[0] == "prometheusMetrics" && azapi_resource.this.body.properties.privateLinkResourceId == var.private_link_resource_id
    error_message = "The target resource and group IDs must be sent."
  }
  assert {
    condition     = length(azapi_resource.this.replace_triggers_refs) == 5
    error_message = "Every create-only property must trigger replacement."
  }
  assert {
    condition     = output.connection_status == "Approved" && output.private_ip_address == "10.0.0.5"
    error_message = "Connection status and private IP must be exposed."
  }
}

run "scaffold_controls" {
  command = apply

  variables {
    resource_types = {
      dashboard_grafana_managed_private_endpoints = "Microsoft.Dashboard/grafana/managedPrivateEndpoints@2025-09-01-preview"
    }
    retry = {
      error_message_regex = ["AnotherOperationInProgress"]
    }
    timeouts = {
      create = "20m"
    }
    ignore_body_changes = {
      dashboard_grafana_managed_private_endpoints = ["properties.requestMessage"]
    }
    tags = {
      environment = "test"
    }
  }

  assert {
    condition     = azapi_resource.this.type == "Microsoft.Dashboard/grafana/managedPrivateEndpoints@2025-09-01-preview"
    error_message = "resource_types must override the API version."
  }
  assert {
    condition     = azapi_resource.this.retry.error_message_regex[0] == "AnotherOperationInProgress" && azapi_resource.this.timeouts.create == "20m"
    error_message = "retry and timeouts must be applied."
  }
  assert {
    condition     = azapi_resource.this.tags["environment"] == "test"
    error_message = "Tags must be applied."
  }
}

run "invalid_parent_id" {
  command = plan

  variables {
    parent_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-grafana"
  }

  expect_failures = [var.parent_id]
}

run "group_ids_required" {
  command = plan

  variables {
    group_ids = []
  }

  expect_failures = [var.group_ids]
}
