# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class EmptyAnchorFilter < InputFilter
    include GitHub::UTF8
    def call(string)
      doc = Nokogiri::HTML.fragment(string)
      # Because input filters don't always return values, we can't be guaranteed that any
      # given string entering or leaving these filters is a utf 8 compatible one.
      # Therefore, we ensure that any content we output is utf8 encoded.
      utf8(GitHub::HTML::EmptyAnchorFilter.new(doc, context).call.to_html)
    end
  end
end
