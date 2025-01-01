# typed: true
# frozen_string_literal: true

require "test_helper"

class FeedPost::ReactionsDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user, :verified)
    @post = create(:feed_post, author: @user)
  end

  context "react" do
    test "creates a reaction" do
      assert_difference("@post.reactions.count", 1) do
        @post.react(actor: @user, content: "heart")
      end
    end
  end

  context "unreact" do
    test "destroys a reaction" do
      create(:reaction, user: @user, subject: @post, content: "heart")
      assert_difference("@post.reactions.count", -1) do
        @post.unreact(actor: @user, content: "heart")
      end
    end
  end
end
