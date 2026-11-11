# typed: true
# frozen_string_literal: true

class Team
  class NavigationTabs < ContextRegion::LocalNavigation::NavigationTabs
    include UrlHelpers
    include UrlHelper
    include Orgs::Teams::TeamRepositories
    include GitHub::ResilienceMixin

    TAB_METADATA = {
      members: {
        icon: :person,
        label: "Members",
        highlight: :members,
      },
      teams: {
        icon: :people,
        label: "Teams",
        highlight: :teams,
      },
      repositories: {
        icon: :repo,
        label: "Repositories",
        highlight: :repositories,
      },
      projects: {
        icon: :table,
        label: "Projects",
        highlight: :projects,
      },
      organization_roles: {
        icon: :organization,
        label: "Organization roles",
        highlight: :organization,
      },
      settings: {
        icon: :gear,
        label: "Settings",
        highlight: :settings,
      },
    }.freeze

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
      record_tab_timing(:members) do
        meta = TAB_METADATA[:members]
        href = team_members_path(team)

        Site::Header::UnderlineNavTab.new(
          text: meta[:label],
          icon: meta[:icon],
          href: href,
          count: team.members_scope_count,
          highlight: meta[:highlight],
          data: { test_selector: "members-button-visible" }
        )
      end
    end

    def custom_org_roles_tab
      record_tab_timing(:custom_org_roles) do
        return unless should_display_custom_org_roles_tab?

        meta = TAB_METADATA[:organization_roles]

        Site::Header::UnderlineNavTab.new(
          text: meta[:label],
          icon: meta[:icon],
          href: team_organization_role_path(team, team.organization),
          count: custom_org_roles_count,
          highlight: meta[:highlight],
          data: { test_selector: "organization-roles-button-visible" }
        )
      end
    end

    def teams_tab
      record_tab_timing(:teams) do
        return unless team.locally_managed?

        meta = TAB_METADATA[:teams]

        Site::Header::UnderlineNavTab.new(
          text: meta[:label],
          icon: meta[:icon],
          href: team_teams_path(team),
          count: team.descendants.count,
          highlight: meta[:highlight],
          data: { test_selector: "teams-button-visible" }
        )
      end
    end

    def repositories_tab
      record_tab_timing(:repositories) do
        meta = TAB_METADATA[:repositories]

        Site::Header::UnderlineNavTab.new(
          text: meta[:label],
          icon: meta[:icon],
          href: team_repositories_path(team),
          count: repositories_count,
          highlight: meta[:highlight],
          counter_arguments: { data: { test_selector: "repositories-count" } }
        )
      end
    end

    def projects_tab
      record_tab_timing(:projects) do
        # Project permissions are not yet supported for enterprise teams.
        return if team.business_team?

        meta = TAB_METADATA[:projects]

        Site::Header::UnderlineNavTab.new(
          text: meta[:label],
          icon: meta[:icon],
          href: team_projects_path(team.organization, team),
          highlight: meta[:highlight]
        )
      end
    end

    def settings_tab
      record_tab_timing(:settings) do
        return unless team.adminable_by?(current_user)

        meta = TAB_METADATA[:settings]

        Site::Header::UnderlineNavTab.new(
          text: meta[:label],
          icon: meta[:icon],
          href: edit_team_path(team.organization, team),
          highlight: meta[:highlight]
        )
      end
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

    def entity_name
      "team"
    end
  end
end
