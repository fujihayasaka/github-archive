# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class CopilotAssignmentInput < Platform::Inputs::Base
      description "Represents configuration for assigning Copilot to an issue"
      # Internal-only input retained for existing internal callers.
      visibility :internal

      argument :target_repository_id, ID, "The Node ID of the target repository where Copilot should work. Defaults to the issue's repository if not provided.", required: false, loads: Objects::Repository
      argument :base_ref, String, "The base ref/branch for the repository. Defaults to the default branch if not provided.", required: false
      argument :custom_instructions, String, "Custom instructions for Copilot.", required: false
      argument :custom_agent, String, "Custom agent for Copilot.", required: false
      argument :model, String, "The model to use for the agent.", required: false, feature_flag: :coding_agent_model_selection
    end
  end
end
