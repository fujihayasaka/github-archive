# typed: true
# frozen_string_literal: true

require "css_parser"

module GitHub::Goomba
  # This filter rewrites image tags with a max-width inline style and wraps top-level images in <p> tags.
  #
  # The max-width inline styles are especially useful in HTML email which
  # don't use a global stylesheets.
  class ImageMaxWidthFilter < NodeFilter
    MAX_HEIGHT_WIDTH = 2000
    HEIGHT_WIDTH_ATTRS = %w(height width)
    SELECTOR = Goomba::Selector.new("img")
    INSIDE_LINK = Goomba::Selector.new("a img")

    def selector
      SELECTOR
    end

    def call(element)
      # Cap height/width attributes.

      HEIGHT_WIDTH_ATTRS.each do |attr|
        if (value = element[attr].try(:to_i)) && value > MAX_HEIGHT_WIDTH
          element[attr] = MAX_HEIGHT_WIDTH.to_s
        end
      end

      # If this image was converted to a /raw/ URL by RawImageFilter, we should
      # link to the non-raw version so users can browse the image's version
      # history etc.
      src = (RawImageFilter.non_raw_image_urls(scratch)[element] || element["src"]).to_s

      # Bail out if src doesn't look like a valid http url. trying to avoid weird
      # js injection via javascript: urls.
      begin
        return unless [nil, "http", "https"].include?(Addressable::URI.parse(src.strip).scheme&.downcase)
      rescue Addressable::URI::InvalidURIError
        return
      end

      styles = CssParser::RuleSet.new(selectors: "*", block: element["style"])

      styles["max-width"] = "100%"
      if styles["height"].empty? &&
        element["height"].present? &&
        (height = element["height"].try(:to_i)) &&
        height > 0 && (element["height"] == height.to_s || element["height"].end_with?("px")) # ensure height is a valid pixel value
        styles["height"] = "auto"
        styles["max-height"] = "#{height}px"
      end
      element["style"] = styles.declarations_to_s

      return element if element.matches(INSIDE_LINK) || element["secured-asset-link"]

      supposedly_safe_image = safe_html_if_sanitized(element.to_html)

      html = ActionController::Base.helpers.link_to(supposedly_safe_image, src, target: "_blank", rel: "noopener noreferrer")
      html = ActionController::Base.helpers.content_tag(:p, html) if element.parent.tag == :html
      html
    end
  end
end
