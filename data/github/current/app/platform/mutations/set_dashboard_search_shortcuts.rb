# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class SetDashboardSearchShortcuts < Platform::Mutations::Base
      description "Set/reset dashboard search shortcuts."
      minimum_accepted_scopes ["user"]
      mobile_only true
      extras [:execution_errors]

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        permission.access_allowed?(
          :update_user,
          resource: permission.viewer,
          current_repo: nil,
          current_org: nil,
          allow_integrations: false,
          allow_user_via_granular_actor: false
        )
      end

      argument :shortcuts, [Inputs::SearchShortcutAttributes], "A list of shortcut inputs to replace existing shortcuts with.", required: true

      field :dashboard, Objects::UserDashboard, "The dashboard owning the shortcuts", null: true
      field :shortcuts, [Objects::SearchShortcut], "The new shortcuts.", null: true
      error_fields

      def resolve(shortcuts:, execution_errors:)
        viewer = context[:viewer]
        result = ::SearchShortcutsSetter.new(viewer).set(shortcuts)

        if result.success?
          {
            dashboard: viewer.dashboard,
            shortcuts: viewer.dashboard.async_shortcuts,
            errors: []
          }
        else
          message = "Could not set search shortcuts, #{result.errors.map { |e| e[:message] }.uniq.join(", ")}."
          Platform::UserErrors.append_legacy_mutation_error_messages_to_context(Array.wrap(message), execution_errors)

          {
            dashboard: nil,
            shortcuts: nil,
            errors: result.errors
          }
        end
      end
    end
  end
end
