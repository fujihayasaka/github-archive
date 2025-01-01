# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class TeamSearchShortcut < Platform::Objects::Base
      description "A shortcut for a search with specified filters"
      scopeless_tokens_as_minimum
      mobile_only true

      implements_node templates: [[:tsc, :team_search_shortcut_id]], as: "TSC", ready_date: "1970-01-01" do |team_search_shortcut|
        {
          prefix: :tsc,
          team_search_shortcut_id: team_search_shortcut.id,
        }
      end
      implements Interfaces::Shortcutable
      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        object.async_dashboard.then do |dashboard|
          dashboard.async_team.then do |team|
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
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        return true if GitHub.enterprise? && permission.viewer&.site_admin?

        object.async_dashboard.then do |dashboard|
          dashboard.async_team.then do |team|
            team.async_visible_to?(permission.viewer)
          end
        end
      end

      field :name, String, "The name of the shortcut.", null: false
      field :description, String, "The description of the shortcut.", null: false
      field :search_type, Enums::SearchShortcutType, "The type of the shortcut.", null: false
      field :icon, Enums::SearchShortcutIcon, "The icon of the shortcut.", null: false
      field :color, Enums::SearchShortcutColor, "The color of the shortcut.", null: false
      field :query, String, "The filter string of the shortcut.", null: false

      field :query_terms, [Unions::SearchShortcutQueryTermsItem], null: false,
        description: "A parsed set of terms from the query string of this shortcut."

      field :scoping_repository, Objects::Repository, "The repository scoping the shortcut.", null: true

      def scoping_repository
        Loaders::ActiveRecord.load(::Repository, object.scoping_repository_id, security_violation_behaviour: :nil)
      end
    end
  end
end
