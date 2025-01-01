# typed: strict
# frozen_string_literal: true

module WorkspaceEditor
  module Cloudspaces
    module Dials
      class MaximumInstancesForUser < Codespaces::Dial

        validates :value,
                  numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 1000 }

        sig { override.returns(String) }
        def key
          "hadron_cloudspaces_maximum_instances_for_user"
        end

        sig { override.returns(String) }
        def default_value
          "16"
        end

        sig { override.returns(String) }
        def description
          "This value restricts the number of workspace editor cloudspaces that a
          user can run concurrently at any given time. For example, when this
          dial's value is set to 16, a user can have up to 16 Copilot workspace
          Codespaces running concurrently at any given time."
        end

        private

        sig { params(value: String).returns(Integer) }
        def transform_value_to_use(value)
          value.to_i
        end
      end
    end
  end
end
