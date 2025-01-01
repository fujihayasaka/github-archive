# PII in Dependency Graph Exceptions
This document outlines, as of 2019-12-03, places in Failbot calls that Dependency Graph might include PII.
Below you'll find a section outlining what additional context we send through Failbot and what context containing PII we'd like to remove.

This effort is part of the switch from Haystack to Sentry and is an effort to satisfy the [migration requirement](https://github.com/github/sentry/blob/a1f8d33c7189019e8549faf7bd923d527fa2564e/docs/migration.md) to "Document and address any issues with sensitive data in exceptions."

## Currently
- `action` - Controller action, only reported from API calls.
- `app` - Hard-coded to `dependency-graph-api`
- `authors_hash` - String of authors from a public package, used in debugging why a string transformation failed. Since this value comes from a public source it isn't sensitive.
- `controller` - Current controller, only reported from API calls.
- `current_user` - The user who was authenticated with GitHub when making the request, only reported from API calls. This is not considered PII.
- `dbconn` - Current DB connection string
- `decode_failure` - Hard-coded boolean: true
- `filename` - Although this *is* a user filename, the file won't get sent to Dependency Graph unless it passes a [Regular Expression in GitHub](https://github.com/github/github/blob/609a9a9cf2028a9a712ffcd4ee5312411b78d0ba/app/models/dependency_manifest_file.rb#L8-L40). This is regularly used for debugging, specifically for Python-based files. I think this is high value and low risk, so it should be kept in Sentry if possible.
- `from` - Combination of class and request_method (controller & action), only reported from API calls.
- `github_repository_id` - PII, but a DB ID so it's OK.
- `graphql_query` - Hard-coded to `:parsed_manifest` for debugging queries.
- `job` - Hard-coded string referring to which portion of the processing pipeline reported the error.
- `json_object` - Raw JSON that couldn't be parsed during Composer/Nuget package ingest. Source JSON is from a public source and therefore isn't sensitive.
- `message` - Human-readable error message that uses string interpolation to present:
    - **HTTP response code** from failed HTTP request during package ingest.
    - **HTTP response message** from failed HTTP request during package ingest.
    - **Package name** that caused the failed message during ingest. This name is from a public source and therefore isn't sensitive.
- `org_id` - GitHub Org ID, used for debugging why a Dependency Insights rebuild failed. This is semi-PII, but used for debugging and a DB ID so I think we're safe to keep it.
- `package_name` - Name of a package that failed while being parsed/ingested. These packages are publicly available, so this shouldn't be considered PII.
- `path` - Lower-value PII that should be removed.
- `repo_is_public` - X-GitHub-Is-Public, only reported from API calls.
- `repository_nwo` - PII that should be removed.
- `request_id` - X-GitHub-Request-Id, only reported from API calls.
- `request_method` - HTTP method used to make the request, only reported from API calls.
- `request_url` - Request URL passed from GitHub requests. This is considered sensitive information and will be removed.
- `response_body` - Response body from ClearlyDefined, used for debugging why license ingest failed. Publicly available data, shouldn't be considered sensitive.
- `response_code` - HTTP response code from ClearlyDefined, used for debugging why license ingest failed. Publicly available data, shouldn't be considered sensitive.
- `response` - Response from our internal SinkProxy. Used for debugging why a flush failed.
- `session_id` - X-GitHub-Session-Id, only reported from API calls.
- `standard_error` - Hard-coded boolean: true
- `user_agent` - Request UserAgent, only reported from API calls.

### MySQL Errors
According to the migration documentation, one common from of PII leaking is through MySQL exceptions being logged containing the *full* statement.
I was able to track down instances of this happening in the past in our Haystack bucket, however a [new Rails 6.0 feature fixed this][rails6-sql].

I searched Haystack for more recent cases of `Trilogy::MysqlError` being reported and was able to confirm that the raw SQL statement is no longer being output in the message.
I didn't observe any traces of the full SQL statement in the more recent needles.


## Remediation
- Remove all instances of `path`
- Remove all instances of `repository_nwo`
- Remove instance of `request_url`

[rails6-sql]: https://github.com/rails/rails/pull/34468
