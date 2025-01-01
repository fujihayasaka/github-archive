# typed: true
# frozen_string_literal: true

module Site
  class HeaderDropdownItemComponent < ApplicationComponent
    include HydroHelper

    SCHEME_DEFAULT = :default
    SCHEMES = [SCHEME_DEFAULT, :primary].freeze

    def initialize(text:, description: nil, url: nil, scheme: :default, icon: nil, external: false, render: true, item_last: false, data: nil, analytics: nil)
      @text = text
      @description = description
      @url = url
      @scheme = fetch_or_fallback(SCHEMES, scheme, SCHEME_DEFAULT)
      @icon = icon
      @external = external
      @render = render
      @item_last = item_last
      @analytics = analytics
      @data = data
    end

    def before_render
      # Generate analytics data from content and merge with other data attributes
      analytics = analytics_tags_from_content_v2(analytics: @analytics, text: @text)
      @analytics = analytics.present? ? analytics_click_attrs_marketing(**analytics) : nil
      @data = @analytics.present? && @data.present? ? @data.merge(@analytics) : @data || @analytics
    end

    def a_classes
      class_names(
        "HeaderMenu-dropdown-link d-block no-underline position-relative py-2",
        {
          "Link--primary text-bold": @scheme == :primary,
          "Link--secondary": @scheme == :default,
          "d-flex flex-items-center Link--has-description": @description.present?,
          "pb-lg-3": !@item_last && @icon.present? && @description.present?,
          "Link--external position-relative": @external,
        },
      )
    end

    def render?
      @render
    end
  end
end
