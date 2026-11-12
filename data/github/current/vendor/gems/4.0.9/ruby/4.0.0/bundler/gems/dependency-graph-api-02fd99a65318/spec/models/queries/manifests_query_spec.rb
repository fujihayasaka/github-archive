require "rails_helper"
require_relative "../../lib/monolith/features_helpers.rb"
require "dependency_snapshots_api/dependencies_client"
require "dependency_graph/object_model/ds_api_dependency.rb"

module Queries
  describe ManifestsQuery do
    include ActiveSupport::Testing::TimeHelpers

    include Monolith::FeaturesHelpers
    before(:each) do
      # Disable the DGP gateway by default
      allow_any_instance_of(Queries::ManifestsQuery).to receive(:dgp_available).and_return(false)
      allow_any_instance_of(DependencyGraphAPI::DependencySnapshotsAPI::DependenciesClient)
        .to receive(:get_dependencies_for_repository).and_return(twirp_response)
      DependencyGraph.flipper.disable(:dependency_graph_graphql_manifest_cache)
      allow(DependencyGraph.features).to receive(:feature_enabled_for_any_repo?).and_return(false)
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

    describe "caching" do
      let(:memory_store) { ActiveSupport::Cache::MemoryStore.new }
      let(:features) { instance_double(Monolith::Features) }

      before do
        allow(Rails).to receive(:cache).and_return(memory_store)
        allow(Instrument).to receive(:increment)
        allow(Instrument).to receive(:distribution)
        allow(DependencyGraph).to receive(:features).and_return(features)
        allow(features).to receive(:feature_enabled_for_any_repo?).and_return(false)
      end

      context "when cache is disabled" do
        it "does not cache results" do
          query = described_class.new(repository_ids: [100])
          query.manifests

          expect(Instrument).not_to have_received(:increment).with("manifests_query.cache.hit")
          expect(Instrument).not_to have_received(:increment).with("manifests_query.cache.miss")
          expect(Instrument).not_to have_received(:distribution).with("manifests_query.cache.write.manifests_count", anything)
        end
      end

      context "when cache is enabled" do
        before { allow(features).to receive(:feature_enabled_for_any_repo?).and_return(true) }

        it "uses a urlsafe base64 digest for the cache key" do
          query = described_class.new(repository_ids: [100], with_dependencies: true)
          digest = query.send(:cache_key).split("/", 2).last

          expect(digest).to match(/\A[A-Za-z0-9\-_]+=*\z/)
          expect(digest).not_to match(/\A[0-9a-f]{64}\z/)
        end

        it "records a cache miss on the first call" do
          query = described_class.new(repository_ids: [100])
          query.manifests

          expect(Instrument).to have_received(:increment).with("manifests_query.cache.miss")
          expect(Instrument).to have_received(:distribution).with("manifests_query.cache.write.manifests_count", kind_of(Integer))
        end

        it "records a cache hit when the result is already cached" do
          first_query = described_class.new(repository_ids: [100])
          first_query.manifests

          second_query = described_class.new(repository_ids: [100])
          second_query.manifests

          expect(Instrument).to have_received(:increment).with("manifests_query.cache.miss").once
          expect(Instrument).to have_received(:increment).with("manifests_query.cache.hit").once
          expect(Instrument).to have_received(:distribution).with("manifests_query.cache.write.manifests_count", kind_of(Integer)).once
        end

        it "returns the same results on cache hit" do
          first_query = described_class.new(repository_ids: [100])
          first_result = first_query.manifests

          second_query = described_class.new(repository_ids: [100])
          second_result = second_query.manifests

          expect(second_result).to eq(first_result)
        end

        it "uses separate cache entries for different query parameters" do
          query_a = described_class.new(repository_ids: [100])
          query_b = described_class.new(repository_ids: [200])

          query_a.manifests
          query_b.manifests

          expect(Instrument).to have_received(:increment).with("manifests_query.cache.miss").twice
        end

        it "uses separate cache entries for different options" do
          query_a = described_class.new(repository_ids: [100], with_dependencies: true)
          query_b = described_class.new(repository_ids: [100], with_dependencies: false)

          query_a.manifests
          query_b.manifests

          expect(Instrument).to have_received(:increment).with("manifests_query.cache.miss").twice
        end

        it "checks the cache flag once for all repository IDs" do
          first_query = described_class.new(repository_ids: [100, 200])
          first_query.manifests
          second_query = described_class.new(repository_ids: [100, 200])
          second_query.manifests

          expect(features).to have_received(:feature_enabled_for_any_repo?).with(
            github_repository_ids: [100, 200],
            feature: :dependency_graph_graphql_manifest_cache
          ).twice
          expect(Instrument).to have_received(:increment).with("manifests_query.cache.miss").once
          expect(Instrument).to have_received(:increment).with("manifests_query.cache.hit").once
        end

        it "respects the cache TTL" do
          stub_const("#{described_class}::DEFAULT_CACHE_TTL_SECONDS", 1)

          query = described_class.new(repository_ids: [100])
          query.manifests

          travel 2.seconds do
            second_query = described_class.new(repository_ids: [100])
            second_query.manifests
          end

          expect(Instrument).to have_received(:increment).with("manifests_query.cache.miss").twice
        end

        it "caches snapshot manifests without serialization errors" do
          allow(DependencyGraphAPI).to receive(:snapshots_enabled?).and_return(true)
          allow_any_instance_of(DependencyGraphAPI::DependencySnapshotsAPI::DependenciesClient)
            .to receive(:get_dependencies_for_repository)
            .and_return(ds_api_manifests(path: "/package-lock.json"))

          first_query = described_class.new(repository_ids: [100])
          expect { first_query.manifests }.not_to raise_error

          second_query = described_class.new(repository_ids: [100])
          expect { second_query.manifests }.not_to raise_error

          expect(Instrument).not_to have_received(:increment).with("manifests_query.cache.serialization_error")
          expect(Instrument).to have_received(:increment).with("manifests_query.cache.miss").once
          expect(Instrument).to have_received(:increment).with("manifests_query.cache.hit").once
        end

        it "caches dgp manifests without serialization errors" do
          allow(DependencyGraphAPI).to receive(:snapshots_enabled?).and_return(false)
          allow_any_instance_of(Queries::ManifestsQuery).to receive(:dgp_available).and_return(true)
          allow_any_instance_of(DependencyGraphAPI::DependencyGraphPlatform::GraphQLResolverClient)
            .to receive(:get_manifests_for_repository)
            .and_return(dgp_manifests(path: "/"))

          first_query = described_class.new(repository_ids: [123], package_manager: Types::PackageManager.coerce(:npm))
          expect { first_query.manifests }.not_to raise_error

          second_query = described_class.new(repository_ids: [123], package_manager: Types::PackageManager.coerce(:npm))
          expect { second_query.manifests }.not_to raise_error

          expect(Instrument).not_to have_received(:increment).with("manifests_query.cache.serialization_error")
          expect(Instrument).to have_received(:increment).with("manifests_query.cache.miss").once
          expect(Instrument).to have_received(:increment).with("manifests_query.cache.hit").once
        end

        it "does not cache when computation raises an error" do
          allow_any_instance_of(DependencyGraphAPI::DependencySnapshotsAPI::DependenciesClient)
            .to receive(:get_dependencies_for_repository).and_raise(StandardError, "connection failed")

          query = described_class.new(repository_ids: [100])
          expect { query.manifests }.to raise_error(StandardError, "connection failed")

          # Cache should still be empty
          allow_any_instance_of(DependencyGraphAPI::DependencySnapshotsAPI::DependenciesClient)
            .to receive(:get_dependencies_for_repository).and_return(twirp_response)

          second_query = described_class.new(repository_ids: [100])
          second_query.manifests

          expect(Instrument).to have_received(:increment).with("manifests_query.cache.miss").once
        end
      end
    end
  end
end
