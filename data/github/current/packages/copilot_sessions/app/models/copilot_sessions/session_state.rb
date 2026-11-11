# typed: strict
# frozen_string_literal: true

module CopilotSessions
  # These should map to the session states defined in the copilot-api service:
  # pkg/agent/session/sessionstore/store.go#allSessionStates
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
      # Session is queued
      QUEUED = new
    end

    # Helper method to determine session state from Hydro topic and message
    sig { params(topic: String, message: T::Hash[Symbol, T.untyped]).returns(T.nilable(SessionState)) }
    def self.from_hydro_message(topic, message)
      case topic
      when "github.copilot.v0.AgentSessionQueuePullRequest"
        QUEUED
      when "github.copilot.v0.AgentSessionStartPullRequest"
        IN_PROGRESS
      when "github.copilot.v0.AgentSessionFinishPullRequest"
        session_state_string = message[:session_state]
        return unless session_state_string.present?

        deserialize(session_state_string)
      end
    end
  end
end
