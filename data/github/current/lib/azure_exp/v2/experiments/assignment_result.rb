# typed: strict
# frozen_string_literal: true

module AzureEXP
  module V2
    module Experiments
      # Holds the result of a TAS treatment assignment.
      #
      # Contains the feature variables (flag -> value), the assignment context
      # string for telemetry attribution, and the config data version.
      #
      # All reads go through `fetch(flag, default)` which returns the default
      # if the assignment failed, the flag is missing, or the result is empty.
      #
      # In tests, construct directly:
      #
      #   result = AzureEXP::V2::Experiments::AssignmentResult.new(
      #     feature_variables: { "/copilot/header_v2" => "treatment_a" },
      #     assignment_context: "test-flight:100",
      #     data_version: 1,
      #   )
      #
      #   result.fetch("/copilot/header_v2", "control") # => "treatment_a"
      #   result.fetch("/unknown", "fallback")           # => "fallback"
      #
      class AssignmentResult < T::Struct
        const :feature_variables, T::Hash[String, String], default: {}
        const :assignment_context, String, default: ""
        const :data_version, Integer, default: 0

        # Returns the value of a feature variable, or default_value if the
        # flag is not present in the assignment. An empty string is a valid
        # value and will be returned as-is.
        #
        # default_value is mandatory to ensure callers always provide a
        # sensible fallback for when the experiment is not running.
        sig { params(flag: String, default_value: String).returns(String) }
        def fetch(flag, default_value)
          feature_variables.fetch(flag, default_value)
        end

        # Returns an empty result where every fetch returns the caller's default.
        sig { returns(AzureEXP::V2::Experiments::AssignmentResult) }
        def self.empty
          @empty ||= T.let(new, T.nilable(AzureEXP::V2::Experiments::AssignmentResult))
        end
      end
    end
  end
end
