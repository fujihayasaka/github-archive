# typed: true
# frozen_string_literal: true

module Site
  module Header
    module ContextRegion
      class CrumbsComponent < ApplicationComponent
        include AnalyticsHelper

        attr_reader :context_crumbs, :current_path

        def initialize(context_crumbs, current_path, compact: false)
          @context_crumbs = context_crumbs
          @compact = compact
          @current_path = current_path
        end

        def compact?
          !!@compact
        end

        def crumb_attributes(item)
          attrs = {
            tag: :span,
            classes: "AppHeader-context-item",
            data: analytics_click_attributes(category: "SiteHeaderComponent", action: "context_region_crumb", label: item.label, screen_size: compact? ? "compact" : "full"),
            test_selector: "context-item"
          }

          attrs[:data].merge!(item.link_data_attrs(include_hovercard: !compact?))

          if item.has_path?
            attrs[:tag] = :a
            attrs[:href] = path(item)
          end

          if is_last?(item) && is_current?(item)
            attrs[:"aria-current"] = "page"
          end

          if compact?
            attrs[:classes] = "Link--primary Truncate"
            attrs[:display] = :flex
            attrs[:align_items] = :center
            attrs[:py] = 1
          end

          attrs
        end

        def path(item)
          return "#" unless item.has_path?

          if item.path
            item.path
          else
            T.unsafe(self).send(item.path_name, *item.path_args)
          end
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
