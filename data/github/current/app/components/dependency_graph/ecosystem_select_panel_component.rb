# typed: true
# frozen_string_literal: true

module DependencyGraph
  class EcosystemSelectPanelComponent < ApplicationComponent
    def initialize(current_repository:, query_builder:, package_managers: [])
      @current_repository = current_repository
      @query_builder = query_builder
      @package_managers = package_managers
    end

    def render_item_hrefs(ecosystem)
      updated_query = @query_builder.toggle_ecosystem(DependencyGraph::Ecosystems.label(ecosystem))
      network_dependencies_path(@current_repository.owner_display_login, @current_repository, q: updated_query)
    end

    def is_active?(ecosystem)
      DependencyGraph::Ecosystems.label(ecosystem) == @query_builder.ecosystem
    end
  end
end
