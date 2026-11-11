# typed: true
# frozen_string_literal: true

class MemexProject
  # This class, along with ColumnFilter, were extracted from FilterItemsDependency and act as intermediaries for
  # filtering items based on a pre-parsed query and a list of columns.  The rationale for the query having to be
  # pre-parse (i.e. passed into this class after parsing) is due to it being needed upstream in order to properly
  # pre-fill the item's associations and columns.  Therefore if we moved any of that parsing here we would still
  # need to expose it to the outside world.
  class Filter
    attr_reader :filters

    # Calculates values to match memex items against a set of columns and string filter values.
    # This aids in matching many items against many distinct types of filters and search terms.
    #
    # Example:
    # queried_columns = [MemexProjectColumn.default_column("Assignees")]
    # search_qualifiers = { assignees: [{ value: ["@me"], negated: false, absence: false }] }
    # values = matching_column_filter_set(queried_columns, search_qualifiers)
    #        [["Assignees", :login, ["monalisa"], false, false]]
    #
    # Parameters:
    #   - queried_columns - Preloaded `MemexProjectColumns` to match against
    #   - search_qualifiers - Hash of column symbols with an array of search term values, including negation and absence
    def initialize(queried_columns, search_qualifiers)
      @filters = make_column_filters(queried_columns, search_qualifiers) + make_is_filters(search_qualifiers)

      freeze
    end

    # Pass in an item hash and return true if the item's value matches ALL the specified filters.
    #
    # Arguments:
    #   - item_values: a hash containing all the item's values.
    #
    # Returns:
    #   - true if the item's value matches ALL the specified filters.
    def matches?(item_values)
      filters.all? do |filter|
        if filter.absence
          column_has_no_values = item_values.none? do |item_column|
            item_column[:value].present? && is_column_matching?(filter.column_id, item_column)
          end

          # Use XOR to apply negation of absence if necessary
          # Using next here should allow us to move to the next iteration without wrapping code in an `else` block
          next filter.negated ^ column_has_no_values
        end

        item_values.any? do |item_column|
          item_column_value = item_column[:value]

          # While iterating through all the item columns, we only want matching columns
          next false unless is_column_matching?(filter.column_id, item_column)

          filter.matches?(item_column_value)
        end
      end
    end

    private

    # Determines if the item column ID matches the expected column ID
    def is_column_matching?(column_id, item_column)
      item_column[:memexProjectColumnId] == column_id
    end

    def make_column_filters(queried_columns, search_qualifiers)
      queried_columns.each_with_object([]) do |column, column_filters|
        column_match_requirements = search_qualifiers[column.name_slug.to_sym]

        column_match_requirements.each do |requirement|
          filter_values = Array.wrap(requirement[:value]).map(&:downcase)
          negated, absence = requirement.values_at(:negated, :absence)

          column_filters << ColumnFilter.new(
            column: column,
            filter_values: filter_values,
            negated: negated,
            absence: absence
          )
        end
      end
    end

    def make_is_filters(search_qualifiers)
      search_qualifiers[:is].to_a.map do |search_qualifier|
        IsKeywordFilter.new(
          keywords: search_qualifier[:value],
          negated: search_qualifier[:negated],
        )
      end
    end
  end
end
