# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class TeamGroupMapping < Platform::Objects::Base
      model_name "Team::GroupMapping"
      description "Maps a group to a Team, used as part of Team Sync"

      visibility :under_development

      minimum_accepted_scopes ["admin:org"]

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, group_mapping)
        group_mapping.async_team.then do |team|
          team.async_organization.then do |organization|
            permission.access_allowed?(:v4_manage_org_users, resource: team, team: team, organization: organization, current_repo: nil, allow_integrations: false, allow_user_via_granular_actor: false)
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        return true if permission.viewer.site_admin?

        object.async_team.then do |team|
          team.async_organization.then do |organization|
            organization.async_readable_by?(permission.viewer)
          end
        end
      end

      field :team_id, Integer, null: false, description: "The Team this group is mapped to."
      field :group_id, String, null: false, description: "The group identifier."
      field :group_name, String, null: false, description: "The group name."
      field :group_description, String, null: true, description: "The group description."

      # TODO field :status, Enums::TeamGroupStatus, null: false
      # See abuse_report_reason as an example

      field :synced_at, Scalars::DateTime, null: true, description: "The timestamp of the most recent sync."
    end
  end
end
