# typed: true
# frozen_string_literal: true

require "test_helper"

module Conduit
  class TopicFeedItemDecoratorTest < GitHub::TestCase
    test "applies a repository label" do
      item = build(:discussion_feed_item)
      buckets = { "repo:#{item.repository.id}" => :top_repository }
      Conduit::TopicFeedItemDecorator.apply_bucket_labels([item], buckets)
      assert_equal "Top repository", item.label
    end

    test "applies a user label" do
      item = build(:discussion_feed_item)
      buckets = { "user:#{item.actor.id}" => :top_contributor }
      Conduit::TopicFeedItemDecorator.apply_bucket_labels([item], buckets)
      assert_equal "Top contributor", item.label
    end

    test "nil when no label is found" do
      item = build(:discussion_feed_item)
      Conduit::TopicFeedItemDecorator.apply_bucket_labels([item], {})
      assert_nil item.label
    end
  end
end
