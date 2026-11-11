# typed: true
# frozen_string_literal: true

module Site
  class CardComponent < ApplicationComponent
    include SvgHelper
    include AnalyticsHelper

    VERSION = "1.0.4"
    SIZE_DEFAULT = :medium
    CTA_DEFAULT = "Learn more"
    COLOR_DEFAULT = :accent
    SIZES = [SIZE_DEFAULT, :large].freeze
    BACKGROUND_DEFAULT = :default
    BACKGROUNDS = [BACKGROUND_DEFAULT, :subtle].freeze

    def initialize(header:, text: nil, url:, cta: CTA_DEFAULT, color: :accent, classes: nil, octicon: nil, size: SIZE_DEFAULT, badge: nil, border: nil, background: BACKGROUND_DEFAULT, analytics: nil, data: nil, id: nil, cache: true, cache_version: 1, render: true, heading_size: :h3)
      @header = header
      @classes = classes
      @text = text
      @cta = cta.present? ? cta : CTA_DEFAULT
      @url = url
      @size = size
      @size = fetch_or_fallback(SIZES, size, SIZE_DEFAULT)
      @badge = badge
      @border = border
      @background = fetch_or_fallback(BACKGROUNDS, background, BACKGROUND_DEFAULT)

      @analytics = analytics.present? ? analytics : {}
      @analytics[:category] = @analytics[:category].present? ? @analytics[:category] : "Resource cards"
      @analytics[:action] = @analytics[:action].present? ? @analytics[:action] : "Learn more about #{@header}"
      @analytics = analytics_click_attributes(**analytics_tags_from_content(analytics: @analytics, text: @cta))
      @data = @analytics.present? && data.present? ? data.merge(@analytics) : data || @analytics
      @data = @data.merge(analytics_visible_attributes(category: "Card", text: @header))
      @octicon = octicon
      @color = color.present? ? color : COLOR_DEFAULT
      @id = id
      @cache = cache
      @cache_version = cache_version
      @render = render
      @heading_size = heading_size
    end

    def cache_key
      digest = Digest::SHA256.hexdigest("#{@header}#{@text}#{@url}#{@size}#{@badge}#{@classes}#{@border}#{@background}#{@analytics.present? ? @analytics.to_json : ""}#{@octicon}#{@color}#{@id}#{@cache_version}")
      "site_card_#{VERSION}_#{digest}"
    end

    def container_classes
      class_names(
        "d-flex col-md-4 pb-5 pb-md-0 mb-5 flex-justify-between",
        @classes
      )
    end

    def header_classes
      class_names(
        "mb-3 text-semibold color-fg-default",
        {
          "h6-mktg": @size == :medium,
          "h4-mktg col-10": @size == :large
        }
      )
    end

    def card_classes
      class_names(
        "d-flex flex-column flex-justify-between no-underline box-shadow-card-border-mktg rounded-2 width-full resource-card arrow-target-mktg",
        {
          "border": @border,
          "color-bg-default": @background == :default,
          "color-bg-subtle": @background == :subtle,
          "p-5": @size == :medium,
          "p-4": @size == :large
        }
      )
    end

    def render?
      @render
    end
  end
end
