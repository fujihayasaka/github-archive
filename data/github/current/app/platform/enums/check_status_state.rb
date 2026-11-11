# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class CheckStatusState < RequestableCheckStatusState
      docs_category :checks
      description "The possible states for a check suite or run status."

      value "REQUESTED",   "The check suite or run has been requested.", value: "requested"
    end
  end
end
