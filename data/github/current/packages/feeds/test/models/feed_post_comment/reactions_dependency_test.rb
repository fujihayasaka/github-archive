# typed: true
# frozen_string_literal: true

require "test_helper"

class FeedPostComment::ReactionsDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user, :verified)
    @comment = create(:feed_post_comment, user: @user)
  end

  test "react" do
    assert_difference("@comment.reactions.count", 1) do
      @comment.react(actor: @user, content: "heart")
    end
  end

  test "unreact" do
    create(:reaction, user: @user, subject: @comment, content: "heart")
    assert_difference("@comment.reactions.count", -1) do
      @comment.unreact(actor: @user, content: "heart")
    end
  end
end
