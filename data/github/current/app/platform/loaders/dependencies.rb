# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class Dependencies < Platform::Loader
      def self.load_manifests(repository, params)
        return stubbed_manifest_data(repository) if stub_data?

        empty_manifests = { manifests: [], page_info: {}, total_count: 0 }

        # Return empty list if dependency graph is disabled.
        return Promise.new.fulfill(GitHub::Result.new { empty_manifests }) if !repository.dependency_graph_enabled?

        has_manifests = repository.has_manifests?

        # If there are no manifests, then we want to return an empty list.
        if !has_manifests
          return Promise.new.fulfill(GitHub::Result.new { empty_manifests })
        end

        self.for(::DependencyGraph::ManifestsQuery).load(params)
      end

      def self.load_package_releases(params)
        return stubbed_package_releases_data(params) if stub_data?

        self.for(::DependencyGraph::PackageReleaseQuery).load(params)
      end

      def self.load_package_release_vulnerabilities(params)
        self.for(::DependencyGraph::PackageReleaseVulnerabilitiesQuery).load(params)
      end

      def self.load_repository_package_releases(params)
        self.for(::DependencyGraph::RepositoryPackageReleaseQuery).load(params)
      end

      def self.load_repository_dependencies(params)
        return stubbed_repository_dependencies(params) if stub_data?

        self.for(::DependencyGraph::RepositoryDependenciesQuery).load(params)
      end

      def self.load_repository_owner_dependencies(params)
        return stubbed_repository_owner_dependencies(params) if stub_data?

        self.for(::DependencyGraph::RepositoryOwnerDependenciesQuery).load(params)
      end

      def self.load_repositories_using_dependencies(params)
        return stubbed_repositories_using_dependencies(params) if stub_data?

        self.for(::DependencyGraph::RepositoriesUsingDependenciesQuery).load(params)
      end

      def self.load_repository_package_release_licenses(params)
        self.for(::DependencyGraph::RepositoryPackageReleaseLicensesQuery).load(params)
      end

      def self.load_repository_package_release_vulnerabilities(params)
        self.for(::DependencyGraph::RepositoryPackageReleaseVulnerabilitySeveritiesQuery).load(params)
      end

      def self.load_packages(params)
        return stubbed_packages_data(params) if stub_data?

        self.for(::DependencyGraph::PackagesQuery).load(params)
      end

      def self.load_unmapped_packages(params)
        self.for(::DependencyGraph::UnmappedPackagesQuery).load(params)
      end

      def self.stub_data?
        Rails.env.development? && GitHub.dependency_graph_api_url.blank?
      end

      def self.stubbed_manifest_data(manifest_repo)
        manifests = ::DependencyGraph.stubbed_manifests(manifest_repo, random_repos)
        stub_data({ manifests: manifests })
      end

      def self.stubbed_package_releases_data(params)
        releases = ::DependencyGraph.stubbed_package_releases(params, random_repos)

        stub_data ArrayWrapper.new(releases)
      end

      def self.stubbed_packages_data(params)
        stub_data ArrayWrapper.new(::DependencyGraph.stubbed_packages(params, random_repos))
      end

      def self.stubbed_repository_dependencies(params)
        stub_data({ direct_dependencies: random_repos.pluck(:id) })
      end

      def self.stubbed_repository_owner_dependencies(params)
        stub_data(dependencies: random_repos(limit: 1_000).pluck(:id))
      end

      def self.stubbed_repositories_using_dependencies(params)
        dependency_ids = params[:dependency_ids] || random_repos.pluck(:id)
        repo_owner_id = params[:owner_id] || random_repos(limit: 1).first.owner_id
        total_repos = 10
        repo_ids = random_repos(scope: Repository.where(owner_id: repo_owner_id),
          limit: total_repos).pluck(:id)

        results = dependency_ids.map do |dependency_id|
          {
            dependency_id: dependency_id,
            repository_ids: repo_ids.sample(rand(repo_ids.size) + 1),
          }
        end

        stub_data(ArrayWrapper.new(results))
      end

      def self.random_repos(scope: nil, limit: 5)
        repos = ::Repository.public_scope
          .where("repositories.id < ?", rand(1_000_000))
        repos = repos.merge(scope) if scope
        repos.first(limit)
      end

      def self.stub_data(data)
        Promise.new.fulfill GitHub::Result.new { data }
      end

      def initialize(query_class)
        @query_class = query_class
      end

      def fetch(keys)
        keys.map do |key|
          [key, query_class.new(**key).results]
        end.to_h
      end

      private

      attr_reader :query_class
    end
  end
end
