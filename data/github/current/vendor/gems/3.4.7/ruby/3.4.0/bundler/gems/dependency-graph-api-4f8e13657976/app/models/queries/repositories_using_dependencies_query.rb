module Queries
  class RepositoriesUsingDependenciesQuery
    # github_owner_id - User or Organization ID; Integer
    # dependency_ids - Array of Integer Repository IDs for dependencies
    def initialize(github_owner_id, dependency_ids:)
      @github_owner_id = github_owner_id.to_i
      @all_dependency_ids = dependency_ids
    end

    # Public: Represents a particular dependency and the repositories, owned by a particular
    # user or org, that use it.
    class RepositoriesUsingDependency
      # Public: dependency Repository ID that is in use by the repositories.
      attr_reader :dependency_id

      # Public: User or Organization ID that owns the repositories.
      attr_reader :repository_owner_id

      # Public: Array of Repository IDs representing the repos that use the dependency.
      attr_reader :repositories

      def initialize(dependency_id, repo_owner_id, repo_ids)
        @dependency_id = dependency_id
        @repository_owner_id = repo_owner_id
        @repositories = repo_ids
      end
    end

    def repositories_using_dependencies
      repos_using_dependencies = repo_ids_by_dependency_id.map do |dependency_id, repo_ids|
        RepositoriesUsingDependency.new(dependency_id, @github_owner_id, repo_ids)
      end

      (@all_dependency_ids - repo_ids_by_dependency_id.keys).each do |dependency_id|
        repos_using_dependencies << RepositoriesUsingDependency.new(dependency_id,
          @github_owner_id, [])
      end

      repos_using_dependencies
    end

    private

    def query_dependencies(dependency_ids)
      return {} if dependency_ids.empty?

      query = Package
        .joins("STRAIGHT_JOIN dg_repositories dr ON dr.github_owner_id = #{@github_owner_id}")
        .joins("STRAIGHT_JOIN dg_abstract_repository_dependencies dard " \
          "ON dg_packages.package_manager = dard.package_manager " \
          "AND dg_packages.name = dard.package_name " \
          "AND dr.id = dard.repository_id")
        .where("dg_packages.repository_id IN (?)", dependency_ids)
        .select("dg_packages.repository_id AS dependency_id, dr.github_repository_id AS repo_id")

      result = {}
      query.map do |ard|
        result[ard.dependency_id] ||= []
        result[ard.dependency_id] << ard.repo_id
      end

      result
    end

    def cache_key(dependency_id)
      "repos-using-dep-#{@github_owner_id}-#{dependency_id}"
    end

    def repo_ids_by_dependency_id
      return @repo_ids_by_dependency_id if defined?(@repo_ids_by_dependency_id)

      dependency_ids_by_cache_key = @all_dependency_ids
        .map { |id| [cache_key(id), id] }
        .to_h

      cached_dependencies = Rails.cache
        .read_multi(*@all_dependency_ids.map { |id| cache_key(id) })
        .transform_keys { |k| dependency_ids_by_cache_key[k] }

      uncached_dependency_ids = @all_dependency_ids - cached_dependencies.keys

      uncached_dependencies = query_dependencies(uncached_dependency_ids)

      Rails.cache.write_multi(uncached_dependencies.transform_keys { |k| cache_key(k) }, expires_in: 12.hours)

      @repo_ids_by_dependency_id = cached_dependencies.merge(uncached_dependencies)
    end
  end
end
