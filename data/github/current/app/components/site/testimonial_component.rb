# typed: true
# frozen_string_literal: true

module Site
  class TestimonialComponent < ApplicationComponent
    include SvgHelper

    SIZE_DEFAULT = :large
    SIZES = [:medium, SIZE_DEFAULT].freeze

    def initialize(quote:, fullname:, title: nil, image: nil, company: nil, logo: nil, size: SIZE_DEFAULT, classes: nil)
      @quote = quote
      @fullname = fullname
      @image = image
      @logo_src = logo
      @company = company
      @title = title
      @size = fetch_or_fallback(SIZES, size, SIZE_DEFAULT)
      @classes = classes
    end

    def container_classes
      class_names(
        "position-relative d-md-flex flex-items-center flex-justify-center text-left",
        {
         "gutter-md-spacious px-3 px-lg-0 mt-8 mb-10 mt-lg-10 mb-lg-12 mx-auto": @size == :large
        },
      )
    end

    def quote_container_classes
      class_names(
        {
         "col-md-8": @size == :large,
         "col-12": @size == :medium
        },
      )
    end

    def blockquote_classes
      class_names(
        "mb-4 f1-mktg text-medium",
      )
    end

    def cite_classes
      class_names(
        "d-block color-fg-muted text-mono",
        {
         "mb-3": @size == :large
        },
      )
    end

    def citation_mark_classes
      class_names(
        {
         "position-md-absolute ml-md-n3": @size == :large,
         "d-block mb-3": @size == :medium
        },
      )
    end

    def name_classes
      class_names(
        {
         "color-fg-default f3-mktg": @size == :medium
        },
      )
    end

    def title_classes
      class_names(
        {
         "d-block": @size == :medium
        },
      )
    end

    def logo_classes
      class_names(
        "mr-2 mr-sm-3 mr-lg-4 width-fit",
        {
          "my-3": @size == :medium
        }
      )
    end
  end
end
