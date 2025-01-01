# typed: true
# frozen_string_literal: true

require "test_helper"

module Conduit
  module TopicFeed
    class Resources::TrendingDevelopersTest < GitHub::TestCase
      include DogstatsTestHelpers

      fixtures do
        @viewer = create(:user)
      end

      test "finds trending developers when a language is present" do
        language = create(:ruby_language_name)

        user1 = create(:user)
        user2 = create(:user, :sponsorable)
        ExploreFeed::Trending::Developer.stubs(raw_trending_developers: [
          { "user_id" => user1.id },
          { "user_id" => user2.id },
        ])

        user_ids = Resources::TrendingDevelopers.new(viewer: @viewer, language: language).collect

        assert_equal 2, user_ids.count
        assert_dogstats_distribution(1, "topic_feed_resource_collector.trending_developers")
      end

      test "returns an empty list when language is nil" do
        user1 = create(:user)
        user2 = create(:user)
        ExploreFeed::Trending::Developer.stubs(raw_trending_developers: [
          { "user_id" => user1.id },
          { "user_id" => user2.id },
        ])

        user_ids = Resources::TrendingDevelopers.new(viewer: @viewer, language: nil).collect

        assert_empty user_ids
      end
    end
  end
end
