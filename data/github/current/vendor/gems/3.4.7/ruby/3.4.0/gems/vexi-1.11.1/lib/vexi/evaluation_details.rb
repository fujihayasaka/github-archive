# frozen_string_literal: true
#              

module Vexi
  class EvaluationDetails
    attr_reader :result
    attr_reader :reason
    attr_reader :error

    def initialize(result:, reason:, error: nil)
      @result =      (result            )
      @reason =      (reason        )
      @error =      (error                          )
    end

    # Returns a boolean indicating if the default value was used for the result.
    def default?
      @reason == ResultReason::ERROR || @reason == ResultReason::NOT_FOUND
    end
  end
end
