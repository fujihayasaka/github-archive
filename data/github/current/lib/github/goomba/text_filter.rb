# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Base class for text filters. Text filters are passed each text node in a
  # document fragment.
  class TextFilter < NodeFilter
    def selector
      Goomba::Selector::Text
    end
  end
end
