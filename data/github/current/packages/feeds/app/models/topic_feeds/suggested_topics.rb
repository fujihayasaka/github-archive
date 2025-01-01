# typed: true
# frozen_string_literal: true

module TopicFeeds
  class SuggestedTopics
    extend T::Sig

    # topic ids determined in https://github.com/github/feeds/issues/1874
    PRESET_TOPIC_IDS = [
      12,
      40,
      45,
      56,
      67,
      84,
      107,
      118,
      160,
      194,
      203,
      242,
      300,
      621,
      743,
      12641,
      21623,
      22808,
      217896,
      1857396
    ]

    sig { params(topics: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
    def self.for_topic_feeds(topics)
      topics.where(id: TopicFeeds::SuggestedTopics::PRESET_TOPIC_IDS)
    end
  end
end
