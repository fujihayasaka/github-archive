# frozen_string_literal: true
#              

module Vexi
  class EvaluationResult
    attr_reader :value
    attr_reader :reason
    attr_reader :error

    def initialize(value:, reason:, error: nil)
      @value =      (value            )
      @reason =      (reason        )
      @error =      (error                          )
    end

    # Returns a boolean indicating if the default value was used for the result.
    def default?
      @reason == ResultReason::ERROR || @reason == ResultReason::NOT_FOUND
    end
  end
end
