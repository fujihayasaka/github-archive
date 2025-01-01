# typed: strict
# frozen_string_literal: true

module ApiInsights::Stats::Queries
  # Represents a filter that can be applied to a query.
  class Filter < BaseFilter

    sig { returns(String) }
    attr_reader :operator

    sig { params(field: FilterField, value: T.untyped, operator: String).void }
    def initialize(field, value, operator: "==")
      super field, value
      @operator = operator
    end

    sig { override.returns(String) }
    def condition
      "#{field} #{@operator} #{parameter_name}"
    end
  end
end
