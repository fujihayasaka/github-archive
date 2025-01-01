# typed: true
# frozen_string_literal: true

module Conduit
  module TopicFeed
    class Resources::TrendingDevelopers
      NUM_DEVS = 15
      PERIOD = "weekly"

      def initialize(viewer:, language:)
        @viewer = viewer
        @language = language
      end

      def collect
        return [] unless language
        timer = Timer.start

        user_ids
      ensure
        GitHub.dogstats.distribution(
          "topic_feed_resource_collector.trending_developers",
          timer.elapsed_ms,
        ) if timer
      end

      private

      attr_reader :viewer, :language

      def user_ids
        ExploreFeed::Trending::Developer.all(
          language: language.name,
          period: PERIOD,
          sponsorable: false,
          limit: NUM_DEVS,
        ).to_a.map(&:id)
      end
    end
  end
end
