# typed: true
# frozen_string_literal: true

module PullRequests::TimelineEvents
  class ReviewerLinkComponent < ApplicationComponent
    attr_reader :reviewer, :team_name

    def initialize(reviewer:, team_name:)
      @reviewer = reviewer
      @team_name = team_name
    end

    def call
      case reviewer
      when User, Mannequin
        render PullRequests::TimelineEvents::UserLinkComponent.new(user: reviewer)
      when Team
        render PullRequests::TimelineEvents::TeamLinkComponent.new(team: reviewer)
      else
        if team_name
          content_tag(:span, class: "Link--primary text-bold") { team_name }
        else
          ""
        end
      end
    end
  end
end
