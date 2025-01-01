# typed: true
# frozen_string_literal: true

module Site
  module Header
    module ContextRegion
      class CrumbsComponent < ApplicationComponent
        include AnalyticsHelper

        attr_reader :context_crumbs, :current_path, :visible_crumbs, :overflow_crumbs, :max_context_items

        def initialize(context_crumbs = [], current_path = nil, max_context_items:)
          @context_crumbs = context_crumbs
          @current_path = current_path
          @visible_crumbs = []
          @overflow_crumbs = []
          @max_context_items = max_context_items

          determine_visible_and_overflow_crumbs
        end

        def determine_visible_and_overflow_crumbs
          if context_crumbs.size <= max_context_items
            @visible_crumbs = context_crumbs
            return
          end

          # we want to force the first and last crumbs to be visible by default, then as many more crumbs that will fit under the max limit, starting from right to left
          # this is to ensure that the last crumb is always visible, even if it is a long name
          # this is to ensure that the first crumb is always visible, even if it is a long name
          @visible_crumbs = context_crumbs.first(1) + context_crumbs.last(max_context_items - 2)
          @overflow_crumbs = context_crumbs[1..-2] - visible_crumbs
        end

        def crumb_attributes(item)
          attrs = {
            tag: :span,
            classes: "AppHeader-context-item",
            data: {
              target: "context-region-crumb.linkElement",
              **analytics_click_attributes(category: "SiteHeaderComponent", action: "context_region_crumb", label: item.label, screen_size: "full"),
              **item.link_data_attrs(include_hovercard: true),
            },
            test_selector: "context-item"
          }

          if item.has_path? || item.has_href?
            attrs[:tag] = :a
            attrs[:href] = path(item)
          end

          if is_last?(item) && is_current?(item)
            attrs[:"aria-current"] = "page"
          end

          attrs
        end

        def path(item)
          helpers.context_crumb_path(item)
        end

        def is_first?(item)
          item == context_crumbs.first
        end

        def is_last?(item)
          item == context_crumbs.last
        end

        def is_current?(item)
          path(item) == current_path
        end

        def page_context
          context_crumbs.map(&:label).join(" / ")
        end
      end
    end
  end
end
