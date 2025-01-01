# typed: true
# frozen_string_literal: true

module DependencyGraph
  class RepositoryOwnerDependenciesQuery < Query
    MAX_REPOSITORY_IDS = 1000
    FILTERS = {
      owner_id: {
        arg: :ownerId,
      },
      public_only: {
        arg: :publicOnly,
      },
      direct_only: {
        arg: :directOnly,
      },
      sort_by: {
        arg: :sortBy,
        type: :enum,
      },
      package_managers: {
        arg: :packageManagers,
        type: :enum_array,
      },
      repository_ids: {
        arg: :repositoryIds,
        type: :array,
      }
    }.freeze

    # owner_id - User or Organization integer database ID
    # sort_by - corresponds with API::Enums::RepositoryOwnerDependencyQuerySort in github/dependency-graph-api
    # package_managers - Array of package manager filters; see
    #                    AdvisoryDB::Ecosystems.dependency_graph_supported for valid values;
    #                    corresponds with API::Enums::PackageManager in github/dependency-graph-api
    # public_only - Boolean controlling whether only the repository owner's public repositories
    #               should be checked for dependencies
    # direct_only - Boolean controlling whether only the owner's direct dependencies should be included, versus those
    #               that are dependencies of their dependencies.
    # repository_ids - optional Array of Integer database IDs for Repository records owned by the specified owner,
    #                  used to limit which of their repos are checked for dependencies; only `MAX_REPOSITORY_IDS`
    #                  IDs will be used
    def initialize(owner_id:, sort_by: nil, package_managers: [], public_only: false, direct_only: false, backend: nil, repository_ids: [])
      @owner_id = owner_id
      @public_only = public_only
      @direct_only = direct_only
      @sort_by = sort_by
      @package_managers = package_managers
      @repository_ids = repository_ids.compact.uniq.take(MAX_REPOSITORY_IDS)
      super(backend: backend)
    end

    def results
      execute_query.map do |response|
        result = response.dig("data", "repositoryOwnerDependencies")
        { dependencies: result&.dig("dependencies") }
      end
    end

    def query(options = {})
      values = {
        public_only: @public_only,
        direct_only: @direct_only,
        owner_id: @owner_id,
      }
      values[:sort_by] = @sort_by if @sort_by
      values[:repository_ids] = @repository_ids if @repository_ids.present?
      values[:package_managers] = @package_managers.to_a.uniq if @package_managers.present?

      field(:repositoryOwnerDependencies, {
        arguments: map_arguments(FILTERS, values),
        selections: [field(:dependencies)],
      }.merge(options))
    end
  end
end
