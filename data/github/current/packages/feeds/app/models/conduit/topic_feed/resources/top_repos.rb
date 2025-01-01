# typed: true
# frozen_string_literal: true

module Conduit
  module TopicFeed
    class Resources::TopRepos
      NUM_REPOS = 15

      def initialize(viewer:, topic:, skip_cache: false)
        @viewer = viewer
        @topic = topic
        @skip_cache = skip_cache
      end

      def collect
        return [] unless topic && viewer
        timer = Timer.start

        if cache_enabled?
          top_repos_from_cache
        else
          top_repos_from_search
        end
      ensure
        GitHub.dogstats.distribution(
          "topic_feed_resource_collector.top_topic_repos",
          timer.elapsed_ms,
        ) if timer
      end

      private

      attr_reader :viewer, :topic, :skip_cache

      def top_repos_from_search
        result = topics_query.execute
        result.models.to_a
      end

      # It's expected that this class returns [Repository]. To make use of caching we'll
      # store the repo ids in the cache and then query for the repos in a single query.
      # This should still be significantly faster than the search query.
      def top_repos_from_cache
        repo_ids = Feeds::KV.store.get(cache_key).value { nil }

        if !repo_ids.blank?
          repo_ids = repo_ids.split(",").map(&:to_i)
          return Repository.where(id: repo_ids).to_a
        end

        repos = top_repos_from_search
        repo_ids = repos.map(&:id)
        ActiveRecord::Base.connected_to(role: :writing) do
          Feeds::KV.store.set(cache_key, repo_ids.join(","), expires: 1.hour.from_now)
        end

        # No need to look up repos if we have fresh results from search
        repos
      end

      def topics_query
        session = viewer.sessions.last
        ip = session&.ip

        Search::Queries::RepoQuery.new(
          current_user: viewer,
          user_session: session,
          remote_ip: ip,
          aggregations: true,
          phrase: "topic:#{topic.name} fork:true is:public",
          page: 1,
          per_page: NUM_REPOS,
          include_topics: true,
        )
      end

      def cache_key
        "topic_feed:top_repos:v1:#{topic.id}"
      end

      def cache_enabled?
        !skip_cache && FeatureFlag.vexi.enabled?(:topic_feed_top_repos_cache, viewer, default: false)
      end
    end
  end
end
