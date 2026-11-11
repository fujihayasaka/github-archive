# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Render colors inline for for hex, rgb/rgba,and hsl/hsla values inside of code tags.
  class ColorFilter < NodeFilter
    include ActionView::Helpers::OutputSafetyHelper
    SELECTOR = Goomba::Selector.new("code")
    DECIMAL = /[\d.]+/
    PERCENT = /#{DECIMAL}%/
    COMMA = /\s*,\s*/ # (with optional whitespace)
    HEX_REGEXP = /\A#\h{6}\z/
    RGB_REGEXP = /\Argb\(\s*#{DECIMAL}#{COMMA}#{DECIMAL}#{COMMA}#{DECIMAL}\s*\)\z/
    RGBA_REGEXP = /\Argba\(\s*#{DECIMAL}#{COMMA}#{DECIMAL}#{COMMA}#{DECIMAL}#{COMMA}#{DECIMAL}\s*\)\z/
    HSL_REGEXP = /\Ahsl\(\s*#{DECIMAL}#{COMMA}#{PERCENT}#{COMMA}#{PERCENT}\s*\)\z/
    HSLA_REGEXP = /\Ahsl\(\s*#{DECIMAL}#{COMMA}#{PERCENT}#{COMMA}#{PERCENT}#{COMMA}#{DECIMAL}\s*\)\z/

    COLOR_REGEXP = Regexp.union(
      HEX_REGEXP,
      RGB_REGEXP,
      RGBA_REGEXP,
      HSL_REGEXP,
      HSLA_REGEXP
    )

    COLOR_CLASS = "ml-1 d-inline-block border circle color-border-subtle"

    def initialize(*args)
      super
    end

    def selector
      SELECTOR
    end

    def call(element)
      text_content = element.text_content
      return nil unless COLOR_REGEXP.match?(text_content)

      inner_span = ActionController::Base.helpers.tag(:span, class: COLOR_CLASS, style: "background-color: #{text_content}; height: 8px; width: 8px;")
      ActionController::Base.helpers.content_tag(:code, safe_join([text_content, inner_span]))
    end
  end
end
