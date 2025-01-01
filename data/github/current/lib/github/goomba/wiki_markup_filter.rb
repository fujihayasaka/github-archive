# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class WikiMarkupFilter < InputFilter
    def call(input)
      GitHub::HTML::WikiMarkupFilter.new(input, @context).call
    end
  end
end
