# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class WorkflowState < Platform::Enums::Base
      description "The possible states for a workflow."

      value "ACTIVE",  "The workflow is active.", value: "active"
      value "DELETED", "The workflow was deleted from the git repository.", value: "deleted"
      value "DISABLED_FORK", "The workflow was disabled by default on a fork.", value: "disabled_fork"
      value "DISABLED_INACTIVITY", "The workflow was disabled for inactivity in the repository.", value: "disabled_inactivity"
      value "DISABLED_MANUALLY", "The workflow was disabled manually.", value: "disabled_manually"
    end
  end
end
