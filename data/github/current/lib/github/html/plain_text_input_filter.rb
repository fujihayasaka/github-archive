# typed: true
# frozen_string_literal: true

module GitHub::HTML
  # Simple filter for plain text input. HTML escapes the text input and wraps it
  # in a div. We subclass the parent to set `context[:html_safe]` to true so
  # that callers can check the safety of the result before using it in an HTML
  # context.
  class PlainTextInputFilter < ::HTML::Pipeline::PlainTextInputFilter
    def call
      doc = super
      result[:html_safe] = true
      doc
    end
  end
end
