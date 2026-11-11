# typed: true
# frozen_string_literal: true

module GitHub
  module CopilotMissionControl
    # The CopilotMissionControl Client provides access to Copilot Mission Control APIs.
    # Each API is implemented as a separate client in the client/ subdirectory.
    class Client
      autoload :Tasks, "github/copilot_mission_control/client/tasks"

      def self.tasks
        Tasks.new
      end
    end
  end
end
