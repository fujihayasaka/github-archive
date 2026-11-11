# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class CopilotAgentType < Platform::Enums::Base
      docs_category :copilot
      description "The type of Copilot Agent that created a Task."

      required_capabilities [:copilot_agents]

      value "CLI", "Task was created via a remote CLI session.", value: "cli"

      value "VS_CODE", "Task was created via a remote VS Code session.", value: "vs_code"

      value "CLOUD", "Task was created via a Cloud Agent.", value: "cloud"

      value "REVIEW", "A code review agent.", value: "review"

      value "AUTOMATION", "An automation agent.", value: "automation"
    end
  end
end
