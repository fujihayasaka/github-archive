# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Chartable

  # Encapsulates Insights chart data queried from Elasticsearch via MemexProjectItemQuery.
  #
  # Possible data shape with xAxis Assignee
  # {
  #   "xAxis": {
  #     "values": ["dewski", "dmarcey", "jayspadie", "_noValue"]
  #   },
  #   "dataSeries": [
  #     {
  #       "name": "",
  #       "data": [3, 4, 2, 5]
  #     }
  #   ],
  #   "totalCount": 10
  # }
  #
  # Possible data shape with xAxis Assignee and Grouped by Status
  # {
  #   "xAxis": {
  #     "values": ["dewski", "dmarcey", "jayspadie"]
  #   },
  #   "dataSeries": [
  #     {
  #       "name": "Todo",
  #       "data": [3, 4, 2]
  #     },
  #     {
  #       "name": "In Progress",
  #       "data": [0, 1, 1]
  #     },
  #     {
  #       "name": "Done",
  #       "data": [5, 3, 4]
  #     }
  #   ],
  #   "totalCount": 10
  # }
  class ChartData < T::Struct

    # Chart dataSeries data can be either Integers or Floats.
    # Integers are used when the y-axis is the count of items (> 90% of all charts).
    # Floats are used with y-axis aggregations on a numeric field (sum, min, max, avg).
    IntegerOrFloat = T.type_alias { T.any(Integer, Float) }

    class XAxis < T::Struct
      const :values, T::Array[String]
    end

    class DataSeries < T::Struct
      const :name, String
      const :data, T::Array[IntegerOrFloat]

      sig { returns(T::Hash[String, T.untyped]) }
      def to_hash
        {
          name: name,
          data: data,
        }.compact
      end
    end

    const :x_axis, XAxis
    const :data_series, T::Array[DataSeries]
    const :total_count, Integer

    def initialize(x_axis:, data_series:, total_count:)
      @x_axis = x_axis
      @data_series = data_series
      @total_count = total_count
    end

    sig { returns(T::Hash[String, T.untyped]) }
    def to_hash
      {
        x_axis: {
          values: x_axis.values
        },
        data_series: data_series.map(&:to_hash),
        total_count:,
      }.compact
    end
  end
end
