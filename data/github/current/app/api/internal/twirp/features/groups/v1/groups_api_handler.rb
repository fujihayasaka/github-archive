# typed: true
# frozen_string_literal: true

require "monolith-twirp-features-groups"

module Api::Internal::Twirp::Features
  module Groups
    module V1
      # Handler for the MonolithTwirp::Features::Groups::V1::GroupsAPIService
      class GroupsAPIHandler < Api::Internal::Twirp::Handler
        extend T::Sig

        STAFFSHIP_GROUP = "preview_features"

        allow_access_for :client, allowed_clients: ["dev_portal_actors"]
        handles_service MonolithTwirp::Features::Groups::V1::GroupsAPIService

        # get_groups does not need the tenant context since it is only returning a hardcoded list of groups
        # that are built into the monolith.
        exempt_from_tenant_context_requirement(only: %i[get_groups])

        # Public: Implementation of the GetGroups Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Features::Groups::V1::GetGroupsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Features::Groups::V1::GetGroupsResponse, or a Twirp::Error.
        sig { params(req: MonolithTwirp::Features::Groups::V1::GetGroupsRequest, env: T.untyped).returns(T.any(MonolithTwirp::Features::Groups::V1::GetGroupsResponse, Twirp::Error)) }
        def get_groups(req, env)
          results = Flipper.group_names.reject { |group_name| group_name == STAFFSHIP_GROUP }
          MonolithTwirp::Features::Groups::V1::GetGroupsResponse.new groups: results.sort!
        end
      end
    end
  end
end
