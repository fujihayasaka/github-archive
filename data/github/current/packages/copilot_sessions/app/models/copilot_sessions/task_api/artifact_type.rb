# typed: strict
# frozen_string_literal: true

module CopilotSessions
  module TaskApi
    # The valid artifact types allowable for filtering tasks via the CAPI "agents/tasks" endpoint.
    class ArtifactType < T::Enum
      enums do
        PullRequest = new("pull")
        ChatThread = new("chat")
      end
    end
  end
end
