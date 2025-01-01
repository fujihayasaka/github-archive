# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class TeamDashboard < Platform::Objects::Base
      description "A team's dashboard."

      implements_node templates: [[:tdb, :organization_id, :team_id, :team_dashboard_id]], as: "TDB", allow_nil_for: [:team_dashboard_id], ready_date: "1970-01-01" do |dashboard|
        {
          prefix: :tdb,
          organization_id: dashboard.team.organization_id,
          team_id: dashboard.team_id,
          team_dashboard_id: dashboard.id
        }
      end

      minimum_accepted_scopes ["read:org"]
      required_capabilities [:mobile_only_schema_mask]

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        object.async_team.then do |team|
          team.async_organization.then do |org|
            permission.access_allowed?(:v4_get_team,
              team: team,
              resource: org,
              organization: org,
              current_repo: nil,
              allow_integrations: true,
              allow_user_via_granular_actor: true
            )
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        return true if GitHub.enterprise? && permission.viewer&.site_admin?

        object.async_team.then do |team|
          team.async_visible_to?(permission.viewer)
        end
      end

      field :team, Objects::Team, "The team this dashboard belongs to.", null: false
      field :shortcuts, Connections.define(Objects::TeamSearchShortcut), "The saved searched shortcuts for this team dashboard", null: false do
        argument :search_types, [Enums::SearchShortcutType], <<~DESC, required: false
          The types of team search shortcuts to return. If not provided, all shortcuts are returned.
        DESC
      end

      def shortcuts(search_types: nil)
        if search_types.nil? # No value provided or explicit nil.
          object.shortcuts
        elsif search_types.empty? # Explicit empty array.
          object.shortcuts.none
        else # Some search types were passed in.
          object.shortcuts.where(search_type: search_types)
        end
      end
    end
  end
end
