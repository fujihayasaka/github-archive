# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class StripImageFilter < NodeFilter
    SELECTOR = Goomba::Selector.new("img")

    def selector
      SELECTOR
    end

    def call(element)
      false
    end
  end
end
