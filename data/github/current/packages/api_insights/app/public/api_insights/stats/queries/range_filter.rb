# typed: strict
# frozen_string_literal: true

module ApiInsights::Stats::Queries
  class RangeFilter < BaseFilter

    sig { returns(T.untyped) }
    attr_reader :max_value

    sig { params(field: FilterField, min_value: T.untyped, max_value: T.untyped).void }
    def initialize(field, min_value, max_value)
      super field, min_value
      @max_value = max_value
    end

    sig { override.returns(String) }
    def condition
      "#{field} >= min_#{parameter_name} and #{field} <= max_#{parameter_name}"
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def parameters
      {
        "min_#{parameter_name}" => value,
        "max_#{parameter_name}" => @max_value
      }
    end
  end
end
