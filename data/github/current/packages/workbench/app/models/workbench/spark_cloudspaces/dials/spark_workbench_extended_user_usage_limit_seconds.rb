# typed: strict
# frozen_string_literal: true

module Workbench
  module SparkCloudspaces
    module Dials
      class SparkWorkbenchExtendedUserUsageLimitSeconds < Codespaces::Dial

        validates :value, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 2_678_400 }

        sig { override.returns(String) }
        def key
          "workbench_cloudspaces_extended_user_usage_limit_seconds"
        end

        sig { override.returns(Integer) }
        def default_value
          # 100 hours by default
          360_000
        end

        sig { override.returns(String) }
        def description
          "This value restricts the amount of time (in seconds) Spark Workbench workspaces can be used by an extended user in a month."
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
