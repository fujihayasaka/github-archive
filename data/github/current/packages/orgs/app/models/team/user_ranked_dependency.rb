# typed: true
# frozen_string_literal: true

module Team::UserRankedDependency
  extend ActiveSupport::Concern

  include UserRanked::Scope

  USER_RANKED_WEIGHT = {
    team_discussions_created: 1,
    team_reviews_fulfilled: 1,
    team_reviews_requested: 1,
  }.freeze

  class_methods do
    def compute_ranked_ids(user:)
      UserActivityRankCalculator.calculate(user: user)
    end
  end

  class UserActivityRankCalculator
    ACTIVITY_TIME_WINDOW = 12.months

    def self.calculate(args)
      new(**args).calculate
    end

    def initialize(user:)
      @since = ACTIVITY_TIME_WINDOW.ago
      @team_ids = user.teams(with_ancestors: false).pluck(:id)
      @user = user
    end

    def calculate
      team_ids.sort_by do |team_id|
        USER_RANKED_WEIGHT.keys.sum do |ranking_type|
          ranking_type_score(ranking_type, team_id: team_id)
        end
      end.reverse
    end

    private

    attr_reader :organization, :since, :team_ids, :user

    def ranking_type_score(ranking_type, team_id:)
      weight = USER_RANKED_WEIGHT.fetch(ranking_type)
      send(ranking_type).fetch(team_id, 0) * weight
    end

    def team_reviews_requested
      return @team_reviews_requested if defined?(@team_reviews_requested)

      @team_reviews_requested = team_review_requests
        .joins(:pull_request)
        .where(pull_requests: { user_id: user.id })
        .where("review_requests.created_at >= ?", since)
        .group(:reviewer_id)
        .count
    end

    def team_reviews_fulfilled
      return @team_reviews_fulfilled if defined?(@team_reviews_fulfilled)

      # Returns a hash of team id => # of review requests fulfilled for that team
      # Get all requests for these teams with a review from this user
      @team_reviews_fulfilled = team_review_requests
          .joins(:pull_request_reviews)
          .where(pull_request_reviews: { user_id: user.id })
          .where("pull_request_reviews.submitted_at >= ?", since)
          .group(:reviewer_id)
          .count
    end

    def team_review_requests
      ReviewRequest.where(reviewer_type: "Team", reviewer_id: team_ids)
    end

    def team_discussions_created
      return @team_discussions_created if defined?(@team_discussions_created)

      @team_discussions_created = DiscussionPost
        .where(team: team_ids, user_id: user.id)
        .where("created_at >= ?", since)
        .group(:team_id)
        .count
    end
  end
end
