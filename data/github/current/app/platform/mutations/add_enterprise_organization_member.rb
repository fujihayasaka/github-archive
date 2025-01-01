# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AddEnterpriseOrganizationMember < Platform::Mutations::Base
      SIZE_LIMIT = 100

      description "Adds enterprise members to an organization within the enterprise."

      minimum_accepted_scopes ["admin:enterprise"]

      argument :enterprise_id, ID, "The ID of the enterprise which owns the organization.", required: true, loads: Objects::Enterprise
      argument :organization_id, ID, "The ID of the organization the users will be added to.", required: true, loads: Objects::Organization
      argument :user_ids, [ID], "The IDs of the enterprise members to add.", required: true
      argument :role, Enums::OrganizationMemberRole, "The role to assign the users in the organization", required: false

      field :users, [Objects::User], "The users who were added to the organization.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, enterprise:, organization:, **inputs)
        permission.access_allowed?(:administer_business, resource: enterprise, repo: nil, organization: organization, allow_integrations: false, allow_user_via_granular_actor: false)
      end

      def resolve(enterprise:, organization:, **inputs)
        ensure_business_can_use_api!(enterprise)

        viewer = context[:viewer]
        actor = context[:actor]
        admin = (inputs[:role] || :member).to_sym == :admin
        members = []

        # User must be an owner of the enterprise
        unless enterprise.owner?(viewer)
          raise Errors::Forbidden.new("Viewer must be an enterprise owner")
        end

        # User must be an admin of the organization
        unless organization.adminable_by?(viewer)
          raise Errors::Forbidden.new("Viewer must be an organization admin")
        end

        # Organization must be owned by the enterprise
        if organization.business&.id != enterprise.id
          raise Errors::Forbidden.new("Organization must belong to the enterprise")
        end

        if inputs[:user_ids].size > SIZE_LIMIT
          raise Errors::Unprocessable.new("Request exceeded limit of #{SIZE_LIMIT} users")
        end

        user_promises = inputs[:user_ids].map do |id|
          Platform::Helpers::NodeIdentification.async_typed_object_from_id(Objects::User, id, context)
        end

        Promise.all(user_promises).then do |users|
          users.each do |user|
            next unless can_add_user_to_organizations?(enterprise, user)
            if organization.direct_member?(user)
              organization.update_member user, updater: actor, action: admin ? :admin : :read
            else
              organization.add_member user, adder: actor, action: admin ? :admin : :read
            end
            members << user
          end
        end.sync

        {
          users: members
        }
      end

      private

      def can_add_user_to_organizations?(enterprise, user)
        if enterprise.supports_unaffiliated_user_accounts?
          enterprise.unaffiliated_member?(user)
        else
          enterprise.member?(user)
        end
      end
    end
  end
end
