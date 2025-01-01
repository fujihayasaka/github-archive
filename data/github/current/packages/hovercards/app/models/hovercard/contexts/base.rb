# typed: true
# frozen_string_literal: true

module Hovercard::Contexts
  class Base
    # Build a nice sentence from the collection, showing a maximum of `max`
    # entries.  Will display max-1 entries with "and n more" if there are more
    #
    # max: the maximum number of entries to show in the list before truncating
    # total: if supplied, the total number of items (useful when full collection is not available)
    # optional &block: yielded once for each result when formatting
    def hovercard_sentence(collection, max:, total: collection.count, &block)
      max = max - 1 if total > max

      front = collection.first(max)
      front = front.map(&block) if block_given?

      [
        *front,
        ("#{total - front.count} more" if total > front.count),
      ].compact.to_sentence
    end
  end
end
