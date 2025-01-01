# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class OrganizationsHovercardContext < Objects::Base
      description "An organization list hovercard context"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, ctx)
        # ctx is UserHovercard::Contexts::Organizations
        resource = if ::FeatureFlag.vexi.enabled_or_raise?(:cap_get_public_member) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
          ctx.user
        else
          nil
        end
        permission.access_allowed?(
          :get_public_member,
          resource: resource,
          current_org: nil,
          current_repo: nil
        )
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        # object is UserHovercard::Contexts::Organizations and field should be pre-filtered based on the viewer
        !object.nil?
      end

      scopeless_tokens_as_minimum

      implements Interfaces::HovercardContext

      field :relevant_organizations, Connections.define(Objects::Organization), connection: true, null: false, resolver: Resolvers::Organizations do
        description "Organizations this user is a member of that are relevant"
      end

      field :total_organization_count, Integer, null: false do
        description "The total number of organizations this user is in"
      end
    end
  end
end
