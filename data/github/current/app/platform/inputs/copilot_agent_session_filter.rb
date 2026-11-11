# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class CopilotAgentSessionFilter < Platform::Inputs::Base
      description "Ways in which lists of Copilot Agent Sessions can be filtered by."

      required_capabilities [:copilot_agents]

      argument :states,
        [Enums::CopilotAgentSessionState],
        "The states to filter Copilot Agent Sessions by.",
        required: false
    end
  end
end
