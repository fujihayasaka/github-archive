# typed: false
# frozen_string_literal: true

module Api::App::CopilotSweAgentDeny
  def deny_copilot_swe_agent!
    if current_integration && current_integration == Apps::Privileged.integration(:copilot_swe_agent)
      deliver_error! 403, message: "Copilot Cloud Agent is forbidden from modifying releases"
    end
  end
end
