# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class ExtractWikiLinksNodeFilter < InputFilter
    def call(input)
      output = GitHub::HTML::ExtractWikiLinksNodeFilter.new(input, @context, @result).call
      output.to_html
    end
  end
end
