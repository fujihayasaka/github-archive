# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class CopilotAgentTaskOrder < Platform::Inputs::Base
      description "Ways in which lists of Copilot Agent tasks can be ordered upon return."

      required_capabilities [:copilot_agents]

      argument :field,
        Enums::CopilotAgentTaskOrderField,
        "The field in which to order Copilot Agent tasks by.",
        required: true

      argument :direction,
        Enums::OrderDirection,
        "The direction in which to order Copilot Agent tasks by the specified field.",
        required: true
    end
  end
end
