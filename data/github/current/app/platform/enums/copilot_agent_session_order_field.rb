# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class CopilotAgentSessionOrderField < Platform::Enums::Base
      description "Properties by which copilot agent sessions can be ordered."

      required_capabilities [:copilot_agents]

      value "LAST_UPDATED_AT", "The session's date and time of last update"
    end
  end
end
