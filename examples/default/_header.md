# Default example

This deploys an Azure Managed Grafana workspace with the module's defaults only (Standard X1, Grafana 12, no identity, public network access) into a new resource group in a randomly selected region where the service is available.

Grafana needs an identity to query Azure data sources: see the `complete` and `user_assigned_identity` examples.
