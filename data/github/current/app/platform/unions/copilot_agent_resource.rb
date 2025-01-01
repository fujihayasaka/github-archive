# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class CopilotAgentResource < Platform::Unions::Base
      description "The resulting output or artifact of a Copilot Agent session."

      required_capabilities [:copilot_agents]

      possible_types Objects::PullRequest
    end
  end
end
