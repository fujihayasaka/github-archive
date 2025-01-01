# typed: true
# frozen_string_literal: true

require "monolith-twirp-modelsgateway-billing"

module Api::Internal::Twirp::Modelsgateway
  module Billing
    module V1
      # Handler for the MonolithTwirp::Modelsgateway::Billing::V1::MultipliersAPIService
      class MultipliersAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["modelsgateway"]
        handles_service MonolithTwirp::Modelsgateway::Billing::V1::MultipliersAPIService

        # Public: Implementation of the GetMultipliers Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Modelsgateway::Billing::V1::GetMultipliersRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Modelsgateway::Billing::V1::GetMultipliersResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Modelsgateway::Billing::V1::GetMultipliersRequest,
            env: Hash
          ).returns(T.any(Hash, Twirp::Error))
        end
        def get_multipliers(req, env)
          multipliers = GitHubModels::Multiplier.includes(model: :models_publisher)
          {
            multipliers: multipliers.map(&:twirp_response)
          }
        end
      end
    end
  end
end
