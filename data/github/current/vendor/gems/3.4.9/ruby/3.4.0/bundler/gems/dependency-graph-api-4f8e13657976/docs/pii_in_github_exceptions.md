# PII in `github-dependency-graph` Exceptions
This document outlines, as of 2020-01-07, the data passed to Failbot calls within `github/github` that report to the `github-dependency-graph` Haystack bucket.
Below you'll find a section outlining what additional context we send through Failbot and what context containing PII we'd like to remove.

This effort is part of the switch from Haystack to Sentry and is an effort to satisfy the [migration requirement](https://github.com/github/sentry/blob/a1f8d33c7189019e8549faf7bd923d527fa2564e/docs/migration.md) to "Document and address any issues with sensitive data in exceptions."

## Currently
### Context Args
These arguments were gathered from looking at existing needles in the [github-dependency-graph](https://haystack.githubapp.com/github-dependency-graph) bucket.
They're likely being pushed via the Resque context:


- `accept` - Media type being requested, standard in GitHub exceptions.
- `action` - Rails controller and action OR action, standard in GitHub exceptions.
- `areas_of_responsibility` - Array of AoRs for the code, standard in all GitHub exceptions.
- `args` - Appears to be a Hash of arguments being passed into the Resque job. Since this is unstructured it seems likely that it _could_ contain PII, so we should consider removing it.
- `cause` - What caused the exception.
- `class_name` - Class name of the exception.
- `connections` - Hash of DB connections, standard in all GitHub exceptions.
- `controller` - Name of the controller, standard in GitHub exceptions.
- `current_ref` - The deployed branch, standard in all GitHub exceptions.
- `datacenter` - The data center where the exception was raised, standard in all GitHub exceptions.
- `deployed_to` - The environment the app is deployed to (garage, lab, production, prod/canary).
- `enabled_features` - Array of feature flags the user has enabled, standard in GitHub exceptions.
- `granted_oauth_scopes`
- `graphql_query` - The GraphQL query being run to populate the page, standard in GitHub exceptions.
- `graphql_schema_target` - The targeted query context. (`:public` / `:internal`)
- `graphql_variables` - Variables passed to the `graphql_query` - Seems likely to contain PII, should probably be removed.
- `integration`
- `job` - Resque job that raised the exception
- `kube_cluster` - Kubernetes cluster the pod is running in, standard in GitHub exceptions.
- `kube_pod_ip` 
- `kube_pod_name`
- `language` - HTTP header specifying accepted language. Seems like PII, standard in GitHub exceptions.
- `master_pid`
- `master_started_at`
- `method` - HTTP method for the request, standard in GitHub exceptions.
- `oauth_access_id`
- `oauth_app`
- `origin`
- `params` - Request parameters, could definitely contain PII! Standard in GitHub exceptions.
- `priavte_repo` - If the target repo is private
- `queue_time` - How long the item was queued.
- `queue` - Name of the Resque queue.
- `queued_from`
- `rails` - The version of Rails that's running, standard in all GitHub exceptions.
- `region` - The region the code ran in, standard in all GitHub exceptions.
- `repo` - Target repository - PII and should be removed
- `request_category`
- `request_id` - Global request ID, standard in all GitHub exceptions.
- `requested_at`
- `requst_wait_time`
- `route`
- `ruby` - The version of Ruby that's running, standard in all GitHub exceptions.
- `server_id`
- `server` - The actual host that raised the exception, standard in all GitHub exceptions.
- `session` - Totes PII, shouldn't be there
- `sha`
- `site` - The site that the server that raised the exception lives in, standard in all GitHub exceptions.
- `stateless`
- `tested_features`
- `url` - URL of the request. PII, should be removed, standard in GitHub exceptions.
- `user_agent` - User's browser user agent. PII, should be removed, standard in GitHub exceptions.
- `user_session_id`
- `user_spammy`
- `user` - User making the request. PII, should be removed, standard in GitHub exceptions.
- `viewer` - Same as user? PII, should be removed, standard in GitHub exceptions.
- `worker_request_count`
- `worker_started_at`
- `worker` - Combination of the server running and a list of the queues it's processing.
- `zone` - Time zone of the user? Probably PII, should be removed, standard in GitHub exceptions.
### Additional Args
We explicitly send these arguments in `Failbot.report` calls:

- `dependency_insights` - If the context of the failure happens in the Dependency Insights feature. Boolean, hard-coded to `true`.
- `owner_ids` - Array of Org DB IDs which are being queried.
- `push_id` - DB ID of a Push record.
- `repo_id` / `repository_id` - DB ID of a Repository which is being queried.
- `repository` - DB ID of a Repository which is being alerted against. Present in the `RepositoryVulnerabilityAlerter`
- `vulnerability_alerting` - If the context of the failure happens while running vulnerability alerting.
- `vulnerable_version_range_alerting_process` - DB ID of a VulnerableVersionRangeAlertingProcess record.


## References
List of the Haystack needles I looked at while developing this list:
- https://haystack.githubapp.com/github-dependency-graph/needles/ZzaIl8iDdk41N64jLfQ1iw#attr-action
- https://haystack.githubapp.com/github-dependency-graph/needles/kJYf-PkDmlP2py4PcJ6AwQ
