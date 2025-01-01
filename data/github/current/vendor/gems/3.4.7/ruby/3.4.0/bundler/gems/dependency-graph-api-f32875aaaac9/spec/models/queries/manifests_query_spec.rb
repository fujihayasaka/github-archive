require "rails_helper"
require_relative "../../lib/monolith/features_helpers.rb"
require "dependency_snapshots_api/dependencies_client"

module Queries
  describe ManifestsQuery do
    include Monolith::FeaturesHelpers

    before(:each) do
      DependencyGraph.flipper.disable(:dependency_graph_dgp_backed_npm_graphql)
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
        package_name: "lib1"
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
        package_manager: Types::PackageManager.coerce(:npm)
      )

      expect(query.manifests).to eq [npm]
    end
  end
end
