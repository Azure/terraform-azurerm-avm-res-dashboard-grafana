# Azure Managed Grafana

AVM Resource Module for Azure Managed Grafana (`Microsoft.Dashboard/grafana`).

It deploys a Standard tier workspace with AzAPI and supports:

- instance size, Grafana major version, zone redundancy, deterministic outbound IPs, public network access, API keys / service accounts, plugins and Grafana server settings (SMTP, snapshots, user permissions, CSRF, alert screenshots);
- linking Azure Monitor workspaces (managed Prometheus) to the workspace;
- managed private endpoints from Grafana to data sources (`managed_private_endpoints`, implemented by the `modules/managed-private-endpoint` submodule);
- the standard AVM interfaces: role assignments, lock, diagnostic settings, managed identities, private endpoints and tags.

The module only manages the Grafana workspace and resources scoped to it. It never creates anything in the scope of another service.

## Data source access

Grafana's identity needs roles on the services it reads, for example `Monitoring Data Reader` on Azure Monitor workspaces (managed Prometheus) and `Monitoring Reader` on the resources or resource groups whose metrics and logs it visualises. Linking an Azure Monitor workspace with `azure_monitor_workspace_integrations` does not grant that access.

Those roles are granted by the modules that own the data sources, through their own `role_assignments` input, using this module's `system_assigned_mi_principal_id` output:

```hcl
module "postgresql" {
  source  = "Azure/avm-res-dbforpostgresql-flexibleserver/azurerm"
  version = "<pinned version>"
  # ...
  role_assignments = {
    grafana = {
      role_definition_id_or_name = "Monitoring Reader"
      principal_id               = module.grafana.system_assigned_mi_principal_id
      principal_type             = "ServicePrincipal"
    }
  }
}
```

When private DNS zones are managed centrally (for example by Azure Policy), set `private_endpoints_manage_dns_zone_group = false` so the module does not create private DNS zone groups for its private endpoints.

## Production choices

These inputs are left to each deployment because the right value depends on the environment:

- **Network access.** `public_network_access_enabled` defaults to `null`: public access is disabled as soon as `private_endpoints` is not empty, and enabled otherwise so that a workspace without private endpoints stays reachable. Set it explicitly to choose, and match the built-in Azure Policy "Azure Managed Grafana workspaces should disable public network access" if it is assigned.
- **Zone redundancy.** Recommended for production where available, but it is offered in a few regions only, costs extra and can only be chosen at creation. `zone_redundancy_enabled` therefore defaults to `false`, so that the module deploys in every region; this deviates from AVM spec SFR5 on purpose. Decide before the first apply: changing it later replaces the workspace and everything stored in it.
- **Lock.** Use `lock = { kind = "CanNotDelete" }` in production. A `ReadOnly` lock also blocks updates and the managed private endpoint refresh.
- **External snapshots** are disabled by default (`grafana_configurations.snapshots_external_enabled = false`), as the security guidance recommends; the service default is enabled.
- **Grafana version.** Major upgrades can't be undone, and Microsoft upgrades workspaces itself when a version retires. After that, raise `grafana_major_version` to match the `grafana_version` output, or add `properties.grafanaMajorVersion` to `ignore_body_changes.dashboard_grafana`. `security_csrf_always_check` and `users_editors_can_admin` only exist up to Grafana 11; the module rejects them for Grafana 12 and later.

## Backup and disaster recovery

Azure Managed Grafana has no backup, restore or cross-region failover of dashboards, folders, alert rules or data sources. Keep them as code (for example with the `grafana/grafana` Terraform provider) so that they can be redeployed, and for a regional outage deploy a second workspace in another region. A `CanNotDelete` lock protects the workspace against accidental deletion.

## Usage notes

- **Identity.** No identity is configured by default. Set `managed_identities = { system_assigned = true }` (or a single user-assigned identity) so Grafana can query Azure data sources. The service accepts exactly one identity.
- **Access to Grafana** is controlled with Azure RBAC through `role_assignments`, using the built-in `Grafana Admin`, `Grafana Editor`, `Grafana Viewer` and `Grafana Limited Viewer` roles. Automation (for example the `grafana/grafana` Terraform provider) can authenticate with a Microsoft Entra token for the audience `https://dashboard.azure.com`, so `api_key_enabled` can stay `false`.
- **Diagnostic settings.** Azure Managed Grafana exports three log categories (`GrafanaLoginEvents`, `GrafanaUsageInsightsEvents`, `GrafanaAlertAuthFailure`; category groups `allLogs` and `audit`) and `AllMetrics`. Azure returns the categories that are not selected as disabled entries, so the module sends them too, which keeps plans clean. That catalog is fixed in `locals.tf`: if Azure adds a category, plans show a diff until the module lists it. `log_analytics_destination_type` is accepted by the standard interface but is not sent, because the service does not support it. A setting without `name` is named `diag-<workspace name>`.
- **Private endpoints.** Unless set, names default per map key: `pep-<workspace>-<key>` for the endpoint, `nic-<endpoint name>` for its network interface and `pse-<workspace>-<key>` for the connection. Endpoints inherit `tags` and the workspace `lock` unless they set their own; `lock = { kind = "None" }` leaves an endpoint unlocked.
- **Role assignments** are replaced when their principal or role changes, because Azure does not allow updating an existing assignment.
- **Create-only settings.** Changing `zone_redundancy_enabled` replaces the workspace and everything stored in it; zone redundancy is only available in some regions (see *Reliability in Azure Managed Grafana* on Microsoft Learn). Every property of a managed private endpoint is create-only too. `sku_size` can be increased from `X1` to `X2` but not decreased.
- **Plugins.** `grafana_plugins` is applied as additions: removing a plugin from the set may not uninstall it.
- **Managed private endpoints** remain `Pending` until the connection is approved on the target resource, by whoever owns it. Grafana only uses an approved endpoint after the workspace is refreshed: the module refreshes it when endpoints are added or removed, and again whenever `managed_private_endpoints_refresh_trigger` changes, so change it after each approval. The `managed-private-endpoint` submodule has no role assignment or lock inputs: role assignments on a managed private endpoint grant nothing useful, and it inherits the workspace lock.
- **SMTP.** Azure does not support enabling SMTP while the workspace is being created: add `grafana_configurations.smtp` in a later apply. The password (`smtp_password`) is ephemeral and write-only, so it is never stored in plan or state. Azure rejects any update of the workspace whose SMTP settings lack the password, so the module sends it with every update: supply it on every apply, for example from Key Vault. After rotating it, change `smtp_password_version` to push the new value without any other change.
- **SKU.** Only `Standard` can be deployed; the `Essential` tier is deprecated and retires on 31 March 2027.
- **Terraform 1.11** or later is required, because of the ephemeral, write-only SMTP password.
