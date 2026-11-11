# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class CopilotAgentSessionState < Platform::Enums::Base
      description "All potential states of a Copilot Agent Session."

      required_capabilities [:copilot_agents]

      value "CANCELLED", "Session has been cancelled", value: "cancelled"

      value "COMPLETED", "Session has finished successfully", value: "completed"

      value "FAILED", "Session has failed", value: "failed"

      value "IDLE", "Session has not started yet", value: "idle"

      value "IN_PROGRESS", "Session is currently active", value: "in_progress"

      value "QUEUED", "Session is queued", value: "queued"

      value "TIMED_OUT", "Session has timed out", value: "timed_out"

      value "WAITING_FOR_USER", "Session is waiting for user input", value: "waiting_for_user"
    end
  end
end
