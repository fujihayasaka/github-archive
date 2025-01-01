# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestReviewCommentEditTest < GitHub::TestCase
  include RepositoriesTestHelper

  fixtures do
    @user = create(:user, login: "steves", plan: "silver")
    @repo = create(:repository, owner: @user, from_example: :pull_request_source)

    @other_user = create(:user, login: "acme")
    fork = fast_fork_repo(@repo, owner: @other_user, example: :pull_request_fork)

    @pull_request = create(:pull_request,
      issue: create(:issue, repository: @repo),
      base_repository: @repo,
      base_user: @user,
      base_ref: "master",
      head_repository: fork,
      head_user: @other_user,
      head_ref: "topic",
    )

    @pull_request_review_comment = create(:pull_request_review_comment, pull_request: @pull_request, body: "old body")
    @pull_request_review_comment.submit!
    @pull_request_review_comment.update_body("new body", @pull_request_review_comment.user)

    @pull_request_review_comment_edit = PullRequestReviewCommentEdit.where(pull_request_review_comment: @pull_request_review_comment).last
    T.must(@pull_request_review_comment_edit).update(user_content_edit_id: nil)

    @legacy_pull_request_review_comment = create(:pull_request_review_comment, pull_request: @pull_request, body: "old body")
    @legacy_pull_request_review_comment.submit!
    @legacy_pull_request_review_comment.update_body("new body", @legacy_pull_request_review_comment.user)

    @legacy_pull_request_review_comment_edit = PullRequestReviewCommentEdit.where(pull_request_review_comment: @legacy_pull_request_review_comment).last
    T.must(@legacy_pull_request_review_comment_edit).update_column(:user_content_edit_id, 1337)
  end

  context "#global_relay_id" do
    test "for a non-legacy edit" do
      id = Platform::Helpers::NodeIdentification.from_global_id(@pull_request_review_comment_edit.global_relay_id)
      if Platform::Objects::UserContentEdit.use_next_id?(@pull_request_review_comment_edit)
        assert_equal ["UserContentEdit", @pull_request_review_comment_edit.id], id
      else
        assert_equal id, ["UserContentEdit", "PullRequestReviewCommentEdit:#{@pull_request_review_comment_edit.id}"]
      end
    end

    test "for a legacy edit" do
      id = Platform::Helpers::NodeIdentification.from_global_id(@legacy_pull_request_review_comment_edit.global_relay_id)
      if Platform::Objects::UserContentEdit.use_next_id?(@legacy_pull_request_review_comment_edit)
        assert_equal ["UserContentEdit", @legacy_pull_request_review_comment_edit.id], id
      else
        assert_equal id, ["UserContentEdit", "#{@legacy_pull_request_review_comment_edit.user_content_edit_id}"]
      end
    end
  end

  test "#soft_delete!" do
    user = create(:user)
    events = subscribe "user_content_edit.delete"

    Timecop.freeze do
      expected_payload = {
        user_content_type: "PullRequestReviewComment",
        user_content_id: @pull_request_review_comment.id,
        editor: @pull_request_review_comment_edit.editor.login,
        editor_id: @pull_request_review_comment_edit.editor.id,
        deleted_by: user.login,
        deleted_by_id: user.id,
        deleted_content: "new body",
      }

      @pull_request_review_comment_edit.soft_delete!(user)

      assert event = events.pop, "an event was expected"
      assert_same_time Time.zone.now, event.payload.delete(:deleted_at)
      assert_equal expected_payload, event.payload
      assert_equal @pull_request_review_comment_edit.deleted_by, user
      refute_nil @pull_request_review_comment_edit.deleted_at
    end
  end

  test "#diff_before" do
    assert_equal "new body", @pull_request_review_comment_edit.diff
    assert_equal "old body", @pull_request_review_comment_edit.diff_before

    @pull_request_review_comment.update_body("newer body", @pull_request_review_comment.user)
    assert_equal "new body", T.must(PullRequestReviewCommentEdit.where(pull_request_review_comment: @pull_request_review_comment).last).diff_before
  end

  test "isn't created when no changes are made" do
    old_body = @pull_request_review_comment.body

    assert_no_difference(-> { PullRequestReviewCommentEdit.count }, -> { UserContentEdit.count }) do
      @pull_request_review_comment.update_body(old_body, @pull_request_review_comment.user)
    end
  end

  context "#safe_diff" do
    test "returns the valid body" do
      assert_equal @pull_request_review_comment_edit.diff, @pull_request_review_comment_edit.safe_diff
    end

    test "encodes emoji correctly" do
      string = "😉".b
      @pull_request_review_comment_edit.update_attribute(:diff, string)
      assert_equal Encoding::ASCII_8BIT, @pull_request_review_comment_edit.diff.encoding
      assert_equal Encoding::UTF_8, @pull_request_review_comment_edit.safe_diff.encoding
    end
  end

  test "copies `repository_id` from the `pull_request_review_comment` during create" do
    pull_request_review_comment_edit = PullRequestReviewCommentEdit.create(
      pull_request_review_comment: @pull_request_review_comment,
      editor_id: @user.id,
      edited_at: Time.current)

    refute_nil pull_request_review_comment_edit.repository_id
    assert_equal pull_request_review_comment_edit.repository_id, @pull_request_review_comment.repository_id
  end
end
