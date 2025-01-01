# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Public: Replaces image elements with their alt text when the alt text is present.
  class ImageAltTextFilter < NodeFilter
    SELECTOR = Goomba::Selector.new("img[alt]")

    def selector
      SELECTOR
    end

    def call(element)
      element["alt"]
    end
  end
end
