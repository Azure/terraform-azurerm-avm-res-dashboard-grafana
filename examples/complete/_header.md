# Complete

This example deploys:

- A sample virtual network and subnet for Private Endpoints.
- A network-isolated Azure Managed Grafana instance with Private Endpoint.
- Two sample Azure Monitor Workspaces using Private Endpoints.
- A log analytics workspace with Azure Monitor Private Link Scope and associated private endpoint, ingesting Grafana diagnostics.
- Managed Private Endpoints for Grafana access to deployed monitoring resources.
- An Azure AD group and role assignment granting read access to Grafana.
- Role assignments granting Grafana access to private monitoring resources.
