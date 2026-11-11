# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  class CopilotWorkspaceFeatureDisabledError < StandardError
    DEFAULT_MESSAGE = "User does not have access to the Copilot Workspace feature. Unable to create using copilot_workspace_id attribute."
    def initialize(msg = DEFAULT_MESSAGE)
      super
    end
  end
end
