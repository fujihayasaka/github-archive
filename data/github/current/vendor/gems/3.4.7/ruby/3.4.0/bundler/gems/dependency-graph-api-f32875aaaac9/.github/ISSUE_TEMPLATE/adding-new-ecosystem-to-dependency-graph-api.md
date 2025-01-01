---
name: Adding [Ecosystem] to dependency-graph-api
about: Steps you must follow to add a new ecosystem to dependency graph
title: 'Adding [Ecosystem] to dependency-graph-api'
---

First off, thank you for deciding to add support for a new ecosystem to dependency graph :100:

This is what you are going to have to do to get everything wired up and functional :rocket:

### Package Manager Adapter
- [ ] Generate template ecosystem code by executing command `package_manager_adapters/script/generate <ecosystem>`. This will create a new folder in `package_manager_adapters/` directory where you will implement your own package ingestion system that ingests packages in the ecosystem from its respective package registry.
- [ ] Implement your package manager adapter and test it out locally first to confirm that it successfully pulls down package metadata from its respective registry
- [ ] Make sure you write comprehensive tests that scope out behavior of your package manager adapter in the `/test` folder created in your new ecosystem folder in `package_manager_adapters/`.
- [ ] Make sure that the ecosystem is in [preview](https://github.com/github/dependency-graph-api/blob/master/config/initializers/preview.rb) mode until we are ready to show it to the world!
- [ ] Decide on how often you'll want to run the ingest process to pull down packages from its registry. Once you have that, schedule this task as a cron by creating a new cronjob. Follow path `config/kubernetes/workers/cronjobs/` and configure your cron by creating a new `yaml` file `extract_<ecosystem>_packages.yaml`. Feel free to use existing crons as a guide.
- [ ] Perform risk assessment with `@github/dependency-graph` to identify potential issues with enabling the new ecosystem package manager adapter
- [ ] Deploy your package manager adapter to production and ensure it pulls down package metadata at the scheduled time you set.
- [ ] Create issues, and document package ingestion failures if they occur. If they don't awesome :100:
- [ ] Merge in your PR when you are certain it works and has satisfied all the above requirements 🍨
- [ ] Update the [Kube](https://github.com/github/dependency-graph-api/blob/master/docs/kube.MD) and [Workers](https://github.com/github/dependency-graph-api/blob/master/docs/workers.md) documentation to include your new ecosystem.

For more information, checkout out the [package manager adapter docs](https://github.com/github/dependency-graph-api/blob/master/package_manager_adapters/README.md)

### Manifest Adapter(s)
- [ ] Add a new folder in `app/manifest_adapters/manifest_adapters` for your new ecosystem.
- [ ] Develop a RegEx matching for manifest files that you will be building your manifest adapter for.
- [ ] Implement your manifest adapter for the respective manifests under the given ecosystem. A manifest adapter for an ecosystem comprises of individual parsers for each specific manifest used by the ecosystem, and an adapter that invokes all these parsers when trying to parse an incoming manifest. Look at the [manifest adapter docs](https://github.com/github/dependency-graph-api/tree/master/app/manifest_adapters) if you need some help and further clarification.
- [ ] Make sure you can locally parse manifests of the ecosystem on real world manifest files. You can use `script/download-sample-manifests` to download a large number of random manifests from public repositories (see the script source for more details).
- [ ] Make sure that you handle manifest parsing errors gracefully to prevent manifest ingestion issues such as head of line blocking of our manifest file changes kafka topic. If a manifest is malformed, try as much as possible to rescue the specific error being thrown, and return an empty parsed manifest object.
- [ ] Test your new manifest adapter by writing tests in the `spec/manifest_adapters/<ecosystem>` directory. Be sure to include some tests against real manifest files.
- [ ] Make sure that manifests are in [preview](https://github.com/github/dependency-graph-api/blob/master/config/initializers/preview.rb) mode until we are ready to show them to the world!
- [ ] Perform risk assessment with `@github/dependency-graph` to identify potential issues with enabling the new ecosystem's manifest adpaters
- [ ] Deploy manifest adapters PR to production and notice if it creates any issues.
- [ ] Create issues, and document failures if they occur. If they don't awesome :100:
- [ ] Get review from team and merge in your PR when you are certain it works and has satisfied all the above requirements 🍨

### Detection of new ecosystems's manifests from github/github
- [ ] Introduce a feature flag, `<ecosystem>_dependency_graph_enabled` and check it before processing manifest files for the ecosystem
- [ ] Add Ecosystem to `Platform::Enums::VulnerabilityPlatform`
- [ ] Regenerate the GraphQL Schema
- [ ] Add Ecosystem to `Vulnerability::PLATFORMS`
- [ ] Develop a RegEx matching for manifest files for desired ecosystem and add them to `DependencyManifestFile.corresponding_package_type`
- [ ] Update `dependency_manifest_file_test.rb`
- [ ] Ensure that manifest detection works locally and that you have written tests that support the detection of the ecosystem's manifests from github/github.
- [ ] Perform risk assessment with `@github/dependency-graph` to identify potential issues with enabling the detection of the new ecosystem's manifests.
- [ ] Flip feature flag on for your detection PR, and make sure preview flag is also set.
- [ ] Deploy your PR to review/staging-lab or another production testing environment where one can verify that manifests are being detected and sent to dependency graph.
- [ ] Create issues, and document ingestion and detection failures if they occur. If they don't awesome :100:
- [ ] Get review from team and merge in your PR when you are certain it works and has satisfied all the above requirements 🍨

### Manifest Backfill
Now that we have packages coming in and the ability to ingest and parse manifests, we need to make sure we backfill all the repositories on GitHub that contain manifests under that ecosystem.
This process is still in flux. If you are creating this issue after we nailed down a process for manifest backfills please **stop what you're doing** and update this template.

### Security Alerts
- [ ] Reach out to `@github/pe-security-workflows` and run an end to end test of vulnerability alerting for new ecosystem, on repositories that have and leverage code from this ecosystem. Interface early with team to ensure that they can curate vulnerability data for this new ecosystem. Look [here](https://github.com/github/dependency-graph-api/blob/master/docs/adding-package-managers.md#vulnerability-detection) for more information.

### License Ingest
Once you have package manager up and manifest ingestion going strong, you will most likely want to start processing licenses for the packages of the ecosystem. Currently, we're leveraging [ClearlyDefined](https://clearlydefined.io/about) to send us license data on a per package version basis
- [ ] Establish if ecosystem is supported by ClearlyDefined, if its not, you will need to interface with them to get a [service](https://github.com/clearlydefined/service) and [crawler](https://github.com/clearlydefined/crawler) for the new ecosystem.
- [ ] Add ecosystems supported to [our ClearlyDefined library](https://github.com/github/dependency-graph-api/blob/master/lib/clearly_defined.rb)
- [ ] Perform risk assessment with `@github/dependency-graph` to identify potential issues with enabling the license ingest.
- [ ] Add a new cron job that will poll ClearlyDefined for licenses, preferably name it `most_popular_<ecosystem>_licenses.yaml` to grab the licenses of the most popular packages in that ecosystem.

### Monitors for new ecosystem
Once all steps above have been followed, we can assume that new ecosystem has been successfully integrated into dependency graph. To ensure we are continously processing data for the new ecosystem, we can create monitors to track how the processing and ingestion of these new packages and manifests are going.

Check the metric `etl.ingest.processed` on stage: `packages` if you want to track rate of packages ingested, or on stage:`manifests` if you want to track rate of manifests ingested. The `package manager` field for the monitor should be the ecosystem name; this will filter ingestion data down to just the newly added ecosystem.
