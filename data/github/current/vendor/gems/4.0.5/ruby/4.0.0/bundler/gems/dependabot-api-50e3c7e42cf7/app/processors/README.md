## Hydro Processors

We have two main categories of information we ingest from Hydro:

1. Events we would historically receive via Webhooks as a third-party application.
1. Requests for UpdateJobs to be performed for a specific vulnerability on a Repository that is specific to the Automated Security Fixes feature.

### Webhooks over Hydro

This is a work-in-progress category for us, at present we only consume Repository Push events via Hydro in lieu of GitHub.

We have implemented this event stream ourselves, but have not repeated this process for [our main hooks](https://github.com/github/dependabot-api/issues/424) yet as ecosystems have put forward an [Architecture Decision Record on delivering existing Webhook schemas over Hydro for internal applications](https://github.com/github/ecosystem-events/pull/307).

Our intent is to make use of the general interface this team implements instead of adding many missing event streams in Hydro.

### Requests for Updates Jobs

The Deltaforce API ingests messages from GitHub requesting an `UpdateJob` is created for a specific `RepositoryVulnerabilityAlert`.

These requests are materialised in the GitHub database as a `RepositoryDependencyUpdate`, which is used to track the overall status of the process as pending, complete or errored.

#### How many topics do we ingest?

We ingest from two topics:

- `github.v1.RepositoryVulnerabilityAlertCreate`
    This topic contains messages created when GitHub publishes a new Vulnerability. These messages go to the back of the queue in terms of PR creation.

    We also use this queue for `dry_run` messages used in testing. These go through Dependabot normally up to the point of creating a PR, which is prevented.

- `github.v1.RepositoryVulnerabilityAlertResolveRequest`
    This topic contains messages created when a User clicks a button on their Security > Alert UI to request a fix for an existing vulnerability. These messages go to the front of the queue in terms of PR creation.

Messages from either topic are structurally the same apart from which `trigger_types` they support. This is a producer validation to avoid messages entering the incorrect topic for prioritisation.

#### What is in a message?

At a high level, a single message contains:

- The `RepositoryDependencyUpdate` id, referred to as the `github_request_id` in Dependabot
- The `RepositoryVulnerabilityAlert`, which provides the repository, manifest file and package name involved
- The `SecurityAdvisory`, which provides the overall description and identifiers of the security issue (e.g. GHSA, CVE)
- The `SecurityVulnerability`, which provides the specific package version the repo is vulnerable to
- The trigger that created this request, e.g. a manual button press, GitHub scanning for vulnerable repos, a vulnerable push to a repo, etc.

This message is created `after_commit` on a `RepositoryDependencyUpdate` in GitHub.

We create `RepositoryDependencyUpdate` objects for each `RepositoryVulnerabilityAlert` generated when we publish a new Vulnerability.

A user can also create one from the Security > Alerts screen in their Repository. In this scenario, we select the `RepositoryVulnerabilityAlert` with the highest fixed version for the package the UI shows and submit it as a 'candidate' that is likely to resolve all CVEs affecting it.

#### Do the messages contain User Generated Content?

Yes, indirectly.

The description of a SecurityAdvisory is User Generated Content that has been through our Advisory DB review process. This includes content from our Maintainer Security Advisory feature, which supports GitHub Markdown, including emoji.

#### Can we ingest messages multiple times?

No, we can only ingest a `github_request_id` into the Dependabot job queue once. Duplicates are only anticipated if a consumer fails to mark a message read after ingestion due to a killed process or interrupt due to deployment.

We write a `github_request_id` into the database as the very last step of ingestion, so if it exists, we are fully done with the message and it is enqueued to be processed into a PR.

#### Can we attempt to fix a specific RepositoryVulnerabilityAlert more than once?

Yes, we just need to request it via a new `RepositoryDependencyUpdate` job. This allows users to retry when an attempt errors while maintaining tracability between GitHub and Dependabot on each attempt.

#### What happens when a message can't be ingested?

It is discarded. We notice the exception in Failbot, mark the message as read and move on.

These are tracked in our dashboard [here](https://app.datadoghq.com/dashboard/mht-jzj-8jz/dependabot?from_ts=1558540233246&to_ts=1558543833246&live=true&tile_size=m&fullscreen_widget=8083756489318718), using the metric `dependabot_api.consumer.dead_letter`.

#### What would prevent us ingesting a message?

- If the message was malformed in some way by GitHub, indicative of a software defect.
- If the message tried to write invalid content to Dependabot, indicative of a bad data.
- A service fault like database connection loss or failure.

Mitigations:

- These cases will require debugging or disaster recovery before replaying the Kafka log for the affected time period.
- For single erroneous cases, manually requested jobs fail over into an errored state after 40 minutes. At this point, a User may retry assuming the underlying defect has been resolved.
- We can re-trigger a request for any alert from the console if we are under duress for a fix.

##### Retriggering a request

since the `RepositoryDependencyUpdate#id` / `github_request_id` has not been ingested, we can recover from a dead letter by just emitting it to Hydro again.

This can be done from a `gh-console` as follows:

```
repository = dat("rails/rails")
updates = repository.dependency_updates.visible.requested.for(path: "Gemfile", package: "rack")
updates.last.enqueue_vulnerability_update_in_hydro
```

- The `visible` scope excludes any 'dry run' records we created while load testing the feature.
- The `requested` scope limits to any records that have not been completed or errored
- The `last` record will be the most recent and therefore 'blocking' if the Alert UI is stuck in a "processing" state

#### Where can I monitor ingestion?

It is monitored as part of the [Dependabot dashboard](https://app.datadoghq.com/dashboard/mht-jzj-8jz/dependabot) (DataDog login required)
