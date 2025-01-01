# typed: true
# frozen_string_literal: true

require "test_helper"

module Conduit
  class TopicFeedResourceCollectorTest < GitHub::TestCase
    test "builds an instance of Conduit::TopicFeedResourceCollector from params" do
      travel_to(Time.now) do
        params = {
          top_repos: 10,
          trending_developers: 8,
          trending_developers_since: "daily",
        }
        c = Conduit::TopicFeedResourceCollectorConfiguration.from_params(params)
        assert_equal 10, c.top_repos_count
        assert_equal 8, c.trending_developers_count
        assert_equal "daily", c.trending_developers_since
      end
    end

    test "builds with default values when params are empty" do
      c = Conduit::TopicFeedResourceCollectorConfiguration.from_params({})
      assert_equal TopicFeed::Resources::TopRepos::NUM_REPOS, c.top_repos_count
      assert_equal TopicFeed::Resources::TrendingDevelopers::NUM_DEVS, c.trending_developers_count
      assert_equal "daily", c.trending_developers_since
    end
  end
end
