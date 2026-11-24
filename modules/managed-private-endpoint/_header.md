# Azure Managed Grafana managed private endpoint

Creates one managed private endpoint (`Microsoft.Dashboard/grafana/managedPrivateEndpoints`) on an existing Azure Managed Grafana workspace, so Grafana can reach a data source over Private Link — for example an Azure Monitor workspace (`prometheusMetrics`) or an Azure Data Explorer cluster.

The parent module instantiates this submodule once per entry of its `managed_private_endpoints` input; it can also be used on its own with the `parent_id` of an existing workspace.

After creation the connection is `Pending` until the owner of the target resource approves it (see the `connection_status` output). Every property is create-only, so changing any of them replaces the managed private endpoint.
