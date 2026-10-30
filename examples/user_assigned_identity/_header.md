# User-assigned identity example

This deploys an Azure Managed Grafana workspace that queries Azure data sources with a user-assigned managed identity instead of a system-assigned one.

Azure Managed Grafana accepts a single identity. A user-assigned identity outlives the workspace, so its access to data sources can be granted once, before the workspace exists, and kept when the workspace is recreated. Grant it roles on the data sources (for example `Monitoring Reader`) through the modules that own them, using the identity's principal ID.
