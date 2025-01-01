# typed: false
# frozen_string_literal: true

module User::PinnedFeedsDependency
  extend ActiveSupport::Concern

  MAX_STARRED_TOPICS = 25

  included do
    has_many :pinned_feeds, inverse_of: :user
  end

  def pinned_topics
    TopicFeeds::SuggestedTopics.for_topic_feeds(starred_topics).limit(MAX_STARRED_TOPICS)
  end

  def pin_feed(topic)
    pinned_feeds.create(topic: topic)
  end

  def unpin_feed(pinned_feed)
    pinned_feed.destroy
  end
end
