# typed: true
# frozen_string_literal: true

module DependencyGraph
  class SearchResultComponent < ApplicationComponent
    @popover_rendered = false
    delegate :package_name,
        :manifest_path,
        :scanned_by,
        :snapshot_detector_name,
        :license,
      to: :@search_result

    attr_reader :alerts, :package_repository, :repository, :search_result

    class << self
      attr_accessor :popover_rendered
    end

    def initialize(
      search_result:,
      alerts:,
      package_repository: nil,
      repository:,
      does_results_have_root_ancestors: false
    )
      @search_result = search_result
      @package_repository = package_repository
      @repository = repository
      @alerts = alerts
      @does_results_have_root_ancestors = does_results_have_root_ancestors
    end

    def package_manager
      label = DependencyGraph::Ecosystems.label(@search_result.package_manager)
      return label if label != DependencyGraph::Ecosystems::UNKNOWN_LABEL

      @search_result.unsupported_package_manager_name
    end

    def requirements
      @search_result.requirements
        .sub(/\A=\s+/, "")
        .gsub(/,(?=[^\s])/, ", ")
    end

    def scanned_at
      @search_result.scanned_at.to_time.strftime("%b %d, %Y")
    end

    def render_relationship_label
      case @search_result.relationship
      when :RELATIONSHIP_UNKNOWN
        # If the relationship is unknown, don't render any label
        nil
      when :RELATIONSHIP_DIRECT
        render_relationship_form("direct", scheme: :default)
      when :RELATIONSHIP_TRANSITIVE
        render_relationship_form("transitive", scheme: :default)
      when :RELATIONSHIP_INCONCLUSIVE
        render_relationship_form("inconclusive", scheme: :secondary)
      end
    end

    def dialog_id
      "show-paths-#{manifest_path}-#{package_name}-#{requirements}"
    end

    def render_action_menu?
      @does_results_have_root_ancestors
    end

    def hide_action_menu?
      "v-hidden" unless search_result.root_ancestors&.any?
    end

    def render_search_paths_popover
      return if self.class.popover_rendered || !search_result.root_ancestors&.any? || current_user&.dismissed_notice?(:dependency_graph_view_transitive_paths)

      self.class.popover_rendered = true
      render "network/dependencies/search_paths_popover"
    end

    private

    def render_relationship_form(relationship_value, scheme: nil)
      render(Primer::Beta::Link.new(href: update_query_params(relationship_value), muted: true, "data-test-selector": "relationship-label-link")) do
        render(Primer::Beta::Label.new(ml: 2, scheme: scheme)) do
          relationship_value.capitalize
        end
      end
    end

    def update_query_params(relationship_value)
      base_path = request&.path
      query_string = request&.query_string || ""

      query_params = Rack::Utils.parse_nested_query(query_string)
      q = query_params["q"] || ""

      q_components = q.split(" ").reject { |component| component.start_with?("relationship:") }
      q_components << "relationship:#{relationship_value}" if relationship_value

      query_params["q"] = q_components.join(" ").strip
      updated_query_string = Rack::Utils.build_nested_query(query_params.except("page"))

      "#{base_path}?#{updated_query_string}"
    end
  end
end
