# typed: true
# frozen_string_literal: true

module Site
  class ButtonComponent < ApplicationComponent
    include SvgHelper
    include HydroHelper

    SIZE_DEFAULT = :medium
    SIZES = [:small, SIZE_DEFAULT, :large].freeze
    SCHEME_DEFAULT = :default
    SCHEMES = [SCHEME_DEFAULT, :muted, :signup, :subtle].freeze

    def initialize(text: nil, url: nil, size: SIZE_DEFAULT, scheme: SCHEME_DEFAULT, classes: nil, analytics: nil, arrow: false, disabled: false, focusable: true, data: nil, submit: false, render: true, **options)
      @text = text
      @url = url
      @is_button = !@url.present?
      @size = fetch_or_fallback(SIZES, size, SIZE_DEFAULT)
      @scheme = fetch_or_fallback(SCHEMES, scheme, SCHEME_DEFAULT)
      @classes = classes
      @analytics = analytics
      @data = data
      @arrow = arrow
      @disabled = disabled
      @focusable = focusable
      @options = options
      @submit = submit
      @render = render
    end

    def before_render
      # Generate analytics data from content and merge with other data attributes
      analytics = analytics_tags_from_content(analytics: @analytics, text: @text)
      @analytics = analytics.present? ? analytics_click_attributes(**analytics) : nil
      @data = @analytics.present? && @data.present? ? @data.merge(@analytics) : @data || @analytics
    end

    def button_classes
      class_names(
        "btn-mktg",
        @classes,
        {
          "btn-large-mktg": @size == :large,
          "btn-small-mktg": @size == :small,
          "btn-signup-mktg": @scheme == :signup,
          "btn-muted-mktg": @scheme == :muted,
          "btn-subtle-mktg": @scheme == :subtle,
          "disabled": @disabled == true
        },
      )
    end

    def element_tag
      @is_button ? "button" : "a"
    end

    def render?
      @render
    end
  end
end
