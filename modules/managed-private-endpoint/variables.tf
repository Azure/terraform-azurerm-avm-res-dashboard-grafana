variable "group_ids" {
  type        = list(string)
  description = "The private link sub-resources to connect to, e.g. `[\"prometheusMetrics\"]` for an Azure Monitor workspace."
  nullable    = false

  validation {
    condition     = length(var.group_ids) > 0
    error_message = "At least one group ID is required."
  }
}

variable "location" {
  type        = string
  description = "The Azure region of the parent Grafana workspace."
  nullable    = false
}

variable "name" {
  type        = string
  description = "The name of the managed private endpoint."
  nullable    = false
}

variable "parent_id" {
  type        = string
  description = "The fully-qualified ARM resource ID of the existing Azure Managed Grafana workspace that owns the managed private endpoint."
  nullable    = false

  validation {
    condition     = can(provider::azapi::parse_resource_id("Microsoft.Dashboard/grafana", var.parent_id))
    error_message = "`parent_id` must be a valid Azure Managed Grafana (Microsoft.Dashboard/grafana) resource ID."
  }
}

variable "private_link_resource_id" {
  type        = string
  description = "The resource ID of the target resource, e.g. an Azure Monitor workspace or an Azure Data Explorer cluster. Any Private Link-enabled resource type is accepted, so the value is not validated against a single type."
  nullable    = false
}

variable "ignore_body_changes" {
  type = object({
    dashboard_grafana_managed_private_endpoints = optional(list(string), [])
  })
  default     = {}
  description = <<DESCRIPTION
Paths in each resource's `body` whose changes the AzAPI provider ignores. Prefer Terraform's `lifecycle.ignore_changes` when the paths are static; use this variable when the paths must be derived from variables or other non-static values.

Paths use dot notation, for example `properties.requestMessage`. Individual list items cannot be targeted — ignore the whole list property instead. Configuration changes at an ignored path are **not** sent to Azure until that path is removed from the list.

Supplying a non-empty value requires Terraform 1.11 or later, because `ignore_body_changes` is a write-only argument. Changes take effect only after an apply, because the value is held in provider-private state.

- `dashboard_grafana_managed_private_endpoints` - Ignored body paths for the managed private endpoint managed by this module.
DESCRIPTION
  nullable    = false
}

variable "private_link_resource_region" {
  type        = string
  default     = null
  description = "(Optional) The region of the target resource."
}

variable "private_link_service_url" {
  type        = string
  default     = null
  description = "(Optional) The URL of the data store behind the Private Link service, as used in the Grafana data source, without protocol and port."
}

variable "request_message" {
  type        = string
  default     = null
  description = "(Optional) A message shown to the approver of the connection request."
}

variable "resource_types" {
  type = object({
    dashboard_grafana_managed_private_endpoints = optional(string, "Microsoft.Dashboard/grafana/managedPrivateEndpoints@2025-08-01")
  })
  default     = {}
  description = <<DESCRIPTION
Override the AzAPI `<provider>/<resource>@<api-version>` strings used by this module. Each key defaults to a tested value; supply only the keys you want to override. Useful when targeting a sovereign cloud with older API versions, or when opting into a newer preview API.

- `dashboard_grafana_managed_private_endpoints` - The managed private endpoint managed by this module.
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
