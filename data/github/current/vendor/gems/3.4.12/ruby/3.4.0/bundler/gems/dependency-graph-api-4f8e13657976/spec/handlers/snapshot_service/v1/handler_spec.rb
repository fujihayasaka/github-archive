require "rails_helper"
require "rantly"
require_relative "../../../etl/snapshot_requests/noop_test_provider"

describe SnapshotService::V1::Handler, :aggregate_failures do
  let(:noop_provider) { SnapshotRequests::Provider::NoOpTestProvider.new }
  let(:handler) { SnapshotService::V1::Handler.new(blob_operations_provider: noop_provider) }
  let(:handler_with_ds_api_diff) { SnapshotService::V1::Handler.new(blob_operations_provider: noop_provider, snapshots_client: DSAPIClientBasicDiff.new) }
  let(:handler_with_ds_api_maven_diff) { SnapshotService::V1::Handler.new(blob_operations_provider: noop_provider, snapshots_client: DSAPIClientMavenDiff.new) }
  let(:handler_with_ds_api_package_json_diff) { SnapshotService::V1::Handler.new(blob_operations_provider: noop_provider, snapshots_client: DSAPIClientPackageJSONDiff.new) }
  let(:handler_with_ds_api_404) { SnapshotService::V1::Handler.new(blob_operations_provider: noop_provider, snapshots_client: DSAPIClientDiff404.new) }
  let(:handler_with_mismatched_snapshots) { SnapshotService::V1::Handler.new(blob_operations_provider: noop_provider, snapshots_client: DSAPIClientMismatchDiff.new) }
  let(:handler_with_unknown_manifest_type) { SnapshotService::V1::Handler.new(blob_operations_provider: noop_provider, snapshots_client: DSAPIClientUnknownManifest.new) }

  describe "get snapshot diff" do
    let(:repository_id) { 23456 }
    let(:repo) { factory.given_repository(github_repository_id: repository_id, github_owner_id: 2) }
    let(:base_sha) { "8532b35330e822e27df629a952cf33bf65" }
    let(:target_sha) { "1fddc8023ec1e7f65e9b0c299ade1084dc7a3b66" }
    let(:gemfile_a) { { path: "Gemfile", blob_id: "abc123", content: 'gem "upgrademe", "6.1.1"' } }
    let(:gemfile_b) { { path: "Gemfile", blob_id: "def456", content: 'gem "upgrademe", "1.0.0"' } }
    let(:gemfile_c) { { path: "other/Gemfile", blob_id: "abcdef", content: 'gem "removeme", "4.0.0"' } }
    let(:gemfile_blob) { { path: "Gemfile", blob_id: "8532b35330e822e27df629a952cf33bf33" } }
    let(:pom_blob) { { path: "pom.xml", blob_id: "30e822e27df629a952cf33bf34" } }
    let(:package_json_blob) {
      {
        path: "package.json",
        blob_id: "75af076a61c9940d288b6eb32526c490146dfe04",
      }
    }
    let(:basic_diff_request) {
      DependencyGraphAPI::V1::GetSnapshotsDiffRequest.new(
          repository_id: repository_id,
          base_sha: base_sha,
          target_sha: target_sha,
          limit_to_files: {
            base: [],
            target: []
          }
        )
    }

    it "returns an empty diff if limit_to_files is empty" do
      req = basic_diff_request
      req.limit_to_files = DependencyGraphAPI::V1::LimitToFiles.new(base: [], target: [])

      response = handler.get_snapshots_diff(req, {})
      expect(response.changed_manifests).to be_empty
    end

    it "returns the right diff" do
      [gemfile_a, gemfile_b, gemfile_c].each do |file|
        mock_manifest_blob(repository_id: repository_id, blob_id: file[:blob_id], content: file[:content])
        file.delete(:content) # the :content key must be removed before they can go into a request
      end

      req = basic_diff_request
      req.limit_to_files = DependencyGraphAPI::V1::LimitToFiles.new(
          # gem "upgrademe", "1.0.0"
          # gem "removeme", "4.0.0"
          base: [gemfile_b, gemfile_c],
          # gem "upgrademe", "6.1.1"
          target: [gemfile_a]
      )

      response = handler.get_snapshots_diff(req, {})
      changed_manifests = response.changed_manifests.sort_by(&:file_path)
      gemfile = changed_manifests.first
      expect(gemfile.file_path).to eq("Gemfile")
      other_gemfile = changed_manifests.second
      expect(other_gemfile.file_path).to eq("other/Gemfile")

      upgrademe = gemfile.dependencies.first.to_h
      expect(upgrademe).to include({
        name: "upgrademe",
        base_version: "1.0.0",
        target_version: "6.1.1",
        change_type: :DEPENDENCY_CHANGE_TYPE_UPDATED
        })

      removeme = other_gemfile.dependencies.first.to_h
      expect(removeme).to include({
        name: "removeme",
        base_version: "4.0.0",
        target_version: "",
        change_type: :DEPENDENCY_CHANGE_TYPE_REMOVED
        })
    end

    it "infers limit_to_files from Spokes read_diff_summary when not supplied" do
      repository_id = 12345
      base_sha = "base123"
      target_sha = "target456"

      [gemfile_a, gemfile_b, gemfile_c].each do |file|
        mock_manifest_blob(repository_id: repository_id, blob_id: file[:blob_id], content: file[:content])
        file.delete(:content) # the :content key must be removed before they can go into a request
      end

      mock_spokes_get_changed_manifests(
        provider: noop_provider,
        repository_id: repository_id,
        base_oid: base_sha,
        target_oid: target_sha,
        result_base: [gemfile_b, gemfile_c],
        result_target: [gemfile_a]
      )

      handler = SnapshotService::V1::Handler.new(blob_operations_provider: noop_provider, snapshots_client: DSAPIClientDiff404.new)

      # Mock get_blob for the returned files
      req = DependencyGraphAPI::V1::GetSnapshotsDiffRequest.new(
        repository_id: repository_id,
        base_sha: base_sha,
        target_sha: target_sha
        # limit_to_files is omitted
      )

      response = handler.get_snapshots_diff(req, {})

      file_paths = response.changed_manifests.map(&:file_path)
      expected_paths = [gemfile_a, gemfile_b, gemfile_c].map { |f| f[:path] }.sort.uniq
      expect(file_paths).to match_array(expected_paths)
    end

    it "overrides static results with snapshot results when the flag is enabled" do
      mock_manifest_blob(
        repository_id: repository_id,
        blob_id: package_json_blob[:blob_id],
        content: '{ "dependencies": { "lodash": "3.5.0" } }'
      )

      req = basic_diff_request
      req.limit_to_files = DependencyGraphAPI::V1::LimitToFiles.new(
        base: [],
        target: [package_json_blob],
      )
      req.page_metadata = DependencyGraphAPI::V1::RequestPageMetadata.new(
        page: 1,
        per_page: 1,
      )
      req.include_dependency_snapshots = true
      req.decompose_updates = true

      # this handler returns ADDED: pkg:npm/snappy@6.2.1
      response = handler_with_ds_api_package_json_diff.get_snapshots_diff(req, {})

      expect(response.repository_id).to eq(req.repository_id)
      expect(response.base_sha).to eq(req.base_sha)
      expect(response.target_sha).to eq(req.target_sha)

      expect(response.changed_manifests.count).to eq(1)
      expect(response.changed_manifests.first.file_path).to eq("package.json")
      expect(response.changed_manifests.first.dependencies.count).to eq(1)
      expect(response.changed_manifests.first.dependencies.first.target_purl).to eq("pkg:npm/snappy@6.2.1")
    end

    it "creates a snapshot diff with vulnerabilities" do
      lodash_vvr = factory.given_vulnerable_version_range({
                                                            github_id: 120,
                                                            package_name: "lodash",
                                                            package_manager: :npm,
                                                            version_range: ">= 3.0.0, < 4.0.0"
                                                          })
      mock_manifest_blob(
        repository_id: repository_id,
        blob_id: package_json_blob[:blob_id],
        content: '{ "dependencies": { "lodash": "3.5.0" } }'
      )

      req = basic_diff_request
      req.limit_to_files = DependencyGraphAPI::V1::LimitToFiles.new(
        base: [],
        target: [package_json_blob]
      )

      response = handler.get_snapshots_diff(req, {})

      # gh_vuln_range_ids: [lodash_vvr.github_id]
      changed_manifests = [
        generate_manifest_diff(:PACKAGE_MANAGER_NPM, "package.json", [
          generate_dependency_diff("npm",
                                   "lodash",
                                   :DEPENDENCY_CHANGE_TYPE_ADDED,
                                   :SCOPE_RUNTIME,
                                   base_version: "",
                                   target_version: "3.5.0",
                                   gh_vuln_range_ids: [lodash_vvr.github_id])
        ])
      ]

      expect(response.repository_id).to eq(req.repository_id)
      expect(response.base_sha).to eq(req.base_sha)
      expect(response.target_sha).to eq(req.target_sha)
      expect(response.changed_manifests).to eq(changed_manifests)
    end

    it "reports vulnerabilities for ds-api dependencies" do
      jquery_vvr = factory.given_vulnerable_version_range({
                                                            github_id: 125,
                                                            package_name: "jquery",
                                                            package_manager: :npm,
                                                            version_range: ">= 1.0.1"
                                                          })
      mock_manifest_blob(
        repository_id: repository_id,
        blob_id: package_json_blob[:blob_id],
        content: '{ "dependencies": { "lodash": "3.5.0" } }'
      )

      req = basic_diff_request
      req.include_dependency_snapshots = true
      req.decompose_updates = true
      req.limit_to_files = DependencyGraphAPI::V1::LimitToFiles.new(
        base: [],
        target: [package_json_blob],
      )

      response = handler_with_ds_api_diff.get_snapshots_diff(req, {})
      changed_manifests = [
        generate_manifest_diff(:PACKAGE_MANAGER_NPM, "package.json", [
          generate_dependency_diff("npm",
                                   "lodash",
                                   :DEPENDENCY_CHANGE_TYPE_ADDED,
                                   :SCOPE_RUNTIME,
                                   base_version: "",
                                   target_version: "3.5.0",
                                   gh_vuln_range_ids: [])]),
        generate_manifest_diff(:PACKAGE_MANAGER_NPM, "package-lock.json", [
          generate_dependency_diff("npm",
                                   "jquery",
                                   :DEPENDENCY_CHANGE_TYPE_ADDED,
                                   :SCOPE_RUNTIME,
                                   base_version: "",
                                   target_version: "2.0.0",
                                   gh_vuln_range_ids: [jquery_vvr.github_id]),
          generate_dependency_diff("npm",
                                   "jquery",
                                   :DEPENDENCY_CHANGE_TYPE_REMOVED,
                                   :SCOPE_RUNTIME,
                                   base_version: "1.0.0",
                                   target_version: "",
                                   gh_vuln_range_ids: [])])
      ]

      expect(response.repository_id).to eq(req.repository_id)
      expect(response.base_sha).to eq(req.base_sha)
      expect(response.target_sha).to eq(req.target_sha)
      expect(response.changed_manifests).to eq(changed_manifests)
    end

    it "reports vulnerabilities for ds-api maven dependencies" do
      jquery_vvr = factory.given_vulnerable_version_range({
                                                            github_id: 125,
                                                            package_name: "jquery",
                                                            package_manager: :npm,
                                                            version_range: ">= 1.0.1"
                                                          })
      liquibase_vvr = factory.given_vulnerable_version_range({
                                                            # copied from real VVR 22452
                                                            github_id: 121,
                                                            package_name: "org.liquibase:liquibase-core",
                                                            package_manager: :maven, # "4"
                                                            version_range: "< 4.8.0"
                                                          })
      mock_manifest_blob(
        repository_id: repository_id,
        blob_id: package_json_blob[:blob_id],
        content: '{ "dependencies": { "lodash": "3.5.0" } }'
      )

      req = basic_diff_request
      req.include_dependency_snapshots = true
      req.decompose_updates = true
      req.limit_to_files = DependencyGraphAPI::V1::LimitToFiles.new(
        base: [],
        target: [package_json_blob],
      )

      response = handler_with_ds_api_maven_diff.get_snapshots_diff(req, {})
      changed_manifests = [
        generate_manifest_diff(:PACKAGE_MANAGER_NPM, "package.json", [
          generate_dependency_diff("npm",
                                   "lodash",
                                   :DEPENDENCY_CHANGE_TYPE_ADDED,
                                   :SCOPE_RUNTIME,
                                   base_version: "",
                                   target_version: "3.5.0",
                                   gh_vuln_range_ids: [])]),
        generate_manifest_diff(:PACKAGE_MANAGER_MAVEN, "build.gradle", [
          generate_dependency_diff("maven",
                                   "org.liquibase:liquibase-core",
                                   :DEPENDENCY_CHANGE_TYPE_ADDED,
                                   :SCOPE_RUNTIME,
                                   base_version: "",
                                   target_version: "4.7.1",
                                   gh_vuln_range_ids: [liquibase_vvr.github_id])])
      ]

      expect(response.repository_id).to eq(req.repository_id)
      expect(response.base_sha).to eq(req.base_sha)
      expect(response.target_sha).to eq(req.target_sha)
      expect(response.changed_manifests).to eq(changed_manifests)
    end

    it "reports vulnerabilities for ds-api dependencies when the manifest type is unknown" do
      jquery_vvr = factory.given_vulnerable_version_range({
                                                            github_id: 125,
                                                            package_name: "jquery",
                                                            package_manager: :npm,
                                                            version_range: ">= 1.0.1"
                                                          })
      rails_vvr = factory.given_vulnerable_version_range({
                                                            github_id: 126,
                                                            package_name: "rails",
                                                            package_manager: :rubygems,
                                                            version_range: "< 4.2.0"
                                                          })

      req = basic_diff_request
      req.include_dependency_snapshots = true
      req.decompose_updates = true
      req.limit_to_files = DependencyGraphAPI::V1::LimitToFiles.new(
        base: [],
        target: [],
      )

      response = handler_with_unknown_manifest_type.get_snapshots_diff(req, {})
      changed_manifests = [
        generate_manifest_diff(:PACKAGE_MANAGER_UNKNOWN, "anything can be a manifest", [
          generate_dependency_diff("npm",
                                   "jquery",
                                   :DEPENDENCY_CHANGE_TYPE_ADDED,
                                   :SCOPE_RUNTIME,
                                   base_version: "",
                                   target_version: "2.0.0",
                                   gh_vuln_range_ids: [jquery_vvr.github_id]),
          generate_dependency_diff("npm",
                                   "jquery",
                                   :DEPENDENCY_CHANGE_TYPE_REMOVED,
                                   :SCOPE_RUNTIME,
                                   base_version: "1.0.0",
                                   target_version: "",
                                   gh_vuln_range_ids: []),
          generate_dependency_diff("rubygems",
                                   "rails",
                                   :DEPENDENCY_CHANGE_TYPE_ADDED,
                                   :SCOPE_RUNTIME,
                                   base_version: "",
                                   target_version: "4.1.9",
                                   gh_vuln_range_ids: [rails_vvr.github_id]),
                                   ])]

      expect(response.repository_id).to eq(req.repository_id)
      expect(response.base_sha).to eq(req.base_sha)
      expect(response.target_sha).to eq(req.target_sha)

      jquery_addition = response.changed_manifests.first.dependencies.find { |d| d.name == "jquery" && d.change_type == :DEPENDENCY_CHANGE_TYPE_ADDED }
      expect(jquery_addition.github_vulnerability_range_ids).to eq([jquery_vvr.github_id])

      rails_addition = response.changed_manifests.first.dependencies.find { |d| d.name == "rails" && d.change_type == :DEPENDENCY_CHANGE_TYPE_ADDED }
      expect(rails_addition.github_vulnerability_range_ids).to eq([rails_vvr.github_id])

      expect(response.changed_manifests.to_a).to match_array(changed_manifests)
    end

    it "handles the case where there's no ds-api data available" do
      mock_manifest_blob(
        repository_id: repository_id,
        blob_id: package_json_blob[:blob_id],
        content: '{ "dependencies": { "lodash": "3.5.0" } }'
      )

      req = basic_diff_request
      req.include_dependency_snapshots = true
      req.decompose_updates = true
      req.limit_to_files = DependencyGraphAPI::V1::LimitToFiles.new(
        base: [],
        target: [package_json_blob],
      )

      response = handler_with_ds_api_404.get_snapshots_diff(req, {})
      changed_manifests = [
        generate_manifest_diff(:PACKAGE_MANAGER_NPM, "package.json", [
          generate_dependency_diff("npm",
                                   "lodash",
                                   :DEPENDENCY_CHANGE_TYPE_ADDED,
                                   :SCOPE_RUNTIME,
                                   base_version: "",
                                   target_version: "3.5.0",
                                   gh_vuln_range_ids: [])]),
      ]

      expect(response.repository_id).to eq(req.repository_id)
      expect(response.base_sha).to eq(req.base_sha)
      expect(response.target_sha).to eq(req.target_sha)
      expect(response.changed_manifests).to eq(changed_manifests)
      expect(response.snapshot_warnings.count).to eq(1)
      expect(response.snapshot_warnings.first).to include("No snapshots were found for the head SHA #{basic_diff_request.target_sha}")
    end

    it "defaults ds-api changes to scope 'runtime' when the scope is not specified" do
      req = basic_diff_request
      req.include_dependency_snapshots = true
      req.decompose_updates = true

      # verify that the scopes are missing in this client
      client_diff = DSAPIClientBasicDiff.new.get_snapshot_diff(1, req.base_sha, req.target_sha)
      expect(client_diff.data.dependency_changes.all? { |c| c.scope == :NONE }).to be true

      response = handler_with_ds_api_diff.get_snapshots_diff(req, {})
      changes = response.changed_manifests.first.dependencies
      expect(changes.count).to eq(2)
      expect(changes.all? { |c| c.scope == :SCOPE_RUNTIME }).to be true
    end

    it "passes through :RUNTIME and :DEVELOPMENT scopes from ds-api" do
      # This handler returns a diff showing jquery@1.0.0 removed from the "development" scope
      # and jquery@2.0.0 added to the "runtime" scope
      handler = SnapshotService::V1::Handler.new(blob_operations_provider: noop_provider, snapshots_client: DSAPIClientScopeChange.new)

      req = basic_diff_request
      req.include_dependency_snapshots = true
      req.decompose_updates = true

      response = handler.get_snapshots_diff(req, {})
      changes = response.changed_manifests.first.dependencies
      expect(changes.count).to eq(2)
      addition = changes.find { |c| c.change_type == :DEPENDENCY_CHANGE_TYPE_ADDED }
      removal = changes.find { |c| c.change_type == :DEPENDENCY_CHANGE_TYPE_REMOVED }

      expect(addition.name).to eq("jquery")
      expect(addition.target_version).to eq("2.0.0")
      expect(addition.scope).to eq(:SCOPE_RUNTIME)

      expect(removal.name).to eq("jquery")
      expect(removal.base_version).to eq("1.0.0")
      expect(removal.scope).to eq(:SCOPE_DEVELOPMENT)
    end

    it "skips the snapshot warning if the repository has no snapshot manifests anyway" do
      handler = SnapshotService::V1::Handler.new(
        blob_operations_provider: noop_provider,
        snapshots_client: DSAPIClientDiff404.new(meta: { "has_manifests": "false", "base_snapshots": "0" })
      )

      mock_manifest_blob(
        repository_id: repository_id,
        blob_id: package_json_blob[:blob_id],
        content: '{ "dependencies": { "lodash": "3.5.0" } }'
      )

      req = basic_diff_request
      req.include_dependency_snapshots = true
      req.decompose_updates = true
      req.limit_to_files = DependencyGraphAPI::V1::LimitToFiles.new(
        base: [],
        target: [package_json_blob],
      )

      response = handler.get_snapshots_diff(req, {})
      expect(response.snapshot_warnings.count).to eq(0)
    end

    it "returns a warning when there's a mismatch between base_snapshots_compared and head_snapshots_compared" do
      mock_manifest_blob(
        repository_id: repository_id,
        blob_id: package_json_blob[:blob_id],
        content: '{ "dependencies": { "lodash": "3.5.0" } }'
      )

      req = basic_diff_request
      req.include_dependency_snapshots = true
      req.decompose_updates = true
      req.limit_to_files = DependencyGraphAPI::V1::LimitToFiles.new(
        base: [],
        target: [package_json_blob],
      )

      response = handler_with_mismatched_snapshots.get_snapshots_diff(req, {})

      expect(response.snapshot_warnings.count).to eq(1)
      expect(response.snapshot_warnings.first).to include("The number of snapshots compared")
      expect(response.snapshot_warnings.first).to include("base SHA (1)")
      expect(response.snapshot_warnings.first).to include("head SHA (2)")
      expect(response.snapshot_warnings.first).to include("do not match.")
      expect(response.snapshot_warnings.first).to include("You may see unexpected additions in the diff")
    end

    it "regression test https://github.com/github/dependency-graph/issues/1413" do
      vvr = factory.given_vulnerable_version_range({
        github_id: 1,
        package_name: "colors",
        package_manager: :npm,
        version_range: ">= 1.4.1"
      })

      mock_manifest_blob(
        repository_id: repository_id,
        blob_id: package_json_blob[:blob_id],
        content: '{ "dependencies": { "colors": "1.3.0" } }'
      )

      req = basic_diff_request
      req.decompose_updates = true
      req.limit_to_files = DependencyGraphAPI::V1::LimitToFiles.new(
        base: [],
        target: [package_json_blob],
      )
      response = handler.get_snapshots_diff(req, {})

      changed_manifests = [
        generate_manifest_diff(:PACKAGE_MANAGER_NPM, "package.json", [
          generate_dependency_diff("npm",
                                   "colors",
                                   :DEPENDENCY_CHANGE_TYPE_ADDED,
                                   :SCOPE_RUNTIME,
                                   base_version: "",
                                   target_version: "1.3.0")
        ])
      ]

      expect(response.changed_manifests).to eq(changed_manifests)
    end

    it "composes updates from ds-api removals/additions" do
      mock_manifest_blob(
        repository_id: repository_id,
        blob_id: package_json_blob[:blob_id],
        content: '{ "dependencies": { "lodash": "3.5.0" } }'
      )

      req = basic_diff_request
      req.include_dependency_snapshots = true
      req.decompose_updates = false
      req.limit_to_files = DependencyGraphAPI::V1::LimitToFiles.new(
        base: [],
        target: [package_json_blob],
      )

      response = handler_with_ds_api_diff.get_snapshots_diff(req, {})

      expect(response.changed_manifests.count).to eq(2)

      # package.json contains one addition, lodash, from dg-api
      package_json = response.changed_manifests.find { |m| m.file_path == "package.json" }
      expect(package_json.dependencies.count).to eq(1)
      lodash_addition = package_json.dependencies.first
      expect(lodash_addition.change_type).to eq(:DEPENDENCY_CHANGE_TYPE_ADDED)
      expect(lodash_addition.target_purl).to eq("pkg:npm/lodash@3.5.0")

      # package-lock.json contains the removal of jquery 1.0.0 and the addition of jquery 2.0.0
      # they should be composed into one update
      package_lock_json = response.changed_manifests.find { |m| m.file_path == "package-lock.json" }
      expect(package_lock_json.dependencies.count).to eq(1)
      jquery_update = package_lock_json.dependencies.first
      expect(jquery_update.change_type).to eq(:DEPENDENCY_CHANGE_TYPE_UPDATED)
      expect(jquery_update.base_purl).to eq("pkg:npm/jquery@1.0.0")
      expect(jquery_update.target_purl).to eq("pkg:npm/jquery@2.0.0")
    end

    it "creates a snapshot diff with addition/removal pairs when decomposing updates" do
      base_manifest = gemfile_blob.dup
      mock_manifest_blob(
        repository_id: repository_id,
        blob_id: gemfile_blob[:blob_id],
        content: <<-eos
          gem "mongrel", "1.3.0"
          gem "rails", "5.3.0" # will be removed
        eos
      )

      target_manifest = gemfile_blob.dup
      target_manifest[:blob_id] = base_manifest[:blob_id].reverse
      mock_manifest_blob(
        repository_id: repository_id,
        blob_id: target_manifest[:blob_id],
        content: <<-eos
          gem "mongrel", "1.4.0" # upgrade
          gem "httparty", "1.0.0" # added
        eos
      )

      req = basic_diff_request
      req.limit_to_files = DependencyGraphAPI::V1::LimitToFiles.new(
        base: [base_manifest],
        target: [target_manifest],
      )
      req.decompose_updates = true

      response = handler.get_snapshots_diff(req, {})

      changed_manifests = [
        generate_manifest_diff(:PACKAGE_MANAGER_RUBYGEMS, "Gemfile", [
          generate_dependency_diff("rubygems", "httparty", :DEPENDENCY_CHANGE_TYPE_ADDED, :SCOPE_RUNTIME, base_version: "", target_version: "1.0.0"),
          generate_dependency_diff("rubygems", "mongrel", :DEPENDENCY_CHANGE_TYPE_ADDED, :SCOPE_RUNTIME, base_version: "", target_version: "1.4.0"),
          generate_dependency_diff("rubygems", "mongrel", :DEPENDENCY_CHANGE_TYPE_REMOVED, :SCOPE_RUNTIME, base_version: "1.3.0", target_version: ""),
          generate_dependency_diff("rubygems", "rails", :DEPENDENCY_CHANGE_TYPE_REMOVED, :SCOPE_RUNTIME, base_version: "5.3.0", target_version: ""),
        ]),
      ]

      expect(response.repository_id).to eq(req.repository_id)
      expect(response.base_sha).to eq(req.base_sha)
      expect(response.target_sha).to eq(req.target_sha)
      expect(response.changed_manifests).to eq(changed_manifests)
    end

    it "removed dependencies have vulnerabilities when decomposing updates" do
      lodash_vvr = factory.given_vulnerable_version_range({
                                                            github_id: 120,
                                                            package_name: "lodash",
                                                            package_manager: :npm,
                                                            version_range: ">= 3.0.0, < 4.0.0"
                                                          })
      base_manifest = package_json_blob.dup
      mock_manifest_blob(
        repository_id: repository_id,
        blob_id: base_manifest[:blob_id],
        content: '{ "dependencies": { "lodash": "3.5.0" } }'
      )

      target_manifest = package_json_blob.dup
      target_manifest[:blob_id] = base_manifest[:blob_id].reverse
      mock_manifest_blob(
        repository_id: repository_id,
        blob_id: target_manifest[:blob_id],
        content: '{ "dependencies": { "lodash": "4.0.1" } }'
      )

      req = basic_diff_request
      req.decompose_updates = true
      req.limit_to_files = DependencyGraphAPI::V1::LimitToFiles.new(
        base: [base_manifest],
        target: [target_manifest],
      )

      response = handler.get_snapshots_diff(req, {})

      # gh_vuln_range_ids: [lodash_vvr.github_id]
      changed_manifests = [
        generate_manifest_diff(:PACKAGE_MANAGER_NPM, "package.json", [
          generate_dependency_diff("npm",
                                   "lodash",
                                   :DEPENDENCY_CHANGE_TYPE_ADDED,
                                   :SCOPE_RUNTIME,
                                   base_version: "",
                                   target_version: "4.0.1"),
          generate_dependency_diff("npm",
                                   "lodash",
                                   :DEPENDENCY_CHANGE_TYPE_REMOVED,
                                   :SCOPE_RUNTIME,
                                   base_version: "3.5.0",
                                   target_version: "",
                                   gh_vuln_range_ids: [lodash_vvr.github_id]),
        ])
      ]

      expect(response.changed_manifests).to eq(changed_manifests)
    end

    it "creates a snapshot diff with purls generated" do
      base_gemfile = gemfile_blob.dup
      base_pom = pom_blob.dup

      mock_manifest_blob(
        repository_id: repository_id,
        blob_id: base_gemfile[:blob_id],
        content: <<-eos
          gem "mongrel", "1.3.0"
        eos
      )

      mock_manifest_blob(
        repository_id: repository_id,
        blob_id: base_pom[:blob_id],
        content: <<-eos
        <project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
        <modelVersion>4.0.0</modelVersion>

        <groupId>com.github</groupId>
        <artifactId>iceberg</artifactId>
        <version>1.0-SNAPSHOT</version>
        <dependencies>
          <dependency>
            <groupId>com.amazonaws</groupId>
            <artifactId>aws-java-sdk-core</artifactId>
            <version>1.3.0</version>
          </dependency>
        </dependencies>
        </project>
        eos
      )

      target_gemfile = gemfile_blob.dup
      target_gemfile[:blob_id] = base_gemfile[:blob_id].reverse

      target_pom = pom_blob.dup
      target_pom[:blob_id] = base_pom[:blob_id].reverse

      mock_manifest_blob(
        repository_id: repository_id,
        blob_id: target_gemfile[:blob_id],
        content: <<-eos
          gem "mongrel", "1.4.0"
        eos
      )

      mock_manifest_blob(
        repository_id: repository_id,
        blob_id: target_pom[:blob_id],
        content: <<-eos
        <project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
        <modelVersion>4.0.0</modelVersion>

        <groupId>com.github</groupId>
        <artifactId>iceberg</artifactId>
        <version>1.0-SNAPSHOT</version>
        <dependencies>
          <dependency>
            <groupId>com.amazonaws</groupId>
            <artifactId>aws-java-sdk-core</artifactId>
            <version>1.5.0</version>
          </dependency>
        </dependencies>
        </project>
        eos
      )

      req = basic_diff_request
      req.limit_to_files = DependencyGraphAPI::V1::LimitToFiles.new(
        base: [base_gemfile, base_pom],
        target: [target_gemfile, target_pom]
      )

      response = handler.get_snapshots_diff(req, {})

      expect(response.repository_id).to eq(req.repository_id)
      expect(response.base_sha).to eq(req.base_sha)
      expect(response.target_sha).to eq(req.target_sha)


      mongrel = response.changed_manifests.first.dependencies.first
      sdk_core = response.changed_manifests[1].dependencies.first

      expect(mongrel.base_purl).to eq("pkg:gem/mongrel@1.3.0")
      expect(mongrel.target_purl).to eq("pkg:gem/mongrel@1.4.0")

      expect(sdk_core.base_purl).to eq("pkg:maven/com.amazonaws/aws-java-sdk-core@1.3.0")
      expect(sdk_core.target_purl).to eq("pkg:maven/com.amazonaws/aws-java-sdk-core@1.5.0")
    end

    it "creates a snapshot diff with correct scopes returned" do
      base_pom = pom_blob.dup

      mock_manifest_blob(
        repository_id: repository_id,
        blob_id: base_pom[:blob_id],
        content: <<-eos
        <project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
        <modelVersion>4.0.0</modelVersion>

        <groupId>com.github</groupId>
        <artifactId>iceberg</artifactId>
        <version>1.0-SNAPSHOT</version>
        <dependencies>
          <dependency>
            <groupId>com.amazonaws</groupId>
            <artifactId>aws-java-sdk-core</artifactId>
            <version>1.3.0</version>
          </dependency>
        </dependencies>
        </project>
        eos
      )

      target_pom = base_pom.dup
      target_pom[:blob_id] = base_pom[:blob_id].reverse

      mock_manifest_blob(
        repository_id: repository_id,
        blob_id: target_pom[:blob_id],
        content: <<-eos
        <project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
        <modelVersion>4.0.0</modelVersion>

        <groupId>com.github</groupId>
        <artifactId>iceberg</artifactId>
        <version>1.0-SNAPSHOT</version>
        <dependencies>
          <dependency>
            <groupId>com.amazonaws</groupId>
            <artifactId>aws-java-sdk-core</artifactId>
            <version>1.5.0</version>
          </dependency>
          <dependency>
            <groupId>new</groupId>
            <artifactId>test-dep</artifactId>
            <version>1.0.0</version>
            <scope>test</scope>
        </dependency>
        </dependencies>
        </project>
        eos
      )

      req = basic_diff_request
      req.limit_to_files = DependencyGraphAPI::V1::LimitToFiles.new(
        base: [base_pom],
        target: [target_pom]
      )

      response = handler.get_snapshots_diff(req, {})

      sdk_core = response.changed_manifests.first.dependencies.first
      test_dep = response.changed_manifests.first.dependencies[1]

      expect(sdk_core.scope).to eq(:SCOPE_RUNTIME)
      expect(test_dep.scope).to eq(:SCOPE_DEVELOPMENT)
    end

    context "pagination" do
      before do
        # Reducing max in specs for performance reasons
        # Apparently mocking thousands of manifest blobs is quite slow

        stub_const("SnapshotService::V1::Handler::MAX_MANIFESTS_PER_PAGE", 100)
      end
      it "returns the full response when page & per_page are not specified" do
        large_num_of_manifests = described_class::MAX_MANIFESTS_PER_PAGE + 50
        base_manifests, target_manifests = generate_manifest_blobs(repository_id: repository_id, num_of_manifests: large_num_of_manifests)

        req = basic_diff_request
        req.limit_to_files = DependencyGraphAPI::V1::LimitToFiles.new(
          base: base_manifests,
          target: target_manifests,
        )

        response = handler.get_snapshots_diff(req, {})
        expect(response.changed_manifests.count).to eq(large_num_of_manifests)
        expect(response.page_metadata).to be_nil
      end

      it "returns pages of manifests when page & per_page are specified" do
        num_of_manifests = 9
        manifests_per_page = 3
        base_manifests, target_manifests = generate_manifest_blobs(repository_id: repository_id, num_of_manifests: num_of_manifests)

        requests = (1..3).map do |page|
          req = basic_diff_request.dup
          req.limit_to_files = DependencyGraphAPI::V1::LimitToFiles.new(
            base: base_manifests,
            target: target_manifests,
          )
          req.page_metadata = DependencyGraphAPI::V1::RequestPageMetadata.new(
            page: page,
            per_page: manifests_per_page,
          )
          req
        end

        response_page_1 = handler.get_snapshots_diff(requests[0], {})
        response_page_2 = handler.get_snapshots_diff(requests[1], {})
        response_page_3 = handler.get_snapshots_diff(requests[2], {})

        expected_page_1_manifests = ["folder1/Gemfile", "folder2/Gemfile", "folder3/Gemfile"]
        expected_page_2_manifests = ["folder4/Gemfile", "folder5/Gemfile", "folder6/Gemfile"]
        expected_page_3_manifests = ["folder7/Gemfile", "folder8/Gemfile", "folder9/Gemfile"]

        expect(response_page_1.changed_manifests.count).to eq(manifests_per_page)
        expect(response_page_1.changed_manifests.map(&:file_path)).to match_array(expected_page_1_manifests)

        expect(response_page_2.changed_manifests.count).to eq(manifests_per_page)
        expect(response_page_2.changed_manifests.map(&:file_path)).to match_array(expected_page_2_manifests)

        expect(response_page_3.changed_manifests.count).to eq(manifests_per_page)
        expect(response_page_3.changed_manifests.map(&:file_path)).to match_array(expected_page_3_manifests)

        res_page_1_metadata = response_page_1.page_metadata
        res_page_2_metadata = response_page_2.page_metadata
        res_page_3_metadata = response_page_3.page_metadata

        expect(res_page_1_metadata.page).to eq(1)
        expect(res_page_2_metadata.page).to eq(2)
        expect(res_page_3_metadata.page).to eq(3)

        [res_page_1_metadata, res_page_2_metadata, res_page_3_metadata].each do |metadata|
          expect(metadata.per_page).to eq(manifests_per_page)
          expect(metadata.first).to eq(1)
          expect(metadata.last).to eq(3)
        end
      end

      it "returns a blank page when page number exceeds the number of pages" do
        num_of_manifests = 9
        manifests_per_page = 3
        base_manifests, target_manifests = generate_manifest_blobs(repository_id: repository_id, num_of_manifests: num_of_manifests)

        req = basic_diff_request
        req.limit_to_files = DependencyGraphAPI::V1::LimitToFiles.new(
          base: base_manifests,
          target: target_manifests,
        )
        req.page_metadata = DependencyGraphAPI::V1::RequestPageMetadata.new(
          page: 5,
          per_page: manifests_per_page,
        )

        response = handler.get_snapshots_diff(req, {})

        expect(response.changed_manifests.count).to eq(0)
        expect(response.changed_manifests.map(&:file_path)).to match_array([])

        expect(response.page_metadata.page).to eq(5)
        expect(response.page_metadata.per_page).to eq(manifests_per_page)
        expect(response.page_metadata.first).to eq(1)
        expect(response.page_metadata.last).to eq(3)
      end

      it "returns uneven page when leftover manifests are less than per_page value" do
        num_of_manifests = 8
        manifests_per_page = 3
        base_manifests, target_manifests = generate_manifest_blobs(repository_id: repository_id, num_of_manifests: num_of_manifests)

        req = basic_diff_request
        req.limit_to_files = DependencyGraphAPI::V1::LimitToFiles.new(
          base: base_manifests,
          target: target_manifests,
        )
        req.page_metadata = DependencyGraphAPI::V1::RequestPageMetadata.new(
          page: 3,
          per_page: manifests_per_page,
        )

        response = handler.get_snapshots_diff(req, {})

        expect(response.changed_manifests.count).to eq(2)
        expect(response.changed_manifests.map(&:file_path)).to match_array(["folder7/Gemfile", "folder8/Gemfile"])

        expect(response.page_metadata.per_page).to eq(manifests_per_page)
        expect(response.page_metadata.first).to eq(1)
        expect(response.page_metadata.last).to eq(3)
      end

      it "returns a Twirp error when page size larger than the max" do
        manifests_per_page = described_class::MAX_MANIFESTS_PER_PAGE + 5
        base_manifests, target_manifests = generate_manifest_blobs(repository_id: repository_id, num_of_manifests: manifests_per_page)

        req = basic_diff_request
        req.limit_to_files = DependencyGraphAPI::V1::LimitToFiles.new(
          base: base_manifests,
          target: target_manifests,
        )
        req.page_metadata = DependencyGraphAPI::V1::RequestPageMetadata.new(
          page: 1,
          per_page: manifests_per_page,
        )

        response = handler.get_snapshots_diff(req, {})

        expect(response.class).to eq(Twirp::Error)
        expect(response.meta[:argument]).to eq("per_page")
      end

      context "with include_dependency_snapshots set to true" do
        it "returns appropriately-sized pages of ds-api manifests (no static manifests), changed manifests not affected by pagination" do
          t = pagination_test_setup(repository_id: repository_id, snapshot_manifests: 6, per_page: 3)

          page_1 = t[:get_page].call(1)
          expect(page_1.page_metadata.last).to eq(2)
          expect(page_1.changed_manifests.count).to eq(6)

          page_2 = t[:get_page].call(2)
          expect(page_2.page_metadata.last).to eq(2)
          expect(page_2.changed_manifests.count).to eq(6)

          # requesting the third page should give an empty response
          page_3 = t[:get_page].call(3)
          expect(page_3.page_metadata.last).to eq(2)
          expect(page_3.changed_manifests.count).to eq(6)

          # Make sure that we have all the manifests, no dups
          all_manifests = page_1.changed_manifests.map(&:file_path) + page_2.changed_manifests.map(&:file_path)
          expect(all_manifests.uniq.count).to eq(6)
        end

        it "returns an uneven page when there are leftover manifests (no static manifests)" do
          t = pagination_test_setup(repository_id: repository_id, snapshot_manifests: 5, per_page: 3)
          page_1 = t[:get_page].call(1)
          expect(page_1.page_metadata.last).to eq(2)
          expect(page_1.changed_manifests.uniq.count).to eq(5)

          page_2 = t[:get_page].call(2)
          expect(page_2.page_metadata.last).to eq(2)
          expect(page_2.changed_manifests.count).to eq(5)

          all_manifests = page_1.changed_manifests.map(&:file_path) + page_2.changed_manifests.map(&:file_path)
          expect(all_manifests.uniq.count).to eq(5)
        end
      end
    end

    it "returns a Twirp error when there is a missing repo id" do
      req = basic_diff_request
      req.repository_id = 0

      response = handler.get_snapshots_diff(req, {})

      expect(response.class).to eq(Twirp::Error)
      expect(response.msg).to eq("is mandatory")
      expect(response.meta[:argument]).to eq("repository_id")
    end

    it "returns a Twirp error when there is a missing base sha" do
      req = basic_diff_request
      req.base_sha = ""

      response = handler.get_snapshots_diff(req, {})

      expect(response.class).to eq(Twirp::Error)
      expect(response.msg).to eq("is mandatory")
      expect(response.meta[:argument]).to eq("base_sha")
    end

    it "returns a Twirp error when there is a missing target sha" do
      req = basic_diff_request
      req.target_sha = ""

      response = handler.get_snapshots_diff(req, {})

      expect(response.class).to eq(Twirp::Error)
      expect(response.msg).to eq("is mandatory")
      expect(response.meta[:argument]).to eq("target_sha")
    end
  end

  # ad-hoc struct to mimic GetBlob responses
  MockBlobData = Struct.new(:content)
  def mock_manifest_blob(repository_id:, blob_id:, content:)
    data = MockBlobData.new(content)
    allow(noop_provider).to receive(:get_blob).with({ repository_id: repository_id, oid: blob_id }).and_return(data)
  end

  # ad-hoc structs to mimic GetTree responses
  RequestTreeEntry = Struct.new(:path, :oid)
  RequestTree = Struct.new(:tree_entries)
  def mock_commit_tree(repository_id:, commit_id:, files:)
    allow(noop_provider) .to receive(:get_tree).with({ repository_id: repository_id, commit_id: commit_id }).and_return(
      RequestTree.new(files.map { |file| RequestTreeEntry.new(file[:path], file[:blob_id]) })
    )
  end

  # Automates setup for the relatively complicated pagination tests
  # involving data from ds-api and dg-api.
  # `req_at_page` and `get_page` are both lambdas, so they must be called
  # like `req_at_page.call(page)`.
  def pagination_test_setup(repository_id: 444, static_manifests: 0, snapshot_manifests: 0, per_page: 5, decompose_updates: true)
    ret = {
      ds_api_client: nil,
      handler: nil,
      req_at_page: nil,
      get_page: nil,
    }
    base_manifests, target_manifests = generate_manifest_blobs(repository_id: repository_id, num_of_manifests: static_manifests)
    ret[:ds_api_client] = DSAPIClientTonsofChanges.new(num_of_manifests: snapshot_manifests)
    ret[:handler] = SnapshotService::V1::Handler.new(
      blob_operations_provider: noop_provider,
      snapshots_client: ret[:ds_api_client],
    )
    ret[:req_at_page] = ->(page) {
      DependencyGraphAPI::V1::GetSnapshotsDiffRequest.new(
       repository_id: repository_id,
       base_sha: "paginationbasesha455",
       target_sha: "paginationtargetsha455",
       limit_to_files: {
         base: base_manifests,
         target: target_manifests,
       },
       page_metadata: {
         page: page,
         per_page: per_page,
       },
       decompose_updates: decompose_updates,
       include_dependency_snapshots: true,
     )
    }
    ret[:get_page] = ->(page) { ret[:handler].get_snapshots_diff(ret[:req_at_page].call(page), {}) }

    ret
  end

  # Given a diff response, return just the gemfile changes.
  # In a typical setup, these will be the mass-produced static manifest changes.
  def select_gemfiles(diff_response)
    diff_response.changed_manifests.select { |m| m.file_path.end_with? "Gemfile" }
  end

  # Given a diff response, return just the package-lock.json changes.
  # In a typical setup, these will be the mass-produced snapshot manifest changes.
  def select_package_locks(diff_response)
    diff_response.changed_manifests.select { |m| m.file_path.end_with? "package-lock.json" }
  end

  # A mock DS-API client that returns N manifests with two changes each, where N is the `num_of_manifests` parameter.
  # Every manifest is a package-lock.json file in a folder named `folderN`, where N is the manifest index.
  # Every manifest has two changes: a removed dependency (react) and an added dependency (jquery).
  class DSAPIClientTonsofChanges < DependencyGraphAPI::DependencySnapshotsAPI::SnapshotsClient
    def initialize(num_of_manifests: 100)
      @num_of_manifests = num_of_manifests
    end

    def get_snapshot_diff(repository_id, base_sha, target_sha)
      snapshot_metadata = {
          snapshot_id: 3,
          correlator: "test",
          detector: "generator of many changes",
      }

      changes = []
      @num_of_manifests.times do |i|
        changes.push(Github::DependencySnapshotsApi::GetSnapshotDiffResponse::DependencyChange.new(
          change_type: :REMOVED,
          snapshot_metadata: Github::DependencySnapshotsApi::GetSnapshotDiffResponse::SnapshotMetadata.new(
            **snapshot_metadata
          ),
          manifest: "folder#{i}/package-lock.json",
          ecosystem: "npm",
          name: "react",
          version: i.to_s,
          package_url: "pkg:npm/react@#{i}"))

        changes.push(Github::DependencySnapshotsApi::GetSnapshotDiffResponse::DependencyChange.new(
          change_type: :ADDED,
          snapshot_metadata: Github::DependencySnapshotsApi::GetSnapshotDiffResponse::SnapshotMetadata.new(
            **snapshot_metadata
          ),
          manifest: "folder#{i}/package-lock.json",
          ecosystem: "npm",
          name: "jquery",
          version: i.to_s,
          package_url: "pkg:npm/jquery@#{i}"))
      end

      Twirp::ClientResp.new(
        data: Github::DependencySnapshotsApi::GetSnapshotDiffResponse.new(dependency_changes: changes)
      )
    end
  end

  class DSAPIClientMismatchDiff < DependencyGraphAPI::DependencySnapshotsAPI::SnapshotsClient
    def get_snapshot_diff(repository_id, base_sha, target_sha)
      # reuse the body from basic diff
      h = DSAPIClientBasicDiff.new
      old_resp = h.get_snapshot_diff(repository_id, base_sha, target_sha)
      Twirp::ClientResp.new(
        data: Github::DependencySnapshotsApi::GetSnapshotDiffResponse.new(
          dependency_changes: old_resp.data.dependency_changes.to_a,
          base_snapshots_compared: 1,
          head_snapshots_compared: 2,
        )
      )
    end
  end

  class DSAPIClientUnknownManifest < DependencyGraphAPI::DependencySnapshotsAPI::SnapshotsClient
    def get_snapshot_diff(repository_id, base_sha, target_sha)
      snapshot_metadata = {
          snapshot_id: 3,
          correlator: "build",
          detector: "funny manifest finder",
      }
      Twirp::ClientResp.new(
        data:
          Github::DependencySnapshotsApi::GetSnapshotDiffResponse.new(
            dependency_changes: [
              Github::DependencySnapshotsApi::GetSnapshotDiffResponse::DependencyChange.new(
                change_type: :ADDED,
                snapshot_metadata: Github::DependencySnapshotsApi::GetSnapshotDiffResponse::SnapshotMetadata.new(
                  **snapshot_metadata
                ),
                manifest: "anything can be a manifest",
                ecosystem: "npm",
                name: "jquery",
                version: "2.0.0",
                package_url: "pkg:npm/jquery@2.0.0",
              ),
              Github::DependencySnapshotsApi::GetSnapshotDiffResponse::DependencyChange.new(
                change_type: :ADDED,
                snapshot_metadata: Github::DependencySnapshotsApi::GetSnapshotDiffResponse::SnapshotMetadata.new(
                  **snapshot_metadata
                ),
                manifest: "anything can be a manifest",
                ecosystem: "rubygems",
                name: "rails",
                version: "4.1.9",
                package_url: "pkg:gem/rails@4.1.9",
              ),
              Github::DependencySnapshotsApi::GetSnapshotDiffResponse::DependencyChange.new(
                change_type: :REMOVED,
                snapshot_metadata: Github::DependencySnapshotsApi::GetSnapshotDiffResponse::SnapshotMetadata.new(
                  **snapshot_metadata
                ),
                manifest: "anything can be a manifest",
                ecosystem: "npm",
                name: "jquery",
                version: "1.0.0",
                package_url: "pkg:npm/jquery@1.0.0",
              )
            ]
          )
        )
    end
  end

  class DSAPIClientScopeChange < DependencyGraphAPI::DependencySnapshotsAPI::SnapshotsClient
    def get_snapshot_diff(repository_id, base_sha, target_sha)
      snapshot_metadata = {
          snapshot_id: 3,
          correlator: "build",
          detector: "ruby script",
      }
      Twirp::ClientResp.new(
        data:
          Github::DependencySnapshotsApi::GetSnapshotDiffResponse.new(
            dependency_changes: [
              Github::DependencySnapshotsApi::GetSnapshotDiffResponse::DependencyChange.new(
                change_type: :ADDED,
                snapshot_metadata: Github::DependencySnapshotsApi::GetSnapshotDiffResponse::SnapshotMetadata.new(
                  **snapshot_metadata
                ),
                manifest: "package-lock.json",
                ecosystem: "npm",
                name: "jquery",
                version: "2.0.0",
                package_url: "pkg:npm/jquery@2.0.0",
                scope: "RUNTIME"
              ),
              Github::DependencySnapshotsApi::GetSnapshotDiffResponse::DependencyChange.new(
                change_type: :REMOVED,
                snapshot_metadata: Github::DependencySnapshotsApi::GetSnapshotDiffResponse::SnapshotMetadata.new(
                  **snapshot_metadata
                ),
                manifest: "package-lock.json",
                ecosystem: "npm",
                name: "jquery",
                version: "1.0.0",
                package_url: "pkg:npm/jquery@1.0.0",
                scope: "DEVELOPMENT"
              )
            ]
          )
        )
    end
  end

  class DSAPIClientBasicDiff < DependencyGraphAPI::DependencySnapshotsAPI::SnapshotsClient
    def get_snapshot_diff(repository_id, base_sha, target_sha)
      snapshot_metadata = {
          snapshot_id: 3,
          correlator: "build",
          detector: "ruby script",
      }
      Twirp::ClientResp.new(
        data:
          Github::DependencySnapshotsApi::GetSnapshotDiffResponse.new(
            dependency_changes: [
              Github::DependencySnapshotsApi::GetSnapshotDiffResponse::DependencyChange.new(
                change_type: :ADDED,
                snapshot_metadata: Github::DependencySnapshotsApi::GetSnapshotDiffResponse::SnapshotMetadata.new(
                  **snapshot_metadata
                ),
                manifest: "package-lock.json",
                ecosystem: "npm",
                name: "jquery",
                version: "2.0.0",
                package_url: "pkg:npm/jquery@2.0.0",
              ),
              Github::DependencySnapshotsApi::GetSnapshotDiffResponse::DependencyChange.new(
                change_type: :REMOVED,
                snapshot_metadata: Github::DependencySnapshotsApi::GetSnapshotDiffResponse::SnapshotMetadata.new(
                  **snapshot_metadata
                ),
                manifest: "package-lock.json",
                ecosystem: "npm",
                name: "jquery",
                version: "1.0.0",
                package_url: "pkg:npm/jquery@1.0.0",
              )
            ]
          )
        )
    end
  end

  class DSAPIClientMavenDiff < DependencyGraphAPI::DependencySnapshotsAPI::SnapshotsClient
    def get_snapshot_diff(repository_id, base_sha, target_sha)
      snapshot_metadata = {
          snapshot_id: 4,
          correlator: "build",
          detector: "whatever",
      }
      Twirp::ClientResp.new(
        data:
          Github::DependencySnapshotsApi::GetSnapshotDiffResponse.new(
            dependency_changes: [
              Github::DependencySnapshotsApi::GetSnapshotDiffResponse::DependencyChange.new(
                change_type: :ADDED,
                snapshot_metadata: Github::DependencySnapshotsApi::GetSnapshotDiffResponse::SnapshotMetadata.new(
                  **snapshot_metadata
                ),
                manifest: "build.gradle",
                ecosystem: "maven",
                name: "liquibase-core",
                version: "4.7.1",
                package_url: "pkg:maven/org.liquibase/liquibase-core@4.7.1",
              ),
            ]
          )
        )
    end
  end

  class DSAPIClientPackageJSONDiff < DependencyGraphAPI::DependencySnapshotsAPI::SnapshotsClient
    def get_snapshot_diff(repository_id, base_sha, target_sha)
      snapshot_metadata = {
          snapshot_id: 5,
          correlator: "build",
          detector: "whatever",
      }
      Twirp::ClientResp.new(
        data:
          Github::DependencySnapshotsApi::GetSnapshotDiffResponse.new(
            dependency_changes: [
              Github::DependencySnapshotsApi::GetSnapshotDiffResponse::DependencyChange.new(
                change_type: :ADDED,
                snapshot_metadata: Github::DependencySnapshotsApi::GetSnapshotDiffResponse::SnapshotMetadata.new(
                  **snapshot_metadata
                ),
                manifest: "package.json",
                ecosystem: "npm",
                name: "snappy",
                version: "6.2.1",
                package_url: "pkg:npm/snappy@6.2.1",
              ),
            ]
          )
        )
    end
  end

  class DSAPIClientDiff404 < DependencyGraphAPI::DependencySnapshotsAPI::SnapshotsClient
    # meta is a hash of string->string that will be included in the Twirp error
    def initialize(meta: nil)
      @meta = meta || {}
    end

    def get_snapshot_diff(repository_id, base_sha, target_sha)
      Twirp::ClientResp.new(
        error: Twirp::Error.new(
          :not_found,
          "no snapshots found for head commit #{target_sha}",
          @meta
          )
        )
    end
  end

  def generate_manifest_diff(package_manager, filepath, dependencies)
    DependencyGraphAPI::V1::GetSnapshotsDiffResponse::ManifestDiff.new(
      type: package_manager,
      file_path: filepath,
      dependencies: dependencies
    )
  end

  def generate_dependency_diff(package_manager, name, change_type, scope, base_version: "", target_version: "", gh_vuln_range_ids: [])
    DependencyGraphAPI::V1::GetSnapshotsDiffResponse::ManifestDiff::DependencyDiff.new(
      name: name,
      base_version: base_version,
      target_version: target_version,
      change_type: change_type,
      scope: scope,
      github_vulnerability_range_ids: gh_vuln_range_ids,
      base_purl: generate_purl(package_manager, name, base_version),
      target_purl: generate_purl(package_manager, name, target_version),
    )
  end

  def generate_purl(package_manager, name, version)
    PackageUrls::PackageUrl.from_package_release(package_manager: package_manager, name: name, version: version).to_purl
  end

  def generate_manifest_blobs(repository_id:, num_of_manifests: 20, base_blob_id_prefix: "baseblob123abc", target_blob_id_prefix: "targetblob123abc")
    base_manifests, target_manifests = [], []

    (1..num_of_manifests).each do |i|
      base_manifest = {
        path: "folder#{i}/Gemfile",
        blob_id: base_blob_id_prefix + i.to_s,
      }

      base_manifests.push(base_manifest)

      mock_manifest_blob(
        repository_id: repository_id,
        blob_id: base_manifest[:blob_id],
        content: <<-eos
          gem "rails", "5.0.#{i}" # will be removed
        eos
      )

      target_manifest = {
        path: "folder#{i}/Gemfile",
        blob_id: target_blob_id_prefix + i.to_s
      }

      target_manifests.push(target_manifest)

      mock_manifest_blob(
        repository_id: repository_id,
        blob_id: target_manifest[:blob_id],
        content: <<-eos
          gem "httparty", "1.0.#{i}" # added
        eos
      )
    end

    return base_manifests, target_manifests
  end
end

# Helper to mock Spokes get_changed_manifests response
def mock_spokes_get_changed_manifests(provider:, repository_id:, base_oid:, target_oid:, result_base:, result_target:)
  spokes_response = [
    result_base.map { |m| m.slice(:path, :blob_id) },
    result_target.map { |m| m.slice(:path, :blob_id) }
  ]
  allow(provider).to receive(:get_changed_manifests)
    .with(repository_id: repository_id, base_oid: base_oid, target_oid: target_oid)
    .and_return(spokes_response)

  allow(provider).to receive(:name).and_return("SpokesProvider (get_changed_manifests)")
end
