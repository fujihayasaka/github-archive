# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class RemoveEnterpriseSupportEntitlement < Platform::Mutations::Base
      description "Removes a support entitlement from an enterprise member."

      # This mutation can only be run by end-users in the Enterprise Cloud environment.
      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      minimum_accepted_scopes ["admin:enterprise"]

      argument :enterprise_id, ID, "The ID of the Enterprise which the admin belongs to.", required: true, loads: Objects::Enterprise
      argument :login, String, "The login of a member who will lose the support entitlement.", required: true

      field :message, String, "A message confirming the result of removing the support entitlement.", null: true

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
          raise Errors::Forbidden.new("#{viewer.display_login} is not authorized to remove support entitlements from this enterprise account.")
        end

        user = find_user!(inputs[:login])

        Ability.transaction do
          enterprise.remove_support_entitlee(user, actor: viewer)
        end

        { message: "#{user.display_login} no longer has a support entitlement." }
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
