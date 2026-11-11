# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Simple filter for plain text input. HTML escapes the text input and wraps it
  # in a div.
  class PlainTextInputFilter < InputFilter
    def call(text)
      GitHub::HTML::PlainTextInputFilter.new(text, context, result).call
    end
  end
end
