# typed: true
# frozen_string_literal: true

module PullRequests::TimelineEvents
  class TeamLinkComponent < ApplicationComponent
    attr_reader :team

    def initialize(team:)
      @team = team
    end

    # Ported from Platform::Objects::Team
    def resource_path
      team.async_organization.then do |org|
        "/orgs/#{org.display_login}/teams/#{team.slug}"
      end.sync
    end
  end
end
