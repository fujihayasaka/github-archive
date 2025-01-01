# typed: true
# frozen_string_literal: true

module DependabotAlerts
  class TransitivePathsErrorComponent < ApplicationComponent

    def initialize(error: "")
      @error = error
    end

    attr_reader :error

    # Returns the appropriate error message based on the transitive results
    def message
      error.presence || "The transitive paths could not be found due to a system error."
    end
  end
end
