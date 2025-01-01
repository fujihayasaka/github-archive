# typed: true
# frozen_string_literal: true

require "test_helper"

module Conduit
  module TopicFeed
    class Resources::StarredReposTest < GitHub::TestCase
      include DogstatsTestHelpers

      fixtures do
        @viewer = create(:user)
      end

      test "find topic repos starred by the viewer" do
        topic = create(:topic)
        topic_repo = create(:repository)
        not_topic_repo = create(:repository)
        create(:repository_topic, topic: topic, repository: topic_repo)

        @viewer.star(topic_repo)
        @viewer.star(not_topic_repo)

        repos = Resources::StarredRepos.new(viewer: @viewer, topic: topic).collect

        assert_equal 1, repos.count
        assert_includes repos, topic_repo
        assert_dogstats_distribution(1, "topic_feed_resource_collector.starred_repos")
      end

      test "returns an empty list when topic is nil" do
        topic = create(:topic)
        topic_repo = create(:repository)
        not_topic_repo = create(:repository)
        create(:repository_topic, topic: topic, repository: topic_repo)

        @viewer.star(topic_repo)
        @viewer.star(not_topic_repo)

        repos = Resources::StarredRepos.new(viewer: @viewer, topic: nil).collect

        assert_empty repos
      end
    end
  end
end
