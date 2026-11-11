# typed: strict
# frozen_string_literal: true

module Workbench
  module SparkCloudspaces
    module Dials
      class MaximumInstancesForFreeUser < Codespaces::Dial

        validates :value,
                  numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 1000 }

        sig { override.returns(String) }
        def key
          "workbench_cloudspaces_maximum_instances_for_free_user"
        end

        sig { override.returns(String) }
        def default_value
          "1"
        end

        sig { override.returns(String) }
        def description
          "This value restricts the number of spark workbench cloudspaces that a
          free user can run concurrently at any given time. For example, when this
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
