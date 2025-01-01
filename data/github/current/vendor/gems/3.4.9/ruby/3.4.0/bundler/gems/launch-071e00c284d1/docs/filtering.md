# Filtering

Users can configure which events a workflow is triggered by, and further subset events on a number of fields.

The filters are processed by this codebase.

For a workflow to run, a logical AND of the following must be true:

- event is present in workflow's `on:` block
- event's `types:` filter matches (`action` field in webhook)
    - some events - importantly `pull_request` - have a default subset of types
- for `push` and `pull_request`
    - `branches:`/`tags:` filter matches (or their mutually exclusive `-ignore` equivalents)
        - ref type filter: if only one of `tags` or `branches` present in `on:` then the other type is never run
        - then run globs vs ref name affected
    - `paths:` filter matches any modified path (or affects any non-ignored path)

Filtered workflows do not create a CheckSuite. To identify why a workflow was not run you can search for `Body="workflow filtered out"` in Splunk,
which contain the `workflow_file_path` and `filter_type` fields.

## Glob timeouts

As we allow users to author globs, which can contain multiple `**` (equivalent to `.*`), we enforce timeouts for both individual globs, and
the entirely globbing operation. This prevents pathological globs like `a**a**a**a**a**a**...` (equivalent to) `a.*a.*...` DOSing us.

## ADRs

- https://github.com/github/pe-actions-experience/blob/adr-path-filter/doc/adr/0021-filtering-v2.md

