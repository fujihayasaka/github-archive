# typed: true
# frozen_string_literal: true

module Suggester
  class RepositoryAdvisorySuggester
    def initialize(viewer:, repository:, advisory:)
      @viewer = viewer
      @repository = repository
      @advisory = advisory
    end

    def users
      users =
        if @advisory
          @advisory.mentionable_users_for(@viewer)
        else
          User.where(id: @repository.admin_ids)
        end
      users = users.to_a
      GitHub::PrefillAssociations.prefill_associations(
        users, [:profile, { user_status: :organization }]
      )
      format = Suggester::UserSerializer.new(viewer: @viewer)
      users.map(&format)
    end

    def team_members
      team_members =
        if @advisory
          @advisory
            .mentionable_users_from_teams_for(@viewer)
        else
          []
        end
      team_members = team_members.to_a
      GitHub::PrefillAssociations.prefill_associations(
        team_members, [:profile, { user_status: :organization }]
      )
      format = Suggester::UserSerializer.new(viewer: @viewer)
      team_members.map(&format)
    end

    def teams
      teams =
        if @advisory
          @advisory.collaborating_teams_visible_to_user(@viewer)
        else
          []
        end
      format = Suggester::TeamSerializer.new
      teams.map(&format)
    end

    def mentions
      users + team_members + teams
    end

    def issues
      @repository.issues.suggestions.not_spammy
    end
  end
end
