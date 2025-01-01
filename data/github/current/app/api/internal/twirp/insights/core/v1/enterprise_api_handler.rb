# typed: true
# frozen_string_literal: true

require "monolith-twirp-insights-core"

module Api::Internal::Twirp::Insights
  module Core
    module V1
      # Handler for the MonolithTwirp::Insights::Core::V1::EnterpriseAPIService
      class EnterpriseAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["insights"]
        handles_service MonolithTwirp::Insights::Core::V1::EnterpriseAPIService

        # Public: Implementation of the GetEnterpriseOrgs Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Insights::Core::V1::GetEnterpriseOrgsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Insights::Core::V1::GetEnterpriseOrgsResponse, or a Twirp::Error.
        def get_enterprise_orgs(req, env)
          GetEnterpriseOrgs.call(req, env)
        end

        # Public: Implementation of the GetOrganizationOwner Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Insights::Core::V1::GetOrganizationOwnerRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Insights::Core::V1::GetOrganizationOwnerResponse, or a Twirp::Error.
        def get_organization_owner(req, env)
          GetOrganizationOwner.call(req, env)
        end
      end
    end
  end
end
