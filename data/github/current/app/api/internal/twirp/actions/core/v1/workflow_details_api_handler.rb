# typed: true
# frozen_string_literal: true

require "monolith-twirp-actions-core"

module Api::Internal::Twirp::Actions
  module Core
    module V1
      # Handler for the MonolithTwirp::Actions::Core::V1::WorkflowDetailsAPIService
      class WorkflowDetailsAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["launch"].freeze
        handles_service MonolithTwirp::Actions::Core::V1::WorkflowDetailsAPIService

        exempt_from_tenant_context_requirement(only: %i[get_billing_details_for_entity])

        resolve_tenant_context only: %i[get_billing_details] do |req, _env|
          begin
            repository_id = Platform::Helpers::NodeIdentification.from_global_id(req.repository_id.global_id).last
            Repositories::Public.resolve_tenant(id: repository_id)
          rescue Platform::Errors::NotFound
            Twirp::Error.invalid_argument("repository id can't be decoded", argument: "repository_id")
          end
        end

        # Public: Implementation of the GetBillingDetails Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Actions::Core::V1::GetBillingDetailsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Actions::Core::V1::GetBillingDetailsResponse, or a Twirp::Error.
        def get_billing_details(req, env)
          GetBillingDetails.call(req)
        end

        # Public: Implementation of the GetBillingDetailsForEntity Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Actions::Core::V1::GetBillingDetailsForEntityRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Actions::Core::V1::GetBillingDetailsForEntityResponse, or a Twirp::Error.
        def get_billing_details_for_entity(req, env)
          GetBillingDetailsForEntity.call(req)
        end
      end
    end
  end
end
