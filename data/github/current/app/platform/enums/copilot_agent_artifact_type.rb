# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class CopilotAgentArtifactType < Platform::Enums::Base
      docs_category :copilot
      description "All potential types of a Copilot Agent Artifact."

      required_capabilities [:copilot_agents]

      value "PULL_REQUEST", "Pull Request created by an Agent.", value: "pull"

      value "CHAT_THREAD", "Chat Thread created by an Agent.", value: "chat"
    end
  end
end
