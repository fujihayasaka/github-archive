# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Groupable
  # Encapsulates options for sub-aggregating items in each group by a metric.
  # Only the 'sum' metric is supported at this time.
  class FieldMetricOptions < T::Struct
    # Aggregate items by summing the values of the specified field ids.
    const :sum, T::Array[MemexProjectColumn::Interface::Summable]
  end
end
