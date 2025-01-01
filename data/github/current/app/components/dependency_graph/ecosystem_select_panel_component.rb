# typed: true
# frozen_string_literal: true

module DependencyGraph
  class EcosystemSelectPanelComponent < ApplicationComponent
    def initialize(current_repository:, query_builder:, package_managers: [])
      @current_repository = current_repository
      @query_builder = query_builder
      @package_managers = package_managers
      @arbitrary_ecosystems_enabled = is_arbitrary_ecosystems_enabled?
    end

    def is_arbitrary_ecosystems_enabled?
      @current_repository.feature_enabled?(:dependency_graph_snapshot_arbitrary_ecosystems) || @current_repository.owner.feature_enabled?(:dependency_graph_snapshot_arbitrary_ecosystems)
    end

    def render_item_hrefs(ecosystem)
      updated_query = @query_builder.toggle_ecosystem(DependencyGraph::Ecosystems.label(ecosystem, ds_arbitrary_ecosystems_enabled: @arbitrary_ecosystems_enabled))
      network_dependencies_path(@current_repository.owner_display_login, @current_repository, q: updated_query)
    end

    def is_active?(ecosystem)
      DependencyGraph::Ecosystems.label(ecosystem, ds_arbitrary_ecosystems_enabled: @arbitrary_ecosystems_enabled) == @query_builder.ecosystem
    end
  end
end
