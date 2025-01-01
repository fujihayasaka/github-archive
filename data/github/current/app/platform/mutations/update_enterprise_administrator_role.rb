# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateEnterpriseAdministratorRole < Platform::Mutations::Base
      description "Updates the role of an enterprise administrator."

      # This mutation can only be run by end-users in the Enterprise Cloud environment.
      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      minimum_accepted_scopes ["admin:enterprise"]

      argument :enterprise_id, ID, "The ID of the Enterprise which the admin belongs to.", required: true, loads: Objects::Enterprise
      argument :login, String, "The login of a administrator whose role is being changed.", required: true
      argument :role, Enums::EnterpriseAdministratorRole, "The new role for the Enterprise administrator.", required: true

      field :message, String, "A message confirming the result of changing the administrator's role.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, enterprise:, **inputs)
        permission.access_allowed?(:administer_business, resource: enterprise, repo: nil, organization: nil, allow_integrations: false, allow_user_via_granular_actor: false)
      end

      def resolve(enterprise:, **inputs)
        ensure_business_can_use_api!(enterprise)

        if enterprise.enterprise_managed_user_enabled?
          raise Errors::Forbidden.new("This enterprise is an IdP managed enterprise.  Administrative roles can only be changed through an IdP.")
        end

        viewer = context[:viewer]

        unless enterprise.owner?(viewer)
          raise Errors::Forbidden.new("#{viewer.display_login} does not have permission to admin this enterprise.")
        end

        user = find_user!(inputs[:login])

        unless enterprise.owner?(user) || enterprise.billing_manager?(user)
          raise Errors::Forbidden.new("#{user.display_login} is not an administrator of the enterprise account")
        end

        Ability.transaction do
          case inputs[:role]
          when T.must(Enums::EnterpriseAdministratorRole.values["OWNER"]).value
            enterprise.change_admin_role(user, new_role: :owner, actor: viewer)
          when T.must(Enums::EnterpriseAdministratorRole.values["BILLING_MANAGER"]).value
            enterprise.change_admin_role(user, new_role: :billing_manager, actor: viewer)
          when T.must(Enums::EnterpriseAdministratorRole.values["UNAFFILIATED"]).value
            enterprise.change_admin_role(user, new_role: :unaffiliated, actor: viewer)
          end
        rescue Business::UserHasTwoFactorDisabledError,
          Business::InvalidAdminStateError,
          Business::UserNotAnAdminError,
          Business::NoAdminsError,
          Business::UserHasNoExternalIdentityError,
          ArgumentError => error
          raise Errors::Unprocessable.new(error.message)
        end

        { message: "#{user.display_login}'s role was set to #{inputs[:role].humanize.downcase}" }
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
