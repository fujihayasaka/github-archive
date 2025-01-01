# typed: true
# frozen_string_literal: true

require "monolith-twirp-registrymetadata-core"

module Api::Internal::Twirp::Registrymetadata
  module Core
    module V1
      # Handler for the MonolithTwirp::Registrymetadata::Core::V1::OrgAPIService
      class OrgAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: %w(packageregistry package_registry).freeze
        handles_service MonolithTwirp::Registrymetadata::Core::V1::OrgAPIService

        # Public: Implementation of the GetOrgId Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Registrymetadata::Core::V1::GetOrgIdRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Registrymetadata::Core::V1::GetOrgIdResponse, or a Twirp::Error.
        def get_org_id(req, env)
          org_or_user = User.find_by_login(req.name)
          if org_or_user.nil?
            return Twirp::Error.not_found("org/user name not found")
          end
          {
            org_id: org_or_user.id
          }
        end
      end
    end
  end
end
