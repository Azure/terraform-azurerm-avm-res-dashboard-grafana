variable "location" {
  type        = string
  description = "Azure region where the Grafana workspace and its telemetry deployment are created."
  nullable    = false
}

variable "name" {
  type        = string
  description = "The name of the Azure Managed Grafana workspace. It is also used as the host name prefix of the workspace endpoint."
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{0,28}[a-zA-Z0-9]$", var.name))
    error_message = "The name must be 2-30 characters, start with a letter, end with a letter or digit, and contain only letters, digits and hyphens."
  }
}

variable "parent_id" {
  type        = string
  description = "The fully-qualified ARM resource ID of the existing resource group into which the Grafana workspace will be deployed."
  nullable    = false

  validation {
    condition     = can(provider::azapi::parse_resource_id("Microsoft.Resources/resourceGroups", var.parent_id))
    error_message = "`parent_id` must be a valid resource group resource ID."
  }
}

variable "api_key_enabled" {
  type        = bool
  default     = false
  description = <<DESCRIPTION
Enables API keys and Grafana service accounts. Defaults to `false`.

Leave this disabled when automation authenticates with Microsoft Entra ID tokens (audience `https://dashboard.azure.com`),
which is the recommended approach: service account tokens bypass Entra ID and are long-lived secrets.
DESCRIPTION
  nullable    = false
}

variable "azure_monitor_workspace_integrations" {
  type = map(object({
    resource_id = string
  }))
  default     = {}
  description = <<DESCRIPTION
A map of Azure Monitor workspaces (managed Prometheus) to link to Grafana. Each link provisions a Prometheus data source in Grafana.
The map key is deliberately arbitrary to avoid issues where map keys may be unknown at plan time.

Linking does not grant access: Grafana's identity also needs `Monitoring Data Reader` on each workspace, granted by the module that manages the workspace (see the `system_assigned_mi_principal_id` output).

- `resource_id` - The resource ID of the Azure Monitor workspace.
DESCRIPTION
  nullable    = false

  validation {
    condition = alltrue([
      for v in values(var.azure_monitor_workspace_integrations) :
      can(provider::azapi::parse_resource_id("Microsoft.Monitor/accounts", v.resource_id))
    ])
    error_message = "Each `resource_id` must be a valid Azure Monitor workspace (Microsoft.Monitor/accounts) resource ID."
  }
}

variable "deterministic_outbound_ip_enabled" {
  type        = bool
  default     = false
  description = "Use deterministic outbound IPs, so that data sources behind a firewall can allow-list Grafana. The IPs are exported in the `outbound_ips` output. Defaults to `false`."
  nullable    = false
}

variable "diagnostic_settings" {
  type = map(object({
    name = optional(string, null)
    logs = optional(set(object({
      category       = optional(string, null)
      category_group = optional(string, null)
      enabled        = optional(bool, true)
      retention_policy = optional(object({
        days    = optional(number, 0)
        enabled = optional(bool, false)
      }), {})
    })), [])
    metrics = optional(set(object({
      category = optional(string, null)
      enabled  = optional(bool, true)
      retention_policy = optional(object({
        days    = optional(number, 0)
        enabled = optional(bool, false)
      }), {})
    })), [])
    log_analytics_destination_type           = optional(string, "Dedicated")
    workspace_resource_id                    = optional(string, null)
    storage_account_resource_id              = optional(string, null)
    event_hub_authorization_rule_resource_id = optional(string, null)
    event_hub_name                           = optional(string, null)
    marketplace_partner_resource_id          = optional(string, null)
  }))
  default     = {}
  description = <<DESCRIPTION
A map of diagnostic settings to create on the resource. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.

- `name` - (Optional) The name of the diagnostic setting. One will be generated if not set, however this will not be unique if you want to create multiple diagnostic setting resources.
- `logs` - (Optional) A set of log entries to send to the destination. Each entry has the following attributes:
  - `category` - (Optional) The name of a specific log category to enable. Mutually exclusive with `category_group`.
  - `category_group` - (Optional) The name of a log category group to enable (for example, `allLogs` or `audit`). Mutually exclusive with `category`.
  - `enabled` - (Optional) Whether the log entry is enabled. Defaults to `true`.
  - `retention_policy` - (Optional) The retention policy for the log entry.
    - `days` - (Optional) The retention period in days. Defaults to `0` (retain indefinitely).
    - `enabled` - (Optional) Whether the retention policy is enabled. Defaults to `false`.
- `metrics` - (Optional) A set of metric entries to send to the destination. Each entry has the following attributes:
  - `category` - (Optional) The name of the metric category to enable.
  - `enabled` - (Optional) Whether the metric entry is enabled. Defaults to `true`.
  - `retention_policy` - (Optional) The retention policy for the metric entry, with the same `days` and `enabled` attributes as `logs.retention_policy`.
- `log_analytics_destination_type` - (Optional) The destination type for the diagnostic setting. Possible values are `Dedicated` and `AzureDiagnostics`. Defaults to `Dedicated`.
- `workspace_resource_id` - (Optional) The resource ID of the log analytics workspace to send logs and metrics to.
- `storage_account_resource_id` - (Optional) The resource ID of the storage account to send logs and metrics to.
- `event_hub_authorization_rule_resource_id` - (Optional) The resource ID of the event hub authorization rule to send logs and metrics to.
- `event_hub_name` - (Optional) The name of the event hub. If none is specified, the default event hub will be selected.
- `marketplace_partner_resource_id` - (Optional) The full ARM resource ID of the Marketplace resource to which you would like to send Diagnostic Logs.
DESCRIPTION
  nullable    = false

  validation {
    condition     = alltrue([for _, v in var.diagnostic_settings : contains(["Dedicated", "AzureDiagnostics"], v.log_analytics_destination_type)])
    error_message = "Log analytics destination type must be one of: 'Dedicated', 'AzureDiagnostics'."
  }
  validation {
    condition = alltrue([
      for _, v in var.diagnostic_settings : alltrue([
        for l in v.logs : (l.category != null) != (l.category_group != null)
      ])
    ])
    error_message = "Each log entry must set exactly one of `category` or `category_group`."
  }
  validation {
    condition = alltrue(
      [
        for _, v in var.diagnostic_settings :
        v.workspace_resource_id != null || v.storage_account_resource_id != null || v.event_hub_authorization_rule_resource_id != null || v.marketplace_partner_resource_id != null
      ]
    )
    error_message = "At least one of `workspace_resource_id`, `storage_account_resource_id`, `marketplace_partner_resource_id`, or `event_hub_authorization_rule_resource_id`, must be set."
  }
  validation {
    condition = alltrue([
      for _, v in var.diagnostic_settings :
      v.workspace_resource_id == null || can(provider::azapi::parse_resource_id("Microsoft.OperationalInsights/workspaces", v.workspace_resource_id))
    ])
    error_message = "Each `workspace_resource_id` must be a valid Log Analytics workspace resource ID, or null."
  }
  validation {
    condition = alltrue([
      for _, v in var.diagnostic_settings :
      v.storage_account_resource_id == null || can(provider::azapi::parse_resource_id("Microsoft.Storage/storageAccounts", v.storage_account_resource_id))
    ])
    error_message = "Each `storage_account_resource_id` must be a valid storage account resource ID, or null."
  }
  validation {
    condition = alltrue([
      for _, v in var.diagnostic_settings :
      v.event_hub_authorization_rule_resource_id == null || can(provider::azapi::parse_resource_id("Microsoft.EventHub/namespaces/authorizationRules", v.event_hub_authorization_rule_resource_id))
    ])
    error_message = "Each `event_hub_authorization_rule_resource_id` must be a valid Event Hub namespace authorization rule resource ID, or null."
  }
}

variable "enable_telemetry" {
  type        = bool
  default     = true
  description = <<DESCRIPTION
This variable controls whether or not telemetry is enabled for the module.
For more information see <https://aka.ms/avm/telemetryinfo>.
If it is set to false, then no telemetry will be collected.
DESCRIPTION
  nullable    = false
}

variable "grafana_configurations" {
  type = object({
    smtp = optional(object({
      enabled          = optional(bool, true)
      host             = string
      from_address     = string
      from_name        = optional(string, null)
      user             = optional(string, null)
      start_tls_policy = optional(string, "MandatoryStartTLS")
      skip_verify      = optional(bool, false)
    }), null)
    security_csrf_always_check                   = optional(bool, null)
    snapshots_external_enabled                   = optional(bool, false)
    unified_alerting_screenshots_capture_enabled = optional(bool, null)
    users_editors_can_admin                      = optional(bool, null)
    users_viewers_can_edit                       = optional(bool, null)
  })
  default     = {}
  description = <<DESCRIPTION
Grafana server settings. Unset (`null`) values are not sent: a new workspace gets the service default and an existing one
keeps its current value.

- `smtp` - (Optional) SMTP settings used for alert notifications and reports. The password is set with `smtp_password`.
  - `enabled` - (Optional) Defaults to `true`.
  - `host` - SMTP server host and port, e.g. `smtp.office365.com:587`.
  - `from_address` - Address used as sender.
  - `from_name` - (Optional) Display name used as sender.
  - `user` - (Optional) SMTP user name.
  - `start_tls_policy` - (Optional) One of `OpportunisticStartTLS`, `MandatoryStartTLS`, `NoStartTLS`. Defaults to `MandatoryStartTLS`.
  - `skip_verify` - (Optional) Skip TLS certificate verification. Defaults to `false`.
- `security_csrf_always_check` - (Optional) Always run the CSRF check, even for requests without a session cookie. Grafana 11 and earlier only.
- `snapshots_external_enabled` - (Optional) Allow publishing snapshots to an external snapshot server. Defaults to `false`, as the Azure Managed Grafana security guidance recommends; the service default is `true`.
- `unified_alerting_screenshots_capture_enabled` - (Optional) Attach panel screenshots to alert notifications.
- `users_editors_can_admin` - (Optional) Let Editors administer the dashboards, folders and teams they create. Grafana 11 and earlier only.
- `users_viewers_can_edit` - (Optional) Let Viewers use Explore and edit (but not save) dashboards.
DESCRIPTION
  nullable    = false

  validation {
    condition     = var.grafana_configurations.smtp == null || contains(["OpportunisticStartTLS", "MandatoryStartTLS", "NoStartTLS"], try(var.grafana_configurations.smtp.start_tls_policy, ""))
    error_message = "`smtp.start_tls_policy` must be one of: OpportunisticStartTLS, MandatoryStartTLS, NoStartTLS."
  }
}

variable "grafana_major_version" {
  type        = string
  default     = "12"
  description = <<DESCRIPTION
The major Grafana version to run. Defaults to `12`.

Microsoft applies minor and patch updates automatically. Major upgrades are opt-in until a version retires; Microsoft then
upgrades the remaining workspaces itself. Upgrades can't be undone: after Microsoft upgraded a workspace, raise this input
to match (the `grafana_version` output shows the running version), or add `properties.grafanaMajorVersion` to
`ignore_body_changes.dashboard_grafana` to let Microsoft manage the version. From Grafana 13, Azure-authenticated
Prometheus uses the `grafana-azureprometheus-datasource` plugin.
DESCRIPTION
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]+$", var.grafana_major_version))
    error_message = "The Grafana major version must be a number, e.g. `12`."
  }
}

variable "grafana_plugins" {
  type        = set(string)
  default     = []
  description = <<DESCRIPTION
A set of additional plugin IDs to install, e.g. `grafana-clock-panel`. An empty set (the default) leaves plugins unmanaged, and the property is not sent.

The service applies this list as additions, so removing a plugin from the set may not uninstall it from the workspace.
DESCRIPTION
  nullable    = false
}

variable "ignore_body_changes" {
  type = object({
    authorization_locks                               = optional(list(string), [])
    authorization_role_assignments                    = optional(list(string), [])
    dashboard_grafana                                 = optional(list(string), [])
    insights_diagnostic_settings                      = optional(list(string), [])
    network_private_endpoints                         = optional(list(string), [])
    network_private_endpoints_private_dns_zone_groups = optional(list(string), [])

    dashboard_grafana_managed_private_endpoints = optional(object({
      dashboard_grafana_managed_private_endpoints = optional(list(string), [])
    }), {})
  })
  default     = {}
  description = <<DESCRIPTION
Paths in each resource's `body` whose changes the AzAPI provider ignores. Prefer Terraform's `lifecycle.ignore_changes` when the paths are static; use this variable when the paths must be derived from variables or other non-static values.

Paths use dot notation, for example `properties.grafanaPlugins`. Individual list items cannot be targeted — ignore the whole list property instead. Configuration changes at an ignored path are **not** sent to Azure until that path is removed from the list.

Supplying a non-empty value requires Terraform 1.11 or later, because `ignore_body_changes` is a write-only argument. Changes take effect only after an apply, because the value is held in provider-private state.

- `authorization_locks` - Ignored body paths for the management locks on the workspace and its private endpoints.
- `authorization_role_assignments` - Ignored body paths for role assignments on the workspace, on its private endpoints, and for its managed identity.
- `dashboard_grafana` - Ignored body paths for the Grafana workspace managed by this module.
- `insights_diagnostic_settings` - Ignored body paths for the diagnostic settings.
- `network_private_endpoints` - Ignored body paths for the private endpoints.
- `network_private_endpoints_private_dns_zone_groups` - Ignored body paths for the private DNS zone groups.
- `dashboard_grafana_managed_private_endpoints` - Override slot for the `managed-private-endpoint` submodule. Supply only the keys you want to override.
  - `dashboard_grafana_managed_private_endpoints` - Ignored body paths for the managed private endpoint managed by the submodule.
DESCRIPTION
  nullable    = false
}

variable "lock" {
  type = object({
    kind  = string
    name  = optional(string, null)
    notes = optional(string, null)
  })
  default     = null
  description = <<DESCRIPTION
Controls the Resource Lock configuration for this resource. The following properties can be specified:

- `kind` - (Required) The type of lock. Possible values are `\"CanNotDelete\"` and `\"ReadOnly\"`.
- `name` - (Optional) The name of the lock. If not specified, it defaults to `lock-<workspace name>`. Changing this forces the creation of a new resource.
- `notes` - (Optional) Notes about the lock. This value maps to `Microsoft.Authorization/locks.properties.notes`.

The default, `null`, creates no lock. The lock also applies to every private endpoint created by this module unless that endpoint sets its own `lock` (use `kind = "None"` to leave an endpoint unlocked).
Prefer `CanNotDelete` in production: a `ReadOnly` lock also blocks later updates of the workspace and the refresh of managed private endpoints.
DESCRIPTION

  validation {
    condition     = var.lock != null ? contains(["CanNotDelete", "ReadOnly"], var.lock.kind) : true
    error_message = "Lock kind must be either `\"CanNotDelete\"` or `\"ReadOnly\"`."
  }
}

variable "managed_identities" {
  type = object({
    system_assigned            = optional(bool, false)
    user_assigned_resource_ids = optional(set(string), [])
  })
  default     = {}
  description = <<DESCRIPTION
Controls the Managed Identity configuration on this resource. The following properties can be specified:

- `system_assigned` - (Optional) Specifies if the System Assigned Managed Identity should be enabled.
- `user_assigned_resource_ids` - (Optional) Specifies a list of User Assigned Managed Identity resource IDs to be assigned to this resource.
DESCRIPTION
  nullable    = false

  validation {
    condition = alltrue([
      for id in var.managed_identities.user_assigned_resource_ids :
      can(provider::azapi::parse_resource_id("Microsoft.ManagedIdentity/userAssignedIdentities", id))
    ])
    error_message = "Each entry in `managed_identities.user_assigned_resource_ids` must be a valid user-assigned managed identity resource ID."
  }
}

variable "managed_private_endpoints" {
  type = map(object({
    name                         = string
    private_link_resource_id     = string
    group_ids                    = list(string)
    private_link_resource_region = optional(string, null)
    private_link_service_url     = optional(string, null)
    request_message              = optional(string, null)
  }))
  default     = {}
  description = <<DESCRIPTION
A map of managed private endpoints that Grafana uses to reach data sources over Private Link.
The map key is deliberately arbitrary to avoid issues where map keys may be unknown at plan time. All attributes can only be set at creation; changing them replaces the managed private endpoint.

Each connection must then be approved on the target resource, by whoever owns it, and the workspace refreshed: Grafana
only uses an approved endpoint after a refresh. The module refreshes whenever endpoints are added or removed; after an
approval, change `managed_private_endpoints_refresh_trigger` to refresh again.

- `name` - The name of the managed private endpoint.
- `private_link_resource_id` - The resource ID of the target resource, e.g. an Azure Monitor workspace or an Azure Data Explorer cluster.
- `group_ids` - The private link sub-resources to connect to, e.g. `["prometheusMetrics"]` for an Azure Monitor workspace.
- `private_link_resource_region` - (Optional) The region of the target resource.
- `private_link_service_url` - (Optional) The URL of the data store behind the Private Link service, as used in the Grafana data source, without protocol and port.
- `request_message` - (Optional) A message shown to the approver of the connection request.

`private_link_resource_id` is not validated because it accepts many resource types.
DESCRIPTION
  nullable    = false
}

variable "managed_private_endpoints_refresh_trigger" {
  type        = string
  default     = null
  description = "Change this value, e.g. to a date, to refresh the managed private endpoints again, typically after their connections were approved on the target resources. Ignored when `managed_private_endpoints` is empty."
}

variable "private_endpoints" {
  type = map(object({
    name = optional(string, null)
    role_assignments = optional(map(object({
      name                                   = optional(string, null)
      role_definition_id_or_name             = string
      principal_id                           = string
      description                            = optional(string, null)
      skip_service_principal_aad_check       = optional(bool, false)
      condition                              = optional(string, null)
      condition_version                      = optional(string, null)
      delegated_managed_identity_resource_id = optional(string, null)
      principal_type                         = optional(string, null)
    })), {})
    lock = optional(object({
      kind  = string
      name  = optional(string, null)
      notes = optional(string, null)
    }), null)
    tags                                    = optional(map(string), null)
    subnet_resource_id                      = string
    subresource_name                        = optional(string, null) # only required if the parent resource exposes more than one private endpoint sub-resource
    private_dns_zone_group_name             = optional(string, "default")
    private_dns_zone_resource_ids           = optional(set(string), [])
    application_security_group_associations = optional(map(string), {})
    private_service_connection_name         = optional(string, null)
    network_interface_name                  = optional(string, null)
    location                                = optional(string, null)
    resource_group_name                     = optional(string, null)
    ip_configurations = optional(map(object({
      name               = string
      private_ip_address = string
      member_name        = optional(string)
    })), {})
  }))
  default     = {}
  description = <<DESCRIPTION
A map of private endpoints to create on the Grafana workspace. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.

- `name` - (Optional) The name of the private endpoint. One will be generated if not set.
- `role_assignments` - (Optional) A map of role assignments to create on the private endpoint. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time. See `var.role_assignments` for more information.
  - `name` - (Optional) The name of the role assignment. If not set, a random UUID will be generated. Changing this forces the creation of a new resource.
  - `role_definition_id_or_name` - The ID or name of the role definition to assign to the principal.
  - `principal_id` - The ID of the principal to assign the role to.
  - `description` - (Optional) The description of the role assignment.
  - `skip_service_principal_aad_check` - (Optional) If set to true, skips the Azure Active Directory check for the service principal in the tenant. Defaults to false.
  - `condition` - (Optional) The condition which will be used to scope the role assignment.
  - `condition_version` - (Optional) The version of the condition syntax. Leave as `null` if you are not using a condition, if you are then valid values are '2.0'.
  - `delegated_managed_identity_resource_id` - (Optional) The delegated Azure Resource Id which contains a Managed Identity. Changing this forces a new resource to be created. This field is only used in cross-tenant scenario.
  - `principal_type` - (Optional) The type of the `principal_id`. Possible values are `User`, `Group` and `ServicePrincipal`. It is necessary to explicitly set this attribute when creating role assignments if the principal creating the assignment is constrained by ABAC rules that filters on the PrincipalType attribute.
- `lock` - (Optional) The lock level to apply to the private endpoint. Default is `None`. Possible values are `None`, `CanNotDelete`, and `ReadOnly`.
  - `kind` - (Required) The type of lock. Possible values are `\"CanNotDelete\"` and `\"ReadOnly\"`.
  - `name` - (Optional) The name of the lock. If not specified, a name will be generated based on the `kind` value. Changing this forces the creation of a new resource.
  - `notes` - (Optional) Notes about the lock. This value maps to `Microsoft.Authorization/locks.properties.notes`.
- `tags` - (Optional) A mapping of tags to assign to the private endpoint.
- `subnet_resource_id` - The resource ID of the subnet to deploy the private endpoint in.
- `subresource_name` (Optional) - The name of the sub resource for the private endpoint.
- `private_dns_zone_group_name` - (Optional) The name of the private DNS zone group. One will be generated if not set.
- `private_dns_zone_resource_ids` - (Optional) A set of resource IDs of private DNS zones to associate with the private endpoint. If not set, no zone groups will be created and the private endpoint will not be associated with any private DNS zones. DNS records must be managed external to this module.
- `application_security_group_associations` - (Optional) A map of resource IDs of application security groups to associate with the private endpoint. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.
- `private_service_connection_name` - (Optional) The name of the private service connection. One will be generated if not set.
- `network_interface_name` - (Optional) The name of the network interface. One will be generated if not set.
- `location` - (Optional) The Azure location where the resources will be deployed. Defaults to the location of the resource group.
- `resource_group_name` - (Optional) The resource group resource ID where the private endpoint resources will be deployed. Defaults to the resource group of the parent resource.
- `ip_configurations` - (Optional) A map of IP configurations to create on the private endpoint. If not specified the platform will create one. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.
  - `name` - The name of the IP configuration.
  - `private_ip_address` - The private IP address of the IP configuration.
  - `member_name` - (Optional) The private IP configuration member name.
DESCRIPTION
  nullable    = false

  validation {
    condition = alltrue([
      for _, v in var.private_endpoints :
      can(provider::azapi::parse_resource_id("Microsoft.Network/virtualNetworks/subnets", v.subnet_resource_id))
    ])
    error_message = "Each `private_endpoints[*].subnet_resource_id` must be a valid subnet resource ID."
  }
  validation {
    condition = alltrue(flatten([
      for _, v in var.private_endpoints : [
        for id in v.private_dns_zone_resource_ids :
        can(provider::azapi::parse_resource_id("Microsoft.Network/privateDnsZones", id))
      ]
    ]))
    error_message = "Each entry in `private_endpoints[*].private_dns_zone_resource_ids` must be a valid private DNS zone resource ID."
  }
  validation {
    condition = alltrue(flatten([
      for _, v in var.private_endpoints : [
        for _, asg in v.application_security_group_associations :
        can(provider::azapi::parse_resource_id("Microsoft.Network/applicationSecurityGroups", asg))
      ]
    ]))
    error_message = "Each value in `private_endpoints[*].application_security_group_associations` must be a valid application security group resource ID."
  }
  validation {
    condition = alltrue(flatten([
      for _, v in var.private_endpoints : [
        for _, ra in v.role_assignments :
        ra.delegated_managed_identity_resource_id == null || can(provider::azapi::parse_resource_id("Microsoft.ManagedIdentity/userAssignedIdentities", ra.delegated_managed_identity_resource_id))
      ]
    ]))
    error_message = "Each `private_endpoints[*].role_assignments[*].delegated_managed_identity_resource_id` must be a valid user-assigned managed identity resource ID, or null."
  }
}

variable "private_endpoints_manage_dns_zone_group" {
  type        = bool
  default     = true
  description = "Whether to manage private DNS zone groups with this module. If set to false, you must manage private DNS zone groups externally, e.g. using Azure Policy."
  nullable    = false
}

variable "public_network_access_enabled" {
  type        = bool
  default     = null
  description = <<DESCRIPTION
Allow access to the Grafana endpoint over the public network. The default, `null`, disables public access when
`private_endpoints` is not empty and enables it otherwise, so a workspace without private endpoints stays reachable.
Set `true` or `false` to choose explicitly. The built-in Azure Policy "Azure Managed Grafana workspaces should disable
public network access" audits, denies or modifies this setting: match it to avoid conflicts.
DESCRIPTION
}

variable "resource_types" {
  type = object({
    authorization_locks                               = optional(string, "Microsoft.Authorization/locks@2020-05-01")
    authorization_role_assignments                    = optional(string, "Microsoft.Authorization/roleAssignments@2022-04-01")
    dashboard_grafana                                 = optional(string, "Microsoft.Dashboard/grafana@2025-08-01")
    insights_diagnostic_settings                      = optional(string, "Microsoft.Insights/diagnosticSettings@2021-05-01-preview")
    network_private_endpoints                         = optional(string, "Microsoft.Network/privateEndpoints@2024-05-01")
    network_private_endpoints_private_dns_zone_groups = optional(string, "Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01")

    dashboard_grafana_managed_private_endpoints = optional(object({
      dashboard_grafana_managed_private_endpoints = optional(string)
    }), {})
  })
  default     = {}
  description = <<DESCRIPTION
Override the AzAPI `<provider>/<resource>@<api-version>` strings used by this module and its submodules. Each key defaults to a tested value; supply only the keys you want to override. Useful when targeting a sovereign cloud with older API versions, or when opting into a newer preview API.

- `authorization_locks` - Management locks applied to the workspace and its private endpoints.
- `authorization_role_assignments` - Role assignments on the workspace, on its private endpoints, and for its managed identity.
- `dashboard_grafana` - The Azure Managed Grafana workspace managed by this module.
- `insights_diagnostic_settings` - Diagnostic settings on the workspace.
- `network_private_endpoints` - Private endpoints to the workspace.
- `network_private_endpoints_private_dns_zone_groups` - Private DNS zone groups of the private endpoints.
- `dashboard_grafana_managed_private_endpoints` - Override slot for the `managed-private-endpoint` submodule. Defaults live in the submodule; supply only the keys you want to override.
  - `dashboard_grafana_managed_private_endpoints` - The managed private endpoint managed by the submodule.
DESCRIPTION
  nullable    = false
}

variable "retry" {
  type = object({
    error_message_regex  = optional(list(string))
    interval_seconds     = optional(number)
    max_interval_seconds = optional(number)
  })
  default     = null
  description = <<DESCRIPTION
Retry configuration applied to every `azapi` resource managed by the module (root resource and all submodules). Defaults to `null` (no custom retry).

- `error_message_regex`  - (Optional) A list of regex patterns matching error messages that trigger a retry.
- `interval_seconds`     - (Optional) Initial interval between retries in seconds.
- `max_interval_seconds` - (Optional) Maximum interval between retries in seconds.

See <https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource#retry> for full semantics.
DESCRIPTION
}

variable "role_assignments" {
  type = map(object({
    name                                   = optional(string, null)
    role_definition_id_or_name             = string
    principal_id                           = string
    description                            = optional(string, null)
    skip_service_principal_aad_check       = optional(bool, false)
    condition                              = optional(string, null)
    condition_version                      = optional(string, null)
    delegated_managed_identity_resource_id = optional(string, null)
    principal_type                         = optional(string, null)
  }))
  default     = {}
  description = <<DESCRIPTION
A map of role assignments to create on the Grafana workspace. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.

- `name` - (Optional) The name of the role assignment. If not set, a random UUID will be generated. Changing this forces the creation of a new resource.
- `role_definition_id_or_name` - The ID or name of the role definition to assign to the principal.
- `principal_id` - The ID of the principal to assign the role to.
- `description` - (Optional) The description of the role assignment.
- `skip_service_principal_aad_check` - (Optional) If set to true, skips the Azure Active Directory check for the service principal in the tenant. Defaults to false.
- `condition` - (Optional) The condition which will be used to scope the role assignment.
- `condition_version` - (Optional) The version of the condition syntax. Leave as `null` if you are not using a condition, if you are then valid values are '2.0'.
- `delegated_managed_identity_resource_id` - (Optional) The delegated Azure Resource Id which contains a Managed Identity. Changing this forces a new resource to be created. This field is only used in cross-tenant scenario.
- `principal_type` - (Optional) The type of the `principal_id`. Possible values are `User`, `Group` and `ServicePrincipal`. It is necessary to explicitly set this attribute when creating role assignments if the principal creating the assignment is constrained by ABAC rules that filters on the PrincipalType attribute.

> Note: only set `skip_service_principal_aad_check` to true if you are assigning a role to a service principal.
DESCRIPTION
  nullable    = false

  validation {
    condition = alltrue([
      for _, v in var.role_assignments :
      v.delegated_managed_identity_resource_id == null || can(provider::azapi::parse_resource_id("Microsoft.ManagedIdentity/userAssignedIdentities", v.delegated_managed_identity_resource_id))
    ])
    error_message = "Each `role_assignments[*].delegated_managed_identity_resource_id` must be a valid user-assigned managed identity resource ID, or null."
  }
}

variable "sku" {
  type        = string
  default     = "Standard"
  description = "The SKU of the Grafana workspace. Only `Standard` can be created; the `Essential` tier is deprecated and retires on 31 March 2027."
  nullable    = false

  validation {
    condition     = var.sku == "Standard"
    error_message = "Only the `Standard` SKU can be deployed. The `Essential` tier is deprecated."
  }
}

variable "sku_size" {
  type        = string
  default     = "X1"
  description = "The instance size of the Standard tier: `X1` (500 alert rules) or `X2` (more memory, 1,000 alert rules). Size can be increased but not decreased. Defaults to `X1`."
  nullable    = false

  validation {
    condition     = contains(["X1", "X2"], var.sku_size)
    error_message = "The SKU size must be `X1` or `X2`."
  }
}

variable "smtp_password" {
  type        = string
  default     = null
  description = "The SMTP password, required whenever `grafana_configurations.smtp.user` is set. Write-only: never stored in plan or state. Supply it on every apply: Azure rejects workspace updates whose SMTP settings lack it."
  sensitive   = true
  ephemeral   = true

  validation {
    condition     = (var.smtp_password != null) == (try(var.grafana_configurations.smtp.user, null) != null)
    error_message = "Set `smtp_password` exactly when `grafana_configurations.smtp.user` is set."
  }
}

variable "smtp_password_version" {
  type        = string
  default     = "1"
  description = "Change this value to push a rotated SMTP password without any other change. Only used when `grafana_configurations.smtp.user` is set."
  nullable    = false
}

variable "tags" {
  type        = map(string)
  default     = null
  description = "(Optional) Tags of the resource."
}

variable "timeouts" {
  type = object({
    create = optional(string)
    read   = optional(string)
    update = optional(string)
    delete = optional(string)
  })
  default     = null
  description = <<DESCRIPTION
Default per-operation timeouts applied to every `azapi` resource managed by the module. Defaults to `null` (provider defaults). Each value is a Go duration string (e.g. `30m`, `1h`).

- `create` - (Optional) Timeout for create operations.
- `read`   - (Optional) Timeout for read operations.
- `update` - (Optional) Timeout for update operations.
- `delete` - (Optional) Timeout for delete operations.
DESCRIPTION
}

variable "zone_redundancy_enabled" {
  type        = bool
  default     = false
  description = <<DESCRIPTION
Enable zone redundancy. Recommended for production in the regions that support it (see "Reliability in Azure Managed
Grafana" on Microsoft Learn); elsewhere the deployment fails. Incurs an additional cost. It can only be chosen when the
workspace is created: changing it replaces the workspace and everything stored in it. Defaults to `false`, so that the
module deploys in every region.
DESCRIPTION
  nullable    = false
}
