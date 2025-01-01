# typed: true
# frozen_string_literal: true

require "github/goomba/suggested_change_filter"

module GitHub::Goomba
  class RemoveNonSuggestedChangeFilter < NodeFilter
    SELECTOR = Goomba::Selector.new(match: "*", reject: GitHub::Goomba::SuggestedChangeFilter::SELECTOR_REGEX)

    def selector
      SELECTOR
    end

    def call(node)
      ""
    end
  end
end
