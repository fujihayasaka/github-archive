# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class GateRequestState < Platform::Enums::Base
      description "The possible states of a gate request."

      value "CLOSED", "The gate request is closed.", value: "closed"
      value "OPEN",   "The gate request is open",    value: "open"
    end
  end
end
