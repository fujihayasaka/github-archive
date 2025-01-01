# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class ExtractWikiCodeBlocksFilter < InputFilter
    def call(input)
      GitHub::HTML::ExtractWikiCodeBlocksFilter.new(input, @context, @result).call
    end
  end
end
