# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class CamoFilter < NodeFilter
    SELECTOR = Goomba::Selector.new("img, picture")
    PICTURE_SOURCE_SELECTOR = Goomba::Selector.new("source")
    PICTURE_IMG_SELECTOR = Goomba::Selector.new("img")

    # HTML Filter for replacing http image URLs with camo versions. See:
    #
    # https://github.com/atmos/camo
    #
    # All images provided in user content should be run through this
    # filter so that http image sources do not cause mixed-content warnings
    # in browser clients.
    #
    # Context options:
    #   :asset_proxy (required) - Base URL for constructed asset proxy URLs.
    #   :asset_proxy_secret_key (required) - The shared secret used to encode URLs.
    #   :asset_proxy_allowlist - Array of host Strings or Regexps to skip
    #                            src rewriting.
    def initialize(*args)
      super
      @filter = GitHub::HTML::CamoFilter.new("", context, result)
    end

    def selector
      SELECTOR
    end

    def self.cache_key(context)
      GitHub::HTML::CamoFilter.cache_key(context)
    end

    def call(element)
      return element unless @filter.asset_proxy_enabled?

      if element.tag == :img
        @filter.camo_image_filter(element, source_attribute: "src")
      elsif element.tag.nil? # goomba doesn't recognize the picture tag and sets element.tag to nil
        element.select(PICTURE_SOURCE_SELECTOR).each do |source|
          @filter.camo_image_filter(source, source_attribute: "srcset")
        end
        element.select(PICTURE_IMG_SELECTOR).each do |source|
          @filter.camo_image_filter(source, source_attribute: "src")
        end
      end

      element
    end
  end
end
