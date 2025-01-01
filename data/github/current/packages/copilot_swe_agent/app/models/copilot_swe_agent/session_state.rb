# typed: strict
# frozen_string_literal: true

module CopilotSweAgent
  class SessionState < T::Enum
    enums do
      # The session is created and Copilot is working
      IN_PROGRESS = new
      # The session is completed and Copilot is done
      COMPLETED = new
      # The session is failed and Copilot has failed
      FAILED = new
      # The session is idle and Copilot is waiting
      IDLE = new
      # The session is waiting for user input
      WAITING_FOR_USER = new
      # The session is timed out
      TIMED_OUT = new
      # The session was cancelled
      CANCELLED = new
    end
  end

end
