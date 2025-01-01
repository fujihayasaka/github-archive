# typed: true
# frozen_string_literal: true

require "test_helper"

class CommentsTest < GitHub::TestCase
  fixtures do
    @comment = create(:issue_comment, body: "This is a comment")
  end

  test "update comment body" do
    assert_all_features_preloaded do
      Issues::Comments.update_comment(@comment, "This is a new comment", @comment.user)
    end

    assert_equal @comment.body, "This is a new comment"
  end

  def assert_all_features_preloaded
    FlipperSubscriber.collector.reset
    FlipperSubscriber.collector.enable

    yield

    FlipperSubscriber.collector.disable
    tested = FlipperSubscriber.tested_features.keys
    preloaded = FlipperSubscriber.preloaded_features

    tested_and_not_preloaded = tested - preloaded.to_a
    assert_empty tested_and_not_preloaded.sort, <<-MSG
      These features were checked but weren't preloaded.
    MSG
  end
end
