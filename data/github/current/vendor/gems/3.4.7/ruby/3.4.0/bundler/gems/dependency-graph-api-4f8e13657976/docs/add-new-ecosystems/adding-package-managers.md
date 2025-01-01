# Adding support for a new Package Manager Adapter (PMA)
As described in the [overview document](./overview.md), an ecosystem's package manager adapter is the primary process by which package release metadata is ingested into the Dependency Graph. This data is used to add rich context to project dependency data captured by Manifest Adapters and the new Dependency Submission API, including:
- All of the package's released versions, including release and last-updated timestamps
- Date of a package release's removal or revokation from it's parent registry, if applicable
- URL of a package's source code repository
- URL of a package's documentation
- Software licenses associated with a package
- Transitive dependency declarations, version range specs, and build-scopes associated with a package
- Package author and contact info, homepage URL etc.
- Detailed package description

_Note:_ each ecosystem and package registry supports it's own subset of this metadata; not all properties listed above are populated for every ecosystem or available from the ecosystem's authoritative data sources.

### Caveats, Dependencies, Code Debt
The current PMA codebase, data model, and dev experience carries some known limitations and quirks you'll want to keep in mind as you implement the PMA for your new ecosystem:
- Code _cannot be shared between PMAs, or the DG-API Rails App!_
    - _Code duplication or cargo-culting_ is common in PMAs, when shared functionality or feature parity with DG-API is required
    - PMAs declare and manage their own dependencies, sometimes including non-Ruby components
- A PMA's only critical dependencies on the DG-API codebase are:
    - Shared [production Docker image](https://github.com/github/dependency-graph-api/blob/master/Dockerfile#L170-L268) includes all PMA code
    - The PMA's Moda/k8s [deploy config](https://github.com/github/dependency-graph-api/tree/master/config/kubernetes/workers/cronjobs) for each latest-updates cronjob
- Each PMA specs out an individual Docker image for test purposes, and copies it's production code and deps into a shared production image
- The "top-level" PMA contract (`wrapper` -> `Rakefile`) as generated for new ecosystems is often customized across individual PMAs; feature parity is rare
- The methods used to backfill PMA datasets and ingest period updates of new releases vary widely across ecosystems, and often are limited by the data sources available when the ecosystem was implemented
- PMAs _do not ship to Enterprise environments_, unlike the manifest ingest pipeline and the DG-API service
- For Actions, our "package manager adapter" is the one oddball of the group. We don't have a separate image and k8s deploy like the other ecosystems. This is because at this time, there is no API that we can ingest new releases and their metadata from. Instead, we pull in novel package releases from manifests during ingestion time. In our [manifest loader](https://github.com/github/dependency-graph-api/blob/master/etl/ingest/manifest_loader.rb#L51) we enqueue an [`ActionsPackageJob`](https://github.com/github/dependency-graph-api/blob/master/app/jobs/actions_package_job.rb#L1) to scan through all the manifest's dependencies and run the package loader for any valid releases we don't have in our database. We only do this on public actions workflows.

See also [Go modules in GitHub's Dependency Graph](../go-modules.md), which discusses various design questions encountered during the addition of support for a particular ecosystem, and links to the concrete implementation of each necessary component.


## Orientation
At the highest level, each PMA is responsible for:
1. Sourcing and ingesting authoritative package metadata for each supported ecosystem
    - Often, legacy PMA's utilize the ecosystem's package registry API for this
    - More recent PMAs use a combination of registry dataset snapshots and latest-update APIs
    - 3rd party sources are under also active investigation, including [Packagist](https://packagist.org/) and [Libraries.io](https://libraries.io/)
1. Processing a full dataset bootstrap and/or backfill for each supported ecosystem
1. Periodically polling for and ingesting new package releases and updates for each supported ecosystem
1. Parsing package manager/language ecosystem dependent _version range specifications_:
    - These must be translated accurately into our internal [DG/Supply Chain requirements format](https://github.com/github/dependency-graph-api/tree/master/app/models/versioning)
    - Transformation of requirements must stay in parity with external DG Manifest Adapter and Dependabot/Supply Chain implementations
1. Managing progress checkpoints to ensure latest-release jobs only process previously-unseen data
1. Publishing well-formed [PackageRelease events](https://hydro.githubapp.com/kafka/clusters/potomac/topic?tab=schema&topic=cp1-iad.ingest.github.dependencygraph.v0.PackageRelease) to Hydro, often via a proxy like [Fjord](https://github.com/github/fjord#fjord)
1. Unit test coverage particular to each ecosystem, it's data sources, and transformations required to publish well-formed release events


## Implementation
First, fire up a DG-API Codespace and cut a new feature branch!

### Generate PMA template
From your new DG-API Codespace and feature branch:
- [Review the generator script](https://github.com/github/dependency-graph-api/blob/master/package_manager_adapters/script/generate)
- Execute: `cd package_manager_adapters; script/generate <NEW_PACKAGE_MANAGER_NAME>` (review your new Manifest Adapter to coordinate naming here)
- Customize your `README.md`: examples [here](https://github.com/github/dependency-graph-api/blob/master/package_manager_adapters/cargo/README.md)
- Customize the `wrapper` and test-scoped `Dockerfile` templates generated at this step as you build out your new PMA:
- Examples [here](https://github.com/github/dependency-graph-api/blob/master/package_manager_adapters/cargo/wrapper), [here](https://github.com/github/dependency-graph-api/blob/master/package_manager_adapters/cargo/Rakefile), [here](https://github.com/github/dependency-graph-api/blob/master/package_manager_adapters/cargo/Dockerfile)

### Implement PMA Base
The PMA contract is limited to the `wrapper` API for the most part. As mentioned above, even this API is regularly extended or altered on a per-PMA/ecosystem basis. That said, there _are_ some basic elements of every PMA implementation that you'll need to account for at this stage:
- Full-dataset bootstrap/backfill process: [example](https://github.com/github/dependency-graph-api/blob/master/package_manager_adapters/cargo/lib/cargo_snapshot.rb)
- Recent releases/updates ingest process: [example](https://github.com/github/dependency-graph-api/blob/master/package_manager_adapters/cargo/lib/cargo_api.rb)
- Version range translation (ecosystem-specific to DG/Supply Chain format): [example](https://github.com/github/dependency-graph-api/blob/master/package_manager_adapters/cargo/lib/requirements.rb)
- Checkpoint management boilerplate: [example](https://github.com/github/dependency-graph-api/blob/master/package_manager_adapters/cargo/lib/cargo_importer.rb)
- Event publishing boilerplate: Fjord-based examples [here](https://github.com/github/dependency-graph-api/blob/master/package_manager_adapters/cargo/lib/parsed_version.rb) and [here](https://github.com/github/dependency-graph-api/blob/master/package_manager_adapters/cargo/lib/fjord_sink.rb)
- Dependency management: examples [here](https://github.com/github/dependency-graph-api/blob/master/package_manager_adapters/cargo/Gemfile) and [here](https://github.com/github/dependency-graph-api/blob/master/package_manager_adapters/cargo/Gemfile.lock)
- Unit test suite and coverage for all of the above: examples [here](https://github.com/github/dependency-graph-api/tree/master/package_manager_adapters/cargo/test)
- Optional (but encouraged for new ecosystems!): implement a one-off `wrapper` command to ingest a single package, in lieu of chatops functionality that is isolated from PMAs [example](https://github.com/github/dependency-graph-api/tree/master/package_manager_adapters/pub/wrapper)

### Register PMA for CI testing
Once your new PMA features a unit test framework and suite, a `./wrapper test` integration with your test framework, and a test Docker image spec, you're ready to [register the PMA with the global test script](https://github.com/github/dependency-graph-api/blob/master/script/cibuild-dependency-graph-api-package-manager-adapters#L39) for CI integration. Generally, this just involves adding the [name of your new PMA](https://github.com/github/dependency-graph-api/tree/master/package_manager_adapters) to the highlighted list in the CI script.

### Register a Moda cronjob
Your PMA's latest-updates implementation should know how to obtain and parse new dependency updates from the previous checkpoint...but it shouldn't know how or when to execute itself. For this, we will register a new Moda (k8s) cronjob - example [here](https://github.com/github/dependency-graph-api/blob/master/config/kubernetes/workers/cronjobs/extract_cargo_packages.yaml). Important things to note at this stage:
- Specify a reasonable [schedule](https://github.com/github/dependency-graph-api/blob/ef6245b73ddcfaf46b54f767f2c087ae04e39955/config/kubernetes/workers/cronjobs/extract_cargo_packages.yaml#L10)
- Ensure deployments don't [overlap executions](https://github.com/github/dependency-graph-api/blob/ef6245b73ddcfaf46b54f767f2c087ae04e39955/config/kubernetes/workers/cronjobs/extract_cargo_packages.yaml#L11)
- Ensure your resource _asks_ and _burst limits_ are robust and fit the resource profile of the job: [example](https://github.com/github/dependency-graph-api/blob/ef6245b73ddcfaf46b54f767f2c087ae04e39955/config/kubernetes/workers/cronjobs/extract_cargo_packages.yaml#L32-L40)
- Ensure your new PMA is configured: examples [here](https://github.com/github/dependency-graph-api/blob/ef6245b73ddcfaf46b54f767f2c087ae04e39955/config/kubernetes/workers/cronjobs/extract_cargo_packages.yaml#L4) and [here](https://github.com/github/dependency-graph-api/blob/ef6245b73ddcfaf46b54f767f2c087ae04e39955/config/kubernetes/workers/cronjobs/extract_cargo_packages.yaml#L42)
- **IMPORTANT!** until your full-dataset bootstrap has been completed, deploy the job [in suspended status](https://github.com/github/dependency-graph-api/pull/2738/files#diff-ec5efdb8865ac0fb5fd2042a94ced2e9743dfc3512c8ce3e5b5f615892ec65f7R10) so latest-update runs don't overlap!

### Bootstrap Full Dataset
How this is accomplished will vary depending on your PMA implementation and data source choices. Exhaustively crawling a data source that is exclusively accessible via an API is often impractical, so legacy PMAs often bootstrap with only the "N most popular packages." Ideally, obtaining a registry snapshot and ingesting it offline is the most robust play here, but YMMV.

Here's an [example of the Rust/Cargo ecosystem backfill process](https://github.com/github/dependency-graph-api/tree/master/package_manager_adapters/cargo/README.md#running-a-production-backfill), including some universal steps:
1. Let the DG oncall and partner Supply Chain teams know you're kicking off the backfill, or take the pager for the duration
1. Make sure stakeholders/oncall folks know how to _safely pause your backfill_ in the event something goes wrong!
1. Isolate your backfill env and ensure it's accessible by your team (`tmux`, `.deploy lock` chatops etc.)
1. Watch DataDog graphs, Sentry, and Splunk for evidence of progress and/or failure that must be addressed
1. Validate that well-formed Hydro events and `dg_packages`, `dg_package_versions`, and `dg_dependency_specifications` records are being created
1. Watch out for sporadic crashes/fails (pod OOMs, PMA bugs w/o test coverage, etc.)
    - Ensure you built a robust method for restarting a partially-complete backfill into your new PMA!
1. Clean up your `tmux` session and DG deploy locks when the backfill is complete

### Enable Cronjob
Once your full-dataset backfill is complete and validated, the final step is to [enable your latest-updates cronjob](https://github.com/github/dependency-graph-api/pull/2782/files#diff-ec5efdb8865ac0fb5fd2042a94ced2e9743dfc3512c8ce3e5b5f615892ec65f7L10). As with the backfill process, you'll need to monitor the initial run to validate your implementation:
- Ensure your [Moda cronjob](https://github.com/github/dependency-graph-api/blob/ef6245b73ddcfaf46b54f767f2c087ae04e39955/config/kubernetes/workers/cronjobs/extract_cargo_packages.yaml#L41-L42)'s [start_kube](https://github.com/github/dependency-graph-api/blob/master/package_manager_adapters/script/start_kube) plumbing plays nice with your new PMA
- Monitor DataDog, Splunk, and Sentry for signs of progress and/or processing failures
- Validate that well-formed Hydro events and `dg_packages`, `dg_package_versions`, and `dg_dependency_specifications` records are being created


## Acceptance Criteria
- [ ] The new PMA bootstrap/backfill process produces well-formed `PackageRelease` events and results in the storage of well-formed database records
- [ ] The new PMA latest-updates cronjob produces well-formed `PackageRelease` events and results in the storage of well-formed database records
- [ ] The new PMA should track checkpoints in a robust and effective way to avoid duplication of work
- [ ] The new PMA processes source data in keeping with the resource limitations declared it's host Moda deployment
- [ ] The new PMA should be sufficiently observable to ensure rapid detection of failures and triage of root causes
- [ ] The new PMA includes a robust unit test suite
- [ ] The new PMA implementation should include an auxiliary ClearlyDefined ingest job if the PMA data source is insufficient


## Cleanup
That's it! As with your new ecosystem's Manifest Adapter release, you'll need to coordinate some brief follow-ups:
1. Communicate to the DG team and Supply Chain partner teams that the new PMA is shipped!
1. Coordinate with your DG EM and PM to ensure any related docs, blog posts, and changelog PRs are shipped
1. Close out appropriate Task/Batch/Epic tracking Issues, after posting final thread updates
1. Consult the [ClearlyDefined](./overview.md) section of the overview document:
    - If you were not able to source robust license metadata or other critical metadata from your PMA data sources alone
    - This source is discouraged for new use cases, but available if needed.
1. Bask in the glory of sweet, sweet success, you've earned it!

## Conclusion
Whew! That was quite a journey, wasn't it! Fear not - there are [plans](https://github.com/github/dependency-graph/blob/main/docs/rfcs/new_pma_service.md) in play to rethink DG's PMA framework. Stay tuned...
