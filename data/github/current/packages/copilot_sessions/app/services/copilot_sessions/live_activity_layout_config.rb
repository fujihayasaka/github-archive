# typed: true
# frozen_string_literal: true

class CopilotSessions::LiveActivityLayoutConfig
  # PR-coupled hydro topics (legacy)
  SESSION_QUEUE_HYDRO_TOPIC = "github.copilot.v0.AgentSessionQueuePullRequest"
  SESSION_START_HYDRO_TOPIC = "github.copilot.v0.AgentSessionStartPullRequest"
  SESSION_FINISH_HYDRO_TOPIC = "github.copilot.v0.AgentSessionFinishPullRequest"

  # Decoupled hydro topics (not tied to a specific PR)
  DECOUPLED_QUEUE_HYDRO_TOPIC = "github.copilot.v0.AgentSessionQueue"
  DECOUPLED_START_HYDRO_TOPIC = "github.copilot.v0.AgentSessionStart"
  DECOUPLED_FINISH_HYDRO_TOPIC = "github.copilot.v0.AgentSessionFinish"
  DECOUPLED_WAITING_FOR_USER_HYDRO_TOPIC = "github.copilot.v0.AgentSessionWaitingForUser"
  DECOUPLED_IDLE_HYDRO_TOPIC = "github.copilot.v0.AgentSessionIdle"

  NOTIFICATION_CONFIGS = {
    CopilotSessions::SessionState::QUEUED => {
      body: "Queued • Starting new session",
      event_type: "start",
      content_state: [:session_state],
      include_attributes: true
    },
    CopilotSessions::SessionState::IN_PROGRESS => {
      body: "In Progress • Your agent is working",
      event_type: "start",
      content_state: [:session_state, :pr_number, :pr_title, :pr_url],
      include_attributes: true
    },
    CopilotSessions::SessionState::COMPLETED => {
      body: "Completed • Your agent is done working",
      event_type: "end",
      content_state: [:session_state, :error_message, :workflow_run_id, :pr_number, :pr_title, :pr_url],
      include_attributes: true
    },
    CopilotSessions::SessionState::FAILED => {
      body: "Failed • Something went wrong",
      event_type: "end",
      content_state: [:session_state, :error_message, :workflow_run_id, :pr_number, :pr_title, :pr_url],
      include_attributes: true
    },
    CopilotSessions::SessionState::TIMED_OUT => {
      body: "Timed Out • Session exceeded time limit",
      event_type: "end",
      content_state: [:session_state, :error_message, :workflow_run_id, :pr_number, :pr_title, :pr_url],
      include_attributes: true
    },
    CopilotSessions::SessionState::CANCELLED => {
      body: "Cancelled • Session stopped by user",
      event_type: "end",
      content_state: [:session_state, :error_message, :workflow_run_id, :pr_number, :pr_title, :pr_url],
      include_attributes: true
    },
    CopilotSessions::SessionState::WAITING_FOR_USER => {
      body: "Action required • Approve or deny to continue",
      event_type: "start",
      content_state: [:session_state, :pr_number, :pr_title, :pr_url],
      include_attributes: true
    },
    CopilotSessions::SessionState::IDLE => {
      body: "Idle",
      event_type: "start",
      content_state: [:session_state, :pr_number, :pr_title, :pr_url],
      include_attributes: true
    }
  }.freeze

  sig { params(state: T.nilable(CopilotSessions::SessionState)).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def self.config_for_state(state)
    return unless state

    NOTIFICATION_CONFIGS[state]
  end
end
