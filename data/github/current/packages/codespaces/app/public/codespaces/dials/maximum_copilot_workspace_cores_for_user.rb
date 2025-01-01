# typed: strict
# frozen_string_literal: true

module Codespaces
  module Dials
    class MaximumCopilotWorkspaceCoresForUser < Codespaces::Dial
      extend T::Sig

      validates :value,
                numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 1000 }

      sig { override.returns(String) }
      def key
        "codespaces_maximum_copilot_workspace_cores_for_user"
      end

      sig { override.returns(String) }
      def default_value
        "64"
      end

      sig { override.returns(String) }
      def description
        "This value restricts the total number of cores utilized by Copilot
        workspace Codespaces for a user at any given time. For example, when
        this dial's value is set to 64, a user can utilize up to 64 cores of
        compute across all their Copilot Workspace codespaces"
      end

      private

      sig { params(value: String).returns(Integer) }
      def transform_value_to_use(value)
        value.to_i
      end
    end
  end
end
