# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Copilot
      autoload :AdministrativeUnblockProcessor, "github/stream_processors/copilot/administrative_unblock_processor"
      autoload :AgentSessionEventProcessor, "github/stream_processors/copilot/agent_session_event_processor"
    end
  end
end
