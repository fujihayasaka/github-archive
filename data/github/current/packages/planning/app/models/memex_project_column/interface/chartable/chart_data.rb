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
  #   ]
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
  #   ]
  # }
  class ChartData < T::Struct

    class XAxis < T::Struct
      const :values, T::Array[String]
    end

    class DataSeries < T::Struct
      const :name, String
      const :data, T::Array[Integer]
    end

    const :x_axis, XAxis
    const :data_series, T::Array[DataSeries]

    def initialize(x_axis:, data_series:)
      @x_axis = x_axis
      @data_series = data_series
    end
  end
end
