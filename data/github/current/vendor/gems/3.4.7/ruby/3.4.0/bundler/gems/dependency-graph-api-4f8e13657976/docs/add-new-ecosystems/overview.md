# Adding a new Language Ecosystem

The Dependency Graph (DG-API) service is responsible for ingesting and exposing project dependency data. The DG-API service accomplishes this via 3 distinct processes, all of which must be implemented, or handled via alternate functionality, to integrate a new feature-complete language ecosystem into the Dependency Graph:

## Manifest Adapter
Each Manifest Adapter component registers a new type of dependency manifest file as ingestable by DG-API, including the implementation for parsing the new manifest type, transforming and validating the captured data to conform to the DG-API data model, and submitting the cleansed data for storage. Since many language ecosystems have more than one popular package registry and associated built tooling and manifest file format, DG-API can support more than one Manifest Adapter per ecosystem, depending on the coverage required to best support each language in our Dependency Graph products.

Manifest Adapter file and dependency parsing code is utilized by the Manifest ETL process to ingest manifest-specific updates tracked in pushes to the parent Git repository. ETL code links: [here](https://github.com/github/dependency-graph-api/blob/9cdba50a670a448c7cefbb4bd50fe5cc6aa0c779/etl/ingest/repository_manifest_file_change_processor.rb), [here](https://github.com/github/dependency-graph-api/blob/9cdba50a670a448c7cefbb4bd50fe5cc6aa0c779/etl/ingest/repository_manifest_file_deleted_processor.rb), [here](https://github.com/github/dependency-graph-api/blob/9cdba50a670a448c7cefbb4bd50fe5cc6aa0c779/etl/ingest/manifest_loader.rb).

The documentation for adding a new Manifest Adapter can be found [here](./adding-new-manifest-adapters.md).

#### Functionality
Once a Manifest Adapter for a given ecosystem has been implemented, merged, and a full data backfill completed, this alone can support the most critical core functionality that Dependency Graph and Dependabot expose. Namely:

- [Repository Insights](https://github.com/github/dependency-graph-api/network/dependencies): declared packages and version requirements only; no backlinks or rich metadata provided
- [Dependency Review](https://github.com/github/dependency-graph-api/actions/workflows/dependency-review.yml): declared package and version requirements data powers the manifest diff functionality required to evaluate PRs for the introduction and/or removal of known-vulnerable project dependencies
- [Org Insights](https://github.com/orgs/github/insights/dependencies): org-level view of declared package dependencies and version requirements. The future of this feature is uncertain atm
- [Dependabot Alerts](https://github.com/github/dependency-graph-api/security/dependabot): Dependabot utilizes per-reopsitory manifest and dependency declarations data captured by Dependency Graph to trigger vulnerability alerts
- [Dependabot Updates](https://github.com/github/dependency-graph-api/network/updates): Dependabot Updates uses the same manifest and dependency data to trigger automated PR submissions to repositories featuring known-vulnerable dependency declarations

The Manifest Adapter data also supports API-based versions of these products and queries against the Dependency Graph. Some details [here](https://docs.github.com/en/rest/dependency-graph) and [here](https://docs.github.com/en/graphql/reference/objects#dependencygraphdependency).

#### Storage
The data ingested by a Manifest Adapter is stored primarily in the following tables:

- [dg_manifests](https://github.com/github/dependency-graph-api/blob/9cdba50a670a448c7cefbb4bd50fe5cc6aa0c779/db/structure.sql#L192-L210) managed by [this Rails model](https://github.com/github/dependency-graph-api/blob/9cdba50a670a448c7cefbb4bd50fe5cc6aa0c779/app/models/manifest.rb) tracks each manifest file present in a given GitHub project repository
- [dg_manifest_dependencies](https://github.com/github/dependency-graph-api/blob/9cdba50a670a448c7cefbb4bd50fe5cc6aa0c779/db/structure.sql#L169-L191) managed by [this Rails model](https://github.com/github/dependency-graph-api/blob/9cdba50a670a448c7cefbb4bd50fe5cc6aa0c779/app/models/manifest_dependency.rb) tracks each package version declared as a project dependency in a particular manifest file
- [dg_repositories](https://github.com/github/dependency-graph-api/blob/9cdba50a670a448c7cefbb4bd50fe5cc6aa0c779/db/structure.sql#L287-L301) managed by [this Rails model](https://github.com/github/dependency-graph-api/blob/9cdba50a670a448c7cefbb4bd50fe5cc6aa0c779/app/models/repository.rb) syncs the GitHub monolith [Repository model](https://github.com/github/github/blob/master/packages/repositories/app/models/repository.rb) metadata to the DG-API DB and helps us map manifest files back to the repository that hosts them. A [new Repository record is created](https://github.com/github/dependency-graph-api/blob/9cdba50a670a448c7cefbb4bd50fe5cc6aa0c779/etl/ingest/package_loader.rb#L26-L46) if the referenced repo is unknown to DG-API
- [dg_abstract_repository_dependencies](https://github.com/github/dependency-graph-api/blob/9cdba50a670a448c7cefbb4bd50fe5cc6aa0c779/db/structure.sql#L23-L35) is updated to track changes in dependencies associated with the manifest's host repository
- [dg_star_counts](https://github.com/github/dependency-graph-api/blob/9cdba50a670a448c7cefbb4bd50fe5cc6aa0c779/db/structure.sql#L333-L340) and [dg_package_release_dependent_counts](https://github.com/github/dependency-graph-api/blob/9cdba50a670a448c7cefbb4bd50fe5cc6aa0c779/db/structure.sql#L211-L222) are also optionally updated to reflect changes to repository-level aggregate stats

## Package Manager Adapter
A language ecosystem's Package Manager Adapter (PMA) is responsible for ingesting published package metadata that provide rich contextual information about packages declared in manifests. This includes an initial backfill of some or all of the published packages associated with the package registry that backs the new ecosystem, as well as deploying a cron job process that will periodically sync recent package releases and changes, including removed/revoked releases, to the Dependency Graph.

The source code is available [here](https://github.com/github/dependency-graph-api/tree/master/package_manager_adapters). The documentation for adding a new Package Manager Adapter can be found [here](./adding-new-package-manager-adapters.md).

#### Functionality
- **Package-Repository Mappings**: PMA metadata is used to map published packages back to the repository that hosts the source code. Only GitHub-hosted mappings are stored. A variable "certainty level" (confidence score) is associated with each mapping, according to how the data was sourced. Stafftools-based chatops allow for manual override of known-bad mappings.
- **Package Version**: PMA metadata is stored globally (`Package` model) as well as per-release (`PackageRelease`) versions, typically in [semver](https://semver.org/) format
- **Package Dependencies**: If available, PMAs capture per-version (`PackageRelease`) dependencies _of the package_ (i.e. transitives of projects depending on the package) and declared version requirements
- **Package Status**: PMA metadata can also record an `unpublished_at` timestamp, as a sentinel value to mark certain versions as removed from the registry that originally published the package
- **Package Description and Links**: PMAs capture detailed package descriptions and URLs of the author's homepage and documentation, if available
- **Package License**: The [PackageRelease Hydro event](https://hydro.githubapp.com/kafka/clusters/potomac/topic?tab=schema&topic=cp1-iad.ingest.github.dependencygraph.v0.PackageRelease) published by PMAs to trigger ingest into the Dependency Graph now accepts an optional license specification string that can replace the ClearlyDefined functionality with PMA-sourced data, if the ecosystem registry makes it available. Currently only supported by the [Rust/Cargo PMA](https://github.com/github/dependency-graph-api/tree/master/package_manager_adapters/cargo)

#### Storage
When PMAs publish `PackageRelease` events, the DG-API package processes bundles package metadata and records it in a number of tables, as part of the PMA ETL process. Code links: [here](https://github.com/github/dependency-graph-api/blob/9cdba50a670a448c7cefbb4bd50fe5cc6aa0c779/etl/packages/package_release.rb), [here](https://github.com/github/dependency-graph-api/blob/9cdba50a670a448c7cefbb4bd50fe5cc6aa0c779/etl/ingest/package_processor.rb), [here](https://github.com/github/dependency-graph-api/blob/9cdba50a670a448c7cefbb4bd50fe5cc6aa0c779/etl/ingest/package_loader.rb).

- [dg_packages](https://github.com/github/dependency-graph-api/blob/9cdba50a670a448c7cefbb4bd50fe5cc6aa0c779/db/structure.sql#L268-L286) managed by [this Rails model](https://github.com/github/dependency-graph-api/blob/master/app/models/package.rb) captures package-global metadata that isn't release version specific
- [dg_package_versions](https://github.com/github/dependency-graph-api/blob/9cdba50a670a448c7cefbb4bd50fe5cc6aa0c779/db/structure.sql#L238-L267) managed by [this Rails model](https://github.com/github/dependency-graph-api/blob/master/app/models/package_release.rb) captures per-version release metadata
- [dg_dependency_specifications](https://github.com/github/dependency-graph-api/blob/9cdba50a670a448c7cefbb4bd50fe5cc6aa0c779/db/structure.sql#L110-L128) managed by these Rails models ([link](https://github.com/github/dependency-graph-api/blob/master/app/models/package_dependency.rb), [link](https://github.com/github/dependency-graph-api/blob/master/app/models/dependency.rb)) captures each package's own dependencies and version requirements, if exposed by the ecosystem's registry
- [dg_abstract_package_dependencies](https://github.com/github/dependency-graph-api/blob/9cdba50a670a448c7cefbb4bd50fe5cc6aa0c779/db/structure.sql#L1-L13) managed by [this Rails model](https://github.com/github/dependency-graph-api/blob/9cdba50a670a448c7cefbb4bd50fe5cc6aa0c779/app/models/abstract_package_dependency.rb) captures dependent relationships and counts for each package

### Event Consumption and Data Ingest
The PMA's responsibility ends at the publishing of well-formed and (ideally!) fully-populated `PackageRelease` events. But, curious reader, let me share what happens to those events _after_ your PMA achieves wild success:
1. A pool of Moda-deployed Aqueduct workers consumes `PackageRelease` events published by our PMAs
    - Moda job defined [here](https://github.com/github/dependency-graph-api/blob/master/config/kubernetes/workers/deployments/ingest_packages.yaml)
    - `Ingest::PackageProcessor` executor [here](https://github.com/github/dependency-graph-api/blob/master/script/etl/ingest_packages)
    - `Ingest::PackageProcessor` defined [here](https://github.com/github/dependency-graph-api/blob/master/etl/ingest/package_processor.rb) from base [here](https://github.com/github/dependency-graph-api/blob/master/etl/ingest/processor.rb)
1. Upon receiving a consumed event, the package processor:
    - [Reshapes the event](https://github.com/github/dependency-graph-api/blob/ef6245b73ddcfaf46b54f767f2c087ae04e39955/etl/ingest/package_processor.rb#L18-L42) into a serializable record suitable for submission as an Aqueduct job argument
    - [Submits an Aqueduct job](https://github.com/github/dependency-graph-api/blob/ef6245b73ddcfaf46b54f767f2c087ae04e39955/etl/ingest/package_processor.rb#L11) to post-process and persist the record to the Dependency Graph database
1. Upon execution, a `LoadPackageJob`:
    - [Executes](https://github.com/github/dependency-graph-api/blob/ef6245b73ddcfaf46b54f767f2c087ae04e39955/app/jobs/load_package_job.rb#L7) the `Ingest::PackageLoader` providing the record as an argument to the `load` method
1. `Ingest::PackageLoader` performs final processing and storage on the record passed to it:
    - [Looks up the parent `Repository`](https://github.com/github/dependency-graph-api/blob/ef6245b73ddcfaf46b54f767f2c087ae04e39955/etl/ingest/package_loader.rb#L217-L233) record associated with the release:
        - From DG-API database, if the record is present
        - Calls out to the GitHub monolith API if this `Repository` is previously unknown to DG-API
        - Persists the `Repository` metadata to the DG-API database if needed
    - Formats subsets of the package release record into various DG-API database tables:
        - [dg_packages](https://github.com/github/dependency-graph-api/blob/ef6245b73ddcfaf46b54f767f2c087ae04e39955/etl/ingest/package_loader.rb#L104-L112)
        - [dg_package_versions](https://github.com/github/dependency-graph-api/blob/ef6245b73ddcfaf46b54f767f2c087ae04e39955/etl/ingest/package_loader.rb#L118-L130)
        - [dg_abstract_package_dependencies](https://github.com/github/dependency-graph-api/blob/ef6245b73ddcfaf46b54f767f2c087ae04e39955/etl/ingest/package_loader.rb#L136-L153)
        - [dg_dependency_specifications](https://github.com/github/dependency-graph-api/blob/ef6245b73ddcfaf46b54f767f2c087ae04e39955/etl/ingest/package_loader.rb#L155-L173)
    - Attempts a [corrective update](https://github.com/github/dependency-graph-api/blob/ef6245b73ddcfaf46b54f767f2c087ae04e39955/etl/ingest/package_loader.rb#L89) to the "repository ID certainty" to track the confidence level of our association of this release to it's parent repository, based on data source and/or heuristic used


## ClearlyDefined license metadata capture
Finally, DG-API ingests package metadata from the [ClearlyDefined](https://clearlydefined.io/?sort=releaseDate&sortDesc=true) service when this data is not available elsewhere. There are some substantial limitations involved with this data source, so ecosystems that rely on this data source typically only collect metadata for the N most popular packages in the ecosystem. ClearlyDefined is primarily used to source package/project license metadata, but can also provide source repository mappings if available.

In the event that your new ecosystem package registry provides high-quality license and repo mapping data, the PMA implementation can own ingest of the package metadata, and no ClearlyDefined update job will need to be implemented.

As of Q4FY23 (June 2023) Dependency Graph now supports the direct import of ClearlyDefined data via Hydro. The main components include a [Hydro consumer](https://github.com/github/dependency-graph-api/blob/3a2a12acafdfbb472bc9004ac45e4de049a0ac0b/etl/ingest/package_metadata_processor.rb), an [Aqueduct job to persist parsed PackageReleases](https://github.com/github/dependency-graph-api/blob/3a2a12acafdfbb472bc9004ac45e4de049a0ac0b/app/jobs/load_package_metadata_job.rb) and a [Kubernetes deploy spec](https://github.com/github/dependency-graph-api/blob/3a2a12acafdfbb472bc9004ac45e4de049a0ac0b/config/kustomize/overlays/production/deployments/package_metadata.yaml).

If you are building support for an ecosystem _already supported by ClearlyDefined_ you may be able to run a targetted backfill by hacking the processor to only process the target ecosystem, then [rewinding the topic](https://github.com/github/dependency-graph-api/pull/3665/files) as per the linked example. **Bear in mind:** it may be most convenient, if you need to rewind and backfill from the OSPO topic, to _temporarily_ deploy a _new, isolated consumer_ (ETL processor) that has it's own consumer group, and can be hacked to filter for only the target ecosystem. This way, the current processor can continue to pick up recent updates from the already supported ecosystems while you backfill the new one. At the end of the backfill, the new ecosystem can be added to the current processor, and the temporary decomissioned. Don't forget to `kubectl delete deploy ...` all sites/instances of your temp when the backfill is over and the code deletion merged into `master`.

The _legacy_ ClearlyDefined processing code is [here](https://github.com/github/dependency-graph-api/blob/master/lib/clearly_defined.rb) and related ecosystem-specific cron jobs that poll for recent updates are [here](https://github.com/github/dependency-graph-api/tree/master/config/kubernetes/workers/cronjobs) with update logic [here](https://github.com/github/dependency-graph-api/tree/master/script/clearly_defined/most_popular). **This is no longer the recommended method for obtaining ClearlyDefined package data!**

## Spot Checks & Data Validation

In any situation where we import a large number of manifests, packages, or
metadata, we want to ensure we're importing the correct
information. We need to validate that what we expect to write to
our database is what's written. We can use spot checks to
perform this validation.

Spot checks involve randomly selecting a sample of the imported data
and comparing it to the original data to ensure it matches. For
example, if you imported a large dataset of package licenses into the
database, you could randomly select a few packages from the imported
dataset and compare their information to the original data to ensure
that it matches. If the data matches, then you can be reasonably sure
that the entire dataset was imported correctly.

You can compare entire records or individual fields. This list is not
exhaustive, but it includes a sample of the data fields you should
think about querying and comparing:

* **Manifests**: `manifest_type`, `path`, `filename`
* **Manifest Dependencies**: `manifest_id`, `package_name`, `requirements`
* **Packages**: `name`, `package_manager`
* **Package Releases**: `package_id`, `name`, `encoded`, `license`, `clearly_defined`

The percentage of data you will want to validate will vary depending on the data size and
shape but consider using 5%-10% of the data as the dataset for
testing. During the dry-run of your transition, you can perform validations/testing
against any fields you consider appropriate.
