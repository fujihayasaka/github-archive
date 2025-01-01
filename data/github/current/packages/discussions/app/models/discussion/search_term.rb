# typed: true
# frozen_string_literal: true

class Discussion::SearchTerm
  # Public: Extract filter values for a given search key.
  #
  # search_key - the Symbol key for which to extract values, e.g., :author
  #
  # Examples
  #
  #   # Given discussions_q value of "author:iancanderson"
  #   Discussion::SearchTerm.values(:author)
  #   # => ["iancanderson"]
  #
  # Returns an array of values for the key.
  sig { params(search_key: T.untyped, parsed_discussions_query: T.untyped, excluded: T.untyped).returns(T.untyped) }
  def self.values(search_key, parsed_discussions_query:, excluded: false)
    keys_and_values = parsed_discussions_query.select do |(key, _value, negation)|
      if negation && !excluded
        # search_key, if negated, is in the form "-term".
        # the equivalent parsed_query value would be [:"term", "value", true]
        # as such, we must prepend `key` with a `-` if negation is true to correctly match negated terms
        "-#{key}" == search_key.to_s
      elsif negation || excluded
        negation && excluded && key == search_key
      else
        key == search_key
      end
    end
    keys_and_values.map { |(_k, v)| v }
  end
end
