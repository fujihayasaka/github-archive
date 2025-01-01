# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class MilestoneState < Platform::Enums::Base
      description "The possible states of a milestone."

      value "OPEN", "A milestone that is still open.", value: "open"
      value "CLOSED", "A milestone that has been closed.", value: "closed"
    end
  end
end
