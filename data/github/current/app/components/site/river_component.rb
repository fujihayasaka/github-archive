# typed: true
# frozen_string_literal: true

module Site
  class RiverComponent < ApplicationComponent
    renders_one :before
    renders_one :text
    renders_one :after
    renders_one :illustration
    renders_one :background

    VERSION = "1.0.1"
    DEPENDENCIES = {
      Site::BadgeComponent.name => Site::BadgeComponent::VERSION,
      Site::ImageComponent.name => Site::ImageComponent::VERSION,
      Site::LinkComponent.name => Site::LinkComponent::VERSION
    }
    ILLUSTRATION_SIZE_DEFAULT = :medium
    ILLUSTRATION_SIZES = [:small, ILLUSTRATION_SIZE_DEFAULT, :large].freeze
    ILLUSTRATION_ALIGNMENT_DEFAULT = :center
    ILLUSTRATION_ALIGNMENTS = [:top, ILLUSTRATION_ALIGNMENT_DEFAULT].freeze
    VERTICAL_ALIGNMENT_DEFAULT = :center
    VERTICAL_ALIGNMENTS = [:top, VERTICAL_ALIGNMENT_DEFAULT, :bottom].freeze
    SIZE_DEFAULT = :medium
    SIZES = [:small, SIZE_DEFAULT, :large].freeze
    TEXT_PLACEMENT_DEFAULT = :left
    TEXT_PLACEMENTS = [TEXT_PLACEMENT_DEFAULT, :right, :center].freeze

    def initialize(
        text_placement: TEXT_PLACEMENT_DEFAULT,
        illustration_size: ILLUSTRATION_SIZE_DEFAULT,
        illustration_alignment: ILLUSTRATION_ALIGNMENT_DEFAULT,
        vertical_alignment: VERTICAL_ALIGNMENT_DEFAULT,
        header: nil,
        sub_header: nil,
        text: nil,
        stagger: 100,
        heading_level: :h2,
        size: SIZE_DEFAULT,
        padding: true,
        build_bottom: nil,
        classes: nil,
        read: nil,
        link: nil,
        images: nil,
        images_classes: nil,
        animate: nil,
        badge: nil,
        cache: true,
        cache_version: 1,
        **options
      )

      @text_placement = fetch_or_fallback(TEXT_PLACEMENTS, text_placement, TEXT_PLACEMENT_DEFAULT)
      @header = header
      @sub_header = sub_header
      @text = text
      @stagger = stagger
      @build_bottom = build_bottom
      @heading_level = heading_level
      @size = fetch_or_fallback(SIZES, size, SIZE_DEFAULT)
      @illustration_size = fetch_or_fallback(ILLUSTRATION_SIZES, illustration_size, ILLUSTRATION_SIZE_DEFAULT)
      @illustration_alignment = fetch_or_fallback(ILLUSTRATION_ALIGNMENTS, illustration_alignment, ILLUSTRATION_ALIGNMENT_DEFAULT)
      @vertical_alignment = fetch_or_fallback(VERTICAL_ALIGNMENTS, vertical_alignment, VERTICAL_ALIGNMENT_DEFAULT)
      @padding = padding
      @classes = classes
      @read = read
      @link = link
      @images = images
      @images_classes = images_classes
      @animate = animate.present? ? animate : @text_placement != :center
      @badge = badge
      @cache = cache
      @cache_version = cache_version
      @options = options
      @dependencies = DEPENDENCIES
    end

    def cache_key
      digest = Digest::SHA256.hexdigest("#{@header}#{@sub_header}#{@text}#{@stagger}#{@build_bottom}#{@heading_level}#{@size}#{@illustration_size}#{@illustration_alignment}#{@vertical_alignment}#{@padding}#{@classes}#{@read.present? ? @read.present? : ""}#{@link.present? ? @link.to_json : ""}#{@images.present? ? @images.to_json : ""}#{@images_classes}#{@animate}#{@badge}#{@cache_version}#{DEPENDENCIES.to_json}")
      "site_river_#{VERSION}_#{digest}"
    end

    def container_classes
      class_names(
        "river-mktg js-build-in-trigger d-flex gutter gutter-spacious my-5 my-sm-7 my-md-8 position-relative",
        @classes,
        {
          "flex-md-items-start": @vertical_alignment == :top,
          "flex-md-items-center": @vertical_alignment == :center,
          "flex-md-items-end": @vertical_alignment == :bottom,
          "flex-md-row-reverse": @text_placement == :right,
          "flex-md-row": @text_placement == :left,
          "text-center": @text_placement == :center,
          "flex-column": @illustration_alignment != :top,
          "flex-column-reverse": @illustration_alignment == :top,
          "pb-4 pb-md-7": @padding == true && (content.present? || @images.present?),
        },
      )
    end

    def illustration_classes
      class_names(
        "col-12 py-3",
        {
          "mt-5": @text_placement == :center,
          "col-md-6": @text_placement != :center,
          "col-lg-6": @text_placement != :center && @illustration_size == :medium,
          "col-lg-7": @text_placement != :center && @illustration_size == :large,
        },
      )
    end

    def images_classes
      class_names(
        "position-relative",
        @images_classes
      )
    end

    def header_classes
      class_names(
        "color-fg-default mb-3",
        {
         "f2-mktg color-fg-muted": @size == :small,
         "h3-mktg": @size == :medium,
         "h2-mktg": @size == :large,
         "mt-5": @size == :large && !@sub_header.present? && !@badge.present?,
         "col-lg-7": @text_placement == :center && @size == :small,
         "col-lg-8": @text_placement == :center && @size == :medium,
         "col-md-10 col-lg-9": @text_placement == :center && @size == :large,
         "mx-md-auto px-3": @text_placement == :center,
        },
      )
    end

    def sub_header_classes
      class_names(
        "text-normal text-mono text-uppercase color-fg-muted f5-mktg text-spaced mt-5 mb-2",
      )
    end

    def text_classes
      class_names(
        "mb-3",
        {
         "f4-mktg color-fg-subtle": @size == :small,
         "f3-mktg color-fg-muted": @size == :medium,
         "f1-mktg color-fg-muted": @size == :large,
         "px-3 mx-auto col-7-max": @text_placement == :center,
         "col-6-max": @text_placement != :center && @illustration_size != :small,
        },
      )
    end

    def content_classes
      class_names(
        "col-12 py-3 mb-2",
        {
          "js-build-in-item": @animate,
          "col-sm-10 col-md-6 text-left": @text_placement != :center,
          "col-lg-8": @text_placement != :center && @illustration_size == :small,
          "col-lg-6": @text_placement != :center && @illustration_size == :medium,
          "col-lg-5": @text_placement != :center && @illustration_size == :large,
          "build-in-slideX-left": @text_placement == :right  && @animate == true,
          "build-in-slideX-right": @text_placement == :left  && @animate == true,
          "build-in-scale-up": @text_placement == :center && @animate == true
        },
      )
    end

    def content_inner_classes
      class_names(
        {
          "pl-md-4": @text_placement == :right,
          "pr-md-4": @text_placement == :left
        },
      )
    end

    def image_with_default_river_sizes(image)
      if image[:sizes].blank?
        image[:sizes] = "(max-width: 768px) 90vw, (max-width: 1320px) 45vw, 616px"
      end

      image
    end
  end
end
