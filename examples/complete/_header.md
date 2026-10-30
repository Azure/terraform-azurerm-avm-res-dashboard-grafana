# Complete example

This deploys an Azure Managed Grafana workspace with the module's main features:

- zone redundancy (in a region that supports it for Managed Grafana) and public network access disabled, reachable through a private endpoint registered in the `privatelink.grafana.azure.com` private DNS zone;
- a role assignment on the private endpoint (`Reader` for the identity running the deployment);
- a `CanNotDelete` lock, which the private endpoint inherits;
- a system-assigned identity;
- a linked Azure Monitor workspace (managed Prometheus), reached through a Grafana managed private endpoint (`prometheusMetrics`);
- login and usage logs sent to a Log Analytics workspace;
- `Grafana Admin` for the identity running the deployment.

The module does not grant Grafana access to its data sources. The example grants `Monitoring Data Reader` on the Azure Monitor workspace with a separate role assignment, outside the module, using the module's `system_assigned_mi_principal_id` output — the same pattern applies to the `role_assignments` input of the module that manages a data source.

The managed private endpoint stays `Pending` until the connection is approved on the Azure Monitor workspace. The module refreshes the workspace when the endpoint is created; after the approval, change `managed_private_endpoints_refresh_trigger` to refresh it again so that Grafana uses the endpoint.

In production, assign `Grafana Viewer`, `Grafana Editor` and `Grafana Limited Viewer` to Microsoft Entra groups rather than to individual identities.
