# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class CopilotAgentTaskOrderField < Platform::Enums::Base
      docs_category :copilot
      description "Properties by which copilot agent tasks can be ordered."

      required_capabilities [:copilot_agents]

      value "LAST_UPDATED_AT", "The task's date and time of last update"

      value "CREATED_AT", "The task's date and time of creation"
    end
  end
end
