# typed: true
# frozen_string_literal: true

require "psych"

module GitHub::Goomba
  class InsightsQueryFilter < NodeFilter
    include GitHub::Goomba::Reference::Helpers

    SELECTOR = Goomba::Selector.new(match: "pre[lang='insights'],pre[lang='datadot']")

    def self.feature_flags
      [:insights_codeblocks]
    end

    def self.enabled?(context)
      if context[:entity].is_a?(Repository)
        return false if context[:entity].public?
        return true if GitHub.flipper[:insights_codeblocks].enabled?(context[:entity])
        return true if GitHub.flipper[:insights_codeblocks].enabled?(context[:entity].owner)
      elsif context[:organization].is_a?(Organization)
        return GitHub.flipper[:insights_codeblocks].enabled?(context[:organization])
      end

      false
    end

    def selector
      SELECTOR
    end

    def call(node)
      query_str = node.children.first.inner_html
      return node if query_str.blank?

      target = node.attributes["lang"]
      current_viewer_reference_wrapper(employee: true) do |wrapper|
        wrapper.authorized { insights_query_component_html(query_str, employee: true, target: target) }
        wrapper.unauthorized { insights_query_component_html(query_str, employee: false, target: target) }
      end
    end

    private

    def insights_query_component_html(query, employee:, target:)
      component = Insights::QueryComponent.new(
        query,
        employee: employee,
        target: target,
        data_context: data_context.data
      )

      ApplicationController.render(component, formats: [:html], layout: false)
    end

    def data_context
      @data_context ||= UI::DataContext.new(context)
    end
  end
end
