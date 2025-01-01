# frozen_string_literal: true
#              

module Vexi
  class EvaluationDetails
    attr_reader :value

    attr_reader :reason

    attr_reader :error

    def initialize(value:, reason:, error: nil)
      @value =      (value            )
      @reason =      (reason        )
      @error =      (error                          )
    end
  end
end
