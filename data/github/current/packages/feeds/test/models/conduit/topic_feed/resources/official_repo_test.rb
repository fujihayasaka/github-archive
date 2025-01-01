# typed: true
# frozen_string_literal: true

require "test_helper"

module Conduit
  module TopicFeed
    class Resources::OfficialRepoTest < GitHub::TestCase
      include DogstatsTestHelpers

      fixtures do
        @viewer = create(:user)
      end

      test "finds the official topic repository" do
        repo = create(:repository)
        topic = create(:topic, github_url: "https://github.com/#{repo.owner.login}/#{repo.name}")

        found = Resources::OfficialRepo.new(viewer: @viewer, topic: topic).collect

        assert_equal repo, found
        assert_dogstats_distribution(1, "topic_feed_resource_collector.official_repo")
      end

      test "finds official repo through alias topic" do
        repo = create(:repository)
        source_topic = create(:topic, github_url: "https://github.com/#{repo.owner.login}/#{repo.name}")
        create(:topic_relation, topic: source_topic, name: "peppers", relation_type: :alias)
        topic = create(:topic, name: "peppers")

        assert_nil topic.repository

        found = Resources::OfficialRepo.new(viewer: @viewer, topic: topic).collect

        assert_equal repo, found
        assert_dogstats_distribution(1, "topic_feed_resource_collector.official_repo")
      end
    end
  end
end
