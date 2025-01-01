# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  module Dials
    class CopilotWorkspaceUsageLimitSeconds < Codespaces::Dial
      extend T::Sig

      validates :value, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 2_678_400 }

      sig { override.returns(String) }
      def key
        "codespaces_copilot_workspace_usage_limit_seconds"
      end

      sig { override.returns(Integer) }
      def default_value
        # 20 hours by default
        72_000
      end

      sig { override.returns(String) }
      def description
        "This value restricts the amount of time (in seconds) Copilot workspaces can be used by a given user in a month."
      end

      private

      def transform_value_to_use(value)
        value.to_i
      end
    end
  end
end
