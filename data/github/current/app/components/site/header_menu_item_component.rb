# typed: true
# frozen_string_literal: true

module Site
  class HeaderMenuItemComponent < ApplicationComponent
    VERSION = "1.0.1"

    def initialize(text:, columns: nil, url: nil, analytics: nil, data: nil, trailing_link: nil)
      @text = text
      @columns = columns
      @url = url
      default_analytics = {
        context: "global",
        location: "navbar",
        tag: "link"
      }
      @analytics = analytics.present? ? analytics : default_analytics
      @data = data
      @trailing_link = trailing_link
      @column_layout = columns.present? && columns.length > 1
      @digest = Digest::SHA256.hexdigest("#{@columns.present? ? @columns.to_json : "columns"}_#{@url}")
    end

    def columns_cache_key
      "site_header_menu_item_columns_#{VERSION}_#{@digest}"
    end

    def before_render
      # Generate analytics data from content and merge with other data attributes
      analytics = analytics_tags_from_content_v2(analytics: @analytics, text: @text)
      @analytics = analytics.present? ? analytics_click_attrs_marketing(**analytics) : nil
      @data = @analytics.present? && @data.present? ? @data.merge(@analytics) : @data || @analytics
    end

    def dropdown_classes
      class_names(
        "HeaderMenu-dropdown dropdown-menu rounded m-0 p-0 pt-2 pt-lg-4 position-relative position-lg-absolute left-0 left-lg-n3",
        {
          "pb-2 pb-lg-4": !@trailing_link.present?,
          "d-lg-flex flex-wrap dropdown-menu-wide": @column_layout,
          "px-lg-4": !@column_layout,
        }
      )
    end

    def group_border_classes(last_group = false, last_column = false)
      class_names(
        "border-bottom pb-3 pb-lg-0",
        {
          "border-lg-bottom-0": @column_layout,
          "border-bottom-0": last_group && last_column,
          "pb-lg-3 mb-3 mb-lg-0": !last_group,
          "mb-lg-3": !last_group && !@column_layout,
        }
      )
    end

    def column_border_classes(last_column = false)
      class_names(
        "HeaderMenu-column",
        {
          "px-lg-4": @column_layout,
          "border-lg-right mb-4 mb-lg-0 pr-lg-7": !last_column && @column_layout,
        }
      )
    end
  end
end
