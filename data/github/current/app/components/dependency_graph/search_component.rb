# typed: true
# frozen_string_literal: true

module DependencyGraph
  class SearchComponent < ApplicationComponent
    def initialize(current_repository:, query: "", package_managers: [])
      @current_repository = current_repository
      @query = query
      @package_managers = package_managers
    end

    def search_ecosystem_suggestions
      ecosystems = @package_managers.map do |package_manager|
        { value: DependencyGraph::Ecosystems.label(package_manager) }
      end
      ecosystems.to_json
    end
  end
end
