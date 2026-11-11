# typed: true
# frozen_string_literal: true

module Conduit
  module TopicFeed
    class Resources::OfficialRepo
      NUM_REPOS = 20

      def initialize(viewer:, topic:)
        @viewer = viewer
        @topic = topic
      end

      def collect
        return unless topic
        timer = Timer.start

        topic.repository || topic.alias_source_topic&.repository
      ensure
        GitHub.dogstats.distribution(
          "topic_feed_resource_collector.official_repo",
          timer.elapsed_ms,
        ) if timer
      end

      private

      attr_reader :viewer, :topic
    end
  end
end
