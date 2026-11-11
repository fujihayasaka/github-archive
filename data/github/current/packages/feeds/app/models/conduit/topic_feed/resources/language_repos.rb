# typed: true
# frozen_string_literal: true

module Conduit
  module TopicFeed
    class Resources::LanguageRepos
      NUM_REPOS = 15

      def initialize(viewer:, language:)
        @viewer = viewer
        @language = language
      end

      def collect
        return [] unless language
        timer = Timer.start

        Repository
          .with_language(language)
          .public_scope
          .most_starred
          .limit(NUM_REPOS)
          .to_a
      ensure
        GitHub.dogstats.distribution(
          "topic_feed_resource_collector.top_language_repos",
          timer.elapsed_ms,
        ) if timer
      end

      private

      attr_reader :viewer, :language
    end
  end
end
