# typed: true
# frozen_string_literal: true

module UserHovercard::Contexts
  class OrganizationTeams < Hovercard::Contexts::Base
    attr_reader :organization, :user

    def initialize(user:, all:, organization:)
      @user = user
      @all = all
      @organization = organization
    end

    def total_team_count
      all.count
    end

    def message
      team_text = hovercard_sentence(highlighted, max: 3, total: all.count) do |team|
        "@#{team.combined_slug}"
      end

      "Member of #{team_text}"
    end

    def highlighted
      T.unsafe(Team).ranked_for(user, scope: all)
    end

    def octicon
      "people"
    end

    def platform_type_name
      "OrganizationTeamsHovercardContext"
    end

    def more_teams_query_value
      # Use User#display_login because this query value will be used in Organization#team_search_for_user which calls
      # User#find_by_login:
      "@#{user.display_login}"
    end

    private

    attr_reader :all
  end
end
