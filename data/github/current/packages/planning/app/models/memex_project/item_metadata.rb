# typed: true
# frozen_string_literal: true

class MemexProject
  # Some item data is necessary for filtering, but this data is not free-form user-entered.
  # Instead, they are characteristics about the items themselves, such as type and state.
  # We need to wrap this data up and pass it into the filtering middle-ware in order to cover
  # all combinations.  One example use-case of metadata filtering would be against the `is` keyword.
  class ItemMetadata
    attr_reader :content_type, :is_draft, :state

    def initialize(content_type:, is_draft:, state:)
      @state        = state.to_s
      @content_type = content_type.to_s
      @is_draft     = is_draft || false

      freeze
    end

    def to_s
      "#{content_type} state: #{state}, is_draft: #{is_draft}"
    end
  end
end
