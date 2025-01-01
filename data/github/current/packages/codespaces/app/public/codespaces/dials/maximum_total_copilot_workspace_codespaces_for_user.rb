# typed: strict
# frozen_string_literal: true

module Codespaces
  module Dials
    class MaximumTotalCopilotWorkspaceCodespacesForUser < Codespaces::Dial

      validates :value,
                numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 1000 }

      sig { override.returns(String) }
      def key
        "codespaces_maximum_total_copilot_workspace_codespaces_for_user"
      end

      sig { override.returns(String) }
      def default_value
        "30"
      end

      sig { override.returns(String) }
      def description
        "This value restricts the total number of Copilot workspace Codespaces
        that a user can have at any given time. For example, when this dial's
        value is set to 5, a user can have up to 5 Copilot workspace Codespaces
        at any given time."
      end

      private

      sig { params(value: String).returns(Integer) }
      def transform_value_to_use(value)
        value.to_i
      end
    end
  end
end
