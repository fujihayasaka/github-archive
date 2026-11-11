# typed: true
# frozen_string_literal: true

module AzureEXP
  module V2
    module Experiments
      # Test helpers for partner teams using the AzureEXP::V2::Experiments wrapper.
      #
      # Include this module in your test class to stub treatment assignments
      # without needing to know about NoOpClient or AssignmentResult internals.
      #
      #   class MyFeatureTest < GitHub::TestCase
      #     include AzureEXP::V2::Experiments::TestHelpers
      #
      #     test "shows new header for treatment users" do
      #       stub_azure_exp_v2_experiment("/copilot/header_v2", "treatment_a")
      #       assert_equal "treatment_a", AzureEXP::V2::Experiments.current.fetch("/copilot/header_v2", "control")
      #     end
      #
      #     test "shows old header by default" do
      #       # No stub: fetch returns the caller-supplied default
      #       assert_equal "control", AzureEXP::V2::Experiments.current.fetch("/copilot/header_v2", "control")
      #     end
      #   end
      #
      module TestHelpers
        extend T::Helpers

        # Stub a single treatment flag to return the given value for the
        # duration of the current test. Multiple calls accumulate.
        sig { params(flag: String, value: String).void }
        def stub_azure_exp_v2_experiment(flag, value)
          @_stubbed_azure_exp_v2_experiments = T.let(@_stubbed_azure_exp_v2_experiments, T.nilable(T::Hash[String, String]))
          @_stubbed_azure_exp_v2_experiments ||= {}
          @_stubbed_azure_exp_v2_experiments[flag] = value

          result = AzureEXP::V2::Experiments::AssignmentResult.new(
            feature_variables: @_stubbed_azure_exp_v2_experiments.dup,
            assignment_context: "test-stub",
            data_version: 0,
          )

          no_op = AzureEXP::V2::Experiments::NoOpClient.new
          no_op.define_singleton_method(:get_assignment) { |*_| result }

          # Reset the process-level cache so the stubbed client is consulted.
          # Stub contexts add no participants, so they all share the same cache
          # key; without resetting, an earlier stub (or a prior test) would be
          # served from the cache instead of the new stub.
          AzureEXP::V2::Experiments::InMemoryCache.reset!

          context = AzureEXP::V2::Experiments::Context.new(no_op)
          T.unsafe(AzureEXP::V2::Experiments::Current).context = context
          # Force the context to resolve immediately with the stubbed result
          context.fetch(flag, value)
        end

        # Clear all stubbed treatments. Called automatically in teardown
        # if you include this module, but safe to call manually.
        sig { void }
        def clear_stubbed_azure_exp_v2_experiments
          @_stubbed_azure_exp_v2_experiments = nil
          AzureEXP::V2::Experiments::Current.reset
          AzureEXP::V2::Experiments::InMemoryCache.reset!
        end
      end
    end
  end
end
