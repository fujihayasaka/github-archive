# typed: true
# frozen_string_literal: true

module UserLists
  class SortingStrategy
    SORT_MAP = {
      "name" => "slug",
      "created_at" => "created_at",
      "updated_at" => "last_added_at",
    }.freeze

    STRATEGY_TO_HUMAN_MAP = {
      "name.asc" => "Name ascending (A-Z)",
      "name.desc" => "Name descending (Z-A)",
      "created_at.desc" => "Newest",
      "created_at.asc" => "Oldest",
      "updated_at.desc" => "Last updated",
    }.freeze

    VALID_DIRECTIONS = %w[asc desc].freeze

    attr_reader :sort_by
    attr_reader :direction

    def initialize(sort_by = default_sort_by, direction = default_direction)
      @sort_by = sort_by.to_s
      @sort_by = default_sort_by unless SORT_MAP.key?(@sort_by)
      @direction = direction.to_s
      @direction = default_direction unless VALID_DIRECTIONS.include?(@direction)
    end

    def apply(ar_query_interface_or_array)
      if ar_query_interface_or_array.is_a?(Array)
        return array_sort(ar_query_interface_or_array)
      end

      ar_query_interface_or_array.order(sort_column => direction)
    end

    def serialize
      "#{sort_by}.#{direction}"
    end

    def self.unserialize(string)
      new(*string.split("."))
    end

    def to_human
      STRATEGY_TO_HUMAN_MAP.fetch(serialize)
    end

    private

    def default_sort_by
      "name"
    end

    def default_direction
      "asc"
    end

    def sort_column
      SORT_MAP[@sort_by]
    end

    def array_sort(lists)
      sorted = lists.sort_by { |l| l.send(sort_column) }

      if direction == "desc"
        return sorted.reverse
      end

      sorted
    end
  end
end
