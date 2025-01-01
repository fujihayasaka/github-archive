# typed: true
# frozen_string_literal: true

module Site
  class FooterCtaComponent < ApplicationComponent
    include SiteHelper

    TEXT_PLACEMENT_DEFAULT = :center
    TEXT_PLACEMENTS = [:left, TEXT_PLACEMENT_DEFAULT].freeze

    def initialize(text_placement: TEXT_PLACEMENT_DEFAULT, header: "Header", text: nil, dark: true, overflow_visible: false, **options)
      @header = header
      @text = text
      @text_placement = fetch_or_fallback(TEXT_PLACEMENTS, text_placement, TEXT_PLACEMENT_DEFAULT)
      @dark = dark
      @overflow_visible = overflow_visible
      @options = options
    end

    def container_classes
      class_names(
        "pt-8 pb-7 pb-md-8 d-flex flex-column flex-items-center",
        {
         "flex-lg-column text-center": @text_placement == :center,
         "overflow-hidden": @overflow_visible == false
        },
      )
    end
  end
end
