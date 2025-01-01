# typed: true
# frozen_string_literal: true

require "test_helper"

class CommitCommentEditTest < GitHub::TestCase
  fixtures do
    @commit_comment = create(:commit_comment, body: "old body")
    @commit_comment.update_body("new body", @commit_comment.user)

    @commit_comment_edit = CommitCommentEdit.where(commit_comment: @commit_comment).last
    T.must(@commit_comment_edit).update(user_content_edit_id: nil)

    @legacy_commit_comment = create(:commit_comment, body: "old body")
    @legacy_commit_comment.update_body("new body", @legacy_commit_comment.user)

    @legacy_commit_comment_edit = CommitCommentEdit.where(commit_comment: @legacy_commit_comment).last
    T.must(@legacy_commit_comment_edit).update_column(:user_content_edit_id, 1337)
  end

  context "#global_relay_id" do
    test "for a non-legacy edit" do
      id = Platform::Helpers::NodeIdentification.from_global_id(@commit_comment_edit.global_relay_id)
      if Platform::Objects::UserContentEdit.use_next_id?(@commit_comment_edit)
        assert_equal id, ["UserContentEdit", @commit_comment_edit.id]
      else
        assert_equal id, ["UserContentEdit", "CommitCommentEdit:#{@commit_comment_edit.id}"]
      end
    end

    test "for a legacy edit" do
      id = Platform::Helpers::NodeIdentification.from_global_id(@legacy_commit_comment_edit.global_relay_id)
      if Platform::Objects::UserContentEdit.use_next_id?(@legacy_commit_comment_edit)
        assert_equal id, ["UserContentEdit", @legacy_commit_comment_edit.id]
      else
        assert_equal id, ["UserContentEdit", "#{@legacy_commit_comment_edit.user_content_edit_id}"]
      end
    end
  end

  test "#soft_delete!" do
    user = create(:user)
    events = subscribe "user_content_edit.delete"

    Timecop.freeze do
      expected_payload = {
        user_content_type: "CommitComment",
        user_content_id: @commit_comment.id,
        editor: @commit_comment_edit.editor.login,
        editor_id: @commit_comment_edit.editor.id,
        deleted_by: user.login,
        deleted_by_id: user.id,
        deleted_content: "new body",
      }

      @commit_comment_edit.soft_delete!(user)

      assert event = events.pop, "an event was expected"
      assert_same_time Time.zone.now, event.payload.delete(:deleted_at)
      assert_equal expected_payload, event.payload
      assert_equal @commit_comment_edit.deleted_by, user
      refute_nil @commit_comment_edit.deleted_at
    end
  end

  test "#diff_before" do
    assert_equal "new body", @commit_comment_edit.diff
    assert_equal "old body", @commit_comment_edit.diff_before

    @commit_comment.update_body("newer body", @commit_comment.user)
    assert_equal "new body", T.must(CommitCommentEdit.where(commit_comment: @commit_comment).last).diff_before
  end

  test "isn't created when no changes are made" do
    old_body = @commit_comment.body

    assert_no_difference(-> { CommitCommentEdit.count }, -> { UserContentEdit.count }) do
      @commit_comment.update_body(old_body, @commit_comment.user)
    end
  end

  context "#safe_diff" do
    test "returns the valid body" do
      assert_equal @commit_comment_edit.diff, @commit_comment_edit.safe_diff
    end

    test "encodes emoji correctly" do
      string = "😉".b
      @commit_comment_edit.update_attribute(:diff, string)
      assert_equal Encoding::ASCII_8BIT, @commit_comment_edit.diff.encoding
      assert_equal Encoding::UTF_8, @commit_comment_edit.safe_diff.encoding
    end
  end

  test "copies `repository_id` from the `commit_comment` during create" do
    commit_comment_edit = CommitCommentEdit.create(commit_comment: @commit_comment, editor: @commit_comment.user, edited_at: Time.current)

    refute_nil commit_comment_edit.repository_id
    assert_equal commit_comment_edit.repository_id, @commit_comment.repository_id
  end
end
