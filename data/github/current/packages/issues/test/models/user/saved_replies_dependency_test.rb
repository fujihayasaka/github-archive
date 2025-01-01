# typed: true
# frozen_string_literal: true

require "test_helper"

class UserSavedRepliesTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
  end

  context "#available_saved_replies" do
    test "returns default issue replies when user has no saved replies" do
      replies = @user.available_saved_replies(context: :issue)

      assert_equal ["Duplicate issue"], replies.map(&:title)
    end

    test "returns default issue replies and saved replies for user" do
      create(:saved_reply, user: @user, title: "Best Ever Reply")
      replies = @user.available_saved_replies(context: :issue)

      assert_equal ["Best Ever Reply", "Duplicate issue"],
        replies.map(&:title)
    end

    test "returns default PR replies when user has no saved replies" do
      replies = @user.available_saved_replies(context: :pull_request)

      assert_equal ["Fixes issue"], replies.map(&:title)
    end

    test "returns default PR replies and saved replies for user" do
      create(:saved_reply, user: @user, title: "Friendly Reply")
      replies = @user.available_saved_replies(context: :pull_request)

      assert_equal ["Fixes issue", "Friendly Reply"], replies.map(&:title)
    end
  end
end
