# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UnfollowOrganization < Platform::Mutations::Base
      description "Unfollow an organization."

      def self.async_api_can_modify?(permission, **inputs)
        permission.access_allowed?(:follow, resource: inputs[:organization],
                                   current_repo: nil, current_org: nil,
                                   allow_integrations: false, allow_user_via_granular_actor: true)
      end

      minimum_accepted_scopes ["user:follow"]

      argument :organization_id, ID, "ID of the organization to unfollow.", required: true, loads: Objects::Organization

      field :organization, Objects::Organization, "The organization that was unfollowed.", null: true

      def resolve(organization:)
        viewer = context[:viewer]

        if !organization.followed_by?(viewer) || viewer.unfollow(organization, context: "api")
          { organization: organization }
        else
          raise Platform::Errors::Execution.new("Failed to unfollow organization.")
        end
      end
    end
  end
end
