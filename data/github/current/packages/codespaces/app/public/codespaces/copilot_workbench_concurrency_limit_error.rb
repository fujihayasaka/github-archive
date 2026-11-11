# typed: strict
# frozen_string_literal: true

module Codespaces
  class CopilotWorkbenchConcurrencyLimitError < StandardError

    sig { params(msg: String).void }
    def initialize(msg = "Limit of active Sparks reached.")
      super
    end
  end
end
