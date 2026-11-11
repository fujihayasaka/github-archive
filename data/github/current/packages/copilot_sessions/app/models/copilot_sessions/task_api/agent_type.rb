# typed: strict
# frozen_string_literal: true

module CopilotSessions
  module TaskApi
    # The type of agent that created a Task.
    class AgentType < T::Enum
      enums do
        Cloud = new("cloud")
        CLI = new("cli")
        VSCode = new("vs_code")
      end
    end
  end
end
