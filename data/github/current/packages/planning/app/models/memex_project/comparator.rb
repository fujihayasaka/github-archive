# typed: strict
# frozen_string_literal: true

class MemexProject
  # A Comparator is a class that knows how to compare two values.  In the context of Memex, one of the values
  # would be the filter value (i.e. entered by a user in a view) and the other would be the actual value
  # within the item.
  #
  # This class serves as the base method for comparison and is very simple: the item's value just has to
  # match one of the filter's value (compared to as downcased strings.)
  class Comparator

    sig { returns(T::Array[T.any(String, Regexp)]) }
    attr_reader :filter_values

    sig { returns(T::Boolean) }
    attr_reader :negated

    # Parameters:
    #   - filter_values: An array of strings to comparare item values against.  If the entries in the array
    #                    are not strings then they will be converted to strings and downcased.
    #   - negated:       A boolean indicating whether the filter is negated.  If true then #matches?
    #                    will essentially return the opposite of the result
    sig { params(filter_values: T.any(String, T::Array[String]), negated: T::Boolean).void }
    def initialize(filter_values, negated: false)
      @filter_values = T.let(sanitize_filter_values(Array(filter_values)), T::Array[T.any(String, Regexp)])
      @negated = T.let(!!negated, T::Boolean)
      freeze
    end

    sig { params(filter_values: T::Array[String]).returns(T::Array[T.any(String, Regexp)]) }
    def sanitize_filter_values(filter_values)
      filter_values.map do |value|
        # Replace wildcards (*) with a regex that matches any character (.*), which is the equivalent of a wildcard
        # search using plain Ruby string comparisons. Note that the replacement is a no-op if the value does not contain
        # any wildcards, but the IGNORECASE flag is always set to ensure the comparison is case-insensitive.
        #
        # Note that this assumes _any_ asterisk (*) is a wildcard and not a literal character. We'll need to revisit this
        # if we ever decide to support literal asterisks.
        Regexp.new("\\A#{value.gsub('*', '.*')}\\z", Regexp::IGNORECASE)
      end
    end

    # Parameters:
    #   - item_value: A string to compare against the filter values. If the item value is not a string then it
    #                 will be converted to a string and downcased.
    #
    # Returns:
    #   - true if the item_value matches one of the filter_values, false otherwise.
    sig { params(item_value: T.any(Integer, Float, String)).returns(T::Boolean) }
    def matches?(item_value)
      @filter_values.any? { |pattern| pattern.match?(item_value.to_s) } ^ @negated
    end
  end
end
