require "rails_helper"
require_relative "../../lib/monolith/features_helpers.rb"
require "dependency_snapshots_api/dependencies_client"
require "dependency_graph/object_model/ds_api_dependency.rb"

module Queries
  describe ManifestsQuery do
    include Monolith::FeaturesHelpers
    before(:each) do
      # Disable the DGP gateway by default
      allow_any_instance_of(Queries::ManifestsQuery).to receive(:dgp_available).and_return(false)
      allow_any_instance_of(DependencyGraphAPI::DependencySnapshotsAPI::DependenciesClient)
        .to receive(:get_dependencies_for_repository).and_return(twirp_response)
    end

    let(:twirp_response) do
      Twirp::ClientResp.new(
        data: Github::DependencySnapshotsApi::GetDependenciesForRepositoryResponse.new(manifests: {})
      )
    end

    let!(:manifest_1) do
      builder = factory.given_manifest(
        github_repo_id: 100,
        manifest_type:  :gemspec,
        filename:       "lib_1.gemspec",
        path:           "/lib"
      )
      builder.add_dependency("rake", "> 0.0.0")

      builder.manifest
    end

    let!(:manifest_2) do
      builder = factory.given_manifest(
        github_repo_id: 200,
        manifest_type:  :gemspec,
        filename:       "lib_2.gemspec",
        path:           "/"
      )

      builder.manifest
    end

    it "returns manifests for repos sorted by path" do
      query = described_class.new(
        repository_ids: [100, 200]
      )

      expect(query.manifests).to eq [
        manifest_2,
        manifest_1,
      ]
    end

    it "scopes to manifests with dependencies" do
      query = described_class.new(
        repository_ids:    [100, 200],
        with_dependencies: true
      )

      expect(query.manifests).to eq [
        manifest_1,
      ]
    end

    it "doesn't include vendored manifests" do
      excluded = factory.given_manifest(
        github_repo_id: 100,
        manifest_type:  :gemspec,
        filename:       "lib_1.gemspec",
        path:           "vendor/gem"
      ).manifest

      query = described_class.new(
        repository_ids: [100],
      )

      expect(query.manifests).to_not include(excluded)
    end

    it "scopes to manifests for a given package name" do
      with_name = factory.given_manifest(
        github_repo_id: 300,
        manifest_type:  :gemspec,
        filename:       "lib_1.gemspec",
        name: "lib1"
      ).manifest

      query = described_class.new(
        repository_ids: [100, 200, 300],
        package_name: "lib1",
      )

      expect(query.manifests).to eq [with_name]
    end

    it "scopes to manifests for a given package manager" do
      npm = factory.given_manifest(
        github_repo_id: 300,
        manifest_type:  :package_lock_json,
        filename:       "package-lock.json",
        package_manager: :npm
      ).manifest

      query = described_class.new(
        repository_ids: [100, 200, 300],
        package_manager: Types::PackageManager.coerce(:npm),
      )

      expect(query.manifests).to eq [npm]
    end

    it "returns only the snapshot manifest when a duplicate exists in local" do
      allow_any_instance_of(Queries::ManifestsQuery).to receive(:dgp_available).and_return(false)
      allow(DependencyGraphAPI).to receive(:snapshots_enabled?).and_return(true)
      allow_any_instance_of(DependencyGraphAPI::DependencySnapshotsAPI::DependenciesClient)
        .to receive(:get_dependencies_for_repository)
        .and_return(ds_api_manifests(path: "/package-lock.json"))

      factory.given_manifest(
        github_repo_id: 123,
        manifest_type:  :package_lock_json,
        filename:       "package-lock.json",
        path:           "/"
      )

      query = described_class.new(
        repository_ids: [123],
      )

      expect(query.manifests).to all be_a(DependencyGraph::ObjectModel::DSGraphqlManifest)
    end

    it "returns only the local manifest when snapshots not enabled" do
      allow_any_instance_of(Queries::ManifestsQuery).to receive(:dgp_available).and_return(false)
      allow(DependencyGraphAPI).to receive(:snapshots_enabled?).and_return(false)
      allow_any_instance_of(DependencyGraphAPI::DependencySnapshotsAPI::DependenciesClient)
        .to receive(:get_dependencies_for_repository)
        .and_return(ds_api_manifests(path: "/package-lock.json"))

      factory.given_manifest(
        github_repo_id: 123,
        manifest_type:  :package_lock_json,
        filename:       "package-lock.json",
        path:           "/"
      )

      query = described_class.new(
        repository_ids: [123],
      )

      expect(query.manifests).to all be_a(Manifest)
    end

    it "returns only the local manifest when with_snapshots option false" do
      allow_any_instance_of(Queries::ManifestsQuery).to receive(:dgp_available).and_return(false)
      allow_any_instance_of(DependencyGraphAPI::DependencySnapshotsAPI::DependenciesClient)
        .to receive(:get_dependencies_for_repository)
        .and_return(ds_api_manifests(path: "/package-lock.json"))

      factory.given_manifest(
        github_repo_id: 123,
        manifest_type:  :package_lock_json,
        filename:       "package-lock.json",
        path:           "/"
      )

      query = described_class.new(
        repository_ids: [123],
        with_snapshots: false
      )

      manifests = query.manifests
      expect(manifests).to all be_a(Manifest)

      expect(manifests.count).to eq(1)
    end

    it "returns local manifests and snapshots when they have different paths" do
      allow_any_instance_of(Queries::ManifestsQuery).to receive(:dgp_available).and_return(false)

      factory.given_manifest(
        github_repo_id: 123,
        manifest_type:  :package_lock_json,
        filename:       "package-lock.json",
        path:           "/local-path/"
      ).manifest

      allow_any_instance_of(DependencyGraphAPI::DependencySnapshotsAPI::DependenciesClient)
        .to receive(:get_dependencies_for_repository)
        .and_return(ds_api_manifests(path: "/package-lock.json"))

      query = described_class.new(
        repository_ids: [123],
      )

      expect(query.manifests.first).to be_a(DependencyGraph::ObjectModel::DSGraphqlManifest)
      expect(query.manifests.second).to be_a(Manifest)
    end

    it "returns snapshots manifests when dgp returns manifests and they have the same path" do
      allow_any_instance_of(Queries::ManifestsQuery).to receive(:dgp_available).and_return(true)
      allow_any_instance_of(DependencyGraphAPI::DependencyGraphPlatform::GraphQLResolverClient)
        .to receive(:get_manifests_for_repository)
        .and_return(dgp_manifests(path: "/"))

      allow_any_instance_of(DependencyGraphAPI::DependencySnapshotsAPI::DependenciesClient)
        .to receive(:get_dependencies_for_repository)
        .and_return(ds_api_manifests(path: "/package-lock.json"))

      query = described_class.new(
        repository_ids: [123],
      )

      expect(query.manifests).to all be_a(DependencyGraph::ObjectModel::DSGraphqlManifest)
    end

    it "uses snapshot name to deduplicate if snapshot does not have path" do
      allow_any_instance_of(Queries::ManifestsQuery).to receive(:dgp_available).and_return(false)
      factory.given_manifest(
        github_repo_id: 123,
        manifest_type:  :package_lock_json,
        filename:       "package-lock.json",
        path:           "/"
      ).manifest

      allow_any_instance_of(DependencyGraphAPI::DependencySnapshotsAPI::DependenciesClient)
        .to receive(:get_dependencies_for_repository)
        .and_return(ds_api_manifests(path: nil, name: "package-lock.json"))

      query = described_class.new(
        repository_ids: [123],
      )

      expect(query.manifests).to all be_a(DependencyGraph::ObjectModel::DSGraphqlManifest)
    end

    it "returns snapshot manifests normalizing paths" do
      allow_any_instance_of(Queries::ManifestsQuery).to receive(:dgp_available).and_return(true)
      allow_any_instance_of(DependencyGraphAPI::DependencyGraphPlatform::GraphQLResolverClient)
        .to receive(:get_manifests_for_repository)
        .and_return(dgp_manifests(path: "./"))

      factory.given_manifest(
        github_repo_id: 123,
        manifest_type:  :package_lock_json,
        filename:       "package-lock.json",
        path:           "/"
      ).manifest

      allow_any_instance_of(DependencyGraphAPI::DependencySnapshotsAPI::DependenciesClient)
        .to receive(:get_dependencies_for_repository)
        .and_return(ds_api_manifests(path: "package-lock.json"))

      query = described_class.new(
        repository_ids: [123],
      )

      expect(query.manifests).to all be_a(DependencyGraph::ObjectModel::DSGraphqlManifest)
    end

    it "returns dgp and snapshots manifests when they have different path" do
      allow_any_instance_of(Queries::ManifestsQuery).to receive(:dgp_available).and_return(true)
      allow_any_instance_of(DependencyGraphAPI::DependencyGraphPlatform::GraphQLResolverClient)
        .to receive(:get_manifests_for_repository)
        .and_return(dgp_manifests(path: "/foo/package-lock.json"))

      allow_any_instance_of(DependencyGraphAPI::DependencySnapshotsAPI::DependenciesClient)
        .to receive(:get_dependencies_for_repository)
        .and_return(ds_api_manifests(path: "/package-lock.json"))

      query = described_class.new(
        repository_ids: [123],
      )

      expect(query.manifests.first).to be_a(DependencyGraph::ObjectModel::DSGraphqlManifest)
      expect(query.manifests.second).to be_a(DependencyGraph::ObjectModel::DGPGraphqlManifest)
    end

    it "returns a total manifests count with duplicates removed" do
      allow_any_instance_of(Queries::ManifestsQuery).to receive(:dgp_available).and_return(true)
      allow_any_instance_of(DependencyGraphAPI::DependencySnapshotsAPI::DependenciesClient)
        .to receive(:get_dependencies_for_repository)
        .and_return(ds_api_manifests(path: "/package-lock.json"))
      allow_any_instance_of(DependencyGraphAPI::DependencyGraphPlatform::GraphQLResolverClient)
        .to receive(:get_manifests_for_repository)
        .and_return(dgp_manifests(path: "/"))

      factory.given_manifest(
        github_repo_id: 123,
        manifest_type:  :package_lock_json,
        filename:       "package-lock.json",
        path:           "/"
      )

      query = described_class.new(
        repository_ids: [123],
        with_snapshots: true
      )

      count = query.total_count_for_repository
      expect(count).to eq(1)
    end

    def ds_api_manifests(path:, name: "package-lock.json")
      manifests = {
        "package-lock.json": Github::DependencySnapshotsApi::Manifest.new(
          snapshot_id: 1,
          file_path: path,
          name: name,
          dependencies: {
            "snapshot-manifest": Github::DependencySnapshotsApi::Manifest::Dependency.new(
              package_url: "pkg:/npm/snapshot-manifest@0.0.6",
              dependencies: [],
              scope: :SCOPE_DEVELOPMENT,
              relationship: :RELATIONSHIP_UNKNOWN,
            ),
          }
        ),
      }

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
          )
        }
      ))
    end

    def dgp_manifests(path:)
      Twirp::ClientResp.new(
        data: Github::DependencyGraphPlatform::Graphql::V1::GetManifestsForRepositoryResponse.new(
          manifests: [
            Github::DependencyGraphPlatform::Graphql::V1::Manifest.new(
              id: 1,
              repository_id: 123,
              path: path,
              name: "package-lock.json",
              ecosystem: 1,
            )
          ]
        )
      )
    end
  end
end
