# typed: true
# frozen_string_literal: true

module Site
  class HeaderMenuItemComponent < ApplicationComponent
    VERSION = "1.0.2"

    DEFAULT_ANALYTICS = {
      context: "global",
      location: "navbar",
      tag: "link"
    }

    def initialize(text:, columns: nil, url: nil, analytics: nil, data: nil, trailing_link: nil)
      @text = text
      @columns = columns
      @url = url
      @analytics = analytics.present? ? analytics : DEFAULT_ANALYTICS
      @data = data
      @trailing_link = trailing_link
    end

    def columns_cache_key
      digest = Digest::SHA256.hexdigest("#{@columns.present? ? @columns.to_json : "columns"}_#{@url}")

      "site_header_menu_item_columns_#{VERSION}_#{digest}"
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
          "dropdown-menu-wide": has_multiple_columns?,
        }
      )
    end

    def group_border_classes(last_group = false, last_column = false, has_no_separator = false, has_trailing_link = false)
      if has_no_separator
        ""
      else
        class_names(
          "border-bottom",
          {
            "border-lg-bottom-0 pb-lg-0": has_multiple_columns? || has_trailing_link,
            "border-bottom-0": last_group && last_column && !has_trailing_link,
            "mb-3": !last_group,
            "mb-lg-3": (!last_column || !last_group) && is_single_column?,
            "pb-3": !last_column || !last_group || has_trailing_link,
            "pb-lg-0": has_trailing_link,
          }
        )
      end
    end

    def column_border_classes(last_column = false, has_no_separator = false)
      class_names(
        "HeaderMenu-column px-lg-4",
        {
          "pb-3 pb-lg-0 border-lg-right": !last_column && !has_no_separator,
        }
      )
    end

    private

    def is_single_column?
      @columns.present? && @columns.length == 1
    end

    def has_multiple_columns?
      @columns.present? && @columns.length > 1
    end
  end
end
