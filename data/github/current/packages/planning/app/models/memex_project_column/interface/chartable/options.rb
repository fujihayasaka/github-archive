# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Chartable

  # Encapsulates options for querying Insights chart data from Elasticsearch via MemexProjectItemQuery.
  #
  # Possible options to query with xAxis Assignee asc (default) and Grouped by Status (desc)
  # yAxis default is an aggregated count of items
  #
  # {
  #   "xAxis": {
  #     "dataSource": {
  #       "field_object_or_id": 1062769,
  #       "order": "asc"
  #     },
  #     "groupBy": {
  #       "field_object_or_id": 841442
  #       "order": "desc"
  #     }
  #   },
  #   "yAxis": {
  #     "aggregate": {
  #       "operation": "count"
  #     }
  #   }
  # }
  class Options

    class XAxisDataSource < T::Struct
      const :field_object_or_id, T.any(String, Integer, MemexProjectColumn::Field::Base) # only "time" is a valid string for historical charts
      const :order, T.nilable(String)  # "asc" or "desc"
    end

    class XAxisGroupBy < T::Struct
      const :field_object_or_id, T.any(Integer, MemexProjectColumn::Field::Base)
      const :order, T.nilable(String)  # "asc" or "desc"
    end

    class XAxis < T::Struct
      const :data_source, XAxisDataSource
      const :group_by, T.nilable(XAxisGroupBy)
    end

    sig { returns(Options::XAxis) }
    attr_reader :x_axis

    # The x-axis field
    sig { returns(MemexProjectColumn::Field::Base) }
    attr_reader :x_axis_field

    # The optional x-axis group by field
    sig { returns(T.nilable(MemexProjectColumn::Field::Base)) }
    attr_reader :x_group_field

    sig do
      params(
        x_axis: Options::XAxis,
      )
      .void
    end
    def initialize(x_axis:)
      @x_axis = x_axis

      # validate input
      # TODO: How to handle 'Time' datasource?
      field = x_axis.data_source.field_object_or_id
      unless field.is_a?(MemexProjectColumn::Field::Base)
        field = MemexProjectColumn.find_by(id: field)&.to_field
      end
      raise ArgumentError, "Could not retrieve x_axis field with ID #{field}" unless field.present?
      @x_axis_field = T.let(field, MemexProjectColumn::Field::Base)

      field = x_axis.group_by&.field_object_or_id
      if field.present?
        unless field.is_a?(MemexProjectColumn::Field::Base)
          field = MemexProjectColumn.find_by(id: field)&.to_field
        end
        raise ArgumentError, "Could not retrieve group_by field with ID #{field}" unless field.present?
        @x_group_field = T.let(field, MemexProjectColumn::Field::Base)
      end
    end
  end
end
