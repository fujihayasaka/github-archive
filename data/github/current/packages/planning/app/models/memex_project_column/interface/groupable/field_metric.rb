# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Groupable
  # Represents the result of a metric sub-aggregation for a group.
  class FieldMetric < T::Struct

    VALUE_PRECISION = 2

    const :field_id, Integer
    const :value, Float, default: 0.0
    # Only the 'sum' metric is supported at this time.
    const :metric_type, Symbol, default: :sum

    sig { returns(T::Hash[String, T.untyped]) }
    def to_hash
      {
        field_id:,
        value: display_value,
        metric_type:,
      }.stringify_keys
    end

    sig { returns(T.any(Float, Integer)) }
    def display_value
      value.round(VALUE_PRECISION)
    end
  end
end
