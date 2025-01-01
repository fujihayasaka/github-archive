# typed: true
# frozen_string_literal: true

module Site
  class LinkComponent < ApplicationComponent
    include SvgHelper

    SIZE_DEFAULT = :large
    SIZES = [:small, :medium, SIZE_DEFAULT].freeze
    VERSION = "1.1.0"

    def initialize(text:, url:, size: SIZE_DEFAULT, classes: nil, analytics: nil, underlined: false, arrow: true, cache: true, data: nil, **options)
      @text = text
      @url = url
      @size = fetch_or_fallback(SIZES, size, SIZE_DEFAULT)
      @classes = classes
      @analytics = analytics
      @data = data
      @underlined = underlined
      @arrow = arrow
      @cache = cache
      @options = options
    end

    def cache_key
      digest = Digest::SHA256.hexdigest("#{@text}#{@url}#{@size}#{@classes}#{@analytics.present? ? @analytics.to_json : ""}#{@underlined}#{@arrow}")
      "site_link_#{VERSION}_#{digest}"
    end

    def before_render
      # Generate analytics data from content and merge with other data attributes
      analytics = analytics_tags_from_content(analytics: @analytics, text: @text)
      @analytics = analytics.present? ? analytics_click_attributes(**analytics) : nil
      @data = @analytics.present? && @data.present? ? @data.merge(@analytics) : @data || @analytics
    end

    def link_classes
      class_names(
        "link-mktg text-semibold color-fg-default py-1",
        @classes,
        {
          "f3-mktg": @size == :large,
          "f4-mktg": @size == :medium,
          "f5-mktg": @size == :small,
          "link-emphasis-mktg": @underlined,
        },
      )
    end
  end
end
