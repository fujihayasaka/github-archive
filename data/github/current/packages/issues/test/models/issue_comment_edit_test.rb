# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueCommentEditTest < GitHub::TestCase
  fixtures do
    @issue_comment = create(:issue_comment, body: "old body")
    @issue_comment.update_body("new body", @issue_comment.user)

    @issue_comment_edit = IssueCommentEdit.where(issue_comment: @issue_comment).last
    T.must(@issue_comment_edit).update(user_content_edit_id: nil)

    @legacy_issue_comment = create(:issue_comment, body: "old body")
    @legacy_issue_comment.update_body("new body", @legacy_issue_comment.user)

    @legacy_issue_comment_edit = IssueCommentEdit.where(issue_comment: @legacy_issue_comment).last
    T.must(@legacy_issue_comment_edit).update_column(:user_content_edit_id, 1337)
  end

  context "#global_relay_id" do
    test "for a non-legacy edit" do
      id = Platform::Helpers::NodeIdentification.from_global_id(@issue_comment_edit.global_relay_id)
      if Platform::Objects::UserContentEdit.use_next_id?(@issue_comment_edit)
        assert_equal id, ["UserContentEdit", @issue_comment_edit.id]
      else
        assert_equal id, ["UserContentEdit", "IssueCommentEdit:#{@issue_comment_edit.id}"]
      end
    end

    test "for a legacy edit" do
      id = Platform::Helpers::NodeIdentification.from_global_id(@legacy_issue_comment_edit.global_relay_id)
      if Platform::Objects::UserContentEdit.use_next_id?(@issue_comment_edit)
        assert_equal id, ["UserContentEdit", @legacy_issue_comment_edit.id]
      else
        assert_equal id, ["UserContentEdit", "#{@legacy_issue_comment_edit.user_content_edit_id}"]
      end
    end
  end

  test "#soft_delete!" do
    user = create(:user)
    events = subscribe "user_content_edit.delete"

    Timecop.freeze do
      expected_payload = {
        user_content_type: "IssueComment",
        user_content_id: @issue_comment.id,
        editor: @issue_comment_edit.editor.login,
        editor_id: @issue_comment_edit.editor.id,
        deleted_by: user.login,
        deleted_by_id: user.id,
        deleted_content: "new body",
      }

      @issue_comment_edit.soft_delete!(user)

      assert event = events.pop, "an event was expected"
      assert_same_time Time.zone.now, event.payload.delete(:deleted_at)
      assert_equal expected_payload, event.payload
      assert_equal @issue_comment_edit.deleted_by, user
      refute_nil @issue_comment_edit.deleted_at
    end
  end

  test "#diff_before" do
    assert_equal "new body", @issue_comment_edit.diff
    assert_equal "old body", @issue_comment_edit.diff_before

    @issue_comment.update_body("newer body", @issue_comment.user)
    assert_equal "new body", T.must(IssueCommentEdit.where(issue_comment: @issue_comment).last).diff_before
  end

  test "isn't created when no changes are made" do
    old_body = @issue_comment.body

    assert_no_difference(-> { IssueCommentEdit.count }, -> { UserContentEdit.count }) do
      @issue_comment.update_body(old_body, @issue_comment.user)
    end
  end

  context "#safe_diff" do
    test "returns the valid body" do
      assert_equal @issue_comment_edit.diff, @issue_comment_edit.safe_diff
    end

    test "encodes emoji correctly" do
      string = "😉".b
      @issue_comment_edit.update_attribute(:diff, string)
      assert_equal Encoding::ASCII_8BIT, @issue_comment_edit.diff.encoding
      assert_equal Encoding::UTF_8, @issue_comment_edit.safe_diff.encoding
    end
  end

  context "assigning a diff" do
    test "assigning a diff also assigns a compressed_diff" do
      new_diff = "this is the new diff"
      @issue_comment_edit.diff = new_diff

      assert_equal new_diff, @issue_comment_edit.compressed_diff
      assert @issue_comment_edit.save
      @issue_comment_edit.reload
      assert_equal new_diff, @issue_comment_edit.diff
      assert_equal new_diff, @issue_comment_edit.compressed_diff
    end
  end

  test "copies `repository_id` from the `issue_comment` during create" do
    issue_comment_edit = IssueCommentEdit.create(issue_comment: @issue_comment, editor: @issue_comment.user, edited_at: Time.current)

    refute_nil issue_comment_edit.repository_id
    assert_equal issue_comment_edit.repository_id, @issue_comment.repository_id
  end
end
