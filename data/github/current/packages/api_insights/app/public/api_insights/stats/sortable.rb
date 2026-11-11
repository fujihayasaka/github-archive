# typed: strict
# frozen_string_literal: true

module ApiInsights::Stats
  module Sortable
    extend T::Helpers

    abstract!
    requires_ancestor { StatsBase }

    sig { params(sort_definitions: T::Array[Queries::SortDefinition]).returns(T.self_type) }
    def with_sorting(sort_definitions)
      sort_definitions.each do |sort_definition|
        query.sort_definitions << sort_definition
      end
      self
    end
  end
end
