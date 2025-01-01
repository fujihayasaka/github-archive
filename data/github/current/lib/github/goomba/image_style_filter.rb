# typed: true
# frozen_string_literal: true

require "css_parser"

module GitHub::Goomba
  # Allows "safe" inline style attributes (eg. `height`, `width`) through on
  # `img` elements, filtering out all others. We generally want to filter out
  # most CSS rules because they can pose security problems (eg. via the CSS
  # `url()` function) or break visuals (eg. `border` and friends).
  class ImageStyleFilter < NodeFilter
    # Matches simple integer or decimal values with units (e.g., 123px, 1.23em,
    # 50%). Does not match values less than one. Does not match decimal values
    # with more than nine decimal places.
    #
    # Changes to this pattern should also be reflected in the
    # ThemedPictureElement Catalyst element's similarly named constant.
    DIMENSION_PATTERN = /\A\s*[1-9]\d*(?:\.\d{1,9})?(?:[a-z]+|%)\z/i

    # Rules are allowed only if the given property (key) is provided with a
    # value matching the regexp.
    ALLOWED_RULES = {
      "height" => DIMENSION_PATTERN,
      "width" => DIMENSION_PATTERN,
    }
    SELECTOR = Goomba::Selector.new("img")

    def selector
      SELECTOR
    end

    def call(element)
      return if element["style"].blank?

      styles = CssParser::RuleSet.new(selectors: "*", block: element["style"])

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
