# typed: true
# frozen_string_literal: true

require "github/goomba/suggested_change_filter"

module GitHub::Goomba
  # This class is used to extract the raw suggestion from a comment body
  # We can't use to_text or other normal "result" methods in the pipeline though
  # because they do HTML conversion and processing we don't want.
  class LightweightSuggestedChangeFilter < SuggestedChangeFilter
    def call(node)
      # Ignore if we've already seen a suggestion
      return "" if scratch[:seen_suggestion]
      scratch[:seen_suggestion] = true

      # Grab plain content before rest of pipeline messes with it
      result[:raw_suggestion] = new_text(node)
    end
  end
end
