# typed: true
# frozen_string_literal: true

module Conduit
  class TopicFeedResourceCollectorConfiguration
    def self.from_params(params)
      new(
        top_repos: params[:top_repos] || Conduit::TopicFeed::Resources::TopRepos::NUM_REPOS,
        trending_developers: params[:trending_developers] || Conduit::TopicFeed::Resources::TrendingDevelopers::NUM_DEVS,
        trending_developers_since: params[:trending_developers_since] || "daily",
      )
    end

    def initialize(top_repos:, trending_developers:, trending_developers_since:)
      @top_repos = top_repos
      @trending_developers = trending_developers
      @trending_developers_since = trending_developers_since
    end

    def top_repos_count
      @top_repos.to_i
    end

    def trending_developers_count
      @trending_developers.to_i
    end

    def trending_developers_since
      @trending_developers_since == "Since" ? "daily" : @trending_developers_since
    end

    def trending_developers_daily?
      trending_developers_since == "daily"
    end

    def trending_developers_weekly?
      trending_developers_since == "weekly"
    end

    def trending_developers_monthly?
      trending_developers_since == "monthly"
    end

    def to_params
      {
        top_repos: @top_repos,
        trending_developers: @trending_developers,
        trending_developers_since: @trending_developers_since,
      }
    end
  end
end
