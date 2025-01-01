# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AddEnterpriseAdmin < Platform::Mutations::Base
      description "Adds an administrator to the global enterprise account."

      # This mutation can only be run by end-users in the Enterprise Server environment.
      visibility :public, environments: [:enterprise]
      visibility :internal, environments: [:dotcom]


      minimum_accepted_scopes ["admin:enterprise"]

      argument :enterprise_id, ID, "The ID of the enterprise account to which the administrator should be added.", required: true, loads: Objects::Enterprise
      argument :login, String, "The login of the user to add as an administrator.", required: true

      field :enterprise, Objects::Enterprise, "The updated enterprise.", null: true
      field :admin, Objects::User, "The user who was added as an administrator.", null: true
      field :viewer, Objects::User, "The viewer performing the mutation.", null: true
      field :role, Enums::EnterpriseAdministratorRole, "The role of the administrator.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, enterprise:, **inputs)
        permission.access_allowed?(:administer_business, resource: enterprise, repo: nil, organization: nil, allow_integrations: false, allow_user_via_granular_actor: false)
      end

      def resolve(enterprise:, **inputs)
        ensure_business_not_suspended!(enterprise)
        ensure_business_payment_completed!(enterprise)

        viewer = context[:viewer]

        unless enterprise.owner?(viewer)
          raise Errors::Forbidden.new("#{viewer.display_login} does not have permission to update this enterprise.")
        end

        admin = find_user!(inputs[:login])

        if GitHub.site_admin_role_managed_externally?
          raise Errors::Unprocessable.new \
            enterprise.external_auth_system_owner_instructions(operation: :add)
        end

        begin
          enterprise.add_owner(admin, actor: viewer)
        rescue Business::UserHasTwoFactorDisabledError,
          Business::InvalidAdminStateError,
          Business::UserHasNoExternalIdentityError => error
          raise Errors::Unprocessable.new error
        end

        {
          enterprise: enterprise,
          admin: admin,
          viewer: viewer,
          role: T.must(Platform::Enums::EnterpriseAdministratorRole.values["OWNER"]).value,
        }
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
