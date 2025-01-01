# typed: true
# frozen_string_literal: true

module DependencyGraph
  class RepositoryDependenciesQuery < Query
    def initialize(repository_id:, backend: nil)
      @repository_id = repository_id
      super(backend: backend)
    end

    def results
      execute_query.map do |response|
        dependencies = response.dig("data", "repositoryDependencies")

        {
          direct_dependencies: dependencies&.dig("directDependencies")
        }
      end
    end

    def query(options = {})
      field(:repositoryDependencies, {
        arguments: [
          argument(:repositoryId, @repository_id),
        ],
        selections: [
          field(:directDependencies)
        ],
      }.merge(options))
    end
  end
end
