# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Adds `js-gh-image-fallback` class and replaces `height: auto` with a fixed
  # height on images that have explicit width/height attributes. This prevents
  # layout shift (jitter) when cached image tokens expire and the browser shows
  # a broken image icon at a different size than the original image.
  #
  # Must run AFTER ImageMaxWidthFilter (which adds height: auto) so we can
  # override it with the correct fixed height.
  class ImageFallbackFilter < NodeFilter
    SELECTOR = Goomba::Selector.new(
      "img[width][height][src*='githubusercontent.com'], img[width][height][src*='github.localhost'], img[width][height][src*='/user-attachments/assets/']"
    )

    FALLBACK_CLASS = "js-gh-image-fallback"

    def selector
      SELECTOR
    end

    def call(element)
      height = element["height"]
      width = element["width"]
      return element unless height && width && height.match?(/\A\d+\z/) && width.match?(/\A\d+\z/)

      # Add fallback class for client-side JS to detect
      if element["class"]
        element["class"] << " #{FALLBACK_CLASS}"
      else
        element["class"] = FALLBACK_CLASS
      end

      # Add aspect-ratio so the placeholder scales proportionally with max-width: 100%.
      # For loaded images, the browser's intrinsic dimensions take priority over aspect-ratio,
      # so this has no visual effect on working images. For broken/expired images, aspect-ratio
      # ensures the placeholder height matches what the loaded image would have been.
      if element["style"].present?
        new_style = element["style"]
        new_style += "; aspect-ratio: #{width} / #{height}; background-color: var(--bgColor-muted); border-radius: 6px"
        element["style"] = new_style
      end

      element
    end
  end
end
