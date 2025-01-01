# typed: true
# frozen_string_literal: true

require "test_helper"
require "explore_feed/feeds/kv"

module Conduit
  module TopicFeed
    class Resources::TopReposTest < GitHub::TestCase
      include DogstatsTestHelpers

      fixtures do
        @viewer = create(:user)
      end

      test "finds top repositories for a given topic" do
        repo = create(:repository)
        topic = create(:topic)
        create(:repository_topic, topic: topic, repository: repo)
        create(:user_session, user: @viewer)

        make_searchable repo

        repos = Resources::TopRepos.new(
          viewer: @viewer,
          topic: topic,
        ).collect

        assert_equal 1, repos.count
        assert_includes repos, repo
        assert_dogstats_distribution(1, "topic_feed_resource_collector.top_topic_repos")
      end

      test "caches top repositories" do
        Flipper[:topic_feed_top_repos_cache].enable

        repo = create(:repository)
        topic = create(:topic)
        create(:repository_topic, topic: topic, repository: repo)
        session = create(:user_session, user: @viewer)

        make_searchable repo

        repos = Resources::TopRepos.new(
          viewer: @viewer,
          topic: topic,
        ).collect

        assert_equal 1, repos.size
        assert_includes repos, repo

        # rubocop:todo GitHub/DoNotUseGlobalKv
        from_cache = Feeds::KV.store.get("topic_feed:top_repos:v1:#{topic.id}").value { nil }
        # rubocop:enable GitHub/DoNotUseGlobalKv
        refute_nil from_cache

        repo_ids = from_cache.split(",").map(&:to_i)
        assert_includes repo_ids, repo.id
      end

      test "skips the cache when skip_cache is true" do
        Flipper[:topic_feed_top_repos_cache].enable

        topic = create(:topic)
        repo = create(:repository)
        create(:repository_topic, topic: topic, repository: repo)
        create(:user_session, user: @viewer)

        Feeds::KV.store.set("topic_feed:top_repos:v1:#{topic.id}", "1,2,3") # rubocop:todo GitHub/DoNotUseGlobalKv
        # rubocop:todo GitHub/DoNotUseGlobalKv
        from_cache = Feeds::KV.store.get("topic_feed:top_repos:v1:#{topic.id}").value { nil }
        # rubocop:enable GitHub/DoNotUseGlobalKv
        assert_equal "1,2,3", from_cache

        make_searchable repo

        repos = Resources::TopRepos.new(
          viewer: @viewer,
          topic: topic,
          skip_cache: true,
        ).collect

        assert_equal 1, repos.size
        assert_includes repos, repo
      end
    end
  end
end
