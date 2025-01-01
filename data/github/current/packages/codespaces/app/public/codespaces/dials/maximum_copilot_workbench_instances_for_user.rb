# typed: strict
# frozen_string_literal: true

module Codespaces
  module Dials
    class MaximumCopilotWorkbenchInstancesForUser < Codespaces::Dial

      validates :value,
                numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 1000 }

      sig { override.returns(String) }
      def key
        "codespaces_maximum_copilot_workbench_instances_for_user"
      end

      sig { override.returns(String) }
      def default_value
        "3"
      end

      sig { override.returns(String) }
      def description
        "This value restricts the number of Copilot Workbench Codespaces, AKA
        Sparks, that a user can run concurrently at any given time. For example,
        when this dial's value is set to 3, a user can have up to 3 Sparks running
        concurrently at any given time."
      end

      private

      sig { params(value: String).returns(Integer) }
      def transform_value_to_use(value)
        value.to_i
      end
    end
  end
end
