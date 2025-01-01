# typed: true
# frozen_string_literal: true

require "test_helper"

module Conduit
  class TopicFeed::ResourcesCollectorTest < GitHub::TestCase
    include DogstatsTestHelpers

    fixtures do
      @user = create(:user)
    end

    test "applies buckets" do
      create(:ruby_language_name)
      user1 = create(:user)
      user2 = create(:user, :sponsorable)
      ExploreFeed::Trending::Developer.stubs(raw_trending_developers: [
        { "user_id" => user1.id },
        { "user_id" => user2.id },
      ])

      topic = create(:topic, name: "ruby")
      c = Conduit::TopicFeed::ResourcesCollector.new(viewer: @user, topic: topic)
      c.to_s # collect resources

      assert_equal c.buckets["user:#{user1.id}"], :trending_developer
      assert_equal c.buckets["user:#{user2.id}"], :trending_developer
    end

    test "#empty? is true when there are no resources" do
      c = Conduit::TopicFeed::ResourcesCollector.new(viewer: @user, topic: nil)
      assert_predicate c, :empty?
    end
  end
end
