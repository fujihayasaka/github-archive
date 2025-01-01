# typed: true
# frozen_string_literal: true

module DependencyGraph
  class SearchComponent < ApplicationComponent
    def initialize(current_repository:, query: "", package_managers: [])
      @current_repository = current_repository
      @query = query
      @package_managers = package_managers
    end

    def is_arbitrary_ecosystems_enabled?
      @current_repository.feature_enabled?(:dependency_graph_snapshot_arbitrary_ecosystems) || @current_repository.owner.feature_enabled?(:dependency_graph_snapshot_arbitrary_ecosystems)
    end

    def search_ecosystem_suggestions
      ecosystems = @package_managers.map do |package_manager|
        { value: DependencyGraph::Ecosystems.label(package_manager, ds_arbitrary_ecosystems_enabled: is_arbitrary_ecosystems_enabled?) }
      end
      ecosystems.to_json
    end
  end
end
