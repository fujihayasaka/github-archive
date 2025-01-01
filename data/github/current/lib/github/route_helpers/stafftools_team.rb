# typed: true
# frozen_string_literal: true

module GitHub
  module RouteHelpers

    def gh_stafftools_team_path(team)
      expand_team :stafftools_user_team_path, team
    end

    def gh_stafftools_sync_team_path(team)
      expand_team :sync_stafftools_user_team_path, team
    end

    def gh_stafftools_reconcile_team_path(team)
      expand_team :reconcile_stafftools_user_team_path, team
    end

    def gh_database_stafftools_team_path(team)
      expand_team :database_stafftools_user_team_path, team
    end

    def gh_members_stafftools_team_path(team)
      expand_team :members_stafftools_user_team_path, team
    end

    def gh_external_groups_stafftools_team_path(team)
      expand_team :external_groups_stafftools_user_team_path, team
    end

    def gh_repositories_stafftools_team_path(team)
      expand_team :repositories_stafftools_user_team_path, team
    end

    def gh_child_teams_stafftools_team_path(team)
      expand_team :child_teams_stafftools_user_team_path, team
    end

    def gh_requests_stafftools_team_path(team)
      expand_team :requests_stafftools_user_team_path, team
    end

    private

    def expand_team(helper, team)
      send(helper, team.organization, team)
    end

  end
end
