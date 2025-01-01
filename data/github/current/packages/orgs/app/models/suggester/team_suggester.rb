# typed: true
# frozen_string_literal: true

module Suggester
  class TeamSuggester
    def initialize(viewer:, team:, cap_filter: nil)
      @viewer = viewer
      @org = team.organization
      @cap_filter = cap_filter
    end

    def mentions
      format = Suggester::MentionSerializer.new(viewer: @viewer)
      format.dump(users, teams)
    end

    private

    def suggested_users
      filter = BlockedUserFilter.new(viewer: @viewer)
      @org.members.includes(:profile).reject(&filter)
    end

    def suggested_teams
      @org.visible_teams_for(@viewer)
    end

    def users
      suggested = @cap_filter.authorized_resources(suggested_users)

      GitHub::PrefillAssociations.prefill_associations(suggested, { user_status: :organization })
      suggested
    end

    def teams
      @cap_filter.authorized_resources(suggested_teams)
    end
  end
end
