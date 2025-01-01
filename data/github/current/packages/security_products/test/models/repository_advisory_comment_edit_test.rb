# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryAdvisoryCommentEditTest < GitHub::TestCase
  fixtures do
    @repository_advisory_comment = create(:repository_advisory_comment, body: "old body")
    @repository_advisory_comment.update_body("new body", @repository_advisory_comment.user)

    @repository_advisory_comment_edit = RepositoryAdvisoryCommentEdit.where(repository_advisory_comment: @repository_advisory_comment).last
    T.must(@repository_advisory_comment_edit).update(user_content_edit_id: nil)

    @legacy_repository_advisory_comment = create(:repository_advisory_comment, body: "old body")
    @legacy_repository_advisory_comment.update_body("new body", @legacy_repository_advisory_comment.user)

    @legacy_repository_advisory_comment_edit = RepositoryAdvisoryCommentEdit.where(repository_advisory_comment: @legacy_repository_advisory_comment).last
    T.must(@legacy_repository_advisory_comment_edit).update_column(:user_content_edit_id, 1337)
  end

  context "#global_relay_id" do
    test "for a non-legacy edit" do
      id = Platform::Helpers::NodeIdentification.from_global_id(@repository_advisory_comment_edit.global_relay_id)
      if Platform::Objects::UserContentEdit.use_next_id?(@repository_advisory_comment_edit)
        assert_equal ["UserContentEdit", @repository_advisory_comment_edit.id], id
      else
        assert_equal ["UserContentEdit", "RepositoryAdvisoryCommentEdit:#{@repository_advisory_comment_edit.id}"], id
      end
    end

    test "for a legacy edit" do
      id = Platform::Helpers::NodeIdentification.from_global_id(@legacy_repository_advisory_comment_edit.global_relay_id)
      if Platform::Objects::UserContentEdit.use_next_id?(@legacy_repository_advisory_comment_edit)
        assert_equal ["UserContentEdit", @legacy_repository_advisory_comment_edit.id], id
      else
        assert_equal ["UserContentEdit", "#{@legacy_repository_advisory_comment_edit.user_content_edit_id}"], id
      end
    end
  end

  test "#soft_delete!" do
    user = create(:user)
    events = subscribe "user_content_edit.delete"

    Timecop.freeze do
      expected_payload = {
        user_content_type: "RepositoryAdvisoryComment",
        user_content_id: @repository_advisory_comment.id,
        editor: @repository_advisory_comment_edit.editor.login,
        editor_id: @repository_advisory_comment_edit.editor.id,
        deleted_by: user.login,
        deleted_by_id: user.id,
        deleted_content: "new body",
      }

      @repository_advisory_comment_edit.soft_delete!(user)

      assert event = events.pop, "an event was expected"
      assert_same_time Time.zone.now, event.payload.delete(:deleted_at)
      assert_equal expected_payload, event.payload
      assert_equal @repository_advisory_comment_edit.deleted_by, user
      refute_nil @repository_advisory_comment_edit.deleted_at
    end
  end

  test "#diff_before" do
    assert_equal "new body", @repository_advisory_comment_edit.diff
    assert_equal "old body", @repository_advisory_comment_edit.diff_before

    @repository_advisory_comment.update_body("newer body", @repository_advisory_comment.user)
    assert_equal "new body", T.must(RepositoryAdvisoryCommentEdit.where(repository_advisory_comment: @repository_advisory_comment).last).diff_before
  end

  test "isn't created when no changes are made" do
    old_body = @repository_advisory_comment.body

    assert_no_difference(-> { RepositoryAdvisoryCommentEdit.count }, -> { UserContentEdit.count }) do
      @repository_advisory_comment.update_body(old_body, @repository_advisory_comment.user)
    end
  end

  context "#safe_diff" do
    test "returns the valid body" do
      assert_equal @repository_advisory_comment_edit.diff, @repository_advisory_comment_edit.safe_diff
    end

    test "encodes emoji correctly" do
      string = "😉".b
      @repository_advisory_comment_edit.update_attribute(:diff, string)
      assert_equal Encoding::ASCII_8BIT, @repository_advisory_comment_edit.diff.encoding
      assert_equal Encoding::UTF_8, @repository_advisory_comment_edit.safe_diff.encoding
    end
  end
end
