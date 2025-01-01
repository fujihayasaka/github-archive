# typed: true
# frozen_string_literal: true

module Site
  class HeaderMenuItemComponent < ApplicationComponent
    VERSION = "1.0.1"

    def initialize(text:, column_layout: false, groups: nil, url: nil, analytics: nil, data: nil)
      @text = text
      @column_layout = column_layout
      @groups = groups
      @url = url
      default_analytics = {
        context: "global",
        location: "navbar",
        tag: "link"
      }
      @analytics = analytics.present? ? analytics : default_analytics
      @data = data
      @digest = Digest::SHA256.hexdigest("#{@groups.present? ? @groups.to_json : "groups"}_#{@url}")
    end

    def groups_cache_key
      "site_header_menu_item_groups_#{VERSION}_#{@digest}"
    end

    def before_render
      # Generate analytics data from content and merge with other data attributes
      analytics = analytics_tags_from_content_v2(analytics: @analytics, text: @text)
      @analytics = analytics.present? ? analytics_click_attrs_marketing(**analytics) : nil
      @data = @analytics.present? && @data.present? ? @data.merge(@analytics) : @data || @analytics
    end

    def dropdown_classes
      class_names(
        "HeaderMenu-dropdown dropdown-menu rounded m-0 p-0 py-2 py-lg-4 position-relative position-lg-absolute left-0 left-lg-n3",
        {
          "d-lg-flex dropdown-menu-wide": @column_layout,
          "px-lg-4": !@column_layout,
        }
      )
    end

    def group_border_classes(last_group = false)
      class_names(
        {
          "px-lg-4": @column_layout,
          "border-lg-right mb-4 mb-lg-0 pr-lg-7": !last_group && @column_layout,
          "border-bottom pb-3 mb-3": !last_group && !@column_layout,
        }
      )
    end
  end
end
