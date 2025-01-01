# typed: true
# frozen_string_literal: true

module Site
  class HeroComponent < ApplicationComponent
    renders_one :before
    renders_one :after
    renders_one :cta

    VERSION = "1.0.2"
    DEPENDENCIES = {
      Site::BadgeComponent.name => Site::BadgeComponent::VERSION,
      Site::ButtonGroupComponent.name => Site::ButtonGroupComponent::VERSION,
      Site::EyebrowBannerComponent.name => Site::EyebrowBannerComponent::VERSION
    }
    TEXT_PLACEMENT_DEFAULT = :center
    TEXT_PLACEMENTS = [:left, TEXT_PLACEMENT_DEFAULT].freeze

    def initialize(text_placement: TEXT_PLACEMENT_DEFAULT, header: "Header", description_color: :muted, text: nil, size: :medium, ctas: nil, classes: nil, badge: nil, banner: nil, cache: true, cache_version: 1, **options)
      @header = header
      @classes = classes
      @text = text
      @size = size
      @text_placement = fetch_or_fallback(TEXT_PLACEMENTS, text_placement, TEXT_PLACEMENT_DEFAULT)
      @ctas = ctas # Renders a Site::ButtonGroupComponent
      @badge = badge # Renders a Site::BadgeComponent
      @badge_size = @size == :large ? :xlarge : :large
      @banner = banner # Renders a Site::EyebrowBannerComponent
      @description_color = description_color
      @cache = cache # If the component should be cached, pass false to disable per instance
      @cache_version = cache_version # Bump to bust cache
      @options = options

      # Add default values and ref_loc to ctas
      if @ctas.present?
        @ctas.first[:size] ||= :large

        @ctas.map do |cta|
          cta[:analytics] = {
            ref_loc: "Hero ctas",
            category: "Hero ctas",
          }
        end
      end
    end

    def cache_key
      digest = Digest::SHA256.hexdigest("#{@header}#{@ctas.present? ? @ctas.to_json : "ctas"}#{@banner.present? ? @banner.to_json : "banner"}#{@text}#{@size}#{@badge}#{@classes}#{@text_placement}#{@cache_version}#{DEPENDENCIES.to_json}")
      "site_hero_#{VERSION}_#{digest}"
    end

    def container_classes
      class_names(
        "pt-10 pb-4 pb-md-7 d-flex flex-column",
        @classes,
        {
         "flex-lg-column flex-items-center text-center": @text_placement == :center,
         "flex-items-start": @text_placement == :left
        },
      )
    end

    def heading_classes
      class_names(
        "col-10-max color-fg-default",
        {
          "mx-auto": @text_placement == :center,
          "h1-mktg": @size == :medium,
          "h0-mktg": @size == :large,
        }
      )
    end

    def description_classes
      class_names(
        "mt-4",
        {
          "f3-mktg": @size == :medium,
          "f2-mktg mb-5": @size == :large,
          "color-fg-muted": @description_color == :muted,
          "color-fg-default": @description_color == :default,
          "mx-auto col-7-max": @text_placement == :center,
          "col-6-max": @text_placement == :left && @size == :medium,
          "col-7-max": @text_placement == :left && @size == :large,
        }
      )
    end
  end
end
