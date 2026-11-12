require "rails_helper"
require "dependency_graph/object_model/ds_graphql_manifest"
require "dependency_graph/object_model/ds_api_dependency"
require "dependency_graph/object_model/ds_graphql_dependency"
require "dependency_graph/object_model/dgp_graphql_manifest"
require "dependency_graph/object_model/dgp_graphql_dependency"

module DependenciesQuerySpecHelpers
  MockDependency = Struct.new(:package_name, :package_manager, keyword_init: true)
end

describe Queries::DependenciesQuery do
  include ActiveSupport::Testing::TimeHelpers

  shared_examples "dependencies query" do
    before do
      factory do
        given_package("rake", "11.2.0")

        given_package("aws", "1.2.0")
          .update_package(github_repository_id: 50)
          .add_dependency("rake", "= 11.2.0")
      end
    end

    def get_dependency(package_name, dependent)
      if dependent.is_a?(Manifest) && DependencyGraph.use_normalized_tables?
        dependent.entries.with_package_name(package_name).first
      else
        dependent.dependencies.where(package_name: package_name).first
      end
    end

    describe "querying dependencies with a `prefer` option" do
      let(:release) do
        factory.given_package("rails", "5.0.0")
          .add_dependency("rake", ">= 11.2.0")
          .add_dependency("aws", ">= 1.2.0")
          .release
      end

      it "works the same when `prefer` option is empty" do
        rake_dependency = get_dependency("rake", release)
        aws_dependency  = get_dependency("aws", release)

        query = described_class.new(dependent: release, prefer: [])
        expect(query.dependencies_count).to eq 2
        expect(query.dependencies).to eq [aws_dependency, rake_dependency]
      end

      it "returns dependencies matching the `prefer` option first" do
        rake_dependency = get_dependency("rake", release)
        aws_dependency  = get_dependency("aws", release)

        query = described_class.new(dependent: release, prefer: ["rake"])
        expect(query.dependencies_count).to eq 2
        expect(query.dependencies).to eq [rake_dependency, aws_dependency]
      end
    end

    describe "a package release dependent" do
      let(:release) do
        factory.given_package("rails", "5.0.0")
          .add_dependency("rake", ">= 11.2.0")
          .add_dependency("aws", ">= 1.2.0")
          .release
      end
      let(:query) { described_class.new(dependent: release) }
      let(:dependencies) { query.dependencies }

      it "returns dependencies" do
        rake_dependency = get_dependency("rake", release)
        aws_dependency  = get_dependency("aws", release)

        expect(query.dependencies_count).to eq 2
        expect(dependencies).to eq [aws_dependency, rake_dependency]
      end

      it "includes repository IDs when possible" do
        # aws has an associated repo
        expect(dependencies.first.package_name).to eq "aws"
        expect(dependencies.first.package_github_repository_id).to eq 50

        # rake has no associated repo
        expect(dependencies.last.package_name).to eq "rake"
        expect(dependencies.last.package_github_repository_id).to be_nil
      end

      it "adds a 'has_dependencies' flag" do
        # aws has one dependency
        expect(dependencies.first.package_name).to eq "aws"
        expect(dependencies.first.has_dependencies?).to be_truthy

        # rake has no dependencies
        expect(dependencies.last.package_name).to eq "rake"
        expect(dependencies.last.has_dependencies?).to be_falsey
      end

      it "uses current package version to detect dependencies" do
        # Latest version of aws gem has no dependencies
        factory.given_package("aws", "1.3.0")

        expect(dependencies.first.package_name).to eq "aws"
        expect(dependencies.first.has_dependencies?).to be_falsey
      end

      it "handles missing packages" do
        PackageDependency.create!({
                                    dependent:    release,
                                    package_name: "unknown",
                                    requirements: ""
                                  })

        expect(query.dependencies_count).to eq 3
        expect(dependencies.last.package_name).to eq "unknown"
        expect(dependencies.last.has_dependencies?).to be_falsey
      end
    end

    describe "a manifest dependent" do
      let(:manifest) do
        factory.given_manifest(github_repo_id: 100)
          .add_dependency("rake", ">= 11.2.0")
          .add_dependency("aws", ">= 1.2.0")
          .manifest
      end
      let(:query) { described_class.new(dependent: manifest) }
      let(:dependencies) { query.dependencies }

      it "returns dependencies" do
        rake_dependency = get_dependency("rake", manifest)
        aws_dependency  = get_dependency("aws", manifest)

        expect(dependencies).to match_model [
          aws_dependency,
          rake_dependency,
                                ]
      end

      it "only includes the latest dependencies" do
        manifest = factory.given_manifest(github_repo_id: 100, revision: 2)
                     .add_dependency("rake", ">= 11.2.0", last_seen_at_revision: 1)
                     .add_dependency("aws", ">= 1.2.0", last_seen_at_revision: 2)
                     .manifest

        query = described_class.new(dependent: manifest)
        expect(query.dependencies_count).to eq 1
        expect(query.dependencies).to match_model [get_dependency("aws", manifest)]
      end

      it "includes repository IDs when possible" do
        # aws has an associated repo
        expect(dependencies.first.package_name).to eq "aws"
        expect(dependencies.first.package_github_repository_id).to eq 50

        # rake has no associated repo
        expect(dependencies.last.package_name).to eq "rake"
        expect(dependencies.last.package_github_repository_id).to be_nil
      end

      it "adds a 'has_dependencies' flag" do
        # aws has one dependency
        expect(dependencies.first.package_name).to eq "aws"
        expect(dependencies.first.has_dependencies?).to be_truthy

        # rake has no dependencies
        expect(dependencies.last.package_name).to eq "rake"
        expect(dependencies.last.has_dependencies?).to be_falsey
      end

      it "handles missing packages" do
        ManifestDependency.create!({
                                     manifest:              manifest,
                                     package_manager:       Types::PackageManager::RUBYGEMS,
                                     package_name:          "unknown",
                                     requirements:          "",
                                     last_seen_at_revision: manifest.revision,
                                   })

        expect(query.dependencies_count).to eq 3
        dependency = dependencies.sort_by(&:package_name).last
        expect(dependency.package_name).to eq "unknown"
        expect(dependency.has_dependencies?).to be_falsey
      end

      it "avoids uncessary check for sub dependencies if non-existent in ecosystem" do
        actions_manifest = factory.given_manifest(github_repo_id: 100, revision: 2, manifest_type: Types::Manifest[:workflow_yaml], package_manager: Types::PackageManager[:actions])
                             .add_dependency("repo/action", "= main")
                             .manifest

        expect_any_instance_of(described_class).to_not receive(:has_dependencies_subquery)

        actions_query = described_class.new(dependent: actions_manifest)
        action = actions_query.dependencies.first

        expect(action.has_dependencies?).to be_falsey
      end

      it "adds a MAX_EXECUTION_TIME optimizer hint to the dependency scope" do
        expect(query.send(:dependency_scope).to_sql).to include("MAX_EXECUTION_TIME(20000)")
      end
    end

    describe "statement timeout handling" do
      let(:release) do
        factory.given_package("rails", "5.0.0")
          .add_dependency("rake", ">= 11.2.0")
          .release
      end
      let(:query) { described_class.new(dependent: release) }

      it "raises a GraphQL execution error when dependencies query times out" do
        allow(Instrument).to receive(:increment)
        allow(query).to receive(:dependency_scope).and_raise(ActiveRecord::StatementTimeout)

        expect { query.dependencies }.to raise_error(GraphQL::ExecutionError, "Query exceeded maximum execution time")
        expect(Instrument).to have_received(:increment).with("query.statement_timeout", query_site: "dependencies_query.dependencies")
      end

      it "returns -1 when dependencies_count times out" do
        allow(Instrument).to receive(:increment)
        allow(query).to receive(:dependency_scope).and_raise(ActiveRecord::StatementTimeout)

        expect(query.dependencies_count).to eq(-1)
        expect(Instrument).to have_received(:increment).with("query.statement_timeout", query_site: "dependencies_query.dependencies_count")
      end
    end
  end

  describe "BaseGraphqlManifest dependent" do
    let(:dep1) { double("dep1", package_name: "aws") }
    let(:dep2) { double("dep2", package_name: "rake") }
    let(:manifest) do
      instance_double(
        DependencyGraph::ObjectModel::BaseGraphqlManifest,
        dependencies: [dep1, dep2]
      ).tap do |m|
        allow(m).to receive(:is_a?).and_return(false)
        allow(m).to receive(:is_a?).with(DependencyGraph::ObjectModel::BaseGraphqlManifest).and_return(true)
      end
    end
    let(:query) { described_class.new(dependent: manifest) }

    it "returns the array size for dependencies_count" do
      expect(query.dependencies_count).to eq(2)
    end

    it "does not call optimizer_hints for dependencies_count" do
      expect(query).not_to receive(:dependency_scope)
      query.dependencies_count
    end

    it "returns sorted dependencies" do
      expect(query.dependencies.map(&:package_name)).to eq(["aws", "rake"])
    end
  end

  describe "normalised tables (dotcom and Proxima)" do
    before do
      allow(DependencyGraph).to receive(:use_normalized_tables?).and_return(true)
    end

    include_examples "dependencies query"
  end

  describe "unnormalised tables (GHES)" do
    before do
      allow(DependencyGraph).to receive(:use_normalized_tables?).and_return(false)
    end

    include_examples "dependencies query"
  end

  describe "caching for BaseGraphqlManifest dependents" do
    let(:memory_store) { ActiveSupport::Cache::MemoryStore.new }
    let(:repository_id) { 42 }
    let(:manifest_id) { 12345 }

    # Use a simple serializable struct instead of test doubles for cache compatibility
    let(:mock_dependencies) do
      [
        DependenciesQuerySpecHelpers::MockDependency.new(package_name: "alpha", package_manager: Types::PackageManager[:rubygems]),
        DependenciesQuerySpecHelpers::MockDependency.new(package_name: "bravo", package_manager: Types::PackageManager[:rubygems]),
      ]
    end

    let(:manifest) do
      instance_double(
        DependencyGraph::ObjectModel::DSGraphqlManifest,
        id: manifest_id,
        github_repository_id: repository_id,
      ).tap do |m|
        allow(m).to receive(:is_a?).and_return(false)
        allow(m).to receive(:is_a?).with(DependencyGraph::ObjectModel::BaseGraphqlManifest).and_return(true)
        allow(m).to receive(:dependencies).and_return(mock_dependencies)
      end
    end

    before do
      allow(Rails).to receive(:cache).and_return(memory_store)
      allow(Instrument).to receive(:increment)
      allow(Instrument).to receive(:distribution)
      DependencyGraph.flipper.disable(:dependency_graph_graphql_manifest_cache)
    end

    context "when cache is disabled" do
      it "does not cache results" do
        query = described_class.new(dependent: manifest)
        query.dependencies

        expect(Instrument).not_to have_received(:increment).with("dependencies_query.cache.hit")
        expect(Instrument).not_to have_received(:increment).with("dependencies_query.cache.miss")
        expect(Instrument).not_to have_received(:distribution).with("dependencies_query.cache.write.dependencies_count", anything)
      end

      it "calls dependent.dependencies directly" do
        query = described_class.new(dependent: manifest)
        query.dependencies

        expect(manifest).to have_received(:dependencies).once
      end
    end

    context "when cache is enabled" do
      before { DependencyGraph.flipper.enable(:dependency_graph_graphql_manifest_cache) }

      it "uses a urlsafe base64 digest for the cache key" do
        query = described_class.new(dependent: manifest)
        digest = query.send(:dependencies_cache_key).split("/", 2).last

        expect(digest).to match(/\A[A-Za-z0-9\-_]+=*\z/)
        expect(digest).not_to match(/\A[0-9a-f]{64}\z/)
      end

      it "records a cache miss on the first call" do
        query = described_class.new(dependent: manifest)
        query.dependencies

        expect(Instrument).to have_received(:increment).with("dependencies_query.cache.miss")
        expect(Instrument).to have_received(:distribution).with("dependencies_query.cache.write.dependencies_count", 2)
      end

      it "records a cache hit when the result is already cached" do
        first_query = described_class.new(dependent: manifest)
        first_query.dependencies

        second_query = described_class.new(dependent: manifest)
        second_query.dependencies

        expect(Instrument).to have_received(:increment).with("dependencies_query.cache.miss").once
        expect(Instrument).to have_received(:increment).with("dependencies_query.cache.hit").once
        expect(Instrument).to have_received(:distribution).with("dependencies_query.cache.write.dependencies_count", 2).once
      end

      it "does not call dependent.dependencies on cache hit" do
        first_query = described_class.new(dependent: manifest)
        first_query.dependencies

        second_query = described_class.new(dependent: manifest)
        second_query.dependencies

        expect(manifest).to have_received(:dependencies).once
      end

      it "returns sorted results on cache hit" do
        first_query = described_class.new(dependent: manifest)
        first_result = first_query.dependencies

        second_query = described_class.new(dependent: manifest)
        second_result = second_query.dependencies

        expect(second_result.map(&:package_name)).to eq(first_result.map(&:package_name))
      end

      it "sorts by prefer after cache retrieval" do
        first_query = described_class.new(dependent: manifest)
        first_result = first_query.dependencies
        expect(first_result.map(&:package_name)).to eq(%w[alpha bravo])

        preferred_query = described_class.new(dependent: manifest, prefer: ["bravo"])
        preferred_result = preferred_query.dependencies
        expect(preferred_result.map(&:package_name)).to eq(%w[bravo alpha])

        # Both queries share the same cache entry (only one miss)
        expect(Instrument).to have_received(:increment).with("dependencies_query.cache.miss").once
        expect(Instrument).to have_received(:increment).with("dependencies_query.cache.hit").once
      end

      it "uses separate cache entries for different manifests" do
        other_manifest = instance_double(
          DependencyGraph::ObjectModel::DSGraphqlManifest,
          id: -99999,
          github_repository_id: repository_id,
        ).tap do |m|
          allow(m).to receive(:is_a?).and_return(false)
          allow(m).to receive(:is_a?).with(DependencyGraph::ObjectModel::BaseGraphqlManifest).and_return(true)
          allow(m).to receive(:dependencies).and_return(
            [DependenciesQuerySpecHelpers::MockDependency.new(package_name: "charlie", package_manager: Types::PackageManager[:rubygems])]
          )
        end

        described_class.new(dependent: manifest).dependencies
        described_class.new(dependent: other_manifest).dependencies

        expect(Instrument).to have_received(:increment).with("dependencies_query.cache.miss").twice
      end

      it "caches dependencies_count too" do
        described_class.new(dependent: manifest).dependencies
        count = described_class.new(dependent: manifest).dependencies_count

        expect(count).to eq(2)
        expect(manifest).to have_received(:dependencies).once
        expect(Instrument).to have_received(:increment).with("dependencies_query.cache.hit").once
      end

      it "respects the cache TTL" do
        stub_const("#{described_class}::DEFAULT_CACHE_TTL_SECONDS", 1)

        described_class.new(dependent: manifest).dependencies

        travel 2.seconds do
          described_class.new(dependent: manifest).dependencies
        end

        expect(Instrument).to have_received(:increment).with("dependencies_query.cache.miss").twice
      end

      it "does not cache when dependent.dependencies raises an error" do
        allow(manifest).to receive(:dependencies).and_raise(StandardError, "connection failed")

        query = described_class.new(dependent: manifest)
        expect { query.dependencies }.to raise_error(StandardError, "connection failed")

        allow(manifest).to receive(:dependencies).and_return(mock_dependencies)

        second_query = described_class.new(dependent: manifest)
        second_query.dependencies

        expect(Instrument).to have_received(:increment).with("dependencies_query.cache.miss").once
      end

      it "caches snapshot dependencies without serialization errors" do
        raw_dep = Github::DependencySnapshotsApi::Manifest::Dependency.new(
          package_url: "pkg:/npm/foo@1.0.0",
          scope: :SCOPE_RUNTIME,
          relationship: :RELATIONSHIP_DIRECT,
        )
        ds_api_dep = DependencyGraph::ObjectModel::DSAPIDependency.new("foo", raw_dep)
        ds_dep = DependencyGraph::ObjectModel::DSGraphqlDependency.new(ds_api_dep, include_transitive_labels: true)

        ds_manifest = instance_double(
          DependencyGraph::ObjectModel::DSGraphqlManifest,
          id: manifest_id,
          github_repository_id: repository_id,
        ).tap do |m|
          allow(m).to receive(:is_a?).and_return(false)
          allow(m).to receive(:is_a?).with(DependencyGraph::ObjectModel::BaseGraphqlManifest).and_return(true)
          allow(m).to receive(:dependencies).and_return([ds_dep])
        end

        first_query = described_class.new(dependent: ds_manifest)
        expect { first_query.dependencies }.not_to raise_error

        second_query = described_class.new(dependent: ds_manifest)
        second_result = second_query.dependencies

        expect(second_result.first.package_name).to eq("foo")
        expect(Instrument).not_to have_received(:increment).with("dependencies_query.cache.serialization_error")
        expect(Instrument).to have_received(:increment).with("dependencies_query.cache.miss").once
        expect(Instrument).to have_received(:increment).with("dependencies_query.cache.hit").once
      end

      it "caches dgp dependencies without serialization errors" do
        raw_dep = Github::DependencyGraphPlatform::Graphql::V1::Dependency.new(
          id: 1, package_name: "bar", requirements: "2.0.0", ecosystem: 1, relationship: :RELATIONSHIP_DIRECT
        )
        dgp_dep = DependencyGraph::ObjectModel::DGPGraphqlDependency.new(raw_dep, include_transitive_labels: true)

        dgp_manifest = instance_double(
          DependencyGraph::ObjectModel::DGPGraphqlManifest,
          id: manifest_id,
          github_repository_id: repository_id,
        ).tap do |m|
          allow(m).to receive(:is_a?).and_return(false)
          allow(m).to receive(:is_a?).with(DependencyGraph::ObjectModel::BaseGraphqlManifest).and_return(true)
          allow(m).to receive(:dependencies).and_return([dgp_dep])
        end

        first_query = described_class.new(dependent: dgp_manifest)
        expect { first_query.dependencies }.not_to raise_error

        second_query = described_class.new(dependent: dgp_manifest)
        second_result = second_query.dependencies

        expect(second_result.first.package_name).to eq("bar")
        expect(Instrument).not_to have_received(:increment).with("dependencies_query.cache.serialization_error")
        expect(Instrument).to have_received(:increment).with("dependencies_query.cache.miss").once
        expect(Instrument).to have_received(:increment).with("dependencies_query.cache.hit").once
      end
    end
  end
end
