# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class RevokeEnterpriseOrganizationsMigratorRole < Platform::Mutations::Base
      description "Revoke the migrator role to a user for all organizations under an enterprise account."

      ROLE_NAME = "octoshift_migrator"
      private_constant :ROLE_NAME

      minimum_accepted_scopes ["admin:enterprise"]

      argument :enterprise_id, ID, "The ID of the enterprise to which all organizations managed by it will be granted the migrator role.", required: true, loads: Objects::Enterprise
      argument :login, String, "The login of the user to revoke the migrator role", required: true

      field :organizations, Connections::Organization, description: "The organizations that had the migrator role revoked for the given user.", null: true, connection: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, enterprise:, **inputs)
        # Maybe add staff permission too
        permission.access_allowed?(:administer_business,
          resource: enterprise, repo: nil, organization: nil,
          allow_integrations: false, allow_user_via_granular_actor: false)
      end

      def resolve(enterprise:, **inputs)
        ensure_business_not_suspended!(enterprise)
        ensure_business_payment_completed!(enterprise)

        user = find_user!(inputs[:login])

        # Organizations removed from
        orgs_removed = []

        enterprise.async_organizations.then do |organizations|
          Promise.all(
            organizations.map do |organization|
              Loaders::ActiveRecord.load(::Organization, organization.id).then do |organization|
                begin
                  Octoshift::AuthorizationPolicy.revoke_octoshift_migrator!(
                    actor_type: "USER",
                    # login is find to use to lookup the actor and for creation
                    actor: user.login, # rubocop:disable GitHub/DoNotAllowLogin
                    organization: organization
                  )
                  orgs_removed << organization
                rescue Octoshift::AuthorizationPolicy::UserDoesNotBelongToOrgError => e
                  # Do nothing, don't revoke role if user is not a member
                  next
                rescue Octoshift::AuthorizationPolicy::RoleGranterError => e
                  raise Errors::Forbidden.new(e.message)
                end
              end
            end
          ).then do
            { organizations: ArrayWrapper.new(orgs_removed) }
          end
        end
      end

      private

      def find_user!(login)
        Loaders::ActiveRecord.load(::User, login, column: :login).sync.tap do |user|
          raise Errors::NotFound.new("Could not find User with login: #{login}") unless user
        end
      end
    end
  end
end
