## HEAD

## v3.0.0

* BREAKING: Remove support for the `ops_slack` field -https://github.com/github/cat/pull/6959
* You can now query latest, unmet `scorecard_summaries` grouped by service - https://github.com/github/cat/pull/6609
* Services can now be filtered by repo owner and host - https://github.com/github/cat/pull/6541
* Services now include a `tier` and `source_checksum` fields - https://github.com/github/cat/pull/6438
* Add ability to query for Services by Group - https://github.com/github/cat/pull/6367
* BREAKING: Remove Support for Heroku service kinds - https://github.com/github/cat/pull/6338
* Action Items now have linked requirements - https://github.com/github/cat/pull/6290
* Add `alert_issue` and `alert_slack` for SupportLevels - https://github.com/github/cat/pull/5572

## v2.3.2

* Fix a missing `require "stringio"` in `client.rb`

## v2.3.1

* Update dependencies (graphql, activesupport).
  * Unpin ActiveSupport, this gem can now be used in Rails 7 projects as it's no longer pinned to v6.

## v2.3.0

* BREAKING: Replace `references.totalCount` with `actionItems.totalCount` when submitting scorecard scores.
* Move toward deprecating `references` by adding the `actionItems` parameter when submitting scorecard scores.

## v2.2.0

* BREAKING: Replace `client.scorecards.trend_report.referenceCount` attribute with `client.scorecards.trend_report.actionItemCount` in default fragment

## v2.1.0

* BREAKING: Remove `client.services.search` method

## v2.0.1

* Pin `activesupport` runtime dependency gem version to the latest 6.1.4.

## v2.0.0

* BREAKING: Remove `default_service_filter` as a field on Scorecard.
* BREAKING: The `mention` field has been removed from the ownership schema.
* Add support for decoding gzipped responses
    * Response stubs in tests must now return `Content-Type: application/json` to be parsed as JSON

## v1.1.0

* Add client gem release workflows and publish to GitHub Packages

## v1.0.0

* BREAKING: All `client.scorecard_subscriptions.*` calls have been
    renamed to `client.subscriptions.*`
* BREAKING: The `volunteers` field has removed from the ownership schema.
* Add `client.scorecard_subscriptions.delete`
* Add `client.services.validate_service_for_deployment`
* Add ability to empty groups with `client.groups.update` and passing an
    empty array for `groups` or `services`
* Make `Net::HTTP#write_timeout=` call optional to support older rubies
* Added `tracer:` option to `Client.new`. Must respond to `in_span(name, attributes:)`.

## v0.13.0

* Add ability to filter by `kind` and `active` on `client.owners.list`
* Add `client.scorecard_subscriptions.list`
* Add `client.scorecard_subscriptions.update`
* Fix: require 'json' so that `JSON` can be used

## v0.12.0

* BREAKING: `client.scorecards.list_scored_services` now accepts `service_detail_fragment` instead of `detail_fragment`
    Also, it will now actually function properly.
* BREAKING: `client.scorecards.update` now accepts a `scorecard` input object.
* Add ability to update scorecard maintainership and Aqueduct queue information to `client.scorecards.update`.
* Add `client.scorecard_jobs.create`
* Add `client.scorecard_jobs.update`
* Add `client.scorecard_jobs.update_scorecard_evaluation`
* Add `client.scorecard_jobs.update_scorecard_evaluation`
* Add `client.scorecard_jobs.batch_update_scorecard_evaluations`

## v0.11.0

* Add `service_name:` argument to `client.slos.list`

## v0.10.0

* Change `client.scorecards.list_scored_services` to send an empty query to skip the `default_service_filter` on the scorecard by default
* Update `client.services.support_levels` to follow the new code pattern and accept a `detail_fragment` argument
* Add `client.task_locks.release` to release a task lock

## v0.9.2 / 2020-10-15

* Drop deprecated `passing_percentage` argument from `client.scorecards.trend_report`

## v0.9.1 / 2020-10-05

* Add `references` as argument to `client.scorecards.update_score` and `client.scorecards.batch_update_scores`.
* Update `client.scorecards.update_score` to accept `detail_fragment` for custom response

## v0.9.0 / 2020-10-01

* Add `client.scorecards.list_scored_services` to list services associated with a scorecard.

## v0.8.0 / 2020-09-15

* Add `client.scorecards.trend_report` to generate a trend report.

## v0.7.0 / 2020-09-02

* `client.services.list` - convert some deprecated parameters to use the ServiceFilterSelectionInput argument

## v0.6.1 / 2020-07-19

* Fix bug in `client.scorecards.batch_update_scores` where the scores were zeroed-out.

## v0.6.0 / 2020-07-17

* Add `ServiceLinkDetail` fragment customization for `client.services.links`
* Add `client.scorecards.batch_update_scores`
* Add Service Filter methods:
    - `client.users.service_filters`
    - `client.users.delete_service_filter`
    - `client.users.create_service_filter`

## v0.5.0 / 2020-05-27

* Add `playbook_url` argument to `client.slos.update`
* Add Scorecard Find query (#1547)
    - `client.scorecards.find`
* Use `pageInfo` in service search query instead of `totalCount` (#1717)

## v0.4.0 / 2020-04-13

* Add Owner mutations to client (#1480)
    - `client.owners.list`
    - `client.owners.update`
* Add Service Link mutations to client (#1460)
    - `client.services.delete_link`
    - `client.services.update_link`

## v0.3.0 / 2020-04-03

* Add Service Search to client #1444
    - `client.services.search`
* Add supportLevel list/update/remove APIs to client (#1280)
    - `client.services.support_level`
    - `client.services.update_support_level`
    - `client.services.remove_support_level`
* Add updateService / deleteService to client (#1354)
    - `client.services.update_service`
    - `client.services.delete_service`
* Add SLO & SLO Summary APIs (#1385)
    - `client.slos.list`
    - `client.slos.update`
    - `client.slos.delete`
    - `client.slos.update_slo_summary`
    - `client.slos.delete_slo_summary`

## v0.2.0

* Add Groups-related methods:
    - `client.groups.list`
    - `client.groups.find`
    - `client.groups.delete`
    - `client.groups.update`

## v0.1.0

* Initial import.
- Services methods:
    - `client.services.list`
    - `client.services.find`
    - `client.services.dependencies`
    - `client.services.links`
    - `client.services.add_service_dependency`
    - `client.services.remove_service_dependency`
- TaskLocks methods:
    - `client.task_locks.acquire`
- Scorecards methods:
    - `client.scorecards.summaries`
    - `client.scorecards.update_score`
