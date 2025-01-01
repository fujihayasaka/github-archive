# typed: true
# frozen_string_literal: true

module TasklistBlocks
  class LimitError
    sig { params(number_of_items: Integer, error: String).void }
    def initialize(number_of_items, error)
      @number_of_items = number_of_items
      @error = error
    end

    sig { returns(String) }
    def to_s
      "Exceeded #{@error} limit, #{@number_of_items} items found"
    end
  end
end
