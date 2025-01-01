# typed: true
# frozen_string_literal: true

module Conduit
  module TopicFeed
    class Resources::StarredRepos
      NUM_REPOS = 20

      def initialize(viewer:, topic:)
        @viewer = viewer
        @topic = topic
      end

      def collect
        return [] unless topic
        timer = Timer.start

        viewer
          .starred_repositories
          .joins(:repository_topics)
          .where("repository_topics.topic_id = ?", topic.id)
          .limit(NUM_REPOS)
          .to_a
      ensure
        GitHub.dogstats.distribution(
          "topic_feed_resource_collector.starred_repos",
          timer.elapsed_ms,
        ) if timer
      end

      private

      attr_reader :viewer, :topic
    end
  end
end
