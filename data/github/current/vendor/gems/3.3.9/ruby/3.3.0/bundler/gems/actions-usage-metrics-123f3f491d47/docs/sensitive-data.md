# Sensitive Data in Actions Usage Metrics

This document catalogs the service's usage of private or otherwise restricted data. Repository names, URLs, and any repository internal details such as file paths are considered restricted. There is a list [here](https://thehub.github.com/epd/engineering/dev-practicals/observability/exception-tracking/secure-exceptions/#examples-of-restricted-user-repository-and-infrastructure-data).

1. Repository Info - Instead of repository names, we use repository IDs
1. Workflow File Paths
   - The item IDs for workflow projections calculate a SHA256 hash of the path. This will allow us to correlate from a workflow event or query to the related projections, and still be able to write the item IDs to logs and other telemetry.
   - The full model still contains the workflow file path. Therefore we must be careful that this data does not appear in the logs in text form.