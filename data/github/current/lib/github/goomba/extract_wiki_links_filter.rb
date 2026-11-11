# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class ExtractWikiLinksFilter < InputFilter
    def call(input)
      GitHub::HTML::ExtractWikiLinksFilter.new(input, @context, @result).call
    end
  end
end
