# typed: true
# frozen_string_literal: true

require "explore_feed/feeds/kv"

module Conduit
  module TopicFeed
    class Resources::TopContributors
      NUM_CONTRIBUTORS = 3
      IGNORED_LOGINS = %w[
        renovate-bot
        camperbot
        engine-flutter-autoroll
        fluttergithubbot
      ].freeze

      def initialize(viewer:, repos:, topic:, skip_cache: false)
        @viewer = viewer
        @repos = repos
        @topic = topic

        @skip_cache = skip_cache
      end

      def collect
        return [] if repos.empty?
        return [] if topic.nil?

        timer = Timer.start

        if cache_enabled?
          top_contributor_ids_from_cache
        else
          top_contributor_ids
        end
      ensure
        GitHub.dogstats.distribution(
          "topic_feed_resource_collector.contributors",
          timer.elapsed_ms,
        ) if timer
      end

      private

      attr_reader :viewer, :repos, :topic, :skip_cache

      def top_contributor_ids
        candidates = repos.map do |repo|
          repo.top_contributors(
            limit: NUM_CONTRIBUTORS,
            viewer: viewer,
            skip_bots: true,
          )
        end.flatten

        candidates = candidates
          .reject { |c| IGNORED_LOGINS.include?(c.display_login) }
          .uniq
          .map(&:id)
      end

      def top_contributor_ids_from_cache
        user_ids = Feeds::KV.store.get(cache_key).value { nil }
        if user_ids.blank?
          user_ids = top_contributor_ids
          ActiveRecord::Base.connected_to(role: :writing) do
            Feeds::KV.store.set(cache_key, user_ids.join(","), expires: 1.hour.from_now)
          end
        else
          user_ids = user_ids.split(",").map(&:to_i)
        end

        user_ids
      end

      def cache_key
        "topic_feed:top_contributors:v1:#{topic.id}"
      end

      def cache_enabled?
        !skip_cache && GitHub.flipper[:topic_feed_top_contributors_cache].enabled?(viewer)
      end
    end
  end
end
