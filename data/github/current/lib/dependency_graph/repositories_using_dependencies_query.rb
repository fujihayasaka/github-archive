# typed: true
# frozen_string_literal: true

module DependencyGraph
  # Public: Query the dependency graph API to find which repositories owned by a particular
  # user or org use any of the specified dependencies.
  class RepositoriesUsingDependenciesQuery < Query
    # owner_id - User or Organization integer database ID
    # dependency_ids - Array of integer Repository database IDs
    def initialize(owner_id:, dependency_ids:, backend: nil)
      @owner_id = owner_id
      @dependency_ids = dependency_ids
      super(backend: backend)
    end

    def results
      execute_query.map do |response|
        result = response.dig("data", "repositoriesUsingDependencies") || []
        result.map do |row|
          {
            dependency_id: row&.dig("dependencyId"),
            repository_ids: row&.dig("repositories"),
          }
        end
      end
    end

    def query(options = {})
      field(:repositoriesUsingDependencies, {
        arguments: [
          argument(:ownerId, @owner_id),
          argument(:dependencyIds, @dependency_ids),
        ],
        selections: [field(:dependencyId), field(:repositories)],
      }.merge(options))
    end
  end
end
