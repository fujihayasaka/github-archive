# Adding support for a new Manifest Adapter
The core component of a new Dependency Graph ecosystem is the Manifest Adapter, which is responsible for:
- Detecting manifest files belonging to supported ecosystems in GitHub repositories by pattern-matching on file name/path/extension
- Parsing all new or changed manifest files on each push to every branch of all DG-enabled GitHub repositories
- Produce well-formed `ManifestAdapters::Manifest` and `ManifestAdapters::Dependency` records (see [here](https://github.com/github/dependency-graph-api/blob/master/app/manifest_adapters/manifest_adapters/manifest.rb))
- [Serialize records](https://github.com/github/dependency-graph-api/blob/master/app/manifest_adapters/manifest_adapters/manifest_serializer.rb) for use in `ActiveJobs` that will persist the new data to the DG database

Some (non-exhaustive!) examples of file-to-package-manager mappings detected on pushes to DG-eligible GitHub repositories:
- The `npm` ecosystem maps to changes on `package.json` and `package-lock.json` files
- The `go` ecosystem maps to changes on `go.mod` files
- The `cargo` ecosystem maps to changes on `Cargo.toml` and `Cargo.lock` files
- The `actions` ecosystem maps to changes on YAML files tracked under the `.github/workflows/` directory


## Orientation
- Manifest Adapter source code is tracked [here](https://github.com/github/dependency-graph-api/blob/master/app/manifest_adapters/)
- The `ManifestAdapters` module API is defined [here](https://github.com/github/dependency-graph-api/blob/master/app/manifest_adapters/manifest_adapters.rb)
- The base class for all Manifest Adapters is [here](https://github.com/github/dependency-graph-api/blob/master/app/manifest_adapters/adapter.rb)
- Ecosystem-specific adapter code, sometimes including _non-Ruby/Rails code_ can be found [here](https://github.com/github/dependency-graph-api/blob/master/app/manifest_adapters/manifest_adapters/)
- Cross-ecosystem utility code (example: generic TOML spec file parser [here](https://github.com/github/dependency-graph-api/blob/master/app/manifest_adapters/manifest_adapters/toml_lockfile_parser.rb) as applied [here](https://github.com/github/dependency-graph-api/blob/master/app/manifest_adapters/manifest_adapters/cargo/parsers/lock.rb) and [here](https://github.com/github/dependency-graph-api/blob/master/app/manifest_adapters/manifest_adapters/pip/parsers/poetry_lock.rb))


## Implementation
Implementing a Manifest Adapter for a new DG ecosystem is a multi-step process extending across several repositories and AoRs/service boundaries. The steps are enumerated below with general and ecosystem-specific examples.

### `github/dependency-graph-api` Manifest Adapter
The Manifest Adapter contract is not well defined, and there are subtle differences between the ways various ecosystem (package manager) specific implementations meet it. The most typical flow is defined below:

1. Add a new entry to `Types::PackageManager`: [here](https://github.com/github/dependency-graph-api/blob/4530dd5711a2283282a80cf1bfca523641df7b4e/app/models/types.rb#L17-L28) and [here](https://github.com/github/dependency-graph-api/blob/4530dd5711a2283282a80cf1bfca523641df7b4e/app/models/types.rb#L30-L53)
1. Add new entries to `Types::Manifest` for each file type supported by the new adapter [here](https://github.com/github/dependency-graph-api/blob/4530dd5711a2283282a80cf1bfca523641df7b4e/app/models/types.rb#L76-L118)
1. Update related test suite as needed [here](https://github.com/github/dependency-graph-api/blob/master/spec/models/types_spec.rb)
1. Implement manifest parsing for the new ecosystem under `app/manifest_adapters/manifest_adapters/<PACKAGE_MANAGER_NAME>`, including
    - Parser for each type of manifest file, accounting for _file type_ and _manifest spec requirements_ (examples [here](https://github.com/github/dependency-graph-api/blob/master/app/manifest_adapters/manifest_adapters/cargo/parsers/toml.rb) and [here](https://github.com/github/dependency-graph-api/blob/master/app/manifest_adapters/manifest_adapters/cargo/parsers/lock.rb))
    - Parser for the ecosystem's _version requirements spec_ (example [here](https://github.com/github/dependency-graph-api/blob/master/app/manifest_adapters/manifest_adapters/cargo/requirements.rb))
1. Implement a `ManifestAdapters::Adapter` subclass and `Adapter` API: [example here](https://github.com/github/dependency-graph-api/blob/master/app/manifest_adapters/manifest_adapters/cargo/adapter.rb) for [base class here](https://github.com/github/dependency-graph-api/blob/master/app/manifest_adapters/manifest_adapters.rb). This subclass must meet the following contract elements:
    - `ManifestAdapters::Adapter#manifest_type`: as called by `test` method to resolve file path/name/extension pattern matching:
        - [Module API usage](https://github.com/github/dependency-graph-api/blob/4530dd5711a2283282a80cf1bfca523641df7b4e/app/manifest_adapters/manifest_adapters.rb#L62)
        - [Adapter base class](https://github.com/github/dependency-graph-api/blob/4530dd5711a2283282a80cf1bfca523641df7b4e/app/manifest_adapters/manifest_adapters/adapter.rb#L5-L16)
        - [Ecosystem-specific subclass](https://github.com/github/dependency-graph-api/blob/4530dd5711a2283282a80cf1bfca523641df7b4e/app/manifest_adapters/manifest_adapters/cargo/adapter.rb#L6-L13)
    - `ManifestAdapters::Adapter#package_manager`: maps `String` labels to the `Types::PackageManager` of a supported ecosystem:
        - [Adapter base class](https://github.com/github/dependency-graph-api/blob/4530dd5711a2283282a80cf1bfca523641df7b4e/app/manifest_adapters/manifest_adapters/cargo/adapter.rb#L15-L17)
        - [Ecosystem-specific subclass](https://github.com/github/dependency-graph-api/blob/4530dd5711a2283282a80cf1bfca523641df7b4e/app/manifest_adapters/manifest_adapters/cargo/adapter.rb#L15-L17)
    - `ManifestAdapters::Adapter#parse`:
        - [The base `parse` method](https://github.com/github/dependency-graph-api/blob/4530dd5711a2283282a80cf1bfca523641df7b4e/app/manifest_adapters/manifest_adapters/adapter.rb#L43-L59) can be overriden with fully custom behavior if required. This is usually not needed.
    - `ManifestAdapters::Adapter#parsed`:
        - The `parsed` method [defined here](https://github.com/github/dependency-graph-api/blob/4530dd5711a2283282a80cf1bfca523641df7b4e/app/manifest_adapters/manifest_adapters/adapter.rb#L97-L99) is called in the Adapter [base class `parse` method](https://github.com/github/dependency-graph-api/blob/4530dd5711a2283282a80cf1bfca523641df7b4e/app/manifest_adapters/manifest_adapters/adapter.rb#L54). This is the typical way per-ecosystem Adapter subclasses meet the `ManifestAdapter` contract
        - The Adapter subclass's `parsed` method often [returns an instance of the underlying parser class](https://github.com/github/dependency-graph-api/blob/4530dd5711a2283282a80cf1bfca523641df7b4e/app/manifest_adapters/manifest_adapters/cargo/adapter.rb#L21-L30), populated with the raw manifest file
        - The Parser object returned from the Adapter subclass's `parsed` **must** meet the [`Parsers::Base` contract](https://github.com/github/dependency-graph-api/blob/master/app/manifest_adapters/manifest_adapters/parsers.rb). Example [here](https://github.com/github/dependency-graph-api/blob/master/app/manifest_adapters/manifest_adapters/pub/parsers/lock.rb)
1. Implement new Manifest Adapter ecosystem test suites. Cargo examples [here](https://github.com/github/dependency-graph-api/tree/master/spec/manifest_adapters/cargo)

### `github/dependency-graph-api` Package Manager and Manifest Filetype Registration

**Very Important Note:** The name we give the enum for our new ecosystem matters! Ideally we decide on the ecosystem name as a cross-team effort, but if there is already an existing ecosystem name defined in other products like Dependabot and AdvisoryDB, we should follow suit.
- [Ecosystem mappings in `dependabot-core`](https://github.com/dependabot/dependabot-core/blob/main/common/lib/dependabot/config/file.rb#L40)
- [Ecosystem definitions in AdvisoryDB helper](https://github.com/github/github/blob/master/packages/security_products/app/models/advisory_db/ecosystems.rb) see the [Vulnerability Detection](#vulnerability_detection) section below for the detailed update checklist

We are particularly coupled with AdvisoryDB + Dependabot Alert's enums as they are used to [validate things such as the package manager](https://github.com/github/github/blob/e85d54c5e19ba52b751e6f13575819dddfcf4dfb/packages/security_products/app/models/vulnerable_version_range.rb#L43) on a given `VulnerableVersionRange`, data that we then ingest in our own DB.

#### DG Registration Checklist
**IMPORTANT!** the changes listed below should be merged _after_ the new Manifest Adapter components detailed above!

1. Maintain parity with the enum in our Twirp protobuf messages [here](https://github.com/github/dependency-graph-api/blob/4530dd5711a2283282a80cf1bfca523641df7b4e/proto/twirp/v1/dependency_graph_api.proto#L72-L86)
    - **IMPORTANT!** Our Twirp APIs are not uniformly preview aware yet!
        - During the Dart ship this caused 5xx's from the Sponsors API consumer when this PR shipped
        - Depending on whether this problem [is resolved yet](https://github.com/github/dependency-graph/issues/1490#issuecomment-1284400913) you'll need to coordinate with stakeholder teams about when changes like this are safe to ship

1. Add the new PM and file types to "DG Preview" status:
    - This is a _temporary_ change, allowing DG to dogfood the new ecosystem during staff ship and production backfill of the new ecosystem across DG-eligible repos
    - DG-API Maniest Adapter plumbing must be merged before merging a code change to add the new ecosystem to preview status
    - Code [here](https://github.com/github/dependency-graph-api/blob/master/config/initializers/preview.rb)
    - Register a `Types::Manifest` entry for _each file type_ supported by the new Manifest Adapter (like `cargo.toml` and `cargo.lock`)
    - Register a `Types::PackageManager` for the new ecosystem's Package Manager (like `cargo`)

### `github/github` Package Manager and File Type(s) Registration

1. Update the `dependency_graph_api` Twirp protobuf Gem in dotcom to sync with DG-API side changes (new ecosystem/Adapter/file types)
1. Register the newly-supported manifest file types with the dotcom monolith. Code to review/update:
    - [File Path Patterns](https://github.com/github/github/blob/babb0b5bcdbf21bf86f2fd74fdf4c0729d1976ab/packages/security_products/app/models/dependency_manifest_file.rb#L6-L55)
    - [Path to Package Manager Resolver](https://github.com/github/github/blob/babb0b5bcdbf21bf86f2fd74fdf4c0729d1976ab/packages/security_products/app/models/dependency_manifest_file.rb#L94-L113)
    - [File Path Pattern Resolver](https://github.com/github/github/blob/babb0b5bcdbf21bf86f2fd74fdf4c0729d1976ab/packages/security_products/app/models/dependency_manifest_file.rb#L116-L174)
    - [Supported Package Managers Resolver](https://github.com/github/github/blob/babb0b5bcdbf21bf86f2fd74fdf4c0729d1976ab/packages/security_products/app/models/dependency_manifest_file.rb#L176-L196)
1. Update DG-owned dotcom helper code:
    - [DependencyReviewHelper](https://github.com/github/github/blob/babb0b5bcdbf21bf86f2fd74fdf4c0729d1976ab/app/helpers/dependency_review_helper.rb#L8-L19)
    - [PackageDependenciesHelper](https://github.com/github/github/blob/babb0b5bcdbf21bf86f2fd74fdf4c0729d1976ab/app/helpers/package_dependencies_helper.rb#L4-L17)
    - [VulnerabilitiesHelper](https://github.com/github/github/blob/master/app/helpers/vulnerability_helper.rb#L19-L64)
    - If your new ecosystem and MA implementation support a notion of a _manifest_ as well as a _lock file_ you should register the lock file as prioritized [here](https://github.com/github/github/blob/master/lib/dependency_graph/manifest.rb#L8-L16)
    - Update related helper tests suites to taste [here](https://github.com/github/github/blob/master/test/helpers/dependency_review_helper_test.rb) and [here](https://github.com/github/github/blob/master/test/helpers/package_dependencies_helper_test.rb)
    - Example PR [here](https://github.com/github/github/pull/218198/files)

## Production Repository Backfill
Once the new ecosystem's Manifest Adapter implementation and registration tasks are complete across DG-API and dotcom repos, we are ready to backfill the `dg_manifests` and `dg_manifest_dependencies` tables by ingesting every matching manifest files across all DG-enabled GitHub repositories that are known to host projects utilizing the new ecosystem.

At present, the best way to do this is to utilize exported dotcom (Rails model) databases in GitHub's Trinio data warehouse. The steps to accomplish this are:

1. Add an appropriate warehouse query to our backfill script. Example [here](https://github.com/github/dependency-graph-api/blob/28e411bc369d5a9304fb23b5d18c1031da223fdb/go/backfill/backfill.go#L210-L222). Note: you can interactively develop your Trinio query (data sources, repo selection heuristic, etc.) [here](https://data.githubapp.com)
1. Merge and deploy your backfill script changes
   1. If you prefer to do a branch deploy instead of merging and deploying your script changes, you can do the following:
   1. Deploy your branch to  the `scripts` env by running `.deploy dependency-graph-api/[name of your branch] to scripts` in `#dg-ops`
   1. Check that this branch has been deployed in [Developer portal](https://devportal.githubapp.com/devportal/apps/dependency-graph-api?tab=deploysAndPipelines), look for `scripts` environment or by running `.wcid dependency-graph-api` in `#dg-ops`
1. Lock the `scripts` env for deploys during your long-running backfill using chatops in `#dg-ops`: `.lock dependency-graph-api to scripts [ecosystem] backfill`
1. SSH to a bastion node
1. On bastion, obtain a shell on a `scripts` pod, at the deploy site of your choice:
    - `. vault-login` (Vault sessions will timeout periodically, at which time you'll need to resume your backfill in-flight)
    - Find a pod in (example site in `ac4-iad`): `kubectl --context general-2-ac4-iad -n dependency-graph-api-scripts get all`
    - Log into the selected pod: `kubectl --context general-2-ac4-iad exec -i -t -n dependency-graph-api-scripts scripts-99599b679-mhcpj -- /bin/bash`
1. From your `kubectl` pod session:
    - `apt install tmux`
    - `tmux -S /tmp/manifest-backfill.sock new -s manifest_backfill_session`
    - `CTRL-b` then `d` to detach from the active session
    - Log back into the session with `tmux -S /tmp/manifest-backfill.sock attach`
1. Alert DG and partner teams in Slack that the backfill is starting:
    - Post the _full `kubectl exec` and `tmux attach` incantations_ (including pod deploy site and name!) for the DG oncall
    - Alternately, offer to take the pager for at least the first 24hrs of the backfill
1. Follow instructions [here](https://github.com/github/dependency-graph-api/blob/28e411bc369d5a9304fb23b5d18c1031da223fdb/go/backfill/backfill.go#L1-L86) to run the backfill for your target ecosystem
1. Monitor your backfill: this will be a _long-running process!_
    - Check on it regularly
    - Watch [Sentry Error Bucket](https://sentry.io/organizations/github/issues/?project=1858608), [Datadog Ingestion Dashboard](https://app.datadoghq.com/dashboard/rb9-x9p-b8f/dg-simple-ingest-dash?from_ts=1670343182852&to_ts=1670429582852&live=true), and overall [Datadog DG API Dashboard](https://app.datadoghq.com/dashboard/cmd-vkt-mii/dg-api?from_ts=1670343220484&to_ts=1670429620484&live=true).
    - Clean up your `tmux` and `scripts` env deploy lock after the backfill is completed by doing the following:
    1. Unlock the `scripts` env in #dg-ops: `.unlock dependency-graph-api in scripts`
    1. If you did a branch deploy, redeploy the main version by running `.deploy dependency-graph-api/master to scripts` in `#dg-ops`
1. **SMOKE TEST**
    - Create a public and a private test repo (under your login or using `dsp-testing` etc.)
    - For the private repo, ensure DG features are enabled
    - Use Okta to obtain JIT Stafftools access
    - Add your test repos (or your user, or the `dsp-testing` org for easy shared access, etc.) to [this feature flag]( https://admin.github.com/devtools/feature_flags/dependency_graph_preview)
    - Commit some test manifests in the new ecosystem to your test repos
    - After a brief pause, check the `network/dependencies` (repo Insights -> Dependency Graph) tab for each of your test repos
    - Result: you should see well-formed per-manifest dependency entries and version range specs for each test manifest and package you declared
    - You will _not_ yet see vulnerability alerts, transitive dependencies, package metadata, source-repo links or Dependabot update scans/PRs (yet!)


## Vulnerability Detection
Once a new manifest type has been introduced, we need to support vulnerability detection for this new ecosystem. Ecosystem support varies across Supply Chain features and teams as [tracked here](https://github.com/github/dsp-supply-chain/blob/main/language-support.md).

There are _two notions of Dependabot Alerts_ we must register, test, and merge separately:
1. **Push-time Alerts** are triggered whenever a manifest file change on a repo includes a vulnerable dependency tracked in AdvisoryDB
2. **Broadcast Alerts** are triggered whenever a new vulnerability on a packge is published to AdvisoryDB

When attempting to implement the registrations listed below, it is critical to consult with collaborators from the **AdvisoryDB, Dependabot Experience and Dependabot Updates teams**. Inspect the **full, self-serve checklist** below to ensure all the details are taken care of, and remember to request PR reviews from our partner teams. There are **known sequencing and dependency Issues among these Supply Chain components** to consider before merging!

In cases where the ecosystem is new to all our partner teams, _fresh implementation work and additional coordination will be required_. At a high level, the additional steps are:

#### Implementation Checklist
The following is a consolidated list of dev taskwork to be reviewed by all the Supply Chain partner teams when integrating/implementing the new ecosystem. Some of this work can be done by DG folks and reviewed by partner teams. In some cases, the partner team should take lead on this work. Review sections of the checklist below with the appropriate partner team to ensure it is accurate and up to date, especially with regard to _sequencing PRs in the right order_, and _dependencies between shared registration code across partner teams' AoRs!_

**IMPORTANT!** Some of this work can be merged any time as prep for the release, especially while the DG ecosystem is in "preview" status. Other components called out below _must be merged at release time_ as they are not at time of this writing integrated with DG's notion of "preview" status, and will _go live upon merge_. Review carefully before merging checklist items!

#### Dependabot Experience
1. Register the new ecosystem as supported by Security Advisories [here](https://github.com/github/dependabot-api/blob/2e0e947e2c7402b57f31c4ce10543dd3a3445cde/app/models/github_security_advisory_importer.rb#L58-L69) and related [tests](https://github.com/github/dependabot-api/blob/main/spec/models/github_security_advisory_importer_spec.rb)
1. Register the new ecosystem with `UpdateConfig`:
    - Register package Manager type [here](https://github.com/github/dependabot-api/blob/2e0e947e2c7402b57f31c4ce10543dd3a3445cde/app/models/update_config.rb#L18-L22)
    - Register Language mapping [here](https://github.com/github/dependabot-api/blob/2e0e947e2c7402b57f31c4ce10543dd3a3445cde/app/models/update_config.rb#L53-L71)
    - Review processing configurations as appropriate to your new ecosystem implementation [here](https://github.com/github/dependabot-api/blob/2e0e947e2c7402b57f31c4ce10543dd3a3445cde/app/models/update_config.rb#L23-L52)
1. Register the new ecosystem on Dependabot `SecurityVulnerability` for event consumption [here](https://github.com/github/dependabot-api/blob/2e0e947e2c7402b57f31c4ce10543dd3a3445cde/app/hydro/hydro_handlers/github/security_vulnerability.rb#L8-L19)


#### Dependabot Experience + AdvisoryDB:
Prior to release date:
1. Register the new ecosystem in "preview" (`is_public = false`) mode [here](https://github.com/github/github/blob/master/packages/security_products/app/models/advisory_db/ecosystems.rb#L41) (detailed instructions below in checklist)
1. Register the new ecosystem with AdvisoryDB's DG-supported ecosystems list [here](https://github.com/github/github/blob/f1b1e40d78ef99d25662f784406f9f88513fb15e/packages/security_products/app/models/advisory_db/ecosystems.rb#L18-L39), [here](https://github.com/github/github/blob/f1b1e40d78ef99d25662f784406f9f88513fb15e/packages/security_products/app/models/advisory_db/ecosystems.rb#L45-L58), [here](https://github.com/github/github/blob/f1b1e40d78ef99d25662f784406f9f88513fb15e/packages/security_products/app/models/advisory_db/ecosystems.rb#L60-L70) and [here](https://github.com/github/github/blob/f1b1e40d78ef99d25662f784406f9f88513fb15e/packages/security_products/app/models/advisory_db/ecosystems.rb#L72-L85)
1. Add new ecosystem to AdvisoryDB's `hydro-schemas`: example PR [here](https://github.com/github/hydro-schemas/pull/2764)
1. Register the new ecosystem with AdvisoryDB's app config [here](https://github.com/github/advisory-db/blob/ccae77cf26f42b86df30c7a97ee7bce1dffb57a0/lib/advisory_db/config/ecosystems.rb) and re-vendor advisoryDB protobufs once `hydro-schemas` PR is merged. Example PR [here](https://github.com/github/advisory-db/pull/1174)
1. Add advisory seed data for the new ecosystem [example here](https://github.com/github/github/blob/28e275e2becb23e5dd2327436b011d511185ed83/script/seeds/runners/global_advisories.rb)

At release date:
1. Prep a PR **to be merged at release time** to bring the new ecosystem out of "preview" mode (`is_public = true`)
    - **IMPORTANT!** At the time of this writing, Dependabot Broadcast Alerts cannot be tested while the ecosytem is not public and in DG preview status

### Sponsors
JUST PRIOR to release date:
1. Update Hydro Schemas enum for new ecosystem [here](https://github.com/github/hydro-schemas/blob/110750b6d0c818cb12125900682fde8ec8fb25a7/proto/hydro/schemas/github/sponsors/v1/explore_filter_change.proto#L27-L37)

At release date:
1. Revendor updated Hydro Schemas in dotcom, once merged in previous step
1. Register the new ecosystem in dotcom for Sponsors filter set [here](https://github.com/github/github/blob/c2025e64e694c4a83106ffb7e15be965b23d01a4/packages/github_sponsors/app/models/sponsors_explore_filter_set.rb#L25) and [here](https://github.com/github/github/blob/c2025e64e694c4a83106ffb7e15be965b23d01a4/packages/github_sponsors/app/models/sponsors_explore_filter_set.rb#L31).
1. Confirm the [sponsors tests pass](https://github.com/github/github/blob/master/test/components/sponsors/explore/ecosystem_filters_component_test.rb#L96).

#### Dependabot Updates:
Prior to release date:
1. Implement/verify support for the new ecosystem in the DU Advisory Cache
1. Implement/verify support for requesting security updates for the new ecosystem
1. Implement/verify support for performing security updates for the new ecosystem in dependabot-core (_Note: this is separate from version updates support_)
1. Example DU tracking Issue [here](https://github.com/github/dependabot-updates/issues/2892)
1. Register new ecosystem for UI icons [here](https://github.com/github/github/blob/c641067a86bb5f65dd611b69616754c631164d77/lib/dependabot.rb#L114-L138)

At release date:
1. Register the new ecosystem for Dependabot `SecurityUpdates` [here](https://github.com/github/github/blob/c641067a86bb5f65dd611b69616754c631164d77/lib/dependabot.rb#L94-L108), and unit tests [here](https://github.com/github/github/blob/master/test/lib/dependabot_test.rb)

For reference, here is the Dependabot Updates team doc with notes on [adding a new ecosystem to Dependabot](https://github.com/github/dependabot-updates/blob/main/docs/development/security-updates/adding-a-new-ecosystem.md).


#### OSSF Docs
1. Fork `ossf/osv-schema` and file a PR to update the supported ecosystem table in Security Advisory format docs [here](https://github.com/ossf/osv-schema/blob/main/docs/schema.md#affectedpackage-field)


## Release/Launch Sequence
The final steps for releasing and testing your new ecosystem Manifest Adapter implementation should be planned carefully and coordinated with partner teams in Supply chain, namely:
1. AdvisoryDB / Advisory Curation
1. Dependabot Experience
1. Dependabot Updates
1. Sponsors (at least until they can be safely gated by DG "preview" until release date!)
1. Your Dependency Graph EM and PM, who must ship changelog updates, blog post, etc. on the day of release. Examples [here](https://github.com/github/releases/issues/2243) and [here](https://github.com/github/blog/pull/3516)

For reference, here is an [example Launch Sequence tracking Issue](https://github.com/github/dependency-graph/issues/1062) from the Rust/Cargo MA release, and a [DG New Ecosystem Issue Template](https://github.com/github/dependency-graph/blob/main/.github/ISSUE_TEMPLATE/ecosystem-launch-issue.md).

### Vulnerability Alerts: Push-Time Smoke Test
1. Add your previously-created test repos (or user, or org as before) to the [vulnerability alerts preview feature flag](https://admin.github.com/devtools/feature_flags/vulnerability_alerts_preview_dependencies)
1. Select a single security advisory to test against from the [AdvisoryDB](https://github.com/advisories)
    - The advisory must be from the new ecosystem and _published_ status
    - Ideally, it should be as _low-priority as possible!_ [Example here](https://github.com/advisories?query=Rust+severity%3Alow+sort%3Apublished-asc)
1. Ensure DG + Dependency Alerts are enabled for the repo:
1. If the new ecosystem is in "preview" status, _ensure the test repo is registered with the preview FF_
1. Add a vulnerable version of the package listed in the Security Advisory to one of your test repo manifests
1. Browse the repo's `Insights` => `Dependency Graph` => `Dependencies` page
   - Now, in addition to manifest dependency listings, you will also see an alert highlighted on the vulnerable package


### Vulnerability Publish: Broadcast Alerts Smoke Test
1. Add your previously-created test repos (or user, or org as before) to the [vulnerability alerts preview feature flag](https://admin.github.com/devtools/feature_flags/vulnerability_alerts_preview_dependencies)
1. Select a single security advisory to test against from the [AdvisoryDB](https://github.com/advisories), you can consult AdvisoryDB for an advisory.
    - The advisory must be:
        - From the new ecosystem and in _published_ status
        - Lowest severity available
        - Not previously used in push testing
        - [Example here](https://github.com/advisories?query=Rust+severity%3Alow+sort%3Apublished-asc)
1. Add a vulnerable version of the effected package declared in the advisory to your test repo manifests
1. From a local checkout of DG-API repo, `scp` the [seed vulnerabilities](https://github.com/github/dependency-graph-api/blob/master/script/seed_vulnerabilities.rb) script up to a dotcom bastion (ops-shell) box
1. Run `gh-console` (read-only mode will be fine!) and `load /home/<YOUR_LOGIN>/seed_vulnerabilities.rb` into the session
1. Review the instructions and example calls at the top of the script file
1. Run the script once, publishing _only the single advisory you selected for testing!_
1. Wait for processing, then evaluate that repo Insights, Dependency Review, Dependabot Alerts, and Dependabot Updates react appropriately to the presense of the vulnerable package in your test repo projects
1. Consult partner Supply Chain teams to review your test repos and validate everything is behaving as expected
1. Final test - add a _new manifest_ to one of your preview-enabled test repos, including a dependency _vulnerable to the published advisory_, and ensure alerting is triggered on PR and/or merge to the test repo

**NOTE!** Until a Package Manager Adapter (PMA) is implemented for the new ecosystem, package metadata and links on DG insights views and other UX affordances will not be available. Their absense does not indicate a problem for the Manifest Adapter portion of the ship!

### Vulnerability Publish: Broadcast Alerts
Be aware that once the new ecosystem is fully enabled in "preview" for all DG-eligible repos, the feature is essentially _shipped in production_. This final step must be coordinated with your PM/EM and partner teams in Supply Chain. Additionally, Dependabot Updates and Experience teams have known scale issues when publishing advisories that are known to effect a high cardinality of GitHub repositories, so coordination of each round of publishing will be critical to a smooth release.

1. Ping oncalls and point-persons on our partner Supply Chain teams in Slack to announce that the production rollout is beginning!
    - Optional: consider a Zoom session with stakeholders to "pair" on watching relevant graphs/logs/exceptions while publishing?
1. Set both [DG new ecosystem](https://admin.github.com/devtools/feature_flags/dependency_graph_preview) and [vulnerability alerts](https://admin.github.com/devtools/feature_flags/vulnerability_alerts_preview_dependencies) preview feature flags to **100% Dark Ship**
1. `ssh` to the bastion (ops-shell) node where you uploaded the seed script for smoke testing
1. Set up a _shareable_ `tmux` session on bastion - this might take a while!
1. Start a read-only `gh-console` from your attached `tmux` session, and `load` the seed script as before
1. Consult the [seed vulnerabilities](https://github.com/github/dependency-graph-api/blob/master/script/seed_vulnerabilities.rb) script instructions at the top of the file
    - Run the script _once for each of the supported severity levels_ for the new ecosystem: `critical`, `high`, `moderate`, and `low`
    - Use the dry-run option to sanity check your console incantation if you're nervous :)
1. Ping Supply Chain folks in Slack to inform them the publish step is completed
1. Sanity check the results across repos _not_ used in the smoke test phase

For reference [this Issue](https://github.com/github/dependency-graph/issues/1135) was used to track a full advisory republish using the seed script as detailed above.

NOTE: to refresh already published advisories, refer to [this Dependabot Updates Rails console snippet](https://github.com/github/dependabot-updates/blob/main/docs/development/security-updates/adding-a-new-ecosystem.md#1-dependabot-needs-to-consume-the-new-advisories) from the DU ecosystem notes doc. Since the seed vulnerabilities script filters for _already published advisories only_ this should not be needed when introducing new DG ecosystems, but consult with our Supply Chain partner teams for more context before your release.

### Acceptance Criteria
- [ ] Verify that adding manifests to private preview-flag-enabled repos works as expected
- [ ] Verify that adding manifests to public preview-flag-enabled repos works as expected
- [ ] Verify that we send alerts when the fake vulnerable package is added to a manifest in a **private** opted-in repo with the preview flag enabled
- [ ] Verify that we send alerts when the fake vulnerable package is added to a manifest in a **public** opted-in repo with the preview flag enabled
- [ ] Verify that we don't send alerts when the fake vulnerable package is added to a manifest in a **public** non-preview flag enabled repo
- [ ] Verify that we don't send alerts when the fake vulnerable package is added to a manifest in a **private** non-preview flag enabled repo


## Cleanup
1. Let your Dependency Graph EM and PM know it's time to publish changelog, blog, and docs updates as needed
1. PR cleanup/removal of the new ecosystem from DG Preview status, example [here](https://github.com/github/dependency-graph-api/pull/2682)
1. Remove custom entries and set "0% Dark Ship" for the preview feature flags: [here](https://admin.github.com/devtools/feature_flags/dependency_graph_preview) and [here](https://admin.github.com/devtools/feature_flags/vulnerability_alerts_preview_dependencies)
1. Close out appropriate Task/Batch/Epic tracking Issues, after posting final thread updates
