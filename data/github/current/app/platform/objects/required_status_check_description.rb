# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class RequiredStatusCheckDescription < Platform::Objects::Base
      minimum_accepted_scopes ["public_repo"]

      description "Represents a required status check for a protected branch, but not any specific run of that check."
      model_name "RequiredStatusCheck"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, status)
        permission.async_repo_and_org_owner(status).then do |repo, org|
          # NOTE: The required permission is `read_branch_protection` instead of
          #  `read_status` because this object only describes the statuses used
          #  by the branch protection rule, it does not provide any actual
          #  status information.
          permission.access_allowed?(:read_branch_protection, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_protected_branch.then do |protected_branch|
          permission.belongs_to_repository(protected_branch)
        end
      end

      field :context, String, "The name of this status.", resolver_method: :status_context, null: false
      # This field should get the _object's_ context, not the GraphQL query context.
      def status_context
        @object.context
      end

      field :app, Objects::App, "The App that must provide this status in order for it to be accepted.", null: true

      def app
        @object.async_integration
      end
    end
  end
end
