# typed: true
# frozen_string_literal: true

module SCIM
  # A helper class for representing a paginated SCIM results
  # collection. Used for serializing result responses.
  class ResultsCollection
    attr_reader :resources, :total_results, :start_index

    def initialize(resources:, total_results:, start_index:)
      @resources = resources.to_a
      @total_results = total_results
      @start_index = start_index
    end

    def items_per_page
      resources.count
    end
  end
end
