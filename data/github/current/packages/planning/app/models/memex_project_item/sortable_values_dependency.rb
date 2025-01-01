# typed: true
# frozen_string_literal: true

module MemexProjectItem::SortableValuesDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { MemexProjectItem }

  included do
    T.bind(self, T.class_of(MemexProjectItem))
  end

  sig do
    params(
      items: T::Array[MemexProjectItem],
      sort_by: T::Array[T::Hash[Symbol, T.untyped]],
      prefilled_associations: MemexProjectItem::PrefilledAssociations
    ).returns(T::Array[MemexProjectItem])
  end
  def self.sort_by_sortable_values(items, sort_by:, prefilled_associations:)
    directions = [
      *sort_by.map { |sort| sort[:direction].to_sym },
      :desc,
      :asc
    ]

    items.lazy.each do |item|
      # We assign sort_values here so that it can be available to expose as a field in GraphQL or other places after
      # sorting, similar to what ElasticSearch does for the "sort" property in sorted search results.
      item.sort_values = item.derive_sortable_values(sort_by:, prefilled_associations:)
    end.sort do |left_item, right_item|
      # We sort by each sort value the direction specified for each column. The zip method will pass nil values into
      # the block if the arrays are not the same length, which is handled in the compare_sortable_value method.
      left_item.sort_values.zip(right_item.sort_values, directions).reduce(0) do |result, (left_value, right_value, direction)|
        result = compare_sortable_value(left_value, right_value, direction)
        break result if result.nonzero?
        result
      end
    end
  end

  # Compares two values that can be used to sort an item relative to other items. This is meant to mimic the behavior
  # of ElasticSearch for data loaded from MySQL. At a minimum the values should include the priority and id of the item.
  sig do
    params(
      left_value: T.untyped,
      right_value: T.untyped,
      direction: Symbol
    ).returns(Integer)
  end
  def self.compare_sortable_value(left_value, right_value, direction = :asc)
    # Regardless of direction, nil values should always be pushed down.
    if left_value.nil? && right_value.nil?
      return 0
    elsif left_value.nil?
      return 1
    elsif right_value.nil?
      return -1
    end

    direction == :asc ? left_value <=> right_value : right_value <=> left_value
  end

  # Returns an array of values that can be used to sort this item relative to other items.
  # This is meant to mimic the behavior of ElasticSearch for data loaded from MySQL.
  # At a minimum the returned values should include the priority and id of the item.
  sig do
    params(
      sort_by: T::Array[T::Hash[Symbol, T.untyped]],
      prefilled_associations: MemexProjectItem::PrefilledAssociations
    ).returns(T::Array[T.untyped])
  end
  def derive_sortable_values(sort_by:, prefilled_associations:)
    sortable_column_values = []

    unless sort_by.empty?
      fetched_column_values = self.column_values(
        columns: sort_by.pluck(:column),
        require_prefilled_associations: true,
        prefilled_associations:,
      )

      sort_by.zip(fetched_column_values).each do |sort, value|
        column = sort[:column]
        direction = sort[:direction].to_sym
        dig_by = MemexProjectItem::ColumnDependency::COLUMN_VALUE_KEYS[column.data_type.to_sym]
        column_data = dig_by.presence && value.dig(*dig_by)
        sortable_column_values.push(column.to_field.graphql_sortable_column_value(direction:, column_data:))
      end
    end

    [
      *sortable_column_values,
      self.virtual_priority.to_d,
      self.id.to_i
    ]
  end
end
