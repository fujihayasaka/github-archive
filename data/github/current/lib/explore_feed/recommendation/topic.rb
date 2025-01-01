# typed: true
# frozen_string_literal: true

module ExploreFeed
  module Recommendation
    class Topic
      CACHE_TIME_FORMAT = "%Y-%m-%e-%H"
      FALLBACK_TOPIC_RECOMMENDATION_SCORE = 1
      NUMBER_OF_FALLBACK_TOPIC_RECOMMENDATIONS = 100

      attr_reader :id, :name, :score

      delegate(
        :logo_url,
        :repositories,
        :safe_display_name,
        :short_description,
        :starred_by?,
        to: :original_topic,
      )

      class << self
        def all(for_user:)
          topics = raw_topic_recommendations(for_user.id).map do |attributes|
            new(attributes)
          end

          Collection.new(topics, for_user).sorted
        end

        private

        def raw_topic_recommendations(user_id)
          cache_key_time = DateTime.current.strftime(CACHE_TIME_FORMAT)
          cache_key = [
            "topic_recommendations",
            user_id,
            cache_key_time,
          ].join(".")

          GitHub.cache.fetch(cache_key) do
            GitHub.munger.topic_recommendations(user_id)&.dig("recommendations").presence || fallback_recommendations
          end
        end

        def fallback_recommendations
          ::Topic
            .popular_on_public_repositories(NUMBER_OF_FALLBACK_TOPIC_RECOMMENDATIONS)
            .pluck(:id, :name)
            .map do |topic_id, topic_name|
              {
                "id" => topic_id,
                "name" => topic_name,
                "score" => FALLBACK_TOPIC_RECOMMENDATION_SCORE,
              }
            end
        end
      end

      def initialize(attributes)
        @id = attributes["id"]
        @name = attributes["name"]
        @score = attributes["score"]
      end

      def repositories_sorted_by_stars(limit:)
        repositories
          .public_scope
          .limit(limit)
          .order(Repository.stargazer_count_column.to_sym => :desc)
      end

      private

      def original_topic
        ::Topic.find_by(id: id)
      end

      class Collection
        include Enumerable

        NUMBER_OF_EXTRA_TOPICS = 10

        def initialize(topics, user)
          @topics = topics
          @user = user
        end

        def each(&block)
          topics.each(&block)
        end

        def size
          topics.count
        end

        def sorted
          sorted_topics = topics
            .sort_by(&:score)
            .reverse
            .lazy

          self.class.new(sorted_topics, user)
        end

        def recommendable
          starred_topic_ids = user.starred_topics.where(id: topics.map(&:id)).pluck(:id)
          unstarred_topics = topics.select { |topic| !topic.id.in?(starred_topic_ids) }

          self.class.new(unstarred_topics, user)
        end

        def spotlight
          self.class.new(topics, user).recommendable.first
        end

        def non_spotlight
          non_spotlight_topics = self.class.new(topics, user)
            .recommendable
            .first(NUMBER_OF_EXTRA_TOPICS)
            .to_a[1..-1]

          self.class.new(non_spotlight_topics || [], user)
        end

        private

        attr_accessor :topics
        attr_reader :user
      end
    end
  end
end
