# typed: true
# frozen_string_literal: true

class MemexProject
  # This class was extracted out of FilterItemsDependency.  It is an intermediate wrapper object around
  # a Memex Project Column and a parsed query filter (the extracted values to match, the negated flag, and the
  # absence flag).  It exposes one main method: #matches? which takes a project item hash to compare against
  # the column and filter.
  class ColumnFilter
    # Path to the value used for filtering within the hash returned by
    # MemexProjectItem#special_type_column_value for columns with a specific data type.
    #
    # Example:
    #
    #   To generate
    #
    #     memex_project = MemexProject.find(1)
    #     memex_project_item = memex_project.memex_project_items.first
    #     memex_project_column = memex_project.find_column_by_name_or_id(MemexProjectColumn::TITLE_COLUMN_NAME)
    #     memex_project_item.to_hash(columns: [memex_project_column])
    #
    # Example:
    #
    #   Using the following hash returned from MemexProjectItem#special_type_column_value for the "title" data type:
    #
    #     {
    #         "memexProjectColumnId": "Title",
    #         "value": {
    #             "url": "https://github.com/9919/531963299/issues/3006",
    #             "state": "open",
    #             "title": {
    #                 "raw": "Identify P1 required feature flags for Enterprise support",
    #                 "html": "Identify P1 required feature flags for Enterprise support"
    #             },
    #             "number": 3006,
    #             "issueId": 3015462063,
    #             "stateReason": null
    #         }
    #     }
    #
    #    The path to the filterable value is ["title", "raw"]
    #
    # Example:
    #
    #  Using the following hash returned from MemexProjectItem#special_type_column_value for the "assignees" data type:
    #
    #    {
    #        "memexProjectColumnId": "Assignees",
    #        "value": [
    #            {
    #                "avatarUrl": "https://avatars.githubusercontent.com/u/6740550?s=40&u=35c60e516d382ac8ce4fd42cc100813cc4a76677&v=4",
    #                "id": 6740550,
    #                "login": "talune",
    #                "url": "https://github.com/talune"
    #            }
    #        ]
    #    }
    #
    #    The path to the filterable value is ["login"]
    TYPES_TO_VALUE_KEYS = {
      assignees:            :login,
      date:                 "value",
      iteration:            "id",
      labels:               :name,
      linked_pull_requests: :number,
      milestone:            :title,
      number:               "value",
      parent_issue:         :nwoReference,
      repository:           :nameWithOwner,
      reviewers:            %i(reviewer login),
      single_select:        "id",
      text:                 "raw",
      title:                %i(title raw),
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
