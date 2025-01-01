# typed: true
# frozen_string_literal: true

class MemexProject
  # This class was extracted out of FilterItemsDependency.  It is an intermediate wrapper object around
  # a Memex Project Column and a parsed query filter (the extracted values to match, the negated flag, and the
  # absence flag).  It exposes one main method: #matches? which takes a project item hash to compare against
  # the column and filter.
  class ColumnFilter
    # Do expose this though, so we can use it to reflect on which types are implemented.
    TYPES_TO_VALUE_KEYS = {
      assignees:            :login,
      date:                 "value",
      iteration:            "id",
      labels:               :name,
      linked_pull_requests: :number,
      milestone:            :title,
      number:               "value",
      repository:           :nameWithOwner,
      reviewers:            %i(reviewer login),
      single_select:        "id",
      text:                 "raw",
      title:                %w(title raw),
      issue_type:           :name,
    }.freeze
    # This mapping determines which comparator class to use for each column type.  If a column type is not
    # found then it will use the default Comparator class.
    TYPES_TO_COMPARATORS = {
      date: DateComparator
    }.freeze

    # To minimize this classes surface area lets not expose these constants unless we have to.
    private_constant :TYPES_TO_COMPARATORS

    attr_reader :absence, :column, :comparator

    delegate :negated, to: :comparator

    def initialize(column:, filter_values:, negated: false, absence: false)
      @column  = column
      @absence = !!absence
      normalized_filter_values = FilterValueResolver.new(column).resolve(filter_values)

      comparator_class = TYPES_TO_COMPARATORS.fetch(column.data_type.to_sym, Comparator)

      @comparator = comparator_class.new(normalized_filter_values, negated: negated)

      freeze
    end

    def column_id
      column.synthetic_id
    end

    # Parameters:
    #   - item_column_value: hash of values representing a project item.
    #
    # Returns:
    #   - true if the value within the item_column_value matches on one of the comparators, false otherwise.
    def matches?(item_column_value)
      # If the item value is nil, return true if negated, and false otherwise
      return negated if item_column_value.blank?

      # If the item column value is an array, it is part of a multi-keyed column like reviewers
      if item_column_value.is_a?(Array)
        item_column_value.any? { |multiselect_value| single_value_matches?(multiselect_value) }
      else
        single_value_matches?(item_column_value)
      end
    end

    private

    def single_value_matches?(item_column_value)
      keys       = TYPES_TO_VALUE_KEYS.fetch(column.data_type.to_sym)
      item_value = item_column_value&.dig(*keys)

      comparator.matches?(item_value)
    end
  end
end
