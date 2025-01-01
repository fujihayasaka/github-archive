# typed: true
# frozen_string_literal: true

module Site
  class FooterCardComponent < ApplicationComponent
    def initialize(header: , text: nil, ctas: nil, classes: nil, background_image: nil)
      @header = header
      @text = text
      @ctas = ctas
      @classes = classes
      @background_image = background_image
    end

    def card_classes
      class_names(
        "width-full mx-auto mb-8 px-5 px-md-8 py-6 py-md-8 py-lg-12 text-center color-bg-default rounded-3 box-shadow-default-border-mktg position-relative z-1",
        @classes
      )
    end
  end
end
