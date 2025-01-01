# typed: true
# frozen_string_literal: true

module Conduit
  module TopicFeed
    class Resources::TrendingRepos
      NUM_REPOS = 5
      PERIOD = "weekly"

      def initialize(viewer:, language:)
        @viewer = viewer
        @language = language
      end

      def collect
        return [] unless language
        timer = Timer.start

        ExploreFeed::Trending::Repository.all(
          language: language.name,
          period: PERIOD,
        ).limit(NUM_REPOS).to_a
      ensure
        GitHub.dogstats.distribution(
          "topic_feed_resource_collector.trending_repos",
          timer.elapsed_ms,
        ) if timer
      end

      private

      attr_reader :viewer, :language
    end
  end
end
