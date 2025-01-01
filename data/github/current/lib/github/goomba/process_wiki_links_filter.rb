# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class ProcessWikiLinksFilter < InputFilter
    def call(input)
      output = GitHub::HTML::ProcessWikiLinksFilter.new(input, @context, @result).call
      output.to_html
    end
  end
end
