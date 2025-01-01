# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class RemoveEnterpriseAdmin < Platform::Mutations::Base
      description "Removes an administrator from the enterprise."

      minimum_accepted_scopes ["admin:enterprise"]

      argument :enterprise_id, ID, "The Enterprise ID from which to remove the administrator.", required: true, loads: Objects::Enterprise
      argument :login, String, "The login of the user to remove as an administrator.", required: true

      field :enterprise, Objects::Enterprise, "The updated enterprise.", null: true
      field :admin, Objects::User, "The user who was removed as an administrator.", null: true
      field :viewer, Objects::User, "The viewer performing the mutation.", null: true
      field :message, String, "A message confirming the result of removing an administrator.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, enterprise:, **inputs)
        permission.access_allowed?(:administer_business, resource: enterprise, repo: nil, organization: nil, allow_integrations: false, allow_user_via_granular_actor: false)
      end

      def resolve(enterprise:, **inputs)
        ensure_business_can_use_api!(enterprise)

        viewer = context[:viewer]

        unless enterprise.owner?(viewer)
          raise Errors::Forbidden.new("#{viewer.display_login} does not have permission to update this enterprise.")
        end

        admin = find_user!(inputs[:login])
        role = if enterprise.owner?(admin)
          :owner
        elsif enterprise.billing_manager?(admin)
          :billing_manager
        else
          :administrator
        end

        if GitHub.site_admin_role_managed_externally?
          raise Errors::Unprocessable.new \
            enterprise.external_auth_system_owner_instructions(operation: :remove)
        end

        if role == :owner
          enterprise.remove_owner(admin, actor: viewer)
        elsif role == :billing_manager
          enterprise.billing.remove_manager(admin, actor: viewer)
        end

        message = if viewer.display_login == admin.display_login
          "You are no longer #{::Business.admin_role_for_message(role)} of #{enterprise.name}."
        else
          "You've removed #{admin.display_login} as #{::Business.admin_role_for_message(role)} of #{enterprise.name}."
        end

        {
          enterprise: enterprise,
          admin: admin,
          viewer: viewer,
          message: message,
        }
      rescue ::Business::NoAdminsError => e
        raise Errors::Unprocessable.new(e.message)
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
