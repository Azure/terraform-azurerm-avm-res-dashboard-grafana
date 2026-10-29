mock_provider "azapi" {
  mock_data "azapi_resource_list" {
    defaults = {
      output = {
        results = [
          {
            id        = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/22926164-76b3-42b3-bc55-97df8dab3e41"
            role_name = "Grafana Admin"
          },
          {
            id        = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/43d0d8ad-25c7-4714-9337-8ba259a9fe05"
            role_name = "Monitoring Reader"
          },
          {
            id        = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b0d8363b-8ddd-447d-831f-62ca05bff136"
            role_name = "Monitoring Data Reader"
          }
        ]
      }
    }
  }
  mock_data "azapi_client_config" {
    defaults = {
      subscription_id          = "00000000-0000-0000-0000-000000000000"
      subscription_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000"
      tenant_id                = "33333333-3333-3333-3333-333333333333"
    }
  }
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-grafana/providers/Microsoft.Network/privateEndpoints/pe-mock"
      output = {
        properties = {
          networkInterfaces = [
            {
              id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-grafana/providers/Microsoft.Network/networkInterfaces/nic-mock"
            }
          ]
          connectionState = {
            status = "Pending"
          }
        }
      }
    }
  }
}

mock_provider "random" {
  mock_resource "random_uuid" {
    defaults = {
      result = "11111111-1111-1111-1111-111111111111"
    }
  }
}

override_resource {
  target = azapi_resource.this
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-grafana/providers/Microsoft.Dashboard/grafana/amg-test"
    identity = {
      principal_id = "22222222-2222-2222-2222-222222222222"
      tenant_id    = "33333333-3333-3333-3333-333333333333"
    }
    output = {
      properties = {
        endpoint       = "https://amg-test-abc123.weu.grafana.azure.com"
        grafanaVersion = "12.1.0"
        outboundIPs    = []
      }
    }
  }
}

variables {
  location  = "westeurope"
  name      = "amg-test"
  parent_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-grafana"
}

run "defaults" {
  command = apply

  assert {
    condition     = azapi_resource.this.type == "Microsoft.Dashboard/grafana@2025-08-01"
    error_message = "The module must deploy the expected Grafana API version by default."
  }
  assert {
    condition     = azapi_resource.this.body.sku.name == "Standard" && azapi_resource.this.body.sku.size == "X1"
    error_message = "Defaults must be Standard / X1."
  }
  assert {
    condition     = azapi_resource.this.body.properties.apiKey == "Disabled"
    error_message = "API keys and service accounts must be disabled by default."
  }
  assert {
    condition     = azapi_resource.this.body.properties.grafanaMajorVersion == "12"
    error_message = "The default Grafana major version must be 12."
  }
  assert {
    condition     = length(azapi_resource.this.identity) == 0
    error_message = "The canonical managed_identities default configures no identity."
  }
  assert {
    condition     = length(azapi_resource.role_assignments) == 0 && length(azapi_resource.lock) == 0
    error_message = "No role assignments or locks should be created by default."
  }
  assert {
    condition     = length(azapi_resource.telemetry) == 1
    error_message = "Telemetry must be enabled by default."
  }
  assert {
    condition     = output.endpoint == "https://amg-test-abc123.weu.grafana.azure.com"
    error_message = "The endpoint output must expose the Grafana URL."
  }
  assert {
    condition     = output.resource_id == azapi_resource.this.id
    error_message = "The resource_id output must match the workspace ID."
  }
  assert {
    condition     = azapi_resource.this.body.properties.publicNetworkAccess == "Enabled"
    error_message = "Without private endpoints, public network access must stay enabled so the workspace is reachable."
  }
  assert {
    condition     = azapi_resource.this.body.properties.grafanaConfigurations.snapshots.externalEnabled == false
    error_message = "External snapshot publishing must be disabled by default."
  }
  assert {
    condition     = length(azapi_resource_action.refresh_managed_private_endpoints) == 0
    error_message = "No managed private endpoint refresh must run without managed private endpoints."
  }
  providers = {
    azapi  = azapi
    random = random
  }
}

run "public_network_access_follows_private_endpoints" {
  command = plan

  variables {
    private_endpoints = {
      pe = {
        subnet_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-pe"
      }
    }
  }

  assert {
    condition     = azapi_resource.this.body.properties.publicNetworkAccess == "Disabled"
    error_message = "With a private endpoint and no explicit choice, public network access must be disabled."
  }
  providers = {
    azapi  = azapi
    random = random
  }
}

run "public_network_access_explicit_choice_wins" {
  command = plan

  variables {
    public_network_access_enabled = true
    private_endpoints = {
      pe = {
        subnet_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-pe"
      }
    }
  }

  assert {
    condition     = azapi_resource.this.body.properties.publicNetworkAccess == "Enabled"
    error_message = "An explicit public_network_access_enabled must override the automatic choice."
  }
  providers = {
    azapi  = azapi
    random = random
  }
}

run "invalid_private_endpoint_resource_group" {
  command = plan

  variables {
    private_endpoints = {
      pe = {
        subnet_resource_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-pe"
        resource_group_name = "rg-not-an-id"
      }
    }
  }

  expect_failures = [azapi_resource.this]
  providers = {
    azapi  = azapi
    random = random
  }
}

run "grafana_11_settings_rejected_on_12" {
  command = plan

  variables {
    grafana_configurations = {
      users_editors_can_admin = true
    }
  }

  expect_failures = [azapi_resource.this]
  providers = {
    azapi  = azapi
    random = random
  }
}

run "grafana_11_settings_allowed_on_11" {
  command = plan

  variables {
    grafana_major_version = "11"
    grafana_configurations = {
      security_csrf_always_check = true
      users_editors_can_admin    = true
    }
  }

  assert {
    condition     = azapi_resource.this.body.properties.grafanaConfigurations.users.editorsCanAdmin == true && azapi_resource.this.body.properties.grafanaConfigurations.security.csrfAlwaysCheck == true
    error_message = "Grafana 11 settings must be sent when the workspace runs Grafana 11."
  }
  providers = {
    azapi  = azapi
    random = random
  }
}

run "telemetry_disabled" {
  command = apply

  variables {
    enable_telemetry = false
  }

  assert {
    condition     = length(azapi_resource.telemetry) == 0
    error_message = "enable_telemetry = false must disable telemetry."
  }
  providers = {
    azapi  = azapi
    random = random
  }
}

run "identity_integration_and_workspace_roles" {
  command = apply
  # Fresh state: the identity must be created, not added to the workspace applied by earlier runs.
  state_key = "identity"

  variables {
    managed_identities = {
      system_assigned = true
    }
    azure_monitor_workspace_integrations = {
      prom = {
        resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mon/providers/Microsoft.Monitor/accounts/amw-test"
      }
    }
    role_assignments = {
      admins = {
        principal_id               = "44444444-4444-4444-4444-444444444444"
        principal_type             = "Group"
        role_definition_id_or_name = "Grafana Admin"
      }
    }
  }

  assert {
    condition     = azapi_resource.this.identity[0].type == "SystemAssigned"
    error_message = "The system-assigned identity must be enabled."
  }
  assert {
    condition     = azapi_resource.this.body.properties.grafanaIntegrations.azureMonitorWorkspaceIntegrations[0].azureMonitorWorkspaceResourceId == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mon/providers/Microsoft.Monitor/accounts/amw-test"
    error_message = "The Azure Monitor workspace must be linked to Grafana."
  }
  assert {
    condition     = alltrue([for ra in values(azapi_resource.role_assignments) : ra.parent_id == azapi_resource.this.id])
    error_message = "The module must only create role assignments on the Grafana workspace itself, never on linked data sources."
  }
  assert {
    condition     = endswith(azapi_resource.role_assignments["admins"].body.properties.roleDefinitionId, "22926164-76b3-42b3-bc55-97df8dab3e41") && azapi_resource.role_assignments["admins"].type == "Microsoft.Authorization/roleAssignments@2022-04-01"
    error_message = "Workspace role assignments must be resolved by name and use the resource_types default."
  }
  assert {
    condition     = output.system_assigned_mi_principal_id == "22222222-2222-2222-2222-222222222222"
    error_message = "The principal ID output must expose the system-assigned identity."
  }
  assert {
    condition     = azapi_resource.role_assignments["admins"].replace_triggers_external_values.principal_id == "44444444-4444-4444-4444-444444444444"
    error_message = "Workspace role assignments must be replaced when the principal changes."
  }
  providers = {
    azapi  = azapi
    random = random
  }
}

run "diagnostic_settings" {
  command = apply

  variables {
    diagnostic_settings = {
      law = {
        logs                  = [{ category_group = "allLogs" }]
        workspace_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mon/providers/Microsoft.OperationalInsights/workspaces/law-test"
      }
      named = {
        name                  = "diag-custom"
        logs                  = [{ category = "GrafanaLoginEvents" }]
        workspace_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mon/providers/Microsoft.OperationalInsights/workspaces/law-test"
      }
    }
  }

  assert {
    condition     = azapi_resource.diagnostic_settings["law"].name == "diag-amg-test" && azapi_resource.diagnostic_settings["named"].name == "diag-custom"
    error_message = "A diagnostic setting without a name must be named diag-<workspace>; an explicit name must be kept."
  }
  # Azure returns every category, disabled when not selected; sending the same list keeps plans clean.
  assert {
    condition = jsonencode(azapi_resource.diagnostic_settings["law"].body.properties.metrics) == jsonencode([
      { category = "AllMetrics", enabled = false, retentionPolicy = { days = 0, enabled = false } },
    ])
    error_message = "AllMetrics must be sent, disabled, when no metrics are requested."
  }
  assert {
    condition     = [for l in azapi_resource.diagnostic_settings["law"].body.properties.logs : [l.categoryGroup, l.enabled]] == [["allLogs", true], ["audit", false]]
    error_message = "Logs selected by category group must list the other group, disabled, after the selected one."
  }
  assert {
    condition = [for l in azapi_resource.diagnostic_settings["named"].body.properties.logs : [l.category, l.enabled]] == [
      ["GrafanaLoginEvents", true], ["GrafanaUsageInsightsEvents", false], ["GrafanaAlertAuthFailure", false],
    ]
    error_message = "Logs selected by category must list the other categories, disabled, in Azure's order."
  }
  assert {
    condition     = !contains(keys(azapi_resource.diagnostic_settings["law"].body.properties), "logAnalyticsDestinationType")
    error_message = "logAnalyticsDestinationType is not supported for Grafana and must not be sent."
  }
  assert {
    condition     = azapi_resource.diagnostic_settings["law"].body.properties.logs[0].categoryGroup == "allLogs"
    error_message = "The configured log category group must be exported."
  }
  assert {
    condition     = azapi_resource.diagnostic_settings["law"].type == "Microsoft.Insights/diagnosticSettings@2021-05-01-preview"
    error_message = "Diagnostic settings must use the resource_types default."
  }
  providers = {
    azapi  = azapi
    random = random
  }
}

run "smtp_configuration" {
  command = apply

  variables {
    grafana_configurations = {
      smtp = {
        host         = "smtp.office365.com:587"
        from_address = "grafana@example.com"
        user         = "grafana@example.com"
      }
    }
    smtp_password         = "not-a-real-password"
    smtp_password_version = "2"
  }

  assert {
    condition = (
      azapi_resource.this.body.properties.grafanaConfigurations.smtp.enabled == true &&
      azapi_resource.this.body.properties.grafanaConfigurations.smtp.host == "smtp.office365.com:587" &&
      azapi_resource.this.body.properties.grafanaConfigurations.smtp.fromAddress == "grafana@example.com" &&
      azapi_resource.this.body.properties.grafanaConfigurations.smtp.startTLSPolicy == "MandatoryStartTLS" &&
      azapi_resource.this.body.properties.grafanaConfigurations.smtp.skipVerify == false
    )
    error_message = "SMTP settings must be mapped to the ARM body with secure defaults."
  }
  assert {
    condition     = azapi_resource.this.sensitive_body_version == null
    error_message = "The SMTP password must not be gated by a version: Azure rejects updates without it."
  }
  assert {
    condition     = length(azapi_resource_action.smtp_password) == 1 && azapi_resource_action.smtp_password[0].method == "PATCH" && terraform_data.smtp_password_version[0].triggers_replace == "2"
    error_message = "smtp_password_version must drive a PATCH that pushes the password."
  }
  providers = {
    azapi  = azapi
    random = random
  }
}

run "smtp_password_requires_smtp" {
  command = plan

  variables {
    smtp_password = "not-a-real-password"
  }

  expect_failures = [var.smtp_password]
  providers = {
    azapi  = azapi
    random = random
  }
}

run "smtp_user_requires_password" {
  command = plan

  variables {
    grafana_configurations = {
      smtp = {
        host         = "smtp.office365.com:587"
        from_address = "grafana@example.com"
        user         = "grafana@example.com"
      }
    }
  }

  expect_failures = [var.smtp_password]
  providers = {
    azapi  = azapi
    random = random
  }
}

run "no_smtp_no_password_version" {
  command = apply

  assert {
    condition     = azapi_resource.this.sensitive_body_version == null && azapi_resource.this.body.properties.grafanaConfigurations.smtp == null
    error_message = "Without SMTP settings no SMTP body or password version must be sent."
  }
  providers = {
    azapi  = azapi
    random = random
  }
}

run "private_endpoint" {
  command = apply

  variables {
    private_endpoints = {
      pe = {
        subnet_resource_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-pe"
        private_dns_zone_resource_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/privateDnsZones/privatelink.grafana.azure.com"]
      }
    }
  }

  assert {
    condition     = azapi_resource.private_endpoints["pe"].body.properties.privateLinkServiceConnections[0].properties.groupIds[0] == "grafana"
    error_message = "The private endpoint must target the `grafana` sub-resource."
  }
  assert {
    condition     = azapi_resource.private_endpoints["pe"].parent_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-grafana"
    error_message = "The private endpoint must default to the workspace resource group."
  }
  assert {
    condition     = length(azapi_resource.private_dns_zone_groups) == 1
    error_message = "A private DNS zone group must be created when zones are supplied."
  }
  assert {
    condition     = length(output.private_endpoints["pe"].network_interface_ids) == 1
    error_message = "The private_endpoints output must expose the network interfaces."
  }
  providers = {
    azapi  = azapi
    random = random
  }
}

run "two_private_endpoints_have_distinct_names" {
  command = apply

  variables {
    private_endpoints = {
      a = {
        subnet_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet/subnets/a"
      }
      b = {
        subnet_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet/subnets/b"
      }
      named = {
        name               = "pep-custom"
        subnet_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet/subnets/c"
      }
    }
  }

  assert {
    condition     = azapi_resource.private_endpoints["a"].name == "pep-amg-test-a" && azapi_resource.private_endpoints["b"].name == "pep-amg-test-b" && azapi_resource.private_endpoints["named"].name == "pep-custom"
    error_message = "Private endpoint names must default per map key and keep explicit names."
  }
  assert {
    condition     = length(distinct([for v in values(azapi_resource.private_endpoints) : v.body.properties.customNetworkInterfaceName])) == 3 && azapi_resource.private_endpoints["a"].body.properties.customNetworkInterfaceName == "nic-pep-amg-test-a" && azapi_resource.private_endpoints["named"].body.properties.customNetworkInterfaceName == "nic-pep-custom"
    error_message = "Network interface names must be distinct per endpoint."
  }
  assert {
    condition     = length(distinct([for v in values(azapi_resource.private_endpoints) : v.body.properties.privateLinkServiceConnections[0].name])) == 3 && azapi_resource.private_endpoints["b"].body.properties.privateLinkServiceConnections[0].name == "pse-amg-test-b"
    error_message = "Private service connection names must be distinct per endpoint."
  }
  providers = {
    azapi  = azapi
    random = random
  }
}

run "private_endpoint_tags_and_locks" {
  command = apply

  variables {
    tags = {
      environment = "test"
    }
    lock = {
      kind = "CanNotDelete"
    }
    private_endpoints = {
      inherit = {
        subnet_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet/subnets/a"
      }
      override = {
        subnet_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet/subnets/b"
        tags               = { owner = "network" }
        lock               = { kind = "ReadOnly" }
      }
      unlocked = {
        subnet_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet/subnets/c"
        lock               = { kind = "None" }
      }
    }
  }

  assert {
    condition     = azapi_resource.private_endpoints["inherit"].tags == tomap({ environment = "test" }) && azapi_resource.private_endpoints["override"].tags == tomap({ owner = "network" })
    error_message = "Private endpoints must inherit the module tags unless they set their own."
  }
  assert {
    condition     = azapi_resource.private_endpoint_locks["inherit"].body.properties.level == "CanNotDelete" && azapi_resource.private_endpoint_locks["override"].body.properties.level == "ReadOnly"
    error_message = "Private endpoints must inherit the workspace lock unless they set their own."
  }
  assert {
    condition     = !contains(keys(azapi_resource.private_endpoint_locks), "unlocked")
    error_message = "A lock kind of None must leave the private endpoint unlocked."
  }
  assert {
    condition     = azapi_resource.lock[0].name == "lock-amg-test"
    error_message = "The workspace lock must default to a stable lock-<workspace> name."
  }
  providers = {
    azapi  = azapi
    random = random
  }
}

run "invalid_private_endpoint_lock_kind" {
  command = plan

  variables {
    private_endpoints = {
      pe = {
        subnet_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet/subnets/a"
        lock               = { kind = "Frozen" }
      }
    }
  }

  expect_failures = [azapi_resource.this]
  providers = {
    azapi  = azapi
    random = random
  }
}

run "managed_private_endpoint" {
  command = apply

  variables {
    managed_private_endpoints = {
      prom = {
        name                         = "mpe-amw"
        private_link_resource_id     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mon/providers/Microsoft.Monitor/accounts/amw-test"
        private_link_resource_region = "westeurope"
        group_ids                    = ["prometheusMetrics"]
      }
    }
  }

  assert {
    condition     = keys(output.managed_private_endpoints) == ["prom"] && module.managed_private_endpoint["prom"].name == "mpe-amw"
    error_message = "One managed private endpoint must be created per map entry, with the configured name."
  }
  assert {
    condition = (
      length(azapi_resource_action.refresh_managed_private_endpoints) == 1 &&
      azapi_resource_action.refresh_managed_private_endpoints[0].action == "refreshManagedPrivateEndpoints" &&
      azapi_resource_action.refresh_managed_private_endpoints[0].method == "POST" &&
      azapi_resource_action.refresh_managed_private_endpoints[0].resource_id == azapi_resource.this.id
    )
    error_message = "Managed private endpoints must be followed by a refresh of the workspace."
  }
  providers = {
    azapi  = azapi
    random = random
  }
}

run "grafana_plugins" {
  command = apply

  variables {
    grafana_plugins = ["grafana-clock-panel", "marcusolsson-json-datasource"]
  }

  assert {
    condition     = toset(keys(azapi_resource.this.body.properties.grafanaPlugins)) == toset(["grafana-clock-panel", "marcusolsson-json-datasource"])
    error_message = "Plugins must be rendered as a map keyed by plugin ID."
  }
  providers = {
    azapi  = azapi
    random = random
  }
}

run "grafana_plugins_unmanaged_by_default" {
  command = apply

  assert {
    condition     = azapi_resource.this.body.properties.grafanaPlugins == null
    error_message = "An empty plugin set must not send grafanaPlugins."
  }
  providers = {
    azapi  = azapi
    random = random
  }
}

run "user_assigned_identity" {
  command = apply

  variables {
    managed_identities = {
      user_assigned_resource_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-id/providers/Microsoft.ManagedIdentity/userAssignedIdentities/uami"]
    }
    azure_monitor_workspace_integrations = {
      prom = {
        resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mon/providers/Microsoft.Monitor/accounts/amw-test"
      }
    }
  }

  assert {
    condition     = azapi_resource.this.identity[0].type == "UserAssigned" && contains(azapi_resource.this.identity[0].identity_ids, "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-id/providers/Microsoft.ManagedIdentity/userAssignedIdentities/uami")
    error_message = "A single user-assigned identity must be configured."
  }
  assert {
    condition     = length(azapi_resource.this.body.properties.grafanaIntegrations.azureMonitorWorkspaceIntegrations) == 1
    error_message = "A workspace with a user-assigned identity must still be linkable to an Azure Monitor workspace."
  }
  providers = {
    azapi  = azapi
    random = random
  }
}

run "scaffold_controls" {
  command = apply

  variables {
    resource_types = {
      dashboard_grafana = "Microsoft.Dashboard/grafana@2025-09-01-preview"
    }
    retry = {
      error_message_regex  = ["ScopeLocked"]
      interval_seconds     = 15
      max_interval_seconds = 60
    }
    timeouts = {
      create = "45m"
      delete = "30m"
    }
    ignore_body_changes = {
      dashboard_grafana = ["properties.grafanaPlugins"]
      dashboard_grafana_managed_private_endpoints = {
        dashboard_grafana_managed_private_endpoints = ["properties.requestMessage"]
      }
    }
    lock = {
      kind = "CanNotDelete"
    }
    managed_private_endpoints = {
      prom = {
        name                     = "mpe-amw"
        private_link_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mon/providers/Microsoft.Monitor/accounts/amw-test"
        group_ids                = ["prometheusMetrics"]
      }
    }
  }

  assert {
    condition     = azapi_resource.this.type == "Microsoft.Dashboard/grafana@2025-09-01-preview"
    error_message = "resource_types must override the workspace API version."
  }
  assert {
    condition     = azapi_resource.this.retry.interval_seconds == 15 && azapi_resource.lock[0].retry.max_interval_seconds == 60
    error_message = "retry must be applied to every AzAPI resource."
  }
  assert {
    condition     = azapi_resource.this.timeouts.create == "45m" && azapi_resource.lock[0].timeouts.delete == "30m"
    error_message = "timeouts must be applied to every AzAPI resource."
  }
  assert {
    condition     = azapi_resource.lock[0].type == "Microsoft.Authorization/locks@2020-05-01" && azapi_resource.lock[0].body.properties.level == "CanNotDelete"
    error_message = "The lock must use the resource_types default and the requested level."
  }
  providers = {
    azapi  = azapi
    random = random
  }
}

run "zone_redundancy_maps_to_body" {
  command = plan

  variables {
    zone_redundancy_enabled = true
  }

  assert {
    condition     = azapi_resource.this.body.properties.zoneRedundancy == "Enabled"
    error_message = "zone_redundancy_enabled must be translated to the ARM value."
  }
  providers = {
    azapi  = azapi
    random = random
  }
}

run "essential_sku_rejected" {
  command = plan

  variables {
    sku = "Essential"
  }

  expect_failures = [var.sku]
  providers = {
    azapi  = azapi
    random = random
  }
}

run "single_identity_only" {
  command = plan

  variables {
    managed_identities = {
      system_assigned            = true
      user_assigned_resource_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-id/providers/Microsoft.ManagedIdentity/userAssignedIdentities/uami"]
    }
  }

  expect_failures = [azapi_resource.this]
  providers = {
    azapi  = azapi
    random = random
  }
}

run "invalid_name" {
  command = plan

  variables {
    name = "-bad-name"
  }

  expect_failures = [var.name]
  providers = {
    azapi  = azapi
    random = random
  }
}

run "invalid_parent_id" {
  command = plan

  variables {
    parent_id = "/subscriptions/00000000-0000-0000-0000-000000000000"
  }

  expect_failures = [var.parent_id]
  providers = {
    azapi  = azapi
    random = random
  }
}

run "invalid_monitor_workspace_id" {
  command = plan

  variables {
    azure_monitor_workspace_integrations = {
      prom = {
        resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mon/providers/Microsoft.OperationalInsights/workspaces/law"
      }
    }
  }

  expect_failures = [var.azure_monitor_workspace_integrations]
  providers = {
    azapi  = azapi
    random = random
  }
}
