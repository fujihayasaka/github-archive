# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class CopilotAgentTaskFilter < Platform::Inputs::Base
      description "Ways in which lists of Copilot Agent Tasks can be filtered by."

      required_capabilities [:copilot_agents]

      argument :states,
        [Enums::CopilotAgentSessionState],
        "Limit tasks to those belonging to sessions with the given states.",
        required: false
    end
  end
end
