# typed: strict
# frozen_string_literal: true

require "test_helper"

class TopicStarrerTest < GitHub::TestCase
  context ".star" do
    test "it stars existing topics for the given user" do
      user = create(:user)
      curated_topic = create(:curated_topic, name: "curated")
      non_curated_topic = create(:topic, name: "non-curated")

      TopicStarrer.star(
        user: user,
        topics: %w[curated non-curated random],
        context: "test",
      )

      assert_equal 2, user.starred_topics_count
      assert curated_topic.starred_by?(user)
      assert non_curated_topic.starred_by?(user)
    end
  end
end
