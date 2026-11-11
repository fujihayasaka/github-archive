# typed: strict
# frozen_string_literal: true

module ApiInsights::Stats::Queries
  class BaseFilter
    extend T::Helpers

    abstract!

    sig { returns(FilterField) }
    attr_reader :field

    sig { returns(T.untyped) }
    attr_reader :value

    sig { params(field: FilterField, value: T.untyped).void }
    def initialize(field, value)
      @field = field
      @value = value
    end

    sig { returns(String) }
    def to_s
      condition
    end

    # The condition string used within a KQL `where` clause.
    sig { abstract.returns(String) }
    def condition; end

    # The name of the parameter used in the KQL query.
    sig { returns(String) }
    def parameter_name
      "#{field}_param"
    end

    sig { overridable.returns(T::Hash[String, T.untyped]) }
    def parameters
      {
          "#{parameter_name}" => value
      }
    end
  end
end
