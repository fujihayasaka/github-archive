# typed: true
# frozen_string_literal: true

require "test_helper"

class GitHubUserContentEditTest < GitHub::TestCase
  fixtures do
    @user_content_edit = create(:user_content_edit)
    @gist_comment = create(:gist_comment, body: "body")
    @gist_comment.update_body("new body", @gist_comment.user)
    # second edit is technically the actual change since the first
    # is for history display purposes only
    @gist_comment_edit = @gist_comment.user_content_edits[1]
  end

  test "has global_relay_id" do
    id = Platform::Helpers::NodeIdentification.from_global_id(@user_content_edit.legacy_global_id)
    refute_nil id
    refute id.last.include?(":")
  end

  test "has special gist comment edit global_relay_id" do
    id = Platform::Helpers::NodeIdentification.from_global_id(@gist_comment_edit.legacy_global_id)
    refute_nil id
    assert id.last.include?(":")
  end

  test "#soft_delete!" do
    user = create(:user)
    events = subscribe "user_content_edit.delete"

    Timecop.freeze do
      expected_payload = {
        user_content_type: "GistComment",
        user_content_id: @gist_comment.id,
        editor: @gist_comment.user.login,
        editor_id: @gist_comment.user.id,
        deleted_by: user.login,
        deleted_by_id: user.id,
        deleted_content: "new body",
      }

      @gist_comment_edit.soft_delete!(user)

      assert event = events.pop, "an event was expected"
      assert_same_time Time.zone.now, event.payload.delete(:deleted_at)
      assert_equal expected_payload, event.payload
      assert_equal @gist_comment_edit.deleted_by, user
      refute_nil @gist_comment_edit.deleted_at
    end
  end

  test "#diff_before" do
    assert_equal "new body", @gist_comment_edit.diff
    assert_equal "body", @gist_comment_edit.diff_before
    @gist_comment.update_body("newer body", @gist_comment.user)
    assert_equal "body", @gist_comment_edit.diff_before
  end

  test "isn't created when no changes are made" do
    old_body = @gist_comment.body
    old_count = @gist_comment.user_content_edits.count
    @gist_comment.update_body(old_body, @gist_comment.user)
    assert_equal old_count, @gist_comment.user_content_edits.count # no new edit records
  end

  context "#safe_diff" do
    test "returns the valid body" do
      assert_equal @gist_comment_edit.diff, @gist_comment_edit.safe_diff
    end

    test "encodes emoji correctly" do
      string = "😉".b
      @gist_comment_edit.update_attribute(:diff, string)
      assert_equal Encoding::ASCII_8BIT, @gist_comment_edit.diff.encoding
      assert_equal Encoding::UTF_8, @gist_comment_edit.safe_diff.encoding
    end
  end


end
