# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class CopilotAgentTaskFilter < Platform::Inputs::Base
      description "Ways in which lists of Copilot Agent Tasks can be filtered by."

      required_capabilities [:copilot_agents]

      argument :states,
        [Enums::CopilotAgentSessionState],
        "Limit tasks to with the given states.",
        required: false

      argument :archived,
        Boolean,
        "Limit tasks by archived status.",
        required: false,
        default_value: nil

      argument :artifact_type,
        Enums::CopilotAgentArtifactType,
        "Limit tasks by artifact type.",
        required: false,
        default_value: nil
    end
  end
end
