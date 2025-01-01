# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class ProcessWikiCodeBlocksFilter < InputFilter
    def call(input)
      output = GitHub::HTML::ProcessWikiCodeBlocksFilter.new(input, @context, @result).call
      if output.is_a?(String)
        output
      else
        output.to_html
      end
    end
  end
end
