# typed: strict
# frozen_string_literal: true

module AzureEXP
  module V2
    module Experiments
      # A client that always returns empty assignments (all fetches return defaults).
      #
      # Used when experimentation is disabled: dev, test, Codespaces, Proxima.
      # Equivalent to the Go SDK's NewNoOpClient().
      #
      #   client = AzureEXP::V2::Experiments::NoOpClient.new
      #   result = client.get_assignment({})
      #   result.fetch("/any_flag", "default") # => "default"
      #
      class NoOpClient
        extend T::Helpers

        sig { params(user_params: T::Hash[String, String], scopes: T.nilable(T::Array[String]), required_variants: T.nilable(T::Array[String]), blocked_variants: T.nilable(T::Array[String])).returns(AzureEXP::V2::Experiments::AssignmentResult) }
        def get_assignment(user_params, scopes: nil, required_variants: nil, blocked_variants: nil)
          AzureEXP::V2::Experiments::AssignmentResult.empty
        end
      end
    end
  end
end
