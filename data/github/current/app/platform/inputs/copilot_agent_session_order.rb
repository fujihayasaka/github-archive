# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class CopilotAgentSessionOrder < Platform::Inputs::Base
      description "Ways in which lists of copilot agent sessions can be ordered upon return."

      required_capabilities [:copilot_agents]

      argument :field, Enums::CopilotAgentSessionOrderField, "The field in which to order copilot agent sessions by.", required: true
      argument :direction, Enums::OrderDirection, "The direction in which to order copilot agent sessions by the specified field.", required: true
    end
  end
end
