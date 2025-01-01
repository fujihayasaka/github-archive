# typed: true
# frozen_string_literal: true

require "css_parser"

module GitHub::Goomba
  # Allows "safe" inline style attributes (eg. `height`, `width`) through on
  # `img` elements, filtering out all others. We generally want to filter out
  # most CSS rules because they can pose security problems (eg. via the CSS
  # `url()` function) or break visuals (eg. `border` and friends).
  class ImageStyleFilter < NodeFilter
    # Rules are allowed only if the given property (key) is provided with a
    # value matching the regexp.
    ALLOWED_RULES = {
      "height" => /\A\s*[1-9]\d*(?:[a-z]+|%)\z/i,
      "width" => /\A\s*[1-9]\d*(?:[a-z]+|%)\z/i,
    }
    SELECTOR = Goomba::Selector.new("img")

    def selector
      SELECTOR
    end

    def call(element)
      return if element["style"].blank?

      styles = CssParser::RuleSet.new("*", element["style"])

      styles.each_declaration do |name, value|
        if ALLOWED_RULES.has_key?(name) && ALLOWED_RULES[name] =~ value
          styles[name] = value
        else
          styles[name] = nil
        end
      end

      style = styles.declarations_to_s

      if style.blank?
        element.remove_attribute("style")
      else
        element["style"] = styles.declarations_to_s
      end

      element
    end
  end
end
