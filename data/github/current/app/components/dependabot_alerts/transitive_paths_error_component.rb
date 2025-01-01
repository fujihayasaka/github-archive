# typed: true
# frozen_string_literal: true

# rubocop:disable ViewComponent/ComponentsHaveUnitTests
module DependabotAlerts
  class TransitivePathsErrorComponent < ApplicationComponent

    def initialize(transitive_results:)
      @transitive_results = transitive_results
    end

    attr_reader :transitive_results

    # Returns the appropriate error message based on the transitive results
    def message
      transitive_results[:error].presence || "The transitive paths could not be found due to a system error."
    end
  end
end
