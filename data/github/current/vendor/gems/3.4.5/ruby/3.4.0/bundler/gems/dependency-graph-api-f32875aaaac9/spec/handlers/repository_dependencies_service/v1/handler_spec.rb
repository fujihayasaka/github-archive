require "dependency-snapshots-api-proto"
require "rails_helper"

RSpec.shared_examples "a dependency search request" do
  describe "search_dependencies_for_repository" do
    before do
      DependencyGraph.flipper.disable(:dependency_graph_npm_dgp_repo_insights)
      DependencyGraph.flipper.enable(:dependency_graph_snapshot_transitive_labels)
      DependencyGraph.flipper.enable(:dependency_graph_snapshot_arbitrary_ecosystems)
    end

    it "returns empty result set if repository not found" do
      resp = handler.search_dependencies_for_repository(DependencyGraphAPI::V1::SearchDependenciesForRepositoryRequest.new({
        repository_id: 1,
        page: 1,
        per_page: 20
      }), {})

      expect(resp.total_results).to eq(0)
      expect(resp.results).to eq([])
      expect(resp.package_managers).to eq([])
    end

    it "pages over results" do
      Package.create!(package_manager: :npm, name: "jquery", repository_id: 1, repository_id_certainty: 90)
      Package.create!(package_manager: :npm, name: "react", repository_id: 2)

      repo = Repository.create!(github_repository_id: 1)

      factory.given_manifest(repository: repo, filename: "package-lock.json", last_pushed_at: Time.utc(2023, 01, 01))
        .add_dependency("react", "= 1.0.0")
        .add_dependency("react", "= 2.0.0")
        .add_dependency("jquery", "= 3.0.0")

      allow(Instrument).to receive(:increment).and_call_original

      page_1_resp = handler.search_dependencies_for_repository(DependencyGraphAPI::V1::SearchDependenciesForRepositoryRequest.new({
        repository_id: 1,
        page: 1,
        per_page: 2
      }), {})

      expect(page_1_resp.repository_has_snapshots).to eq(false)
      expect(page_1_resp.total_results).to eq(3)
      expect(page_1_resp.package_managers).to eq([:PACKAGE_MANAGER_NPM])
      expect(page_1_resp.results.map(&:to_h)).to eq([
        { package_manager: :PACKAGE_MANAGER_NPM,
          package_name: "jquery",
          unsupported_package_manager_name: "",
          requirements: "= 3.0.0",
          manifest_path: "package-lock.json",
          scope: :SCOPE_UNKNOWN,
          relationship: :RELATIONSHIP_UNKNOWN,
          repository_id: 1,
          license: "",
          scanned_at: { nanos: 0, seconds: 1672531200 },
          scanned_by: :DG,
          snapshot_detector_name: "",
          vulnerable_version_range_ids: [],
          root_ancestors: []
        },
        { package_manager: :PACKAGE_MANAGER_NPM,
          package_name: "react",
          unsupported_package_manager_name: "",
          requirements: "= 1.0.0",
          manifest_path: "package-lock.json",
          scope: :SCOPE_UNKNOWN,
          relationship: :RELATIONSHIP_UNKNOWN,
          repository_id: 2,
          license: "",
          scanned_at: { nanos: 0, seconds: 1672531200 },
          scanned_by: :DG,
          snapshot_detector_name: "",
          vulnerable_version_range_ids: [],
          root_ancestors: []
        }
      ])

      expect(Instrument).to have_received(:increment).with("package_to_repo_mapping.viewed",
        package_manager: "npm",
        certainty: 0
      )

      expect(Instrument).to have_received(:increment).with("package_to_repo_mapping.viewed",
        package_manager: "npm",
        certainty: 90
      )

      page_2_resp = handler.search_dependencies_for_repository(DependencyGraphAPI::V1::SearchDependenciesForRepositoryRequest.new({
        repository_id: 1,
        page: 2,
        per_page: 2
      }), {})

      expect(page_2_resp.results.map(&:to_h)).to eq([
        { package_manager: :PACKAGE_MANAGER_NPM,
          package_name: "react",
          unsupported_package_manager_name: "",
          requirements: "= 2.0.0",
          manifest_path: "package-lock.json",
          scope: :SCOPE_UNKNOWN,
          relationship: :RELATIONSHIP_UNKNOWN,
          repository_id: 2,
          license: "",
          scanned_at: { nanos: 0, seconds: 1672531200 },
          scanned_by: :DG,
          snapshot_detector_name: "",
          vulnerable_version_range_ids: [],
          root_ancestors: []
        },
      ])
    end


    it "filters searched dependencies by manifest path" do
      repo = Repository.create!(github_repository_id: 1)

      factory.given_manifest(repository: repo, filename: "package-lock.json", last_pushed_at: Time.utc(2023, 01, 01))
        .add_dependency("react", "= 1.0.0")
        .add_dependency("jquery", "= 3.0.0")

      factory.given_manifest(repository: repo, filename: "Gemfile", last_pushed_at: Time.utc(2023, 01, 01))
          .add_dependency("rails", "= 1.0.0")

      package_json_resp = handler.search_dependencies_for_repository(DependencyGraphAPI::V1::SearchDependenciesForRepositoryRequest.new({
        repository_id: 1,
        page: 1,
        per_page: 20,
        manifest_path: "package-lock.json"
      }), {})

      expect(package_json_resp.total_results).to eq(2)
      expect(package_json_resp.package_managers).to eq([:PACKAGE_MANAGER_RUBYGEMS, :PACKAGE_MANAGER_NPM])
      expect(package_json_resp.results.map(&:to_h)).to eq([
        { package_manager: :PACKAGE_MANAGER_NPM,
          package_name: "jquery",
          unsupported_package_manager_name: "",
          requirements: "= 3.0.0",
          manifest_path: "package-lock.json",
          scope: :SCOPE_UNKNOWN,
          relationship: :RELATIONSHIP_UNKNOWN,
          repository_id: 0,
          license: "",
          scanned_at: { nanos: 0, seconds: 1672531200 },
          scanned_by: :DG,
          snapshot_detector_name: "",
          vulnerable_version_range_ids: [],
          root_ancestors: []
        },
        { package_manager: :PACKAGE_MANAGER_NPM,
          package_name: "react",
          unsupported_package_manager_name: "",
          requirements: "= 1.0.0",
          manifest_path: "package-lock.json",
          scope: :SCOPE_UNKNOWN,
          relationship: :RELATIONSHIP_UNKNOWN,
          repository_id: 0,
          license: "",
          scanned_at: { nanos: 0, seconds: 1672531200 },
          scanned_by: :DG,
          snapshot_detector_name: "",
          vulnerable_version_range_ids: [],
          root_ancestors: []
        }
      ])

      gemfile_resp = handler.search_dependencies_for_repository(DependencyGraphAPI::V1::SearchDependenciesForRepositoryRequest.new({
        repository_id: 1,
        page: 1,
        per_page: 20,
        manifest_path: "Gemfile"
      }), {})

      expect(gemfile_resp.total_results).to eq(1)
      expect(gemfile_resp.package_managers).to eq([:PACKAGE_MANAGER_RUBYGEMS, :PACKAGE_MANAGER_NPM])
      expect(gemfile_resp.results.map(&:to_h)).to eq([
        { package_manager: :PACKAGE_MANAGER_RUBYGEMS,
          package_name: "rails",
          unsupported_package_manager_name: "",
          requirements: "= 1.0.0",
          manifest_path: "Gemfile",
          scope: :SCOPE_UNKNOWN,
          relationship: :RELATIONSHIP_UNKNOWN,
          repository_id: 0,
          license: "",
          scanned_at: { nanos: 0, seconds: 1672531200 },
          scanned_by: :DG,
          snapshot_detector_name: "",
          vulnerable_version_range_ids: [],
          root_ancestors: []
        }
      ])
    end

    it "filters searched dependencies by ecosystem" do
      repo = Repository.create!(github_repository_id: 1)

      factory.given_manifest(repository: repo, filename: "package-lock.json", last_pushed_at: Time.utc(2023, 01, 01))
        .add_dependency("react", "= 1.0.0")
        .add_dependency("jquery", "= 3.0.0")

      factory.given_manifest(repository: repo, filename: "Gemfile", last_pushed_at: Time.utc(2023, 01, 01))
          .add_dependency("rails", "= 1.0.0")

      npm_resp = handler.search_dependencies_for_repository(DependencyGraphAPI::V1::SearchDependenciesForRepositoryRequest.new({
        repository_id: 1,
        page: 1,
        per_page: 20,
        ecosystem_filter: [:PACKAGE_MANAGER_NPM]
      }), {})

      expect(npm_resp.total_results).to eq(2)
      expect(npm_resp.package_managers).to eq([:PACKAGE_MANAGER_RUBYGEMS, :PACKAGE_MANAGER_NPM])
      expect(npm_resp.results.map(&:to_h)).to eq([
        { package_manager: :PACKAGE_MANAGER_NPM,
          package_name: "jquery",
          unsupported_package_manager_name: "",
          requirements: "= 3.0.0",
          manifest_path: "package-lock.json",
          scope: :SCOPE_UNKNOWN,
          relationship: :RELATIONSHIP_UNKNOWN,
          repository_id: 0,
          license: "",
          scanned_at: { nanos: 0, seconds: 1672531200 },
          scanned_by: :DG,
          snapshot_detector_name: "",
          vulnerable_version_range_ids: [],
          root_ancestors: []
        },
        { package_manager: :PACKAGE_MANAGER_NPM,
          package_name: "react",
          unsupported_package_manager_name: "",
          requirements: "= 1.0.0",
          manifest_path: "package-lock.json",
          scope: :SCOPE_UNKNOWN,
          relationship: :RELATIONSHIP_UNKNOWN,
          repository_id: 0,
          license: "",
          scanned_at: { nanos: 0, seconds: 1672531200 },
          scanned_by: :DG,
          snapshot_detector_name: "",
          vulnerable_version_range_ids: [],
          root_ancestors: []
        }
      ])

      rubygems_resp = handler.search_dependencies_for_repository(DependencyGraphAPI::V1::SearchDependenciesForRepositoryRequest.new({
        repository_id: 1,
        page: 1,
        per_page: 20,
        ecosystem_filter: [:PACKAGE_MANAGER_RUBYGEMS]
      }), {})

      expect(rubygems_resp.total_results).to eq(1)
      expect(rubygems_resp.package_managers).to eq([:PACKAGE_MANAGER_RUBYGEMS, :PACKAGE_MANAGER_NPM])
      expect(rubygems_resp.results.map(&:to_h)).to eq([
        { package_manager: :PACKAGE_MANAGER_RUBYGEMS,
          package_name: "rails",
          unsupported_package_manager_name: "",
          requirements: "= 1.0.0",
          manifest_path: "Gemfile",
          scope: :SCOPE_UNKNOWN,
          relationship: :RELATIONSHIP_UNKNOWN,
          repository_id: 0,
          license: "",
          scanned_at: { nanos: 0, seconds: 1672531200 },
          scanned_by: :DG,
          snapshot_detector_name: "",
          vulnerable_version_range_ids: [],
          root_ancestors: []
        }
      ])

      multi_ecosystem_resp = handler.search_dependencies_for_repository(DependencyGraphAPI::V1::SearchDependenciesForRepositoryRequest.new({
        repository_id: 1,
        page: 1,
        per_page: 20,
        ecosystem_filter: [:PACKAGE_MANAGER_NPM, :PACKAGE_MANAGER_RUBYGEMS]
      }), {})

      expect(multi_ecosystem_resp.total_results).to eq(3)
      expect(multi_ecosystem_resp.package_managers).to eq([:PACKAGE_MANAGER_RUBYGEMS, :PACKAGE_MANAGER_NPM])
      expect(multi_ecosystem_resp.results.map(&:to_h)).to eq([
         { package_manager: :PACKAGE_MANAGER_NPM,
           package_name: "jquery",
           unsupported_package_manager_name: "",
           requirements: "= 3.0.0",
           manifest_path: "package-lock.json",
           scope: :SCOPE_UNKNOWN,
           relationship: :RELATIONSHIP_UNKNOWN,
           repository_id: 0,
           license: "",
           scanned_at: { nanos: 0, seconds: 1672531200 },
           scanned_by: :DG,
           snapshot_detector_name: "",
           vulnerable_version_range_ids: [],
           root_ancestors: []
         },
         { package_manager: :PACKAGE_MANAGER_NPM,
           package_name: "react",
           unsupported_package_manager_name: "",
           requirements: "= 1.0.0",
           manifest_path: "package-lock.json",
           scope: :SCOPE_UNKNOWN,
           relationship: :RELATIONSHIP_UNKNOWN,
           repository_id: 0,
           license: "",
           scanned_at: { nanos: 0, seconds: 1672531200 },
           scanned_by: :DG,
           snapshot_detector_name: "",
           vulnerable_version_range_ids: [],
           root_ancestors: []
         },
         { package_manager: :PACKAGE_MANAGER_RUBYGEMS,
           package_name: "rails",
           unsupported_package_manager_name: "",
           requirements: "= 1.0.0",
           manifest_path: "Gemfile",
           scope: :SCOPE_UNKNOWN,
           relationship: :RELATIONSHIP_UNKNOWN,
           repository_id: 0,
           license: "",
           scanned_at: { nanos: 0, seconds: 1672531200 },
           scanned_by: :DG,
           snapshot_detector_name: "",
           vulnerable_version_range_ids: [],
           root_ancestors: []
         }
       ])
    end

    it "searches by package name" do
      handler = RepositoryDependenciesService::V1::Handler.new(
        dependencies_client: SimpleTestDependenciesClient.new,
        blob_operations_provider: noop_blob_operations_provider
      )

      factory.given_package("react", "1.0.0", Types::PackageManager[:npm])
        .update_package_release(license: "mit")
      factory.given_package("react", "2.0.0", Types::PackageManager[:npm])
        .update_package_release(license: "cc")
      factory.given_package("jquery", "3.0.0", Types::PackageManager[:npm])
        .update_package_release(license: "gpl")
      factory.given_package("@actions/core", "1.1.9", Types::PackageManager[:npm])
        .update_package_release(license: "mit")
      factory.given_package("@actions/http-client", "1.0.7", Types::PackageManager[:npm])
        .update_package_release(license: "gpl")

      repo = Repository.create!(github_repository_id: 1)

      factory.given_manifest(repository: repo, filename: "package-lock.json", last_pushed_at: Time.utc(2023, 01, 01))
        .add_dependency("react", "= 1.0.0")
        .add_dependency("react", "= 2.0.0")
        .add_dependency("jquery", "= 3.0.0")

      resp = handler.search_dependencies_for_repository(DependencyGraphAPI::V1::SearchDependenciesForRepositoryRequest.new({
        repository_id: 1,
        page: 1,
        per_page: 20,
        query: "react"
      }), {})

      expect(resp.repository_has_snapshots).to eq(true)
      expect(resp.results.map(&:to_h)).to eq([
        { package_manager: :PACKAGE_MANAGER_NPM,
          package_name: "react",
          unsupported_package_manager_name: "",
          requirements: "= 1.0.0",
          manifest_path: "package-lock.json",
          scope: :SCOPE_UNKNOWN,
          relationship: :RELATIONSHIP_UNKNOWN,
          repository_id: 0,
          license: "mit",
          scanned_at: { nanos: 0, seconds: 1672531200 },
          scanned_by: :DG,
          snapshot_detector_name: "",
          vulnerable_version_range_ids: [],
          root_ancestors: []
        },
        { package_manager: :PACKAGE_MANAGER_NPM,
          package_name: "react",
          unsupported_package_manager_name: "",
          requirements: "= 2.0.0",
          manifest_path: "package-lock.json",
          scope: :SCOPE_UNKNOWN,
          relationship: :RELATIONSHIP_UNKNOWN,
          repository_id: 0,
          license: "cc",
          scanned_at: { nanos: 0, seconds: 1672531200 },
          scanned_by: :DG,
          snapshot_detector_name: "",
          vulnerable_version_range_ids: [],
          root_ancestors: []
        }
      ])

      resp = handler.search_dependencies_for_repository(DependencyGraphAPI::V1::SearchDependenciesForRepositoryRequest.new({
        repository_id: 1,
        page: 1,
        per_page: 20,
        query: "jquery"
      }), {})

      expect(resp.repository_has_snapshots).to eq(true)
      expect(resp.results.map(&:to_h)).to eq([
        { package_manager: :PACKAGE_MANAGER_NPM,
          package_name: "jquery",
          unsupported_package_manager_name: "",
          requirements: "= 3.0.0",
          manifest_path: "package-lock.json",
          scope: :SCOPE_UNKNOWN,
          relationship: :RELATIONSHIP_UNKNOWN,
          repository_id: 0,
          license: "gpl",
          scanned_at: { nanos: 0, seconds: Time.utc(2023, 01, 01).to_i },
          scanned_by: :DG,
          snapshot_detector_name: "",
          vulnerable_version_range_ids: [],
          root_ancestors: []
        }
      ])

      resp = handler.search_dependencies_for_repository(DependencyGraphAPI::V1::SearchDependenciesForRepositoryRequest.new({
        repository_id: 1,
        page: 1,
        per_page: 20,
        query: "@actions"
      }), {})

      expect(resp.repository_has_snapshots).to eq(true)
      expect(resp.results.map(&:to_h)).to eq([
        { package_manager: :PACKAGE_MANAGER_NPM,
          package_name: "@actions/core",
          unsupported_package_manager_name: "",
          requirements: "= 1.1.9",
          manifest_path: "/some/path/package-lock.json",
          scope: :SCOPE_UNKNOWN,
          relationship: :RELATIONSHIP_DIRECT,
          repository_id: 0,
          license: "mit",
          scanned_at: { nanos: 0, seconds: Time.utc(2023, 01, 01).to_i },
          scanned_by: :DS,
          snapshot_detector_name: "test-detector",
          vulnerable_version_range_ids: [],
          root_ancestors: []
        },
        { package_manager: :PACKAGE_MANAGER_NPM,
          package_name: "@actions/http-client",
          unsupported_package_manager_name: "",
          requirements: "= 1.0.7",
          manifest_path: "/some/path/package-lock.json",
          scope: :SCOPE_UNKNOWN,
          relationship: :RELATIONSHIP_TRANSITIVE,
          repository_id: 0,
          license: "gpl",
          scanned_at: { nanos: 0, seconds: Time.utc(2023, 01, 01).to_i },
          scanned_by: :DS,
          snapshot_detector_name: "test-detector",
          vulnerable_version_range_ids: [],
          root_ancestors: [{ package_name: "@actions/core", requirements: "1.0.7", relationship: :PARENT }]
        }
      ])

      DependencyGraph.flipper.disable(:dependency_graph_snapshot_transitive_labels)
      resp = handler.search_dependencies_for_repository(DependencyGraphAPI::V1::SearchDependenciesForRepositoryRequest.new({
        repository_id: 1,
        page: 1,
        per_page: 20,
        query: "@actions"
      }), {})

      expect(resp.repository_has_snapshots).to eq(true)
      expect(resp.results.map(&:to_h)).to eq([
        { package_manager: :PACKAGE_MANAGER_NPM,
          package_name: "@actions/core",
          unsupported_package_manager_name: "",
          requirements: "= 1.1.9",
          manifest_path: "/some/path/package-lock.json",
          scope: :SCOPE_UNKNOWN,
          relationship: :RELATIONSHIP_UNKNOWN,
          repository_id: 0,
          license: "mit",
          scanned_at: { nanos: 0, seconds: Time.utc(2023, 01, 01).to_i },
          scanned_by: :DS,
          snapshot_detector_name: "test-detector",
          vulnerable_version_range_ids: [],
          root_ancestors: []
        },
        { package_manager: :PACKAGE_MANAGER_NPM,
          package_name: "@actions/http-client",
          unsupported_package_manager_name: "",
          requirements: "= 1.0.7",
          manifest_path: "/some/path/package-lock.json",
          scope: :SCOPE_UNKNOWN,
          relationship: :RELATIONSHIP_UNKNOWN,
          repository_id: 0,
          license: "gpl",
          scanned_at: { nanos: 0, seconds: Time.utc(2023, 01, 01).to_i },
          scanned_by: :DS,
          snapshot_detector_name: "test-detector",
          vulnerable_version_range_ids: [],
          root_ancestors: []
        }
      ])
    end

    it "sorts dependencies by vulnerability severity" do
      handler = RepositoryDependenciesService::V1::Handler.new(
        dependencies_client: SimpleTestDependenciesClient.new,
        blob_operations_provider: noop_blob_operations_provider
      )

      repo = Repository.create!(github_repository_id: 1)

      factory.given_manifest(repository: repo, path: "hello", filename: "package-lock.json", last_pushed_at: Time.utc(2023, 01, 01))
        .add_dependency("react", "= 1.0.0")
        .add_dependency("react", "= 2.0.0")
        .add_dependency("jquery", "= 3.0.0")
        .add_dependency("apple", "= 1.0.0")

      dependabot_alerts = [
        {
          vulnerable_manifest_path: "hello/package-lock.json",
          vulnerable_version_range_affects: "ApPle",
          vulnerable_requirements: "= 1.0.0",
          vulnerability_severity: :SEVERITY_CRITICAL
        },
        {
          vulnerable_manifest_path: "hello/package-lock.json",
          vulnerable_version_range_affects: "react",
          vulnerable_requirements: "= 1.0.0",
          vulnerability_severity: :SEVERITY_CRITICAL
        },
        {
          vulnerable_manifest_path: "hello/package-lock.json",
          vulnerable_version_range_affects: "react",
          vulnerable_requirements: "= 1.0.0",
          vulnerability_severity: :SEVERITY_LOW
        },
        {
          vulnerable_manifest_path: "hello/package-lock.json",
          vulnerable_version_range_affects: "jquery",
          vulnerable_requirements: "= 3.0.0",
          vulnerability_severity: :SEVERITY_CRITICAL
        },
        {
          vulnerable_manifest_path: "hello/package-lock.json",
          vulnerable_version_range_affects: "jquery",
          vulnerable_requirements: "= 3.0.0",
          vulnerability_severity: :SEVERITY_CRITICAL
        },
        {
          vulnerable_manifest_path: "/some/path/package-lock.json",
          vulnerable_version_range_affects: "@actions/http-client",
          vulnerable_requirements: "= 1.0.7",
          vulnerability_severity: :SEVERITY_CRITICAL
        },
        {
          vulnerable_manifest_path: "/some/path/package-lock.json",
          vulnerable_version_range_affects: "@actions/core",
          vulnerable_requirements: "= 1.1.9",
          vulnerability_severity: :SEVERITY_MODERATE
        },
      ]

      resp = handler.search_dependencies_for_repository(DependencyGraphAPI::V1::SearchDependenciesForRepositoryRequest.new({
        repository_id: 1,
        page: 1,
        per_page: 20,
        dependabot_alerts: dependabot_alerts
      }), {})

      expected_results = [
        { package_manager: :PACKAGE_MANAGER_NPM,
          package_name: "jquery",
          unsupported_package_manager_name: "",
          requirements: "= 3.0.0",
          manifest_path: "hello/package-lock.json",
          scope: :SCOPE_UNKNOWN,
          relationship: :RELATIONSHIP_UNKNOWN,
          repository_id: 0,
          license: "",
          scanned_at: { nanos: 0, seconds: 1672531200 },
          scanned_by: :DG,
          snapshot_detector_name: "",
          vulnerable_version_range_ids: [],
          root_ancestors: []
        },
        { package_manager: :PACKAGE_MANAGER_NPM,
          package_name: "@actions/http-client",
          unsupported_package_manager_name: "",
          requirements: "= 1.0.7",
          manifest_path: "/some/path/package-lock.json",
          scope: :SCOPE_UNKNOWN,
          relationship: :RELATIONSHIP_TRANSITIVE,
          repository_id: 0,
          license: "",
          scanned_at: { nanos: 0, seconds: Time.utc(2023, 01, 01).to_i },
          scanned_by: :DS,
          snapshot_detector_name: "test-detector",
          vulnerable_version_range_ids: [],
          root_ancestors: [{ package_name: "@actions/core", requirements: "1.0.7", relationship: :PARENT }]
        },
        { package_manager: :PACKAGE_MANAGER_NPM,
          package_name: "apple",
          unsupported_package_manager_name: "",
          requirements: "= 1.0.0",
          manifest_path: "hello/package-lock.json",
          scope: :SCOPE_UNKNOWN,
          relationship: :RELATIONSHIP_UNKNOWN,
          repository_id: 0,
          license: "",
          scanned_at: { nanos: 0, seconds: 1672531200 },
          scanned_by: :DG,
          snapshot_detector_name: "",
          vulnerable_version_range_ids: [],
          root_ancestors: []
        },
        { package_manager: :PACKAGE_MANAGER_NPM,
          package_name: "react",
          unsupported_package_manager_name: "",
          requirements: "= 1.0.0",
          manifest_path: "hello/package-lock.json",
          scope: :SCOPE_UNKNOWN,
          relationship: :RELATIONSHIP_UNKNOWN,
          repository_id: 0,
          license: "",
          scanned_at: { nanos: 0, seconds: 1672531200 },
          scanned_by: :DG,
          snapshot_detector_name: "",
          vulnerable_version_range_ids: [],
          root_ancestors: []
        },
        { package_manager: :PACKAGE_MANAGER_NPM,
          package_name: "@actions/core",
          unsupported_package_manager_name: "",
          requirements: "= 1.1.9",
          manifest_path: "/some/path/package-lock.json",
          scope: :SCOPE_UNKNOWN,
          relationship: :RELATIONSHIP_DIRECT,
          repository_id: 0,
          license: "",
          scanned_at: { nanos: 0, seconds: Time.utc(2023, 01, 01).to_i },
          scanned_by: :DS,
          snapshot_detector_name: "test-detector",
          vulnerable_version_range_ids: [],
          root_ancestors: []
        },
        { package_manager: :PACKAGE_MANAGER_NPM,
          package_name: "react",
          unsupported_package_manager_name: "",
          requirements: "= 2.0.0",
          manifest_path: "hello/package-lock.json",
          scope: :SCOPE_UNKNOWN,
          relationship: :RELATIONSHIP_UNKNOWN,
          repository_id: 0,
          license: "",
          scanned_at: { nanos: 0, seconds: 1672531200 },
          scanned_by: :DG,
          snapshot_detector_name: "",
          vulnerable_version_range_ids: [],
          root_ancestors: []
        },
        { package_manager: :PACKAGE_MANAGER_NPM,
          package_name: "tunnel",
          unsupported_package_manager_name: "",
          requirements: "= 0.0.6",
          manifest_path: "/some/path/package-lock.json",
          scope: :SCOPE_UNKNOWN,
          relationship: :RELATIONSHIP_UNKNOWN,
          repository_id: 0,
          license: "",
          scanned_at: { nanos: 0, seconds: Time.utc(2023, 01, 01).to_i },
          scanned_by: :DS,
          snapshot_detector_name: "test-detector",
          vulnerable_version_range_ids: [],
          root_ancestors: [{ package_name: "@actions/core", requirements: "1.0.7", relationship: :ANCESTOR }]
        },
        {
          package_manager: :PACKAGE_MANAGER_UNKNOWN,
          package_name: "alpine/curl",
          requirements: "= 7.83.0-r0",
          manifest_path: "sbom.spdx",
          scope: :SCOPE_UNKNOWN,
          repository_id: 0,
          license: "",
          scanned_at: { seconds: 1672531200, nanos: 0 },
          scanned_by: :DS,
          snapshot_detector_name: "test-detector",
          relationship: :RELATIONSHIP_DIRECT,
          vulnerable_version_range_ids: [],
          root_ancestors: [],
          unsupported_package_manager_name: "APK"
          },
        {
          package_manager: :PACKAGE_MANAGER_UNKNOWN,
          package_name: "ubuntu/dpkg",
          requirements: "= 1.19.0.4",
          manifest_path: "sbom.spdx",
          scope: :SCOPE_UNKNOWN,
          repository_id: 0,
          license: "",
          scanned_at: { seconds: 1672531200, nanos: 0 },
          scanned_by: :DS,
          snapshot_detector_name: "test-detector",
          relationship: :RELATIONSHIP_DIRECT,
          vulnerable_version_range_ids: [],
          root_ancestors: [],
          unsupported_package_manager_name: "Debian"
        }
      ]

      expect(resp.repository_has_snapshots).to eq(true)
      expect(resp.package_managers).to eq([:PACKAGE_MANAGER_UNKNOWN, :PACKAGE_MANAGER_NPM])
      expect(resp.results.map(&:to_h)).to eq(expected_results)

      (1..6).each do |per_page|
        (1..5).each do |page|
          resp = handler.search_dependencies_for_repository(DependencyGraphAPI::V1::SearchDependenciesForRepositoryRequest.new({
            repository_id: 1,
            page: page,
            per_page: per_page,
            dependabot_alerts: dependabot_alerts
          }), {})
          expected_page_results = expected_results.slice((page - 1) * per_page, per_page) || []
          expect(resp.total_results).to eq(expected_results.length)
          expect(resp.results.map(&:to_h)).to eq(expected_page_results)
        end
      end
    end

    context "preview ecosystems" do
      let(:github_repo_id) { 123 }

      it "excludes preview package managers unless preview is enabled" do
        stub_const("DependencyGraph::PACKAGE_MANAGER_PREVIEW", [
          Types::PackageManager[:rubygems]
        ])

        factory.given_manifest(github_repo_id: github_repo_id)
          .add_dependency("rails", "1.2.3")
          .add_dependency("pry", "4.5.6")

        resp = handler.search_dependencies_for_repository(DependencyGraphAPI::V1::SearchDependenciesForRepositoryRequest.new({
          repository_id: github_repo_id,
          page: 1,
          per_page: 20
        }), {})

        expect(resp.total_results).to eq(0)
        expect(resp.package_managers).to eq([])

        resp = handler.search_dependencies_for_repository(DependencyGraphAPI::V1::SearchDependenciesForRepositoryRequest.new({
          repository_id: github_repo_id,
          page: 1,
          per_page: 20,
          preview_enabled: true
        }), {})

        expect(resp.total_results).to eq(2)
        expect(resp.package_managers).to eq([:PACKAGE_MANAGER_RUBYGEMS])
      end

      it "excludes preview manifest types unless preview is enabled" do
        stub_const("DependencyGraph::MANIFEST_TYPE_PREVIEW", [
          Types::Manifest[:pyproject_toml]
        ])

        factory.given_manifest(github_repo_id: github_repo_id, manifest_type: :poetry_lock, package_manager: :pip)
          .add_dependency("poetry-dep", "1.2.3")

        factory.given_manifest(github_repo_id: github_repo_id, manifest_type: :pyproject_toml, package_manager: :pip)
          .add_dependency("pyproject-dep", "1.2.3")
          .add_dependency("toml-dep", "4.5.6")

        resp = handler.search_dependencies_for_repository(DependencyGraphAPI::V1::SearchDependenciesForRepositoryRequest.new({
          repository_id: github_repo_id,
          page: 1,
          per_page: 20
        }), {})

        # should only include the poetry dependency
        expect(resp.results.map(&:to_h)).to include(hash_including package_name: "poetry-dep")
        expect(resp.total_results).to eq(1)
        expect(resp.package_managers).to eq([:PACKAGE_MANAGER_PIP])

        resp = handler.search_dependencies_for_repository(DependencyGraphAPI::V1::SearchDependenciesForRepositoryRequest.new({
          repository_id: github_repo_id,
          page: 1,
          per_page: 20,
          preview_enabled: true
        }), {})

        expect(resp.total_results).to eq(3)
      end
    end

    context "NPM in DGP" do
      before do
        DependencyGraph.flipper.enable(:dependency_graph_npm_dgp_repo_insights)
      end

      it "sources NPM dependencies from DGP" do
        mock_dgp_insights_client = MockDGPRepoInsightsClient.new(
          vulnerable_dependencies: [
            {
              ecosystem: :ECOSYSTEM_NPM,
              package_name: "some-other-package",
              requirements: "1.5.0",
              manifest_path: "lama/package-lock.json",
              scope: :SCOPE_RUNTIME,
              relationship: :RELATIONSHIP_DIRECT,
              scanned_at: Time.utc(2023, 01, 01),
              vulnerable_version_range_ids: [3],
              package_license: "MIT"
            },
            {
              ecosystem: :ECOSYSTEM_NPM,
              package_name: "react",
              requirements: "1.2.3",
              manifest_path: "hello/package-lock.json",
              scope: :SCOPE_RUNTIME,
              relationship: :RELATIONSHIP_DIRECT,
              scanned_at: Time.utc(2023, 01, 01),
              vulnerable_version_range_ids: [2],
              package_license: "GPL"
            }
          ],
          non_vulnerable_dependencies: [
            {
              ecosystem: :ECOSYSTEM_NPM,
              package_name: "react-query",
              requirements: "2.4.0",
              manifest_path: "hello/package-lock.json",
              scope: :SCOPE_RUNTIME,
              relationship: :RELATIONSHIP_DIRECT,
              scanned_at: Time.utc(2023, 01, 01),
              package_license: ""
            }
          ]
        )

        handler = RepositoryDependenciesService::V1::Handler.new(
          dependencies_client: SimpleTestDependenciesClient.new,
          dgp_insights_client: mock_dgp_insights_client,
          blob_operations_provider: noop_blob_operations_provider
        )

        repo = Repository.create!(github_repository_id: 1)

        factory.given_manifest(repository: repo, path: "hello", filename: "package-lock.json", last_pushed_at: Time.utc(2023, 01, 01))
          .add_dependency("react", "= 1.0.0")
          .add_dependency("jquery", "= 3.0.0")

        factory.given_manifest(repository: repo, path: "", filename: "Gemfile", last_pushed_at: Time.utc(2023, 01, 01))
          .add_dependency("rails", "~> 7.1.3")
          .add_dependency("rails_semantic_logger", "= 4.16")

        dependabot_alerts = [
          {
            vulnerable_manifest_path: "hello/package-lock.json",
            vulnerable_version_range_affects: "apple",
            vulnerable_requirements: "= 1.0.0",
            vulnerability_severity: :SEVERITY_MODERATE,
            vulnerable_version_range_requirements: "< 1.2.0",
            vulnerable_version_range_id: 1
          },
          {
            vulnerable_manifest_path: "hello/package-lock.json",
            vulnerable_version_range_affects: "react",
            vulnerable_requirements: "= 1.2.3",
            vulnerability_severity: :SEVERITY_MODERATE,
            vulnerable_version_range_requirements: "< 2.0.0",
            vulnerable_version_range_id: 2
          },
          {
            vulnerable_manifest_path: "lama/package-lock.json",
            vulnerable_version_range_affects: "some-other-package",
            vulnerable_requirements: "= 1.5.0",
            vulnerability_severity: :SEVERITY_CRITICAL,
            vulnerable_version_range_requirements: "< 3.0.0",
            vulnerable_version_range_id: 3
          }
        ]

        resp = handler.search_dependencies_for_repository(DependencyGraphAPI::V1::SearchDependenciesForRepositoryRequest.new({
          repository_id: 1,
          page: 1,
          per_page: 20,
          dependabot_alerts: dependabot_alerts
        }), {})

        expected_results = [
          { package_manager: :PACKAGE_MANAGER_NPM,
            package_name: "some-other-package",
            unsupported_package_manager_name: "",
            requirements: "1.5.0",
            manifest_path: "lama/package-lock.json",
            scope: :SCOPE_UNKNOWN,
            relationship: :RELATIONSHIP_DIRECT,
            repository_id: 0,
            license: "MIT",
            scanned_at: { nanos: 0, seconds: 1672531200 },
            scanned_by: :DGP,
            snapshot_detector_name: "",
            vulnerable_version_range_ids: [3],
            root_ancestors: []
          },
          { package_manager: :PACKAGE_MANAGER_NPM,
            package_name: "react",
            unsupported_package_manager_name: "",
            requirements: "1.2.3",
            manifest_path: "hello/package-lock.json",
            scope: :SCOPE_UNKNOWN,
            relationship: :RELATIONSHIP_DIRECT,
            repository_id: 0,
            license: "GPL",
            scanned_at: { nanos: 0, seconds: 1672531200 },
            scanned_by: :DGP,
            snapshot_detector_name: "",
            vulnerable_version_range_ids: [2],
            root_ancestors: []
          },
          { package_manager: :PACKAGE_MANAGER_NPM,
            package_name: "react-query",
            unsupported_package_manager_name: "",
            requirements: "2.4.0",
            manifest_path: "hello/package-lock.json",
            scope: :SCOPE_UNKNOWN,
            relationship: :RELATIONSHIP_DIRECT,
            repository_id: 0,
            license: "",
            scanned_at: { nanos: 0, seconds: 1672531200 },
            scanned_by: :DGP,
            snapshot_detector_name: "",
            vulnerable_version_range_ids: [],
            root_ancestors: []
          },
          { package_manager: :PACKAGE_MANAGER_RUBYGEMS,
            package_name: "rails",
            unsupported_package_manager_name: "",
            requirements: "~> 7.1.3",
            manifest_path: "Gemfile",
            scope: :SCOPE_UNKNOWN,
            relationship: :RELATIONSHIP_UNKNOWN,
            repository_id: 0,
            license: "",
            scanned_at: { nanos: 0, seconds: 1672531200 },
            scanned_by: :DG,
            snapshot_detector_name: "",
            vulnerable_version_range_ids: [],
            root_ancestors: []
          },
          { package_manager: :PACKAGE_MANAGER_RUBYGEMS,
            package_name: "rails_semantic_logger",
            unsupported_package_manager_name: "",
            requirements: "= 4.16",
            manifest_path: "Gemfile",
            scope: :SCOPE_UNKNOWN,
            relationship: :RELATIONSHIP_UNKNOWN,
            repository_id: 0,
            license: "",
            scanned_at: { nanos: 0, seconds: 1672531200 },
            scanned_by: :DG,
            snapshot_detector_name: "",
            vulnerable_version_range_ids: [],
            root_ancestors: []
          },
          { package_manager: :PACKAGE_MANAGER_NPM,
            package_name: "@actions/core",
            unsupported_package_manager_name: "",
            requirements: "= 1.1.9",
            manifest_path: "/some/path/package-lock.json",
            scope: :SCOPE_UNKNOWN,
            relationship: :RELATIONSHIP_DIRECT,
            repository_id: 0,
            license: "",
            scanned_at: { nanos: 0, seconds: Time.utc(2023, 01, 01).to_i },
            scanned_by: :DS,
            snapshot_detector_name: "test-detector",
            vulnerable_version_range_ids: [],
            root_ancestors: []
          },
          { package_manager: :PACKAGE_MANAGER_NPM,
            package_name: "@actions/http-client",
            unsupported_package_manager_name: "",
            requirements: "= 1.0.7",
            manifest_path: "/some/path/package-lock.json",
            scope: :SCOPE_UNKNOWN,
            relationship: :RELATIONSHIP_TRANSITIVE,
            repository_id: 0,
            license: "",
            scanned_at: { nanos: 0, seconds: Time.utc(2023, 01, 01).to_i },
            scanned_by: :DS,
            snapshot_detector_name: "test-detector",
            vulnerable_version_range_ids: [],
            root_ancestors: [{ package_name: "@actions/core", requirements: "1.0.7", relationship: :PARENT }]
          },
          { package_manager: :PACKAGE_MANAGER_NPM,
            package_name: "tunnel",
            unsupported_package_manager_name: "",
            requirements: "= 0.0.6",
            manifest_path: "/some/path/package-lock.json",
            scope: :SCOPE_UNKNOWN,
            relationship: :RELATIONSHIP_UNKNOWN,
            repository_id: 0,
            license: "",
            scanned_at: { nanos: 0, seconds: Time.utc(2023, 01, 01).to_i },
            scanned_by: :DS,
            snapshot_detector_name: "test-detector",
            vulnerable_version_range_ids: [],
            root_ancestors: [{ package_name: "@actions/core", requirements: "1.0.7", relationship: :ANCESTOR }]
          },
          {
            package_manager: :PACKAGE_MANAGER_UNKNOWN,
            package_name: "alpine/curl",
            requirements: "= 7.83.0-r0",
            manifest_path: "sbom.spdx",
            scope: :SCOPE_UNKNOWN,
            repository_id: 0,
            license: "",
            scanned_at: { seconds: 1672531200, nanos: 0 },
            scanned_by: :DS,
            snapshot_detector_name: "test-detector",
            relationship: :RELATIONSHIP_DIRECT,
            vulnerable_version_range_ids: [],
            root_ancestors: [],
            unsupported_package_manager_name: "APK"
          },
          {
            package_manager: :PACKAGE_MANAGER_UNKNOWN,
            package_name: "ubuntu/dpkg",
            requirements: "= 1.19.0.4",
            manifest_path: "sbom.spdx",
            scope: :SCOPE_UNKNOWN,
            repository_id: 0,
            license: "",
            scanned_at: { seconds: 1672531200, nanos: 0 },
            scanned_by: :DS,
            snapshot_detector_name: "test-detector",
            relationship: :RELATIONSHIP_DIRECT,
            vulnerable_version_range_ids: [],
            root_ancestors: [],
            unsupported_package_manager_name: "Debian"
          }
        ]

        expect_no_twirp_error(resp)

        expect(resp.repository_has_snapshots).to eq(true)
        expect(resp.package_managers).to eq([:PACKAGE_MANAGER_UNKNOWN, :PACKAGE_MANAGER_RUBYGEMS, :PACKAGE_MANAGER_NPM])
        expect(resp.results.map(&:to_h)).to eq(expected_results)

        (1..6).each do |per_page|
          (1..5).each do |page|
            resp = handler.search_dependencies_for_repository(DependencyGraphAPI::V1::SearchDependenciesForRepositoryRequest.new({
              repository_id: 1,
              page: page,
              per_page: per_page,
              dependabot_alerts: dependabot_alerts
            }), {})
            expected_page_results = expected_results.slice((page - 1) * per_page, per_page) || []
            expect(resp.total_results).to eq(expected_results.length)
            expect(resp.results.map(&:to_h)).to eq(expected_page_results)
          end
        end
      end

      it "filters by relationship" do
        mock_dgp_insights_client = MockDGPRepoInsightsClient.new(
          vulnerable_dependencies: [
            {
              ecosystem: :ECOSYSTEM_NPM,
              package_name: "some-other-package",
              requirements: "1.5.0",
              manifest_path: "lama/package-lock.json",
              scope: :SCOPE_RUNTIME,
              relationship: :RELATIONSHIP_DIRECT,
              scanned_at: Time.utc(2023, 01, 01),
              vulnerable_version_range_ids: [3],
              package_license: "MIT"
            },
            {
              ecosystem: :ECOSYSTEM_NPM,
              package_name: "react",
              requirements: "1.2.3",
              manifest_path: "hello/package-lock.json",
              scope: :SCOPE_RUNTIME,
              relationship: :RELATIONSHIP_DIRECT,
              scanned_at: Time.utc(2023, 01, 01),
              vulnerable_version_range_ids: [2],
              package_license: "GPL"
            }
          ],
          non_vulnerable_dependencies: [
            {
              ecosystem: :ECOSYSTEM_NPM,
              package_name: "react-query",
              requirements: "2.4.0",
              manifest_path: "hello/package-lock.json",
              scope: :SCOPE_RUNTIME,
              relationship: :RELATIONSHIP_DIRECT,
              scanned_at: Time.utc(2023, 01, 01),
              package_license: ""
            },
            {
              ecosystem: :ECOSYSTEM_NPM,
              package_name: "chalk",
              requirements: "2.5.3",
              manifest_path: "hello/package-lock.json",
              scope: :SCOPE_RUNTIME,
              relationship: :RELATIONSHIP_INDIRECT,
              scanned_at: Time.utc(2023, 01, 01),
              vulnerable_version_range_ids: [],
              package_license: "MIT"
            },
            {
              ecosystem: :ECOSYSTEM_NPM,
              package_name: "argparse",
              requirements: "1.0.7",
              manifest_path: "hello/package-lock.json",
              scope: :SCOPE_RUNTIME,
              relationship: :RELATIONSHIP_INDIRECT,
              scanned_at: Time.utc(2023, 01, 01),
              vulnerable_version_range_ids: [],
              package_license: "MIT"
            },
            {
              ecosystem: :ECOSYSTEM_NPM,
              package_name: "qs",
              requirements: "6.10.1",
              manifest_path: "hello/package-lock.json",
              scope: :SCOPE_RUNTIME,
              relationship: :RELATIONSHIP_UNKNOWN,
              scanned_at: Time.utc(2023, 01, 01),
              vulnerable_version_range_ids: [],
              package_license: "GPL"
            }
          ]
        )

        handler = RepositoryDependenciesService::V1::Handler.new(
          dependencies_client: SimpleTestDependenciesClient.new,
          dgp_insights_client: mock_dgp_insights_client,
          blob_operations_provider: noop_blob_operations_provider
        )

        repo = Repository.create!(github_repository_id: 1)

        factory.given_manifest(repository: repo, path: "hello", filename: "package-lock.json", last_pushed_at: Time.utc(2023, 01, 01))
               .add_dependency("react", "= 1.0.0")
               .add_dependency("jquery", "= 3.0.0")

        factory.given_manifest(repository: repo, path: "", filename: "Gemfile", last_pushed_at: Time.utc(2023, 01, 01))
               .add_dependency("rails", "~> 7.1.3")
               .add_dependency("rails_semantic_logger", "= 4.16")

        dependabot_alerts = [
          {
            vulnerable_manifest_path: "hello/package-lock.json",
            vulnerable_version_range_affects: "apple",
            vulnerable_requirements: "= 1.0.0",
            vulnerability_severity: :SEVERITY_MODERATE,
            vulnerable_version_range_requirements: "< 1.2.0",
            vulnerable_version_range_id: 1
          },
          {
            vulnerable_manifest_path: "hello/package-lock.json",
            vulnerable_version_range_affects: "react",
            vulnerable_requirements: "= 1.2.3",
            vulnerability_severity: :SEVERITY_MODERATE,
            vulnerable_version_range_requirements: "< 2.0.0",
            vulnerable_version_range_id: 2
          },
          {
            vulnerable_manifest_path: "lama/package-lock.json",
            vulnerable_version_range_affects: "some-other-package",
            vulnerable_requirements: "= 1.5.0",
            vulnerability_severity: :SEVERITY_CRITICAL,
            vulnerable_version_range_requirements: "< 3.0.0",
            vulnerable_version_range_id: 3
          }
        ]

        only_direct = handler.search_dependencies_for_repository(DependencyGraphAPI::V1::SearchDependenciesForRepositoryRequest.new({
          repository_id: 1,
          page: 1,
          per_page: 20,
          dependabot_alerts: dependabot_alerts,
          relationship_filter: :RELATIONSHIP_DIRECT
        }), {})

        expected_results = [
          {
            package_manager: :PACKAGE_MANAGER_NPM,
            package_name: "some-other-package",
            unsupported_package_manager_name: "",
            requirements: "1.5.0",
            manifest_path: "lama/package-lock.json",
            scope: :SCOPE_UNKNOWN,
            relationship: :RELATIONSHIP_DIRECT,
            repository_id: 0,
            license: "MIT",
            scanned_at: { nanos: 0, seconds: 1672531200 },
            scanned_by: :DGP,
            snapshot_detector_name: "",
            vulnerable_version_range_ids: [3],
            root_ancestors: []
          },
          {
            package_manager: :PACKAGE_MANAGER_NPM,
            package_name: "react",
            unsupported_package_manager_name: "",
            requirements: "1.2.3",
            manifest_path: "hello/package-lock.json",
            scope: :SCOPE_UNKNOWN,
            relationship: :RELATIONSHIP_DIRECT,
            repository_id: 0,
            license: "GPL",
            scanned_at: { nanos: 0, seconds: 1672531200 },
            scanned_by: :DGP,
            snapshot_detector_name: "",
            vulnerable_version_range_ids: [2],
            root_ancestors: []
          },
          {
            package_manager: :PACKAGE_MANAGER_NPM,
            package_name: "react-query",
            unsupported_package_manager_name: "",
            requirements: "2.4.0",
            manifest_path: "hello/package-lock.json",
            scope: :SCOPE_UNKNOWN,
            relationship: :RELATIONSHIP_DIRECT,
            repository_id: 0,
            license: "",
            scanned_at: { nanos: 0, seconds: 1672531200 },
            scanned_by: :DGP,
            snapshot_detector_name: "",
            vulnerable_version_range_ids: [],
            root_ancestors: []
          },
          {
            package_manager: :PACKAGE_MANAGER_NPM,
            package_name: "@actions/core",
            unsupported_package_manager_name: "",
            requirements: "= 1.1.9",
            manifest_path: "/some/path/package-lock.json",
            scope: :SCOPE_UNKNOWN,
            relationship: :RELATIONSHIP_DIRECT,
            repository_id: 0,
            license: "",
            scanned_at: { nanos: 0, seconds: 1672531200 },
            scanned_by: :DS,
            snapshot_detector_name: "test-detector",
            vulnerable_version_range_ids: [],
            root_ancestors: []
          },
          {
            package_manager: :PACKAGE_MANAGER_UNKNOWN,
            package_name: "alpine/curl",
            requirements: "= 7.83.0-r0",
            manifest_path: "sbom.spdx",
            scope: :SCOPE_UNKNOWN,
            repository_id: 0,
            license: "",
            scanned_at: { seconds: 1672531200, nanos: 0 },
            scanned_by: :DS,
            snapshot_detector_name: "test-detector",
            relationship: :RELATIONSHIP_DIRECT,
            vulnerable_version_range_ids: [],
            root_ancestors: [],
            unsupported_package_manager_name: "APK"
          },
          {
            package_manager: :PACKAGE_MANAGER_UNKNOWN,
            package_name: "ubuntu/dpkg",
            requirements: "= 1.19.0.4",
            manifest_path: "sbom.spdx",
            scope: :SCOPE_UNKNOWN,
            repository_id: 0,
            license: "",
            scanned_at: { seconds: 1672531200, nanos: 0 },
            scanned_by: :DS,
            snapshot_detector_name: "test-detector",
            relationship: :RELATIONSHIP_DIRECT,
            vulnerable_version_range_ids: [],
            root_ancestors: [],
            unsupported_package_manager_name: "Debian"
          }
        ]
        expect(only_direct.results.map(&:to_h)).to eq(expected_results)

        only_transitive = handler.search_dependencies_for_repository(DependencyGraphAPI::V1::SearchDependenciesForRepositoryRequest.new({
          repository_id: 1,
          page: 1,
          per_page: 20,
          dependabot_alerts: dependabot_alerts,
          relationship_filter: :RELATIONSHIP_TRANSITIVE
        }), {})

        expected_results = [
          { package_manager: :PACKAGE_MANAGER_NPM,
            package_name: "chalk",
            unsupported_package_manager_name: "",
            requirements: "2.5.3",
            manifest_path: "hello/package-lock.json",
            scope: :SCOPE_UNKNOWN,
            relationship: :RELATIONSHIP_TRANSITIVE,
            repository_id: 0,
            license: "MIT",
            scanned_at: { nanos: 0, seconds: 1672531200 },
            scanned_by: :DGP,
            snapshot_detector_name: "",
            vulnerable_version_range_ids: [],
            root_ancestors: []
          },
          { package_manager: :PACKAGE_MANAGER_NPM,
            package_name: "argparse",
            unsupported_package_manager_name: "",
            requirements: "1.0.7",
            manifest_path: "hello/package-lock.json",
            scope: :SCOPE_UNKNOWN,
            relationship: :RELATIONSHIP_TRANSITIVE,
            repository_id: 0,
            license: "MIT",
            scanned_at: { nanos: 0, seconds: 1672531200 },
            scanned_by: :DGP,
            snapshot_detector_name: "",
            vulnerable_version_range_ids: [],
            root_ancestors: []
          },
          { package_manager: :PACKAGE_MANAGER_NPM,
            package_name: "@actions/http-client",
            unsupported_package_manager_name: "",
            requirements: "= 1.0.7",
            manifest_path: "/some/path/package-lock.json",
            scope: :SCOPE_UNKNOWN,
            relationship: :RELATIONSHIP_TRANSITIVE,
            repository_id: 0,
            license: "",
            scanned_at: { nanos: 0, seconds: 1672531200 },
            scanned_by: :DS,
            snapshot_detector_name: "test-detector",
            vulnerable_version_range_ids: [],
            root_ancestors: [{ package_name: "@actions/core", relationship: :PARENT, requirements: "1.0.7" }],
          }
        ]

        expect_no_twirp_error(only_transitive)
        expect(only_transitive.results.map(&:to_h)).to eq(expected_results)

        only_unknown = handler.search_dependencies_for_repository(DependencyGraphAPI::V1::SearchDependenciesForRepositoryRequest.new({
           repository_id: 1,
           page: 1,
           per_page: 20,
           dependabot_alerts: dependabot_alerts,
           relationship_filter: :RELATIONSHIP_UNKNOWN
         }), {})

        expected_results = [
          { package_manager: :PACKAGE_MANAGER_NPM,
            package_name: "qs",
            unsupported_package_manager_name: "",
            requirements: "6.10.1",
            manifest_path: "hello/package-lock.json",
            scope: :SCOPE_UNKNOWN,
            relationship: :RELATIONSHIP_UNKNOWN,
            repository_id: 0,
            license: "GPL",
            scanned_at: { nanos: 0, seconds: 1672531200 },
            scanned_by: :DGP,
            snapshot_detector_name: "",
            vulnerable_version_range_ids: [],
            root_ancestors: []
          },
          { package_manager: :PACKAGE_MANAGER_NPM,
            package_name: "tunnel",
            unsupported_package_manager_name: "",
            requirements: "= 0.0.6",
            manifest_path: "/some/path/package-lock.json",
            scope: :SCOPE_UNKNOWN,
            relationship: :RELATIONSHIP_UNKNOWN,
            repository_id: 0,
            license: "",
            scanned_at: { nanos: 0, seconds: 1672531200 },
            scanned_by: :DS,
            snapshot_detector_name: "test-detector",
            vulnerable_version_range_ids: [],
            root_ancestors: [{ package_name: "@actions/core", relationship: :ANCESTOR, requirements: "1.0.7" }],
          }
        ]

        expect_no_twirp_error(only_unknown)
        expect(only_unknown.results.map(&:to_h)).to eq(expected_results)
      end

      it "decorates a set of DGP results with top level direct dependencies" do
        mock_dgp_insights_client = MockDGPRepoInsightsClient.new(
          vulnerable_dependencies: [
            {
              id: 1,
              ecosystem: :ECOSYSTEM_NPM,
              package_name: "some-other-package",
              requirements: "1.5.0",
              manifest_path: "lama/package-lock.json",
              scope: :SCOPE_RUNTIME,
              relationship: :RELATIONSHIP_INDIRECT,
              scanned_at: Time.utc(2023, 01, 01),
              vulnerable_version_range_ids: [3],
              package_license: "MIT"
            },
            {
              id: 2,
              ecosystem: :ECOSYSTEM_NPM,
              package_name: "react",
              requirements: "1.2.3",
              manifest_path: "hello/package-lock.json",
              scope: :SCOPE_RUNTIME,
              relationship: :RELATIONSHIP_DIRECT,
              scanned_at: Time.utc(2023, 01, 01),
              vulnerable_version_range_ids: [2],
              package_license: "GPL"
            }
          ],
          non_vulnerable_dependencies: [
            {
              id: 3,
              ecosystem: :ECOSYSTEM_NPM,
              package_name: "react-query",
              requirements: "2.4.0",
              manifest_path: "hello/package-lock.json",
              scope: :SCOPE_RUNTIME,
              relationship: :RELATIONSHIP_DIRECT,
              scanned_at: Time.utc(2023, 01, 01),
              package_license: ""
            },
            {
              id: 4,
              ecosystem: :ECOSYSTEM_NPM,
              package_name: "argparse",
              requirements: "1.0.7",
              manifest_path: "hello/package-lock.json",
              scope: :SCOPE_RUNTIME,
              relationship: :RELATIONSHIP_INDIRECT,
              scanned_at: Time.utc(2023, 01, 01),
              vulnerable_version_range_ids: [],
              package_license: "MIT"
            }
          ]
        )
        # github.dependency_graph_platform.repo_insights.v1.AncestorRelationship
        mock_dgp_insights_client.set_mock_root_ancestors_for_dependencies({
          1 => [{ package_name: "react", requirements: "1.2.3", relationship: :ANCESTOR_RELATIONSHIP_PARENT }],
          4 => [{ package_name: "react-query", requirements: "2.4.0", relationship: :ANCESTOR_RELATIONSHIP_ANCESTOR }]
        })

        handler = RepositoryDependenciesService::V1::Handler.new(
          dependencies_client: SimpleTestDependenciesClient.new,
          dgp_insights_client: mock_dgp_insights_client,
          blob_operations_provider: noop_blob_operations_provider
        )

        repo = Repository.create!(github_repository_id: 1)

        factory.given_manifest(repository: repo, path: "hello", filename: "package-lock.json", last_pushed_at: Time.utc(2023, 01, 01))
          .add_dependency("react", "= 1.0.0")
          .add_dependency("jquery", "= 3.0.0")

        factory.given_manifest(repository: repo, path: "", filename: "Gemfile", last_pushed_at: Time.utc(2023, 01, 01))
          .add_dependency("rails", "~> 7.1.3")
          .add_dependency("rails_semantic_logger", "= 4.16")

        dependabot_alerts = [
          {
            vulnerable_manifest_path: "hello/package-lock.json",
            vulnerable_version_range_affects: "react",
            vulnerable_requirements: "= 1.2.3",
            vulnerability_severity: :SEVERITY_MODERATE,
            vulnerable_version_range_requirements: "< 2.0.0",
            vulnerable_version_range_id: 2
          },
          {
            vulnerable_manifest_path: "lama/package-lock.json",
            vulnerable_version_range_affects: "some-other-package",
            vulnerable_requirements: "= 1.5.0",
            vulnerability_severity: :SEVERITY_CRITICAL,
            vulnerable_version_range_requirements: "< 3.0.0",
            vulnerable_version_range_id: 3
          }
        ]

        resp = handler.search_dependencies_for_repository(DependencyGraphAPI::V1::SearchDependenciesForRepositoryRequest.new({
          repository_id: 1,
          page: 1,
          per_page: 20,
          dependabot_alerts: dependabot_alerts
        }), {})

        expected_results = [
          { package_manager: :PACKAGE_MANAGER_NPM,
            package_name: "some-other-package",
            unsupported_package_manager_name: "",
            requirements: "1.5.0",
            manifest_path: "lama/package-lock.json",
            scope: :SCOPE_UNKNOWN,
            relationship: :RELATIONSHIP_TRANSITIVE,
            repository_id: 0,
            license: "MIT",
            scanned_at: { nanos: 0, seconds: 1672531200 },
            scanned_by: :DGP,
            snapshot_detector_name: "",
            vulnerable_version_range_ids: [3],
            root_ancestors: [
              { package_name: "react", requirements: "1.2.3", relationship: :PARENT }
            ]
          },
          { package_manager: :PACKAGE_MANAGER_NPM,
            package_name: "react",
            unsupported_package_manager_name: "",
            requirements: "1.2.3",
            manifest_path: "hello/package-lock.json",
            scope: :SCOPE_UNKNOWN,
            relationship: :RELATIONSHIP_DIRECT,
            repository_id: 0,
            license: "GPL",
            scanned_at: { nanos: 0, seconds: 1672531200 },
            scanned_by: :DGP,
            snapshot_detector_name: "",
            vulnerable_version_range_ids: [2],
            root_ancestors: [],
          },
          { package_manager: :PACKAGE_MANAGER_NPM,
            package_name: "react-query",
            unsupported_package_manager_name: "",
            requirements: "2.4.0",
            manifest_path: "hello/package-lock.json",
            scope: :SCOPE_UNKNOWN,
            relationship: :RELATIONSHIP_DIRECT,
            repository_id: 0,
            license: "",
            scanned_at: { nanos: 0, seconds: 1672531200 },
            scanned_by: :DGP,
            snapshot_detector_name: "",
            vulnerable_version_range_ids: [],
            root_ancestors: [],
          },
          { package_manager: :PACKAGE_MANAGER_NPM,
            package_name: "argparse",
            unsupported_package_manager_name: "",
            requirements: "1.0.7",
            manifest_path: "hello/package-lock.json",
            scope: :SCOPE_UNKNOWN,
            relationship: :RELATIONSHIP_TRANSITIVE,
            repository_id: 0,
            license: "MIT",
            scanned_at: { nanos: 0, seconds: 1672531200 },
            scanned_by: :DGP,
            snapshot_detector_name: "",
            vulnerable_version_range_ids: [],
            root_ancestors: [
              { package_name: "react-query", requirements: "2.4.0", relationship: :ANCESTOR }
            ]
          },
          { package_manager: :PACKAGE_MANAGER_RUBYGEMS,
            package_name: "rails",
            unsupported_package_manager_name: "",
            requirements: "~> 7.1.3",
            manifest_path: "Gemfile",
            scope: :SCOPE_UNKNOWN,
            relationship: :RELATIONSHIP_UNKNOWN,
            repository_id: 0,
            license: "",
            scanned_at: { nanos: 0, seconds: 1672531200 },
            scanned_by: :DG,
            snapshot_detector_name: "",
            vulnerable_version_range_ids: [],
            root_ancestors: [],
          },
          { package_manager: :PACKAGE_MANAGER_RUBYGEMS,
            package_name: "rails_semantic_logger",
            unsupported_package_manager_name: "",
            requirements: "= 4.16",
            manifest_path: "Gemfile",
            scope: :SCOPE_UNKNOWN,
            relationship: :RELATIONSHIP_UNKNOWN,
            repository_id: 0,
            license: "",
            scanned_at: { nanos: 0, seconds: 1672531200 },
            scanned_by: :DG,
            snapshot_detector_name: "",
            vulnerable_version_range_ids: [],
            root_ancestors: [],
          },
          { package_manager: :PACKAGE_MANAGER_NPM,
            package_name: "@actions/core",
            unsupported_package_manager_name: "",
            requirements: "= 1.1.9",
            manifest_path: "/some/path/package-lock.json",
            scope: :SCOPE_UNKNOWN,
            relationship: :RELATIONSHIP_DIRECT,
            repository_id: 0,
            license: "",
            scanned_at: { nanos: 0, seconds: Time.utc(2023, 01, 01).to_i },
            scanned_by: :DS,
            snapshot_detector_name: "test-detector",
            vulnerable_version_range_ids: [],
            root_ancestors: [],
          },
          { package_manager: :PACKAGE_MANAGER_NPM,
            package_name: "@actions/http-client",
            unsupported_package_manager_name: "",
            requirements: "= 1.0.7",
            manifest_path: "/some/path/package-lock.json",
            scope: :SCOPE_UNKNOWN,
            relationship: :RELATIONSHIP_TRANSITIVE,
            repository_id: 0,
            license: "",
            scanned_at: { nanos: 0, seconds: Time.utc(2023, 01, 01).to_i },
            scanned_by: :DS,
            snapshot_detector_name: "test-detector",
            vulnerable_version_range_ids: [],
            root_ancestors: [{ package_name: "@actions/core", requirements: "1.0.7", relationship: :PARENT }],
          },
          { package_manager: :PACKAGE_MANAGER_NPM,
            package_name: "tunnel",
            unsupported_package_manager_name: "",
            requirements: "= 0.0.6",
            manifest_path: "/some/path/package-lock.json",
            scope: :SCOPE_UNKNOWN,
            relationship: :RELATIONSHIP_UNKNOWN,
            repository_id: 0,
            license: "",
            scanned_at: { nanos: 0, seconds: Time.utc(2023, 01, 01).to_i },
            scanned_by: :DS,
            snapshot_detector_name: "test-detector",
            vulnerable_version_range_ids: [],
            root_ancestors: [{ package_name: "@actions/core", requirements: "1.0.7", relationship: :ANCESTOR }],
          },
          {
            package_manager: :PACKAGE_MANAGER_UNKNOWN,
            package_name: "alpine/curl",
            requirements: "= 7.83.0-r0",
            manifest_path: "sbom.spdx",
            scope: :SCOPE_UNKNOWN,
            repository_id: 0,
            license: "",
            scanned_at: { seconds: 1672531200, nanos: 0 },
            scanned_by: :DS,
            snapshot_detector_name: "test-detector",
            relationship: :RELATIONSHIP_DIRECT,
            vulnerable_version_range_ids: [],
            root_ancestors: [],
            unsupported_package_manager_name: "APK"
          },
          {
            package_manager: :PACKAGE_MANAGER_UNKNOWN,
            package_name: "ubuntu/dpkg",
            requirements: "= 1.19.0.4",
            manifest_path: "sbom.spdx",
            scope: :SCOPE_UNKNOWN,
            repository_id: 0,
            license: "",
            scanned_at: { seconds: 1672531200, nanos: 0 },
            scanned_by: :DS,
            snapshot_detector_name: "test-detector",
            relationship: :RELATIONSHIP_DIRECT,
            vulnerable_version_range_ids: [],
            root_ancestors: [],
            unsupported_package_manager_name: "Debian"
          }
        ]

        expect_no_twirp_error(resp)
        expect(resp.results.map(&:to_h)).to eq(expected_results)
      end
    end
  end
end

RSpec.shared_examples "a get dependencies for repository request" do
  describe "get_dependencies_for_repository" do
    before do
      DependencyGraph.flipper.disable(:dependency_graph_faster_get_dependencies_for_repository)
      DependencyGraph.flipper.disable(:dependency_graph_get_dependencies_for_repository_ignore_sha)
    end

    before do
      factory do
        # direct, Pip-managed dependencies of the input repository
        Repository.create!({
          github_repository_id: 12345,
          nwo: "django/django"
        })

        VulnerableVersionRange::GitHubVulnerability.create!({
          severity: "critical",
          status: "published"
        }).vulnerable_version_ranges.create!({
          affects: "symfony/symfony",
          ecosystem: "composer",
          requirements: "> 2.0, < 4.0",
          fixed_in: "4.0.0"
        })

        VulnerableVersionRange::GitHubVulnerability.create!({
          severity: "critical",
          status: "published"
        }).vulnerable_version_ranges.create!({
          affects: "@actions/core",
          ecosystem: "npm",
          requirements: "< 1.2.0",
          fixed_in: "1.2.0"
        })
        VulnerableVersionRange::GitHubVulnerability.create!({
          severity: "critical",
          status: "published"
        }).vulnerable_version_ranges.create!({
          affects: "@actions/http-client",
          ecosystem: "npm",
          requirements: "< 1.0.7",
          fixed_in: "1.0.7"
        })
        VulnerableVersionRange::GitHubVulnerability.create!({
          severity: "critical",
          status: "published"
        }).vulnerable_version_ranges.create!({
          affects: "tunnel",
          ecosystem: "npm",
          requirements: "<= 0.0.6",
          fixed_in: "0.0.7"
        })

        VulnerableVersionRange::GitHubVulnerability.create!({
          severity: "critical",
          status: "published"
        }).vulnerable_version_ranges.create!({
          affects: "backtrace",
          ecosystem: "rust",
          requirements: "<= 0.5.0",
          fixed_in: "0.5.1"
        })

        VulnerableVersionRange::GitHubVulnerability.create!({
          severity: "critical",
          status: "published"
        }).vulnerable_version_ranges.create!({
          affects: "org.springframework:spring-core",
          ecosystem: "maven",
          requirements: "<= 1.0.0",
          fixed_in: "1.0.1"
        })

        VulnerableVersionRange.sync
      end
    end

    it "handler has expected default implementations when initialized" do
      handler = RepositoryDependenciesService::V1::Handler.new
      expect(handler.send(:dependencies_client).is_a?(DependencyGraphAPI::DependencySnapshotsAPI::DependenciesClient)).to be(true)
      expect(handler.send(:blob_operations_provider).is_a?(SnapshotRequests::Provider::SpokesProvider)).to be(true)
    end

    describe "dependency snapshot + static rollup functionality" do
      before do
        factory do
          django_repository = Repository.find_by(github_repository_id: 12345)
          manifest = Manifest.create!({
            repository_id: django_repository.id,
            package_manager: Types::PackageManager[:composer],
            manifest_type:   Types::Manifest[:composer_lock],
            filename:        "composer.lock",
            path:            "",
            latest_git_ref:  "77dab21",
            last_pushed_at:  Time.now,
          })

          manifest.dependencies.create!({
            package_name:          "symfony/symfony",
            package_manager:       :composer,
            requirements:          "~> 3.9",
            scope:                 :runtime,
            last_seen_at_revision: 0,
          })
        end
      end

      it "finds dependencies (happy path)" do
        vvr_actions_core = VulnerableVersionRange.where(package_name: "@actions/core")[0]
        vvr_tunnel = VulnerableVersionRange.where(package_name: "tunnel")[0]

        handler = RepositoryDependenciesService::V1::Handler.new(
          dependencies_client: SimpleTestDependenciesClient.new
        )
        req = DependencyGraphAPI::V1::GetDependenciesForRepositoryRequest.new({
          repository_id: 12345
        })

        resp = handler.get_dependencies_for_repository(req, {})
        expect(resp.is_a?(Twirp::Error)).to eq(false)
        expect(resp.manifests.count).to eq(3)

        # First, check the static file manifest
        manifest = resp.manifests.find { |m| m.file_path == "composer.lock" && m.source == "dependency graph" }
        expect(manifest).not_to be_nil
        expect(manifest.package_manager).to eq(DependencyGraphAPI::V1::PackageManager.lookup(DependencyGraphAPI::V1::PackageManager::PACKAGE_MANAGER_COMPOSER))
        expect(manifest.dependencies.length).to eq(1)
        symfony_dependency = manifest.dependencies[0]
        expect(symfony_dependency.name).to eq("symfony/symfony")
        expect(symfony_dependency.requirements).to eq("~> 3.9")
        expect(symfony_dependency.vulnerable_version_ranges.length).to eq(1)
        expect(symfony_dependency.vulnerable_version_ranges[0].is_contained).to eq(true)
        expect(symfony_dependency.package_manager).to eq(DependencyGraphAPI::V1::PackageManager.lookup(DependencyGraphAPI::V1::PackageManager::PACKAGE_MANAGER_COMPOSER))

        # Then check the snapshot file manifest.
        manifest = resp.manifests.find { |m| m.file_path == "/some/path/package-lock.json" && m.source == "snapshots" }
        # until relative paths are fixed from ds-api, this assertion doesn't work.
        # expect(manifest.file_path).to eq("path/package-lock.json")
        expect(manifest.file_path).to eq("/some/path/package-lock.json")
        expect(manifest.original_file_path).to eq("/some/path/package-lock.json")
        expect(manifest.is_vendored.value).to eq(false)
        expect(manifest.package_manager).to eq(:PACKAGE_MANAGER_NPM)
        expect(manifest.dependencies.count).to eq(3)

        expect(manifest.dependencies[0].name).to eq("@actions/http-client")
        expect(manifest.dependencies[0].vulnerable_version_ranges.length).to eq(1)
        expect(manifest.dependencies[0].vulnerable_version_ranges[0].is_contained).to eq(false)
        expect(manifest.dependencies[0].exact_version).to eq("1.0.7")
        expect(manifest.dependencies[0].requirements).to eq("= 1.0.7")
        expect(manifest.dependencies[0].package_manager).to eq(DependencyGraphAPI::V1::PackageManager.lookup(DependencyGraphAPI::V1::PackageManager::PACKAGE_MANAGER_NPM))
        expect(manifest.dependencies[0].relationship).to eq(:RELATIONSHIP_TRANSITIVE)

        expect(manifest.dependencies[1].name).to eq("tunnel")
        expect(manifest.dependencies[1].vulnerable_version_ranges.length).to eq(1)
        expect(manifest.dependencies[1].vulnerable_version_ranges[0].github_id).to eq(vvr_tunnel.github_id)
        expect(manifest.dependencies[1].vulnerable_version_ranges[0].is_contained).to eq(true)
        expect(manifest.dependencies[1].package_manager).to eq(DependencyGraphAPI::V1::PackageManager.lookup(DependencyGraphAPI::V1::PackageManager::PACKAGE_MANAGER_NPM))
        expect(manifest.dependencies[1].relationship).to eq(:RELATIONSHIP_UNKNOWN)

        expect(manifest.dependencies[2].name).to eq("@actions/core")
        expect(manifest.dependencies[2].vulnerable_version_ranges[0].github_id).to eq(vvr_actions_core.github_id)
        expect(manifest.dependencies[2].vulnerable_version_ranges[0].is_contained).to eq(true)
        expect(manifest.dependencies[2].package_manager).to eq(DependencyGraphAPI::V1::PackageManager.lookup(DependencyGraphAPI::V1::PackageManager::PACKAGE_MANAGER_NPM))
        expect(manifest.dependencies[2].relationship).to eq(:RELATIONSHIP_DIRECT)

        # Finally, make sure the internal snapshot is not included
        internal_manifest = resp.manifests.find { |m| m.file_path == "internal/package-lock.json" }
        expect(internal_manifest).to be_nil
      end

      # See https://github.com/github/dependency-graph/issues/3612
      it "ignores SHA argument if dependency_graph_get_dependencies_for_repository_ignore_sha is enabled" do
        DependencyGraph.flipper.enable(:dependency_graph_get_dependencies_for_repository_ignore_sha)

        handler = RepositoryDependenciesService::V1::Handler.new(
          dependencies_client: SimpleTestDependenciesClient.new
        )
        req = DependencyGraphAPI::V1::GetDependenciesForRepositoryRequest.new({
           repository_id: 12345,
           sha: "somesha"
        })

        expect(handler).to receive(:manifests_for_repository_from_db).and_return([])
        expect(handler).to receive(:sleep).with(30.seconds)

        resp = handler.get_dependencies_for_repository(req, {})

        expect(resp.is_a?(Twirp::Error)).to eq(false)
      end

      it "returns internal snapshots when the include_internal_snapshots flag is true" do
        handler = RepositoryDependenciesService::V1::Handler.new(
          dependencies_client: SimpleTestDependenciesClient.new
        )
        req = DependencyGraphAPI::V1::GetDependenciesForRepositoryRequest.new({
           repository_id: 12345,
           include_internal_snapshots: true
        })

        resp = handler.get_dependencies_for_repository(req, {})
        expect(resp.is_a?(Twirp::Error)).to eq(false)
        expect(resp.manifests.count).to eq(4)
      end

      it "doesn't call ds-api if enterprise? = true" do
        handler = RepositoryDependenciesService::V1::Handler.new(
          dependencies_client:  FailsTestIfCalledDependenciesClient::new,
          blob_operations_provider: noop_blob_operations_provider
        )
        vvr_actions_core = VulnerableVersionRange.where(package_name: "@actions/core")[0]
        vvr_tunnel = VulnerableVersionRange.where(package_name: "tunnel")[0]

        req = DependencyGraphAPI::V1::GetDependenciesForRepositoryRequest.new({
          repository_id: 12345
        })

        allow(DependencyGraphAPI).to receive(:enterprise?).and_return(true)

        resp = handler.get_dependencies_for_repository(req, {})
        expect(resp.is_a?(Twirp::Error)).to eq(false)
        expect(resp.manifests.count).to eq(1)

        # First, check the static file manifest
        manifest = resp.manifests.find { |m| m.file_path == "composer.lock" && m.source == "dependency graph" }
        expect(manifest).not_to be_nil
        expect(manifest.package_manager).to eq(DependencyGraphAPI::V1::PackageManager.lookup(DependencyGraphAPI::V1::PackageManager::PACKAGE_MANAGER_COMPOSER))
        expect(manifest.dependencies.length).to eq(1)
        symfony_dependency = manifest.dependencies[0]
        expect(symfony_dependency.name).to eq("symfony/symfony")
        expect(symfony_dependency.requirements).to eq("~> 3.9")
        expect(symfony_dependency.vulnerable_version_ranges.length).to eq(1)
        expect(symfony_dependency.vulnerable_version_ranges[0].is_contained).to eq(true)
        expect(symfony_dependency.package_manager).to eq(DependencyGraphAPI::V1::PackageManager.lookup(DependencyGraphAPI::V1::PackageManager::PACKAGE_MANAGER_COMPOSER))
      end
    end

    it "doesn't n+1" do
      Package.create!(package_manager: :npm, name: "jquery", repository_id: 1, repository_id_certainty: 90)
      Package.create!(package_manager: :npm, name: "react", repository_id: 2)

      repo = Repository.create!(github_repository_id: 500)

      manifest = Manifest.create!(
        repository_id: repo.id,
        package_manager: Types::PackageManager[:npm],
        manifest_type: Types::Manifest[:package_lock_json],
        filename: "package-lock.json",
        path: "",
        latest_git_ref: "77dab21",
        last_pushed_at: Time.utc(2023, 01, 01),
        revision: 1,
      )
      manifest.dependencies.create!(
        package_name: "react",
        package_manager: :npm,
        requirements: "= 2.0.0",
        scope: :runtime,
        last_seen_at_revision: 1,
      )
      manifest.dependencies.create!(
        package_name: "jquery",
        package_manager: :npm,
        requirements: "= 3.0.0",
        scope: :runtime,
        last_seen_at_revision: 1,
      )
      manifest.dependencies.create!(
        package_name: "left-pad",
        package_manager: :npm,
        requirements: "= 1.0.0",
        scope: :runtime,
        last_seen_at_revision: 0,
      )


      handler = RepositoryDependenciesService::V1::Handler.new(
        dependencies_client: NoOpTestDependenciesClient.new
      )
      req = DependencyGraphAPI::V1::GetDependenciesForRepositoryRequest.new({ repository_id: 500 })

      resp = nil
      expect {
        resp = handler.get_dependencies_for_repository(req, {})
      }.to make_database_queries(count: 3)


      expect(resp.manifests.count).to eq(1)
      manifest = resp.manifests[0]
      expect(manifest.dependencies.count).to eq(2)
    end

    describe "dependency snapshot functionality" do
      let(:simple_dependencies_client) { SimpleTestDependenciesClient::new }

      let(:handler) {
        RepositoryDependenciesService::V1::Handler.new(
          dependencies_client: simple_dependencies_client,
          blob_operations_provider: noop_blob_operations_provider
        )
      }

      it "handles weird dependency versions" do
        vvr_spring_core = VulnerableVersionRange.where(package_name: "org.springframework:spring-core")[0]
        repo = Repository.where(github_repository_id: 12345)[0]
        handler = RepositoryDependenciesService::V1::Handler.new(
          # Returns a snapshot containing this purl: pkg:maven/org.springframework/spring-core@6.+%20FAILED
          dependencies_client: GnarlyPurlTestDependenciesClient.new
        )

        req = DependencyGraphAPI::V1::GetDependenciesForRepositoryRequest.new({
          repository_id: repo.id
        })

        resp = handler.get_dependencies_for_repository(req, {})
        expect(resp.is_a?(Twirp::Error)).to eq(false)
        expect(resp.manifests.count).to eq(1)
        expect(resp.manifests[0].file_path).to eq("pom.xml")
        expect(resp.manifests[0].dependencies.count).to eq(1)
        expect(resp.manifests[0].dependencies[0].package_manager).to eq(DependencyGraphAPI::V1::PackageManager.lookup(DependencyGraphAPI::V1::PackageManager::PACKAGE_MANAGER_MAVEN))
        expect(resp.manifests[0].dependencies[0].vulnerable_version_ranges.length).to eq(1)
        expect(resp.manifests[0].dependencies[0].vulnerable_version_ranges[0].github_id).to eq(vvr_spring_core.github_id)
        expect(resp.manifests[0].dependencies[0].vulnerable_version_ranges[0].is_contained).to eq(false)
      end

      it "handles unexpected manifest types" do
        vvr_actions_http_client = VulnerableVersionRange.where(package_name: "@actions/http-client")[0]
        repo = Repository.where(github_repository_id: 12345)[0]
        handler = RepositoryDependenciesService::V1::Handler.new(
          dependencies_client: UnknownPackageTestDependenciesClient.new
        )

        req = DependencyGraphAPI::V1::GetDependenciesForRepositoryRequest.new({
          repository_id: 12345
        })

        resp = handler.get_dependencies_for_repository(req, {})
        expect(resp.is_a?(Twirp::Error)).to eq(false)
        expect(resp.manifests.count).to eq(1)
        expect(resp.manifests[0].file_path).to eq("/some/path/unknown.filename")
        expect(resp.manifests[0].dependencies.count).to eq(1)
        expect(resp.manifests[0].dependencies[0].package_manager).to eq(DependencyGraphAPI::V1::PackageManager.lookup(DependencyGraphAPI::V1::PackageManager::PACKAGE_MANAGER_NPM))
        expect(resp.manifests[0].dependencies[0].vulnerable_version_ranges.length).to eq(1)
        expect(resp.manifests[0].dependencies[0].vulnerable_version_ranges[0].github_id).to eq(vvr_actions_http_client.github_id)
        expect(resp.manifests[0].dependencies[0].vulnerable_version_ranges[0].is_contained).to eq(true)

      end

      it "finds dependencies (happy path)" do
        vvr_actions_core = VulnerableVersionRange.where(package_name: "@actions/core")[0]
        vvr_tunnel = VulnerableVersionRange.where(package_name: "tunnel")[0]

        req = DependencyGraphAPI::V1::GetDependenciesForRepositoryRequest.new({
          repository_id: 12345
        })

        resp = handler.get_dependencies_for_repository(req, {})
        expect(resp.is_a?(Twirp::Error)).to eq(false)
        expect(resp.manifests.count).to eq(2)
        manifest = resp.manifests[0]
        # until relative paths are fixed from ds-api, this assertion doesn't work.
        # expect(manifest.file_path).to eq("path/package-lock.json")
        expect(manifest.file_path).to eq("/some/path/package-lock.json")
        expect(manifest.original_file_path).to eq("/some/path/package-lock.json")
        expect(manifest.is_vendored.value).to eq(false)
        expect(manifest.package_manager).to eq(:PACKAGE_MANAGER_NPM)
        expect(manifest.dependencies.count).to eq(3)

        expect(manifest.dependencies[0].name).to eq("@actions/http-client")
        expect(manifest.dependencies[0].scope).to eq("")
        expect(manifest.dependencies[0].vulnerable_version_ranges.length).to eq(1)
        expect(manifest.dependencies[0].vulnerable_version_ranges[0].is_contained).to eq(false)
        expect(manifest.dependencies[0].exact_version).to eq("1.0.7")
        expect(manifest.dependencies[0].requirements).to eq("= 1.0.7")
        expect(manifest.dependencies[0].package_manager).to eq(DependencyGraphAPI::V1::PackageManager.lookup(DependencyGraphAPI::V1::PackageManager::PACKAGE_MANAGER_NPM))
        expect(manifest.dependencies[0].relationship).to eq(:RELATIONSHIP_TRANSITIVE)

        expect(manifest.dependencies[1].name).to eq("tunnel")
        expect(manifest.dependencies[1].scope).to eq("development")
        expect(manifest.dependencies[1].vulnerable_version_ranges.length).to eq(1)
        expect(manifest.dependencies[1].vulnerable_version_ranges[0].github_id).to eq(vvr_tunnel.github_id)
        expect(manifest.dependencies[1].vulnerable_version_ranges[0].is_contained).to eq(true)
        expect(manifest.dependencies[1].package_manager).to eq(DependencyGraphAPI::V1::PackageManager.lookup(DependencyGraphAPI::V1::PackageManager::PACKAGE_MANAGER_NPM))
        expect(manifest.dependencies[1].relationship).to eq(:RELATIONSHIP_UNKNOWN)

        expect(manifest.dependencies[2].name).to eq("@actions/core")
        expect(manifest.dependencies[2].scope).to eq("runtime")
        expect(manifest.dependencies[2].vulnerable_version_ranges[0].github_id).to eq(vvr_actions_core.github_id)
        expect(manifest.dependencies[2].vulnerable_version_ranges[0].is_contained).to eq(true)
        expect(manifest.dependencies[2].package_manager).to eq(DependencyGraphAPI::V1::PackageManager.lookup(DependencyGraphAPI::V1::PackageManager::PACKAGE_MANAGER_NPM))
        expect(manifest.dependencies[2].relationship).to eq(:RELATIONSHIP_DIRECT)
      end

      it "collapses manifests with the same filename" do
        handler = RepositoryDependenciesService::V1::Handler.new(
          dependencies_client: MultipleManifestsForSameFileDependenciesTestClient.new
        )
        vvr_actions_core = VulnerableVersionRange.where(package_name: "@actions/core")[0]
        vvr_actions_http_client = VulnerableVersionRange.where(package_name: "@actions/http-client")[0]
        vvr_tunnel = VulnerableVersionRange.where(package_name: "tunnel")[0]

        req = DependencyGraphAPI::V1::GetDependenciesForRepositoryRequest.new({
          repository_id: 12345
        })

        resp = handler.get_dependencies_for_repository(req, {})
        expect(resp.is_a?(Twirp::Error)).to eq(false)
        expect(resp.manifests.count).to eq(1)
        manifest = resp.manifests[0]
        # until relative paths are fixed from ds-api, this assertion doesn't work.
        # expect(manifest.file_path).to eq("path/package-lock.json")
        expect(manifest.file_path).to eq("/some/path/package-lock.json")
        expect(manifest.original_file_path).to eq("/some/path/package-lock.json")
        expect(manifest.is_vendored.value).to eq(false)
        expect(manifest.package_manager).to eq(:PACKAGE_MANAGER_NPM)
        expect(manifest.dependencies.count).to eq(5)

        dependency_non_vuln_http_client = manifest.dependencies.find { |d| d.name == "@actions/http-client" && d.exact_version == "1.0.7" }
        expect(dependency_non_vuln_http_client).not_to be_nil
        expect(dependency_non_vuln_http_client.vulnerable_version_ranges.length).to eq(1)
        expect(dependency_non_vuln_http_client.vulnerable_version_ranges[0].is_contained).to eq(false)
        expect(dependency_non_vuln_http_client.requirements).to eq("= 1.0.7")
        expect(dependency_non_vuln_http_client.package_manager).to eq(DependencyGraphAPI::V1::PackageManager.lookup(DependencyGraphAPI::V1::PackageManager::PACKAGE_MANAGER_NPM))
        expect(dependency_non_vuln_http_client.relationship).to eq(:RELATIONSHIP_UNKNOWN)

        dependency_vuln_http_client = manifest.dependencies.find { |d| d.name == "@actions/http-client" && d.exact_version == "1.0.6" }
        expect(dependency_vuln_http_client).not_to be_nil
        expect(dependency_vuln_http_client.vulnerable_version_ranges.length).to eq(1)
        expect(dependency_vuln_http_client.vulnerable_version_ranges[0].is_contained).to eq(true)
        expect(dependency_vuln_http_client.requirements).to eq("= 1.0.6")
        expect(dependency_vuln_http_client.package_manager).to eq(DependencyGraphAPI::V1::PackageManager.lookup(DependencyGraphAPI::V1::PackageManager::PACKAGE_MANAGER_NPM))
        expect(dependency_vuln_http_client.relationship).to eq(:RELATIONSHIP_UNKNOWN)

        dependency_vuln_core = manifest.dependencies.find { |d| d.name == "@actions/core" && d.exact_version == "1.1.9" }
        expect(dependency_vuln_core).not_to be_nil
        expect(dependency_vuln_core.vulnerable_version_ranges.length).to eq(1)
        expect(dependency_vuln_core.vulnerable_version_ranges[0].is_contained).to eq(true)
        expect(dependency_vuln_core.requirements).to eq("= 1.1.9")
        expect(dependency_vuln_core.package_manager).to eq(DependencyGraphAPI::V1::PackageManager.lookup(DependencyGraphAPI::V1::PackageManager::PACKAGE_MANAGER_NPM))
        expect(dependency_vuln_core.relationship).to eq(:RELATIONSHIP_UNKNOWN)

        dependency_not_vuln_core = manifest.dependencies.find { |d| d.name == "@actions/core" && d.exact_version == "1.2.0" }
        expect(dependency_not_vuln_core).not_to be_nil
        expect(dependency_not_vuln_core.vulnerable_version_ranges.length).to eq(1)
        expect(dependency_not_vuln_core.vulnerable_version_ranges[0].is_contained).to eq(false)
        expect(dependency_not_vuln_core.requirements).to eq("= 1.2.0")
        expect(dependency_not_vuln_core.package_manager).to eq(DependencyGraphAPI::V1::PackageManager.lookup(DependencyGraphAPI::V1::PackageManager::PACKAGE_MANAGER_NPM))
        expect(dependency_not_vuln_core.relationship).to eq(:RELATIONSHIP_UNKNOWN)

        dependency_tunnel = manifest.dependencies.find { |d| d.name == "tunnel" && d.exact_version == "0.0.6" }
        expect(dependency_tunnel).not_to be_nil
        expect(dependency_tunnel.vulnerable_version_ranges.length).to eq(1)
        expect(dependency_tunnel.vulnerable_version_ranges[0].is_contained).to eq(true)
        expect(dependency_tunnel.requirements).to eq("= 0.0.6")
        expect(dependency_tunnel.package_manager).to eq(DependencyGraphAPI::V1::PackageManager.lookup(DependencyGraphAPI::V1::PackageManager::PACKAGE_MANAGER_NPM))
        expect(dependency_tunnel.relationship).to eq(:RELATIONSHIP_UNKNOWN)
      end

      it "returns twirp error if Snapshots call raises an exception" do
        deps_client = double(DependencyGraphAPI::DependencySnapshotsAPI::DependenciesClient.class)
        allow(deps_client).to receive(:get_dependencies_for_repository).and_raise(Faraday::TimeoutError)

        test_handler = RepositoryDependenciesService::V1::Handler.new(
          dependencies_client: deps_client,
          blob_operations_provider: noop_blob_operations_provider
        )

        req = DependencyGraphAPI::V1::GetDependenciesForRepositoryRequest.new({
          repository_id: 987654321
        })

        resp = test_handler.get_dependencies_for_repository(req, {})
        expect(resp).to be_a Twirp::Error
        expect(resp.code).to be(:internal)
      end

      it "returns Twirp::Error object if Snapshots call returns an error" do
        deps_client = double(DependencyGraphAPI::DependencySnapshotsAPI::DependenciesClient.class)
        allow(deps_client).to receive(:get_dependencies_for_repository).and_return(
          Twirp::ClientResp.new(error: Twirp::Error.internal("Snapshots internal error"))
        )

        test_handler = RepositoryDependenciesService::V1::Handler.new(
          dependencies_client: deps_client,
          blob_operations_provider: noop_blob_operations_provider
        )

        req = DependencyGraphAPI::V1::GetDependenciesForRepositoryRequest.new({
          repository_id: 987654321
        })

        resp = test_handler.get_dependencies_for_repository(req, {})
        expect(resp).to be_a Twirp::Error
        # The error message is changed within the handler
        expect(resp.msg).to eq("An unexpected error occurred during snapshot retrieval")
      end
    end

    # Optimisation. When GetDependenciesForRepository is called with a SHA,
    # instead of dynamically enumerating and parsing all manifests at that SHA, we use what's available
    # in the database and only dynamically fetch blobs and parse what's not in the database already.
    # Thus "mixed". It's both dynamic and static enumeration.
    describe "faster GetDependenciesForRepository when SHA specified" do
      let(:repo) { Repository.create!(github_repository_id: 1) }

      let(:blob_provider) { double(SnapshotRequests::Provider::BlobOperationsProvider) }

      def mkblob(contents)
        oid = SecureRandom.hex(64)
        { oid: oid, contents: contents }
      end

      let(:composer_json_v1) { mkblob(%{
        {
          "require": {
            "php": ">=7.3",
            "symfony/symfony": "^3.4"
          }
        }
      })
      }

      let(:composer_json_v1_deps) { [
        ["php", ">= 7.3"],
        ["symfony/symfony", ">= 3.4,< 4.0"]
      ]
      }

      let(:composer_json_v2) { mkblob(%{
        {
          "require": {
            "php": ">=7.3",
            "symfony/symfony": "^4.1"
          }
        }
      })
      }

      let(:composer_json_v2_deps) { [
        ["php", ">= 7.3"],
        ["symfony/symfony", ">= 4.1,< 5.0"]
      ]
      }

      let(:package_json) { mkblob(%{
        {
          "dependencies": {
            "relaxed-json": "0.2.9",
            "undici": "^5.28.4"
          }
        }
      })
      }

      let(:package_json_deps) { [
        ["relaxed-json", "= 0.2.9"],
        ["undici", "^ 5.28.4"]
      ]
      }

      let(:stale_yaml) { mkblob(%{
        name: Close stale pull requests
        on:
          schedule:
          - cron: "0 0 * * *"
        jobs:
          stale:
            runs-on: ubuntu-latest
            steps:
            - uses: actions/stale@v9
      })
      }

      let(:stale_yaml_deps) { [
        ["actions/stale", "= 9.*.*"],
      ]
      }

      def load_manifest_in_db(full_path, blob, updated_at)
        latest_git_ref = SecureRandom.hex(64)
        content = blob[:contents]
        filename = File.basename(full_path)
        path = File.dirname(full_path)
        if path == "."
          path = ""
        end
        parsed = ::ManifestAdapters.parse(
          filename: filename,
          path: path,
          content: content,
          git_ref: latest_git_ref,
          pushed_at: 1.hour.ago,
          github_repository_id: repo.github_repository_id,
          fork: false,
          visibility_private: false
        )
        m = factory.given_manifest(repository: repo, filename: filename, latest_git_ref: latest_git_ref)
        parsed.dependencies.each do |dep|
          m.add_dependency(dep.package_name, dep.requirements, scope: dep.scope)
        end
        m.get.touch(time: updated_at)
        return m.get
      end

      def test_case(tree:, database:, expected_blob_requests:, expected_response:)
        # Set up the DB state
        database.each do |filename, entry|
          blob, updated_at = entry
          load_manifest_in_db(filename, blob, updated_at)
        end

        # Set up tree
        allow(blob_provider).to receive(:manifest_tree_entries_at_sha).and_return(tree.map { |full_path, blob|
          BlobOperations::Responses::TreeEntry.new(
            blob_operations_provider: blob_provider,
            mode: "100644",
            oid: blob[:oid],
            path: full_path,
          )
        })

        # Set up blobs
        expected_blob_requests.each do |blob|
          expect(blob_provider).to receive(:get_blob).with(repository_id: anything, oid: blob[:oid]).and_return(OpenStruct.new(content: blob[:contents]))
        end

        # Set up resolve objects
        expect(blob_provider).to receive(:resolve_objects) do |**kwargs|
          kwargs[:object_selectors].map do |os|
            GitHub::Spokes::Proto::Objects::V1::ResolveObjectsResponse::ResolvedItem.new(
              object: {
                oid: { id: database[os[:by_treeish_and_path][:path][:name]][0][:oid] }
              }
            )
          end
        end

        DependencyGraph.flipper.enable(:dependency_graph_faster_get_dependencies_for_repository)

        stubbed_handler = RepositoryDependenciesService::V1::Handler.new(
          blob_operations_provider: blob_provider,
          dependencies_client: noop_dependencies_client
        )

        req = DependencyGraphAPI::V1::GetDependenciesForRepositoryRequest.new({ repository_id: repo.github_repository_id, sha: "fakefake" })
        resp = stubbed_handler.get_dependencies_for_repository(req, {})

        expect(resp.manifests).not_to be_empty
        expect(resp.manifests.count).to eq(tree.count)

        resp.manifests.each do |m|
          deps = m.dependencies.map { |d| [d.name, d.requirements] }
          expect(deps).to eq(expected_response[m.file_path])
        end
      end

      it "it does not make blob requests for blobs which are in the database" do
        test_case(
          tree: {
            "composer.json" => composer_json_v1,
            "package.json" => package_json,
            ".github/workflows/stale.yaml" => stale_yaml,
          },
          database: {
            "composer.json" => [composer_json_v1, 1.hour.ago]
          },
          expected_blob_requests: [package_json, stale_yaml],
          expected_response: {
            "./composer.json" => composer_json_v1_deps,
            "./package.json" => package_json_deps,
            ".github/workflows/stale.yaml" => stale_yaml_deps,
          }
        )
      end

      it "it make a blob request if database was updated recently" do
        test_case(
          tree: {
            "composer.json" => composer_json_v1,
            "package.json" => package_json,
            ".github/workflows/stale.yaml" => stale_yaml,
          },
          database: {
            "composer.json" => [composer_json_v1, 5.seconds.ago]
          },
          expected_blob_requests: [composer_json_v1, package_json, stale_yaml],
          expected_response: {
            "./composer.json" => composer_json_v1_deps,
            "./package.json" => package_json_deps,
            ".github/workflows/stale.yaml" => stale_yaml_deps,
          }
        )
      end

      it "if database has an outdated blob, it requests the new blob" do
        test_case(
          tree: {
            "composer.json" => composer_json_v2,
            "package.json" => package_json,
            ".github/workflows/stale.yaml" => stale_yaml,
          },
          database: {
            "composer.json" => [composer_json_v1, 1.hour.ago]
          },
          expected_blob_requests: [composer_json_v2, package_json, stale_yaml],
          expected_response: {
            "./composer.json" => composer_json_v2_deps,
            "./package.json" => package_json_deps,
            ".github/workflows/stale.yaml" => stale_yaml_deps,
          }
        )
      end
    end

    describe "dynamic enumeration functionality" do
      it "finds manifests based off a SHA when the feature flag isn't enabled" do
        input = {
          repository_id: 12345,
          sha: "r34ll337sh17",
        }
        req = DependencyGraphAPI::V1::GetDependenciesForRepositoryRequest.new(input)

        resp = handler.get_dependencies_for_repository(req, {})
        expect(resp.manifests).to be_empty
      end

      it "returns parsed manifests when they're found in a repository" do
        vvr = VulnerableVersionRange.where(package_name: "symfony/symfony")[0]

        stubbed_blob_provider = SnapshotRequests::Provider::NoOpProvider.new

        fake_blobs = {
          "fake-composer-json-oid" => OpenStruct.new(content: file_fixture("composer.json").read),
          "fake-composer-lock-oid" => OpenStruct.new(content: file_fixture("composer.lock").read),
        }
        fake_tree = [
          BlobOperations::Responses::TreeEntry.new(
            blob_operations_provider: stubbed_blob_provider,
            mode: "100644",
            oid: "fake-composer-json-oid",
            path: "composer.json",
          ),
          BlobOperations::Responses::TreeEntry.new(
            blob_operations_provider: stubbed_blob_provider,
            mode: "100755",
            oid: "fake-composer-lock-oid",
            path: "composer.lock",
          ),
          # not a blob! should be filtered out by manifest_tree_entries_at_sha
          BlobOperations::Responses::TreeEntry.new(
            blob_operations_provider: stubbed_blob_provider,
            mode: "040000", # not a file!
            oid: "fake-directory",
            path: "lib",
          ),
        ]
        stubbed_blob_provider.get_tree_returns = fake_tree
        stubbed_blob_provider.get_blob_returns = fake_blobs
        stubbed_handler = RepositoryDependenciesService::V1::Handler.new(
          blob_operations_provider: stubbed_blob_provider,
          dependencies_client: noop_dependencies_client
        )

        req = DependencyGraphAPI::V1::GetDependenciesForRepositoryRequest.new({ repository_id: 12345, sha: "fakefake" })
        resp = stubbed_handler.get_dependencies_for_repository(req, {})

        composer_json = resp.manifests.find { |m| m.file_path == "./composer.json" }
        composer_lock = resp.manifests.find { |m| m.file_path == "./composer.lock" }

        expect(resp.manifests).not_to be_empty
        expect(resp.manifests.count).to eq(2)

        expect(composer_json.package_manager).to eq(:PACKAGE_MANAGER_COMPOSER)
        expect(composer_json.type).to eq("composer_json")
        expect(composer_lock.package_manager).to eq(:PACKAGE_MANAGER_COMPOSER)
        expect(composer_lock.type).to eq("composer_lock")

        expect(composer_json.dependencies).not_to be_empty
        expect(composer_json.dependencies.find { |d| d.name == "exact-version-package" }.exact_version).to eq("1.2.3")
        expect(composer_json.dependencies.find { |d| d.name == "exact-version-package" }.requirements).to eq("= 1.2.3")
        expect(composer_json.dependencies.find { |d| d.name == "exact-version-package" }.package_manager).to eq(DependencyGraphAPI::V1::PackageManager.lookup(DependencyGraphAPI::V1::PackageManager::PACKAGE_MANAGER_COMPOSER))
        # php has a non-exact version in composer.json
        expect(composer_json.dependencies.find { |d| d.name == "php" }.exact_version).to eq("")
        expect(composer_json.dependencies.find { |d| d.name == "php" }.requirements).to eq(">= 7.3")
        expect(composer_json.dependencies.find { |d| d.name == "php" }.package_manager).to eq(DependencyGraphAPI::V1::PackageManager.lookup(DependencyGraphAPI::V1::PackageManager::PACKAGE_MANAGER_COMPOSER))

        expect(composer_json.dependencies.find { |d| d.name == "symfony/symfony" }.vulnerable_version_ranges[0].github_id).to eq(vvr.github_id)
        expect(composer_json.dependencies.find { |d| d.name == "symfony/symfony" }.vulnerable_version_ranges[0].is_contained).to eq(true)
        expect(composer_json.dependencies.find { |d| d.name == "symfony/symfony" }.package_manager).to eq(DependencyGraphAPI::V1::PackageManager.lookup(DependencyGraphAPI::V1::PackageManager::PACKAGE_MANAGER_COMPOSER))
        expect(composer_json.dependencies.find { |d| d.name == "symfony/symfony" }.scope).to eq("runtime")

        dev_dependency = composer_json.dependencies.find { |d| d.name == "symfony/phpunit-bridge" }
        expect(dev_dependency.scope).to eq("development")
      end

      it "returns sorted parsed manifests when they're found in a repository" do
        stubbed_blob_provider = SnapshotRequests::Provider::NoOpProvider.new
        fake_blobs = {
          "fake-composer-json-oid" => OpenStruct.new(content: file_fixture("composer.json").read),
          "fake-composer-lock-oid" => OpenStruct.new(content: file_fixture("composer.lock").read),
        }
        fake_tree = [
          BlobOperations::Responses::TreeEntry.new(
            blob_operations_provider: stubbed_blob_provider,
            mode: "100755",
            oid: "fake-composer-lock-oid",
            path: "some/deep/path/composer.lock",
          ),
          BlobOperations::Responses::TreeEntry.new(
            blob_operations_provider: stubbed_blob_provider,
            mode: "100644",
            oid: "fake-composer-json-oid",
            path: "some/deep/path/composer.json",
          ),
          BlobOperations::Responses::TreeEntry.new(
            blob_operations_provider: stubbed_blob_provider,
            mode: "100755",
            oid: "fake-composer-lock-oid",
            path: "composer.lock",
          ),
        ]
        stubbed_blob_provider.get_tree_returns = fake_tree
        stubbed_blob_provider.get_blob_returns = fake_blobs
        stubbed_handler = RepositoryDependenciesService::V1::Handler.new(
          blob_operations_provider: stubbed_blob_provider,
          dependencies_client: noop_dependencies_client
        )

        req = DependencyGraphAPI::V1::GetDependenciesForRepositoryRequest.new({ repository_id: 12345, sha: "fakefake" })
        resp = stubbed_handler.get_dependencies_for_repository(req, {})

        # Sorting should order by count of "/" ascending, then alphabetically
        expect(resp.manifests[0].file_path).to eq("./composer.lock")
        expect(resp.manifests[1].file_path).to eq("some/deep/path/composer.json")
        expect(resp.manifests[2].file_path).to eq("some/deep/path/composer.lock")

        # Swap orders in the input array once just to verify our sort order produces the same result
        fake_tree[0], fake_tree[2] = fake_tree[2], fake_tree[0]
        resp = stubbed_handler.get_dependencies_for_repository(req, {})

        expect(resp.manifests[0].file_path).to eq("./composer.lock")
        expect(resp.manifests[1].file_path).to eq("some/deep/path/composer.json")
        expect(resp.manifests[2].file_path).to eq("some/deep/path/composer.lock")

        # One more swap that should be a different case yet.
        fake_tree[0], fake_tree[1] = fake_tree[1], fake_tree[0]
        resp = stubbed_handler.get_dependencies_for_repository(req, {})

        expect(resp.manifests[0].file_path).to eq("./composer.lock")
        expect(resp.manifests[1].file_path).to eq("some/deep/path/composer.json")
        expect(resp.manifests[2].file_path).to eq("some/deep/path/composer.lock")
      end

      it "returns only non-vendored manifests when they're found in a repository" do
        fake_blobs = {
          "fake-composer-json-oid" => OpenStruct.new(content: file_fixture("composer.json").read),
          "fake-composer-lock-oid" => OpenStruct.new(content: file_fixture("composer.lock").read),
        }
        stubbed_blob_provider = SnapshotRequests::Provider::NoOpProvider.new(get_blob_returns: fake_blobs)
        fake_tree = [
          BlobOperations::Responses::TreeEntry.new(
            blob_operations_provider: stubbed_blob_provider,
            mode: "100755",
            oid: "fake-composer-lock-oid",
            path: "vendor/deep/path/composer.lock",
          ),
          BlobOperations::Responses::TreeEntry.new(
            blob_operations_provider: stubbed_blob_provider,
            mode: "100644",
            oid: "fake-composer-json-oid",
            path: "some/deep/path/composer.json",
          ),
          BlobOperations::Responses::TreeEntry.new(
            blob_operations_provider: stubbed_blob_provider,
            mode: "100755",
            oid: "fake-composer-lock-oid",
            path: "vendor/composer.lock",
          ),
        ]
        stubbed_blob_provider.get_tree_returns = fake_tree
        stubbed_handler = RepositoryDependenciesService::V1::Handler.new(
          blob_operations_provider: stubbed_blob_provider,
          dependencies_client: noop_dependencies_client
        )

        req = DependencyGraphAPI::V1::GetDependenciesForRepositoryRequest.new({ repository_id: 12345, sha: "fakefake" })
        resp = stubbed_handler.get_dependencies_for_repository(req, {})

        expect(resp.manifests.count).to eq(1)
        expect(resp.manifests[0].file_path).to eq("some/deep/path/composer.json")
      end

      it "doesn't blow up when one manifest path is unusually encoded" do
        fake_blobs = {
          "fake-composer-json-oid" => OpenStruct.new(content: file_fixture("composer.json").read),
          "fake-unusually-encoded-oid" => OpenStruct.new(content: file_fixture("composer.json").read),
        }
        stubbed_blob_provider = SnapshotRequests::Provider::NoOpProvider.new(get_blob_returns: fake_blobs)
        fake_tree = [
          BlobOperations::Responses::TreeEntry.new(
            blob_operations_provider: stubbed_blob_provider,
            mode: "100755",
            oid: "fake-unusually-encoded-oid",
            path: "composer.lock",
          ),
          BlobOperations::Responses::TreeEntry.new(
            blob_operations_provider: stubbed_blob_provider,
            mode: "100755",
            oid: "fake-composer-json-oid",
            path: "\xC4/deep/path/composer.json".force_encoding("ASCII-8BIT"),
          ),
          BlobOperations::Responses::TreeEntry.new(
            blob_operations_provider: stubbed_blob_provider,
            mode: "100755",
            oid: "fake-composer-json-oid",
            path: "\xF0\x9F\x99\x82/deep/path/composer.json".force_encoding("ASCII-8BIT"),
          )
        ]
        stubbed_blob_provider.get_tree_returns = fake_tree
        stubbed_handler = RepositoryDependenciesService::V1::Handler.new(
          blob_operations_provider: stubbed_blob_provider,
          dependencies_client: noop_dependencies_client
        )

        req = DependencyGraphAPI::V1::GetDependenciesForRepositoryRequest.new({ repository_id: 12345, sha: "fakefake" })
        resp = stubbed_handler.get_dependencies_for_repository(req, {})

        expect(resp.manifests.count).to eq(2)
        expect(resp.manifests[0].file_path).to eq("./composer.lock")
        expect(resp.manifests[1].file_path).to eq("\xF0\x9F\x99\x82/deep/path/composer.json")
      end

      it "returns preview manifests when preview_enabled is true" do
        stub_const("DependencyGraph::PACKAGE_MANAGER_PREVIEW", [
          Types::PackageManager[:rust]
        ])

        vvr = VulnerableVersionRange.where(package_name: "backtrace")[0]

        fake_blobs = {
          "fake-cargo-lock-oid" => OpenStruct.new(content: file_fixture("Cargo_v3.lock").read),
          "fake-composer-lock-oid" => OpenStruct.new(content: file_fixture("composer.lock").read),
        }
        stubbed_blob_provider = SnapshotRequests::Provider::NoOpProvider.new(get_blob_returns: fake_blobs)
        fake_tree = [
          BlobOperations::Responses::TreeEntry.new(
            blob_operations_provider: stubbed_blob_provider,
            mode: "100755",
            oid: "fake-composer-lock-oid",
            path: "composer.lock",
          ),
          BlobOperations::Responses::TreeEntry.new(
            blob_operations_provider: stubbed_blob_provider,
            mode: "100755",
            oid: "fake-cargo-lock-oid",
            path: "cargo.lock",
          ),
        ]
        stubbed_blob_provider.get_tree_returns = fake_tree
        stubbed_handler = RepositoryDependenciesService::V1::Handler.new(
          blob_operations_provider: stubbed_blob_provider,
          dependencies_client: noop_dependencies_client
        )

        req = DependencyGraphAPI::V1::GetDependenciesForRepositoryRequest.new({ repository_id: 12345,
                                                                                sha: "fakefake",
                                                                                enable_preview_ecosystems: true })

        resp = stubbed_handler.get_dependencies_for_repository(req, {})

        cargo_lock = resp.manifests.find { |m| m.file_path == "./cargo.lock" }

        expect(resp.manifests).not_to be_empty
        expect(resp.manifests.count).to eq(2)

        expect(cargo_lock.package_manager).to eq(:PACKAGE_MANAGER_RUST)
        expect(cargo_lock.type).to eq("cargo_lock")

        expect(cargo_lock.dependencies).not_to be_empty

        backtrace = cargo_lock.dependencies.find { |d| d.name == "backtrace" }
        expect(backtrace.exact_version).to eq("0.3.64")
        expect(backtrace.requirements).to eq("= 0.3.64")
        expect(backtrace.package_manager).to eq(DependencyGraphAPI::V1::PackageManager.lookup(DependencyGraphAPI::V1::PackageManager::PACKAGE_MANAGER_RUST))

        expect(backtrace.vulnerable_version_ranges[0].github_id).to eq(vvr.github_id)
        expect(backtrace.vulnerable_version_ranges[0].is_contained).to eq(true)
        expect(backtrace.package_manager).to eq(DependencyGraphAPI::V1::PackageManager.lookup(DependencyGraphAPI::V1::PackageManager::PACKAGE_MANAGER_RUST))
      end

      it "does not return manifests from excluded package managers" do
        stub_const("DependencyGraph::PACKAGE_MANAGER_PREVIEW", [
          Types::PackageManager[:rust]
        ])

        fake_blobs = {
          "fake-cargo-lock-oid" => OpenStruct.new(content: file_fixture("Cargo_v3.lock").read),
          "fake-composer-lock-oid" => OpenStruct.new(content: file_fixture("composer.lock").read),
          "fake-yarn-lock-oid" => OpenStruct.new(content: file_fixture("yarn.lock").read),
          "fake-poetry-lock-oid" => OpenStruct.new(content: file_fixture("poetry.lock").read),
        }
        stubbed_blob_provider = SnapshotRequests::Provider::NoOpProvider.new(get_blob_returns: fake_blobs)
        fake_tree = [
          BlobOperations::Responses::TreeEntry.new(
            blob_operations_provider: stubbed_blob_provider,
            mode: "100755",
            oid: "fake-composer-lock-oid",
            path: "composer.lock",
          ),
          BlobOperations::Responses::TreeEntry.new(
            blob_operations_provider: stubbed_blob_provider,
            mode: "100755",
            oid: "fake-cargo-lock-oid",
            path: "cargo.lock",
          ),
          BlobOperations::Responses::TreeEntry.new(
            blob_operations_provider: stubbed_blob_provider,
            mode: "100644",
            oid: "fake-yarn-lock-oid",
            path: "yarn.lock",
          ),
          BlobOperations::Responses::TreeEntry.new(
            blob_operations_provider: stubbed_blob_provider,
            mode: "100644",
            oid: "fake-poetry-lock-oid",
            path: "poetry.lock",
          ),
        ]
        stubbed_blob_provider.get_tree_returns = fake_tree
        stubbed_handler = RepositoryDependenciesService::V1::Handler.new(
          blob_operations_provider: stubbed_blob_provider,
          dependencies_client: noop_dependencies_client
        )

        req = DependencyGraphAPI::V1::GetDependenciesForRepositoryRequest.new({ repository_id: 12345,
                                                                                sha: "fakefake",
                                                                                enable_preview_ecosystems: true,
                                                                                exclude_ecosystems: ["PACKAGE_MANAGER_NPM", "PACKAGE_MANAGER_RUST"] })

        resp = stubbed_handler.get_dependencies_for_repository(req, {})
        manifests = resp.manifests.map { |m| m.file_path }

        expect(resp.manifests).not_to be_empty
        expect(resp.manifests.count).to eq(2)

        expect(manifests).to match_array(["./composer.lock", "./poetry.lock"])
      end

      it "limits parsed manifests to 150 by default" do
        fake_blobs = {}

        stubbed_blob_provider = SnapshotRequests::Provider::NoOpProvider.new(get_blob_returns: fake_blobs)
        struct_to_use = OpenStruct.new(content: file_fixture("composer.lock").read)
        fake_tree = []
        (0..1000).to_a.each do |n|
          fake_tree.push BlobOperations::Responses::TreeEntry.new(
            blob_operations_provider: stubbed_blob_provider,
            mode: "100755",
            oid: "fake-composer-lock-oid-#{n}",
            path: "#{n}/composer.lock",
          )

          fake_blobs["fake-composer-lock-oid-#{n}"] = struct_to_use
        end

        stubbed_blob_provider.get_tree_returns = fake_tree
        stubbed_handler = RepositoryDependenciesService::V1::Handler.new(
          blob_operations_provider: stubbed_blob_provider,
          dependencies_client: noop_dependencies_client
        )

        req = DependencyGraphAPI::V1::GetDependenciesForRepositoryRequest.new({ repository_id: 12345, sha: "fakefake" })
        resp = stubbed_handler.get_dependencies_for_repository(req, {})

        expect(resp.manifests).not_to be_empty
        expect(resp.manifests.count).to eq(150)

        req = DependencyGraphAPI::V1::GetDependenciesForRepositoryRequest.new({ repository_id: 12345, sha: "fakefake", max_static_manifests: 600 })
        resp = stubbed_handler.get_dependencies_for_repository(req, {})

        expect(resp.manifests).not_to be_empty
        expect(resp.manifests.count).to eq(600)


        req = DependencyGraphAPI::V1::GetDependenciesForRepositoryRequest.new({ repository_id: 12345, sha: "fakefake", max_static_manifests: 2000 })
        resp = stubbed_handler.get_dependencies_for_repository(req, {})

        expect(resp.manifests).not_to be_empty
        expect(resp.manifests.count).to eq(1001)
      end

      it "returns a Twirp error if Spokes call raises an exception" do
        spokes_provider = double(SnapshotRequests::Provider::SpokesProvider.class)
        allow(spokes_provider).to receive(:manifest_tree_entries_at_sha).and_raise(BlobOperations::Spokes::SpokesClientError.new("Some error happened"))

        test_handler = RepositoryDependenciesService::V1::Handler.new(
          dependencies_client: noop_dependencies_client,
          blob_operations_provider: spokes_provider
        )

        req = DependencyGraphAPI::V1::GetDependenciesForRepositoryRequest.new({
          repository_id: 987654321,
          sha: "boom-sha-kalaka",
          max_static_manifests: 100
        })

        resp = test_handler.get_dependencies_for_repository(req, {})
        expect(resp).to be_a Twirp::Error
        expect(resp.code).to eq(:internal)
      end

      it "returns a twirp not found error if a 'not found' Spokes exception is raised" do
        spokes_provider = double(SnapshotRequests::Provider::SpokesProvider.class)
        # For better or worse, right now this is a magic string
        # https://github.com/github/dependency-graph-api/blob/b0d8d2c475b0dbd8b9e95f5cd34ba39661ff0c11/app/handlers/repository_dependencies_service/v1/handler.rb#L222-L224
        allow(spokes_provider).to receive(:manifest_tree_entries_at_sha).and_raise(BlobOperations::Spokes::SpokesClientError.new("object_id.id must be a valid object id"))

        test_handler = RepositoryDependenciesService::V1::Handler.new(
          dependencies_client: noop_dependencies_client,
          blob_operations_provider: spokes_provider
        )

        req = DependencyGraphAPI::V1::GetDependenciesForRepositoryRequest.new({
          repository_id: 987654321,
          sha: "boom-sha-kalaka",
          max_static_manifests: 100
        })

        resp = test_handler.get_dependencies_for_repository(req, {})
        expect(resp).to be_a Twirp::Error
        expect(resp.code).to eq(:not_found)
      end
    end

    describe "db source manifests functionality" do
      before do
        factory do
          django_repository = Repository.find_by(github_repository_id: 12345)
          manifest = Manifest.create!({
            repository_id: django_repository.id,
            package_manager: Types::PackageManager[:composer],
            manifest_type:   Types::Manifest[:composer_lock],
            filename:        "composer.lock",
            path:            "",
            latest_git_ref:  "77dab21",
            last_pushed_at:  Time.now,
          })

          manifest.dependencies.create!({
            package_name:          "symfony/symfony",
            package_manager:       :composer,
            requirements:          "~> 3.9",
            scope:                 :runtime,
            last_seen_at_revision: 0,
            })

          manifest.dependencies.create!({
            package_name:          "symfony/phpunit-bridge",
            package_manager:       :composer,
            requirements:          "~> 4.2",
            scope:                 :development,
            last_seen_at_revision: 0,
          })
        end
      end

      it "returns expect dependencies for repo, with a vulnerability" do
        input = {
          repository_id: 12345
        }
        req = DependencyGraphAPI::V1::GetDependenciesForRepositoryRequest.new(input)
        resp = handler.get_dependencies_for_repository(req, {})

        expect(resp.manifests.length).to eq(1)
        manifest = resp.manifests[0]
        expect(manifest.file_path).to eq("composer.lock")
        expect(manifest.package_manager).to eq(DependencyGraphAPI::V1::PackageManager.lookup(DependencyGraphAPI::V1::PackageManager::PACKAGE_MANAGER_COMPOSER))
        expect(manifest.file_path).to eq("composer.lock")
        expect(manifest.dependencies.length).to eq(2)

        symfony_dependency = manifest.dependencies.find { |d| d.name == "symfony/symfony" }
        expect(symfony_dependency.requirements).to eq("~> 3.9")
        expect(symfony_dependency.scope).to eq("runtime")
        expect(symfony_dependency.vulnerable_version_ranges.length).to eq(1)
        expect(symfony_dependency.vulnerable_version_ranges[0].is_contained).to eq(true)
        expect(symfony_dependency.package_manager).to eq(DependencyGraphAPI::V1::PackageManager.lookup(DependencyGraphAPI::V1::PackageManager::PACKAGE_MANAGER_COMPOSER))

        symfony_dev_dependency = manifest.dependencies.find { |d| d.name == "symfony/phpunit-bridge" }
        expect(symfony_dev_dependency.scope).to eq("development")
      end

      it "returns preview dependencies for repo, with a vulnerability" do
        stub_const("DependencyGraph::PACKAGE_MANAGER_PREVIEW", [
          Types::PackageManager[:rust]
        ])
        stub_const("DependencyGraph::MANIFEST_TYPE_PREVIEW", [
          Types::Manifest[:cargo_lock],
          Types::Manifest[:cargo_toml]
        ])

        factory.given_manifest(
          github_repo_id: 12345,
          manifest_type:  :cargo_lock,
          package_manager: :rust,
          filename:       "Cargo.lock",
          path:           "/",
          dependencies: [
              {
                package_name: "backtrace",
                requirements: "= 0.3.64",
                scope:        :runtime,
              }
            ]

        )

        input = {
          repository_id: 12345,
          enable_preview_ecosystems: true,
        }
        req = DependencyGraphAPI::V1::GetDependenciesForRepositoryRequest.new(input)
        resp = handler.get_dependencies_for_repository(req, {})

        expect(resp.manifests.length).to eq(2)
        manifest = resp.manifests.find { |m| m.file_path == "/Cargo.lock" }

        expect(manifest.package_manager).to eq(DependencyGraphAPI::V1::PackageManager.lookup(DependencyGraphAPI::V1::PackageManager::PACKAGE_MANAGER_RUST))
        expect(manifest.dependencies.length).to eq(1)
        backtrace = manifest.dependencies[0]
        expect(backtrace.name).to eq("backtrace")
        expect(backtrace.requirements).to eq("= 0.3.64")
        expect(backtrace.vulnerable_version_ranges.length).to eq(1)
        expect(backtrace.vulnerable_version_ranges[0].is_contained).to eq(true)
      end

      it "does not return excluded ecosystems" do
        stub_const("DependencyGraph::PACKAGE_MANAGER_PREVIEW", [
          Types::PackageManager[:rust]
        ])
        stub_const("DependencyGraph::MANIFEST_TYPE_PREVIEW", [
          Types::Manifest[:cargo_lock],
          Types::Manifest[:cargo_toml]
        ])

        # to be excluded
        factory.given_manifest(
          github_repo_id: 12345,
          manifest_type:  :package_lock_json,
          package_manager: :npm,
          filename:       "package-lock.json",
          path:           "/",
          dependencies: [
              {
                package_name: "backtrace",
                requirements: "= 0.3.64",
                scope:        :runtime,
              }
            ]

        )

        # a second exclusion
        factory.given_manifest(
          github_repo_id: 12345,
          manifest_type:  :pom_xml,
          package_manager: :maven,
          filename:       "pom.xml",
          path:           "/",
          dependencies: [
              {
                package_name: "backtrace",
                requirements: "= 0.3.64",
                scope:        :runtime,
              }
            ]

        )

        # to be included
        factory.given_manifest(
          github_repo_id: 12345,
          manifest_type:  :cargo_lock,
          package_manager: :rust,
          filename:       "Cargo.lock",
          path:           "/",
          dependencies: [
              {
                package_name: "backtrace",
                requirements: "= 0.3.64",
                scope:        :runtime,
              }
            ]

        )

        input = {
          repository_id: 12345,
          enable_preview_ecosystems: true,
          exclude_ecosystems: ["PACKAGE_MANAGER_NPM", "PACKAGE_MANAGER_MAVEN"],
        }
        req = DependencyGraphAPI::V1::GetDependenciesForRepositoryRequest.new(input)
        resp = handler.get_dependencies_for_repository(req, {})

        expect(resp.manifests.length).to eq(2)
        manifests = resp.manifests.map { |m| m.file_path }

        expect(manifests).to match_array(["composer.lock", "/Cargo.lock"])
      end

      it "gracefully handles a repository with no manifests" do
        input = {
          repository_id: 987654321
        }
        req = DependencyGraphAPI::V1::GetDependenciesForRepositoryRequest.new(input)
        resp = handler.get_dependencies_for_repository(req, {})

        expect(resp.is_a?(Twirp::Error)).to eq(false)
        expect(resp.manifests).to be_empty
      end

      it "returns a Twirp error if database call raises an exception" do
        allow(Repository).to receive(:find_by).and_raise(ActiveRecord::DatabaseConnectionError.new)

        input = {
          repository_id: 987654321
        }
        req = DependencyGraphAPI::V1::GetDependenciesForRepositoryRequest.new(input)

        expect(handler.get_dependencies_for_repository(req, {})).to be_a Twirp::Error
      end
    end
  end
end

describe RepositoryDependenciesService::V1::Handler do
  let(:noop_blob_operations_provider) { SnapshotRequests::Provider::NoOpProvider.new }
  let(:noop_dependencies_client) { NoOpTestDependenciesClient::new }

  let(:handler) {
    RepositoryDependenciesService::V1::Handler.new(
      dependencies_client: noop_dependencies_client,
      blob_operations_provider: noop_blob_operations_provider
    )
  }

  context "normalised tables (dotcom and Proxima)" do
    before do
      allow(DependencyGraph).to receive(:use_normalized_tables?).and_return(true)
    end

    context "search_dependencies" do
      it_behaves_like "a dependency search request"
    end

    context "get_dependencies_for_repository" do
      it_behaves_like "a get dependencies for repository request"
    end
  end

  context "unnormalised tables (GHES)" do
    before do
      allow(DependencyGraph).to receive(:use_normalized_tables?).and_return(false)
    end

    context "search_dependencies" do
      it_behaves_like "a dependency search request"
    end

    context "get_dependencies_for_repository" do
      it_behaves_like "a get dependencies for repository request"
    end
  end

  describe "has_manifests" do
    before do
      factory do
        Repository.create!({
          github_repository_id: 100,
          nwo: "django/django"
        })

        Repository.create!({
          github_repository_id: 200,
          nwo: "numpy/numpy"
        })

        given_manifest(
          github_repo_id: 100,
          package_manager: :pip,
          manifest_type:  :requirements_txt,
          filename:       "requirements.txt",
          path:           "/",
          dependencies:   [
            {
              package_name: "requests",
              requirements: "= 2.0.0",
            }
          ]
        )
      end

      DependencyGraph.flipper.disable(:dependency_graph_dgp_backed_npm_graphql)
    end

    # convenience definitions
    let(:nonexistent_repository_id) { 333 }
    let(:input_repository_id) { 100 }
    let(:empty_respository_id) { 200 }

    let(:snapshot_has_manifests_client) {
      SnapshotsHasManifestsTestClient.new(should_return: true)
    }

    let(:snapshot_has_manifests_error_client) {
      SnapshotsHasManifestsErrorClient.new
    }

    let(:handler_has_snapshot_manifests) {
      RepositoryDependenciesService::V1::Handler.new(
        dependencies_client: snapshot_has_manifests_client,
      )
    }

    let(:handler_has_snapshots_error) {
      RepositoryDependenciesService::V1::Handler.new(
        dependencies_client: snapshot_has_manifests_error_client,
      )
    }

    let(:dgp_has_manifests_client) {
      MockDGPGraphQLResolverClient.new(has_manifests: true)
    }

    let(:dgp_has_manifests_error_client) {
      MockDGPGraphQLResolverClient.new(has_errors: true)
    }

    let(:handler_has_dgp_manifests) {
      RepositoryDependenciesService::V1::Handler.new(
        dgp_graphql_resolver_client: dgp_has_manifests_client,
      )
    }

    let(:handler_has_dgp_error) {
      RepositoryDependenciesService::V1::Handler.new(
        dgp_graphql_resolver_client: dgp_has_manifests_error_client,
      )
    }

    it "returns a 4xx Twirp error if a nonexistent repository ID is supplied" do
      req = DependencyGraphAPI::V1::HasManifestsRequest.new({
        repository_id: nonexistent_repository_id,
        only_static_manifests: true
      })

      resp = handler.has_manifests(req, {})
      expect(resp.code).to eq(:not_found)
    end

    it "returns a 4xx Twirp error if no repository ID is supplied" do
      req = DependencyGraphAPI::V1::HasManifestsRequest.new({
        repository_id: nil
      })

      resp = handler.has_manifests(req, {})
      expect(resp.code).to eq(:invalid_argument)
    end

    it "returns true for a repository that has manifests" do
      req = DependencyGraphAPI::V1::HasManifestsRequest.new({
        repository_id: input_repository_id,
        only_static_manifests: true
      })

      resp = handler.has_manifests(req, {})
      assert resp.has_manifests
    end

    it "does not call DGP nor Snapshots service if there are manifests in the database" do
      repo_id = Repository.find_by_github_repository_id(input_repository_id).id
      expect(Manifest.where(repository_id: repo_id).count).to be > 0

      # Ensure the feature flag is enabled so we will call DGP if there are _no_ manifests.
      DependencyGraph.flipper.enable(:dependency_graph_dgp_backed_npm_graphql)

      req = DependencyGraphAPI::V1::HasManifestsRequest.new({
        repository_id: input_repository_id,
        # Ensure this is 'false' so we will call the snapshots service if there are _no_ manifests.
        only_static_manifests: false
      })

      allow(dgp_has_manifests_client).to receive(:repository_has_manifests).and_call_original
      allow(snapshot_has_manifests_client).to receive(:has_manifests).and_call_original

      resp = handler_has_snapshot_manifests.has_manifests(req, {})

      expect(dgp_has_manifests_client).not_to have_received(:repository_has_manifests)
      expect(snapshot_has_manifests_client).not_to have_received(:has_manifests)
      expect(resp.has_manifests).to be true
    end

    it "returns true for a repository that has manifests in dgp when the flag is enabled" do
      # ensure all Manifests are deleted
      Manifest.all.each(&:destroy)

      # First assert that if we only check for static manifests without the feature flag, we get false
      req = DependencyGraphAPI::V1::HasManifestsRequest.new({
        repository_id: input_repository_id,
        only_static_manifests: true
      })
      resp = handler_has_dgp_manifests.has_manifests(req, {})
      refute resp.has_manifests

      # Next assert that if we enable the feature flag, we get true
      DependencyGraph.flipper.enable(:dependency_graph_dgp_backed_npm_graphql)
      req = DependencyGraphAPI::V1::HasManifestsRequest.new({
        repository_id: input_repository_id,
        only_static_manifests: true
      })
      resp = handler_has_dgp_manifests.has_manifests(req, {})
      assert resp.has_manifests
    end

    it "bubbles up an error if there is an error in DGP" do
      # ensure all Manifests are deleted to ensure we proceed to Snapshots service
      Manifest.all.each(&:destroy)

      # Ensure the feature flag is enabled so we will call DGP if there are _no_ manifests.
      DependencyGraph.flipper.enable(:dependency_graph_dgp_backed_npm_graphql)

      req = DependencyGraphAPI::V1::HasManifestsRequest.new({
        repository_id: input_repository_id,
        only_static_manifests: true
      })

      resp = handler_has_dgp_error.has_manifests(req, {})

      expect(resp).to be_a(Twirp::Error)
      expect(resp.code).to be :internal
    end

    it "calls DGP even if the repository does not exist in the repository table" do
      # ensure all Manifests are deleted to ensure we proceed to DGP
      Manifest.all.each(&:destroy)
      Repository.where(github_repository_id: input_repository_id).each(&:destroy)

      # Ensure the feature flag is enabled so we will call DGP if there are _no_ manifests.
      DependencyGraph.flipper.enable(:dependency_graph_dgp_backed_npm_graphql)

      req = DependencyGraphAPI::V1::HasManifestsRequest.new({
        repository_id: input_repository_id,
        only_static_manifests: true
      })

      allow(dgp_has_manifests_client).to receive(:repository_has_manifests).and_call_original

      resp = handler_has_dgp_manifests.has_manifests(req, {})

      expect(dgp_has_manifests_client).to have_received(:repository_has_manifests)
      expect(resp.has_manifests).to be true
    end

    it "returns true for a repository that has manifests in snapshots" do
      # ensure all Manifests are deleted
      Manifest.all.each(&:destroy)

      # First assert that if we only check for static manifests, we get false
      req = DependencyGraphAPI::V1::HasManifestsRequest.new({
        repository_id: input_repository_id,
        only_static_manifests: true
      })
      resp = handler_has_snapshot_manifests.has_manifests(req, {})
      refute resp.has_manifests

      # Next assert that if we include snapshot manifests, we get true
      req = DependencyGraphAPI::V1::HasManifestsRequest.new({
        repository_id: input_repository_id,
        only_static_manifests: false
      })
      resp = handler_has_snapshot_manifests.has_manifests(req, {})
      assert resp.has_manifests
    end

    it "bubbles up an error if there is an error in Snapshot service" do
      # ensure all Manifests are deleted to ensure we proceed to Snapshots service
      Manifest.all.each(&:destroy)

      req = DependencyGraphAPI::V1::HasManifestsRequest.new({
        repository_id: input_repository_id,
        only_static_manifests: false
      })

      resp = handler_has_snapshots_error.has_manifests(req, {})

      expect(resp).to be_a(Twirp::Error)
      expect(resp.code).to be :internal
    end

    it "calls Snapshots service even if the repository does not exist in the repository table" do
      # ensure all Manifests are deleted to ensure we proceed to Snapshots service
      Manifest.all.each(&:destroy)
      Repository.where(github_repository_id: input_repository_id).each(&:destroy)

      req = DependencyGraphAPI::V1::HasManifestsRequest.new({
        repository_id: input_repository_id,
        only_static_manifests: false
      })

      allow(snapshot_has_manifests_client).to receive(:has_manifests).and_call_original

      resp = handler_has_snapshot_manifests.has_manifests(req, {})

      expect(snapshot_has_manifests_client).to have_received(:has_manifests)
      expect(resp.has_manifests).to be true
    end

    it "returns false for a repository that has no manifests" do
      req = DependencyGraphAPI::V1::HasManifestsRequest.new({
        repository_id: empty_respository_id,
        only_static_manifests: true
      })

      resp = handler.has_manifests(req, {})
      refute resp.has_manifests
    end
  end

  describe "repositories_containing_dependency"  do
    it "returns a valid response object if ds-api returns it" do
      handler = RepositoryDependenciesService::V1::Handler.new(
        dependencies_client: RepositoriesContainingDependencyClient.new
      )
      req = DependencyGraphAPI::V1::RepositoriesContainingDependencyRequest.new({
        base_purl: "valid purl",
        version_range: ">=1.0.0"
      })
      resp = handler.repositories_containing_dependency(req, {})
      expect(resp.is_a?(Twirp::Error)).to eq(false)
      expect(resp.repository_ids).to eq([1, 2, 3, 4, 5])
    end

    it "returns a properly formatted Twirp error if ds-api returns an error " do
      handler = RepositoryDependenciesService::V1::Handler.new(
        dependencies_client: RepositoriesContainingDependencyClient.new
      )
      req = DependencyGraphAPI::V1::RepositoriesContainingDependencyRequest.new({
        base_purl: "invalid purl",
        version_range: ">=1.0.0"
      })
      resp = handler.repositories_containing_dependency(req, {})
      expect(resp.is_a?(Twirp::Error)).to eq(true)
      expect(resp.code).to eq(:invalid_argument)
    end
  end
end


class NoOpTestDependenciesClient
  def get_dependencies_for_repository(repository_id, include_internal_snapshots: false, **kwargs)
    Twirp::ClientResp.new(data: Github::DependencySnapshotsApi::GetDependenciesForRepositoryResponse.new(manifests: {}))
  end
end

class MockDGPRepoInsightsClient
  attr_reader :vulnerable_dependencies,
    :non_vulnerable_dependencies

  def initialize(vulnerable_dependencies: [], non_vulnerable_dependencies: [])
    @vulnerable_dependencies = vulnerable_dependencies
    @non_vulnerable_dependencies = non_vulnerable_dependencies
    @root_ancestors_for_dependencies = {}
  end

  def get_dependencies_for_repository(**kwargs)
    results = case kwargs[:vulnerability_filter]
              when :VULNERABILITY_FILTER_VULNERABLE
                get_vulnerable_dependencies_for_repository(**kwargs)
              when :VULNERABILITY_FILTER_NOT_VULNERABLE
                get_non_vulnerable_dependencies_for_repository(**kwargs)
              else
                raise "expected vulnerability filter"
              end

    if kwargs[:relationship_filter]
      results.data.dependencies.select! { |dependency| dependency.relationship == kwargs[:relationship_filter].to_sym }
      results.data.total_dependencies = results.data.dependencies.size
    end

    results
  end

  def set_mock_root_ancestors_for_dependencies(dependency_map)
    @root_ancestors_for_dependencies = dependency_map
  end

  def get_root_ancestors_for_dependencies(repository_id:, dependency_ids:)
    dependencies = dependency_ids.map do |dependency_id|
      {
        id: dependency_id,
        root_ancestors: @root_ancestors_for_dependencies[dependency_id] || []
      }
    end

    Twirp::ClientResp.new(
      data: Github::DependencyGraphPlatform::RepoInsights::V1::GetRootAncestorsForDependenciesResponse.new(
        dependencies: dependencies,
      )
    )
  end

  private

  def get_vulnerable_dependencies_for_repository(**kwargs)
    Twirp::ClientResp.new(
      data: Github::DependencyGraphPlatform::RepoInsights::V1::GetDependenciesForRepositoryResponse.new(
        dependencies: vulnerable_dependencies,
        total_dependencies: vulnerable_dependencies.count,
        ecosystems: [:ECOSYSTEM_NPM]
      )
    )
  end

  def get_non_vulnerable_dependencies_for_repository(pagination:, **kwargs)
    Twirp::ClientResp.new(
      data: Github::DependencyGraphPlatform::RepoInsights::V1::GetDependenciesForRepositoryResponse.new(
        dependencies: non_vulnerable_dependencies.slice(pagination[:offset], pagination[:limit]),
        total_dependencies: non_vulnerable_dependencies.count,
        ecosystems: [:ECOSYSTEM_NPM]
      )
    )
  end
end

class MockDGPGraphQLResolverClient
  def initialize(has_manifests: false, has_errors: false)
    @has_manifests = has_manifests
    @has_errors = has_errors
  end

  def repository_has_manifests(_)
    if @has_errors
      return Twirp::ClientResp.new(error: Twirp::Error.new(:internal, "internal error", {}))
    end
    Twirp::ClientResp.new(data: Github::DependencyGraphPlatform::Graphql::V1::RepositoryHasManifestsResponse.new(
      has_manifests: @has_manifests
    ))
  end
end

class SimpleTestDependenciesClient
  def get_dependencies_for_repository(repository_id, include_internal_snapshots: false, include_root_ancestors: false, relationship_filter: nil, **kwargs)
    manifests = {
      "package-lock.json": Github::DependencySnapshotsApi::Manifest.new(
            snapshot_id: 1,
            file_path: "/some/path/package-lock.json",
            dependencies: {
              "@actions/http-client": Github::DependencySnapshotsApi::Manifest::Dependency.new(
                package_url: "pkg:/npm/%40actions/http-client@1.0.7",
                dependencies: ["tunnel"],
                scope: :SCOPE_NONE,
                relationship: :RELATIONSHIP_TRANSITIVE,
                root_ancestors: [{ package_name: "@actions/core", requirements: "1.0.7", relationship: :ANCESTOR_RELATIONSHIP_PARENT }]
              ),
              "@actions/core": Github::DependencySnapshotsApi::Manifest::Dependency.new(
                package_url: "pkg:/npm/%40actions/core@1.1.9",
                dependencies: ["@actions/http-client"],
                scope: :SCOPE_RUNTIME,
                relationship: :RELATIONSHIP_DIRECT,
                root_ancestors: []
              ),
              "tunnel": Github::DependencySnapshotsApi::Manifest::Dependency.new(
                package_url: "pkg:/npm/tunnel@0.0.6",
                dependencies: [],
                scope: :SCOPE_DEVELOPMENT,
                relationship: :RELATIONSHIP_UNKNOWN,
                root_ancestors: [{ package_name: "@actions/core", requirements: "1.0.7", relationship: :ANCESTOR_RELATIONSHIP_ANCESTOR }]
              ),
            }
          ),
      "sbom": Github::DependencySnapshotsApi::Manifest.new(
            snapshot_id: 2,
            file_path: "sbom.spdx",
            dependencies: {
              "ubuntu": Github::DependencySnapshotsApi::Manifest::Dependency.new(
                package_url: "pkg:deb/ubuntu/dpkg@1.19.0.4?arch=amd64",
                dependencies: [],
                scope: :SCOPE_NONE,
                relationship: :RELATIONSHIP_DIRECT,
              ),
              "curl": Github::DependencySnapshotsApi::Manifest::Dependency.new(
                package_url: "pkg:apk/alpine/curl@7.83.0-r0?arch=x86",
                dependencies: [],
                scope: :SCOPE_NONE,
                relationship: :RELATIONSHIP_DIRECT,
              ),
            }
          )
        }
    unless include_root_ancestors
      manifests[:"package-lock.json"].dependencies.each do |_, dep|
        dep.root_ancestors = dep.root_ancestors.clear
      end
    end
    if relationship_filter
      manifests.each do |key, manifest|
        to_delete = manifest.dependencies.filter_map { |k, dep| dep.relationship != relationship_filter ? k : nil }
        to_delete.each { |k| manifests[key].dependencies.delete(k) }
      end
    end

    internal_manifest = Github::DependencySnapshotsApi::Manifest.new(
      file_path: "internal/package-lock.json",
      dependencies: {
        "react": Github::DependencySnapshotsApi::Manifest::Dependency.new(
          package_url: "pkg:/npm/react@1.2.3",
          dependencies: ["react-dom"]
        ),
        "react-dom": Github::DependencySnapshotsApi::Manifest::Dependency.new(
          package_url: "pkg:/npm/react-dom@2.3.4",
          dependencies: []
      )
    }
    )
    manifests["internal/package-lock.json"] = internal_manifest if include_internal_snapshots
    all_manifests = manifests.map do |name, manifest|
      manifest.name = name
      manifest
    end
    Twirp::ClientResp.new(data: Github::DependencySnapshotsApi::GetDependenciesForRepositoryResponse.new(
      manifests: manifests,
      all_manifests: all_manifests,
      snapshots: {
        1 => Github::DependencySnapshotsApi::GetDependenciesForRepositoryResponse::Snapshot.new(
          scanned: Time.utc(2023, 01, 01),
          detector: Github::DependencySnapshotsApi::GetDependenciesForRepositoryResponse::Snapshot::DetectorMetadata.new(
            name: "test-detector"
          )
        ),
        2 => Github::DependencySnapshotsApi::GetDependenciesForRepositoryResponse::Snapshot.new(
          scanned: Time.utc(2023, 01, 01),
          detector: Github::DependencySnapshotsApi::GetDependenciesForRepositoryResponse::Snapshot::DetectorMetadata.new(
            name: "test-detector"
          )
        )
      }
    ))
  end
end

class FailsTestIfCalledDependenciesClient
  def get_dependencies_for_repository(repository_id, include_internal_snapshots: false, **kwargs)
    raise "get_dependencies_for_repository should not be called for this test method"
  end
end

class MultipleManifestsForSameFileDependenciesTestClient
  def get_dependencies_for_repository(repository_id, include_internal_snapshots: false, **kwargs)
    Twirp::ClientResp.new(data: Github::DependencySnapshotsApi::GetDependenciesForRepositoryResponse.new(
        manifests: {
          "first entry for same package-lock": Github::DependencySnapshotsApi::Manifest.new(
            file_path: "/some/path/package-lock.json",
            dependencies: {
              "@actions/http-client": Github::DependencySnapshotsApi::Manifest::Dependency.new(
                package_url: "pkg:/npm/%40actions/http-client@1.0.6",
                dependencies: ["tunnel"]
              ),
              "@actions/core": Github::DependencySnapshotsApi::Manifest::Dependency.new(
                package_url: "pkg:/npm/%40actions/core@1.2.0",
                dependencies: ["@actions/http-client"],
              )
            }
          ),
          "second entry for same package lock": Github::DependencySnapshotsApi::Manifest.new(
            file_path: "/some/path/package-lock.json",
            dependencies: {
              "@actions/http-client": Github::DependencySnapshotsApi::Manifest::Dependency.new(
                package_url: "pkg:/npm/%40actions/http-client@1.0.7",
                dependencies: ["tunnel"]
              ),
              "@actions/core": Github::DependencySnapshotsApi::Manifest::Dependency.new(
                package_url: "pkg:/npm/%40actions/core@1.1.9",
                dependencies: ["@actions/http-client"],
              ),
              "tunnel": Github::DependencySnapshotsApi::Manifest::Dependency.new(
                package_url: "pkg:/npm/tunnel@0.0.6",
                dependencies: [],
              ),
            }
          )
        },
        all_manifests: [
          Github::DependencySnapshotsApi::Manifest.new(
            file_path: "/some/path/package-lock.json",
            name: "first entry for same package-lock",
            dependencies: {
              "@actions/http-client": Github::DependencySnapshotsApi::Manifest::Dependency.new(
                package_url: "pkg:/npm/%40actions/http-client@1.0.6",
                dependencies: ["tunnel"]
              ),
              "@actions/core": Github::DependencySnapshotsApi::Manifest::Dependency.new(
                package_url: "pkg:/npm/%40actions/core@1.2.0",
                dependencies: ["@actions/http-client"],
              )
            }
          ),
          Github::DependencySnapshotsApi::Manifest.new(
            file_path: "/some/path/package-lock.json",
            name: "second entry for same package lock",
            dependencies: {
              "@actions/http-client": Github::DependencySnapshotsApi::Manifest::Dependency.new(
                package_url: "pkg:/npm/%40actions/http-client@1.0.7",
                dependencies: ["tunnel"]
              ),
              "@actions/core": Github::DependencySnapshotsApi::Manifest::Dependency.new(
                package_url: "pkg:/npm/%40actions/core@1.1.9",
                dependencies: ["@actions/http-client"],
              ),
              "tunnel": Github::DependencySnapshotsApi::Manifest::Dependency.new(
                package_url: "pkg:/npm/tunnel@0.0.6",
                dependencies: [],
              ),
            }
          )
        ]
      ))
  end
end

class GnarlyPurlTestDependenciesClient
  # pkg:maven/org.springframework/spring-core@6.+%20FAILED
  def get_dependencies_for_repository(repository_id, include_internal_snapshots: false, **kwargs)
    Twirp::ClientResp.new(data: Github::DependencySnapshotsApi::GetDependenciesForRepositoryResponse.new(
      manifests: {
        "pom.xml": Github::DependencySnapshotsApi::Manifest.new(
          file_path: "pom.xml",
          dependencies: {
            "pkg:maven/org.springframework/spring-core@6.+%20FAILED": Github::DependencySnapshotsApi::Manifest::Dependency.new(
              package_url: "pkg:maven/org.springframework/spring-core@6.+%20FAILED",
              dependencies: []
            ),
          }
        )
      },
      all_manifests: [
        Github::DependencySnapshotsApi::Manifest.new(
          file_path: "pom.xml",
          name: "pom.xml",
          dependencies: {
            "pkg:maven/org.springframework/spring-core@6.+%20FAILED": Github::DependencySnapshotsApi::Manifest::Dependency.new(
              package_url: "pkg:maven/org.springframework/spring-core@6.+%20FAILED",
              dependencies: []
            ),
          }
        )
      ]
    ))
  end
end

class UnknownPackageTestDependenciesClient
  def get_dependencies_for_repository(repository_id, include_internal_snapshots: false, **kwargs)
    Twirp::ClientResp.new(data: Github::DependencySnapshotsApi::GetDependenciesForRepositoryResponse.new(
      manifests: {
        "unknown.lock": Github::DependencySnapshotsApi::Manifest.new(
          file_path: "/some/path/unknown.filename",
          dependencies: {
            "@actions/http-client": Github::DependencySnapshotsApi::Manifest::Dependency.new(
              package_url: "pkg:/npm/%40actions/http-client@1.0.6",
              dependencies: []
            ),
          }
        )
      },
      all_manifests: [
        Github::DependencySnapshotsApi::Manifest.new(
          file_path: "/some/path/unknown.filename",
          name: "unknown.lock",
          dependencies: {
            "@actions/http-client": Github::DependencySnapshotsApi::Manifest::Dependency.new(
              package_url: "pkg:/npm/%40actions/http-client@1.0.6",
              dependencies: []
            ),
          }
        )
      ]
    ))
  end
end

class RepositoriesContainingDependencyClient
  def repositories_containing_dependency(base_purl, version_range)
    if base_purl == "valid purl"
      Twirp::ClientResp.new(data: DependencyGraphAPI::V1::RepositoriesContainingDependencyResponse.new(
        repository_ids: [1, 2, 3, 4, 5]
      ))
    else
      OpenStruct.new(error: (OpenStruct.new(code: :invalid_argument, msg: "invalid purl", meta: {})))
    end
  end
end

class SnapshotsHasManifestsTestClient
  def initialize(should_return:)
    @has_manifests = should_return
  end

  def has_manifests(_)
    Twirp::ClientResp.new(data: Github::DependencySnapshotsApi::HasManifestsResponse.new(
      has_manifests: @has_manifests
    ))
  end
end

class SnapshotsHasManifestsErrorClient
  def has_manifests(_)
    Twirp::ClientResp.new(error: Twirp::Error.new(:internal, "internal error", {}))
  end
end

# Real dirty helper because I was fed up of debugging failint handlers without seeing
# the actual cause of the failure in tests.
def expect_no_twirp_error(obj)
  str = ""
  last_failbot_report = Failbot.reports.first
  if last_failbot_report.present?
    ed = last_failbot_report["exception_detail"].first
    str += ed["type"] + "\n"
    str += ed["value"] + "\n"
    ed["stacktrace"].each do |frame|
      if frame["in_app"]
        str += "\t#{frame['filename']}:#{frame['lineno']}\n"
      end
    end
  end

  expect(obj).not_to be_a(Twirp::Error), str
end
