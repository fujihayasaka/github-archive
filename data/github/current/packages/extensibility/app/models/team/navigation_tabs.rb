# typed: true
# frozen_string_literal: true

class Team
  class NavigationTabs
    include UrlHelpers
    include UrlHelper
    include Orgs::Teams::TeamRepositories
    include GitHub::ResilienceMixin

    def self.for(team:, current_user:, **opts)
      T.unsafe(self).new(team: team, current_user: current_user, **opts).tabs
    end

    attr_reader :team, :current_user

    def initialize(team:, current_user:, **opts)
      @team = team
      @current_user = current_user

      @repositories_count = opts[:repositories_count] if opts[:repositories_count]
    end

    def tabs
      [
        members_tab,
        teams_tab,
        repositories_tab,
        projects_tab,
        custom_org_roles_tab,
        settings_tab
      ].compact
    end

    def members_tab
      Site::Header::UnderlineNavTab.new(text: "Members", icon: :person, href: team_members_path(team), count: team.members_scope_count, highlight: :members, data: { test_selector: "members-button-visible" })
    end

    def custom_org_roles_tab
      return unless should_display_custom_org_roles_tab?
      Site::Header::UnderlineNavTab.new(text: "Organization roles", icon: :organization, href: team_organization_role_path(team, team.organization), count: custom_org_roles_count, highlight: :organization, data: { test_selector: "organization-roles-button-visible" })
    end

    def teams_tab
      return unless team.locally_managed?

      Site::Header::UnderlineNavTab.new(text: "Teams", icon: :people, href: team_teams_path(team), count: team.descendants.count, highlight: :teams, data: { test_selector: "teams-button-visible" })
    end

    def repositories_tab
      Site::Header::UnderlineNavTab.new(text: "Repositories", icon: :repo, href: team_repositories_path(team), count: repositories_count, highlight: :repositories, counter_arguments: { data: { test_selector: "repositories-count" } })
    end

    def projects_tab
      Site::Header::UnderlineNavTab.new(text: "Projects", icon: :table, href: team_projects_path(team.organization, team), highlight: :projects)
    end

    def settings_tab
      return unless team.adminable_by?(current_user)

      Site::Header::UnderlineNavTab.new(text: "Settings", icon: :gear, href: edit_team_path(team.organization, team), count: team.descendants.count, highlight: :settings)
    end

    private

    def should_display_custom_org_roles_tab?
      team.organization.adminable_by?(@current_user)
    end

    def custom_org_roles_count
      # Hide the security manager role.
      UserRole.where(target_type: "Organization", target_id: team.organization.id, actor_type: "Team", actor_id: team.id)
      .where.not(role_id: Role.security_manager_role.id)
      .count
    end

    def repositories_count
      @repositories_count ||= with_database_error_fallback(fallback: 0) do
        accessible_team_repository_ids_for_current_user(current_user, team, team.organization).count
      end
    end
  end
end
