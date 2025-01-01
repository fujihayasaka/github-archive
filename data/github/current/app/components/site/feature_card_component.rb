# typed: true
# frozen_string_literal: true

module Site
  class FeatureCardComponent < ApplicationComponent
    def initialize(header: "", link: nil, image: nil, classes: nil, orientation: :horizontal, text_placement: :left, header_classes: nil, cache: true, cache_version: 1)
      @header = header
      @link = link
      @image = image
      @classes = classes
      @orientation = orientation
      @text_placement = text_placement
      @header_classes = header_classes
      @cache = cache
      @cache_version = cache_version

      # Default to sensible sizing rules for images
      if @image.present? && @image[:sizes].nil?
        @image[:sizes] = "(max-width: 768px) 90vw, (max-width: 1280px) 50vw, #{@image[:width] / 2}px"
      end
    end

    def cache_key
      digest = Digest::SHA256.hexdigest("#{@images.present? ? @images.to_json : ""}#{@header}#{@link.present? ? @link.to_json : ""}#{@classes}#{@orientation}#{@text_placement}#{@header_classes}#{@cache_version}")
      "site_feature_card_#{digest}"
    end

    def container_classes
      class_names(
        "feature-card-mktg d-md-flex rounded-3 color-bg-subtle border position-relative flex-justify-between z-1 height-full",
        @classes,
        {
          "flex-row": @orientation == :horizontal,
          "flex-column": @orientation == :vertical,
          "flex-row-reverse": @orientation == :horizontal && @text_placement == :right,
        }
      )
    end

    def content_classes
      class_names(
        "d-md-flex flex-column flex-1 p-5 p-sm-6 py-lg-8 pl-lg-8 pr-lg-12",
        {
          "col-md-6 flex-justify-between": @orientation == :horizontal,
          "flex-justify-start": @orientation == :vertical,
        }
      )
    end

    def header_classes
      class_names(
        "f2-mktg text-medium color-fg-muted mb-4",
        @header_classes,
      )
    end

    def image_container_classes
      class_names(
        "overflow-hidden",
        {
          "col-md-6": @orientation == :horizontal,
          "rounded-right-3": @orientation == :horizontal && @text_placement == :left,
          "rounded-left-3": @orientation == :horizontal && @text_placement == :right,
          "rounded-bottom-3": @orientation == :vertical,
        }
      )
    end
  end
end
