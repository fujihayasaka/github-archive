# typed: strict
# frozen_string_literal: true

module Codespaces
  module Dials
    class CopilotWorkspaceMaxCodespaceUsers < Codespaces::Dial

      validates :value, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

      sig { override.returns(String) }
      def key
        "codespaces_copilot_workspace_max_codespace_users"
      end

      sig { override.returns(Integer) }
      def default_value
        0
      end

      sig { override.returns(String) }
      def description
        "For use with capacity grants managed by Copilot Workspace. A value of 0 enforces no limit. Any other value will be treated as the max number of users who can be creating codespaces within the past 5 minutes."
      end

      private

      sig { params(value: String).returns(Integer) }
      def transform_value_to_use(value)
        value.to_i
      end
    end
  end
end
