# typed: true
# frozen_string_literal: true

require "test_helper"

class TopicFeeds::SuggestedTopicsTest < GitHub::TestCase
  test ".for_topic_feeds" do
    TopicFeeds::SuggestedTopics::PRESET_TOPIC_IDS.each { |id| create(:topic, id: id) }
    other_topic = create(:topic)
    scoped_ids = TopicFeeds::SuggestedTopics.for_topic_feeds(Topic.all).pluck(:id)
    assert_same_elements scoped_ids, TopicFeeds::SuggestedTopics::PRESET_TOPIC_IDS
    refute_includes scoped_ids, other_topic.id
  end
end
