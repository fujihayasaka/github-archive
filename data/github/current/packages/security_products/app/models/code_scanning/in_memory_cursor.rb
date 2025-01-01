# typed: strict
# frozen_string_literal: true

module CodeScanning
  # InMemoryCursor is a generic cursor for paginating through an array of items.
  # It is used in code scanning and security campaigns for paginating through groups of repositories.
  class InMemoryCursor < T::ImmutableStruct
    extend T::Generic
    Elem = type_member

    sig do
      type_parameters(:T).
      params(
        items: T::Array[T.all(T.type_parameter(:T), Kernel)],
        after_cursor: T.nilable(String),
        before_cursor: T.nilable(String),
        page_size: Integer,
      ).returns(
        InMemoryCursor[T.type_parameter(:T)]
      )
    end
    def self.page(items:, after_cursor:, before_cursor:, page_size:)
      from = if after_cursor.present?
        items.index { |item| item.to_s == after_cursor }
      elsif before_cursor.present?
        # if we find the before cursor element then subtract page_size from the index and subtract 1 to include the before cursor value
        items.index { |item| item.to_s == before_cursor }&.- page_size - 1
      end
      # from must be non-nil and > 0 as negative numbers index from the end of an array
      from = 0 if from.nil? || from < 0
      to = from + page_size

      page = items[from...to]

      # there should only be a next cursor if we are not past the end of the list
      next_cursor = items[to]&.to_s if to <= items.size
      # if from is zero then there are no more elements to show before this
      prev_cursor = items[[0, from - 1].max]&.to_s if from > 0

      InMemoryCursor.new(items: page || [], next: next_cursor, prev: prev_cursor)
    end

    const :items, T::Array[Elem]
    const :next, T.nilable(String)
    const :prev, T.nilable(String)
  end
end
