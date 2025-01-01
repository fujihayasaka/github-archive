# typed: strict
# frozen_string_literal: true

module ApiInsights::Stats::Queries
  class SortDefinition

    sig { returns(SortField) }
    attr_reader :field

    sig { returns(T::Boolean) }
    attr_reader :descending

    sig { params(field: SortField, descending: T::Boolean).void }
    def initialize(field, descending: false)
      @field = T.let(field, SortField)
      @descending = T.let(descending, T::Boolean)
    end

    sig { returns(String) }
    def to_s
      "#{field} #{descending ? "desc" : "asc"}"
    end
  end
end
