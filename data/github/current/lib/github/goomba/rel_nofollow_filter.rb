# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class RelNofollowFilter < NodeFilter
    SELECTOR = Goomba::Selector.new(match: "a")

    def initialize(*args)
      super
      @filter = GitHub::HTML::RelNofollowFilter.new("", context, result)
    end

    def selector
      SELECTOR
    end

    def call(element)
      @filter.call_element(element)
    end
  end
end
