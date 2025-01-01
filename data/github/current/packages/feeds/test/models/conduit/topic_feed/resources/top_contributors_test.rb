# typed: true
# frozen_string_literal: true

require "test_helper"
require "explore_feed/feeds/kv"

module Conduit
  module TopicFeed
    class Resources::TopContributorsTest < GitHub::TestCase
      include DogstatsTestHelpers

      fixtures do
        @viewer = create(:user)
      end

      test "finds the top contributors for all repositories" do
        Flipper[:topic_feed_top_contributors_cache].disable

        topic = create(:topic)

        repo1 = create(:repository)
        repo1_user1 = create(:user)
        repo1_user2 = create(:user)

        create(:commit_contribution, repository: repo1, user: repo1_user1, commit_count: 5)
        create(:commit_contribution, repository: repo1, user: repo1_user2, commit_count: 3)

        repo2 = create(:repository)
        repo2_user1 = create(:user)
        repo2_user2 = create(:user)

        create(:commit_contribution, repository: repo2, user: repo2_user1, commit_count: 7)
        create(:commit_contribution, repository: repo2, user: repo2_user2, commit_count: 2)

        user_ids = Resources::TopContributors.stub_const(:NUM_CONTRIBUTORS, 1) do
          Resources::TopContributors.new(viewer: @viewer, repos: [repo1, repo2], topic: topic).collect
        end

        assert_equal 2, user_ids.size
        assert_includes user_ids, repo1_user1.id
        assert_includes user_ids, repo2_user1.id
        assert_dogstats_distribution(1, "topic_feed_resource_collector.contributors")
      end

      test "caches top contributors" do
        Flipper[:topic_feed_top_contributors_cache].enable

        topic = create(:topic)

        repo1 = create(:repository)
        repo1_user = create(:user)

        create(:commit_contribution, repository: repo1, user: repo1_user, commit_count: 5)

        repo2 = create(:repository)
        repo2_user = create(:user)

        create(:commit_contribution, repository: repo2, user: repo2_user, commit_count: 7)

        user_ids = Resources::TopContributors.new(
          viewer: @viewer, repos: [repo1, repo2], topic: topic,
        ).collect

        assert_equal 2, user_ids.size
        assert_includes user_ids, repo1_user.id
        assert_includes user_ids, repo2_user.id

        # rubocop:todo GitHub/DoNotUseGlobalKv
        from_cache = Feeds::KV.store.get("topic_feed:top_contributors:v1:#{topic.id}").value { nil }
        # rubocop:enable GitHub/DoNotUseGlobalKv
        refute_nil from_cache

        user_ids = from_cache.split(",").map(&:to_i)
        assert_includes user_ids, repo1_user.id
        assert_includes user_ids, repo2_user.id
      end

      test "skips cache when skip_cache is true" do
        Flipper[:topic_feed_top_contributors_cache].enable

        topic = create(:topic)
        Feeds::KV.store.set("topic_feed:top_contributors:v1:#{topic.id}", "1,2,3") # rubocop:todo GitHub/DoNotUseGlobalKv

        repo = create(:repository)
        user = create(:user)
        create(:commit_contribution, repository: repo, user: user, commit_count: 7)

        # rubocop:todo GitHub/DoNotUseGlobalKv
        from_cache = Feeds::KV.store.get("topic_feed:top_contributors:v1:#{topic.id}").value { nil }
        # rubocop:enable GitHub/DoNotUseGlobalKv
        assert_equal "1,2,3", from_cache

        user_ids = Resources::TopContributors.new(
          viewer: @viewer, repos: [repo], topic: topic, skip_cache: true
        ).collect

        assert_equal 1, user_ids.size
        assert_includes user_ids, user.id
      end
    end
  end
end
