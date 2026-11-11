# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class TrackedIssueStates < Platform::Enums::Base
      visibility :public, environments: [:dotcom, :enterprise]

      description "The possible states of a tracked issue."

      value "OPEN", "The tracked issue is open", value: :open
      value "CLOSED", "The tracked issue is closed", value: :closed
    end
  end
end
