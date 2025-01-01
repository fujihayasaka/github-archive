# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/pull_requests"

class PullRequestReviewCommentLegacyPositionDataTest < GitHub::TestCase
  include GitHub::PullRequestTestHelpers

  fixtures do
    user = create(:user)
    @pull = make_pr_and_repos(source_example: :review_comment_source, fork_example: :review_comment_fork)

    review = @pull.pending_review_for(user: user)
    thread = review.build_thread
    @comment = thread.build_first_comment(body: "text", path: "aquaman.txt", line: 4)

    review.save! && @comment.save!
  end

  context "#async_from_comment" do
    test "yields expected position data" do
      data = PullRequestReviewComment::LegacyPositionData.async_from_comment(@comment).sync

      assert_equal 3, data.blob_position
      assert_equal "aquaman.txt", data.path
      assert_equal @pull.head_repository.heads.find("topic").target_oid, data.commit_oid
      refute data.left_blob?
    end
  end

  context "#blob_position" do
    test "works for deletion lines" do
      review = @pull.pending_review_for(user: create(:user))
      thread = review.build_thread
      comment = thread.build_first_comment(body: "text", path: "aquaman.txt", line: 5, side: :left)
      comment.save!
      data = PullRequestReviewComment::LegacyPositionData.async_from_comment(comment).sync

      assert_equal 4, data.blob_position
      assert_equal "aquaman.txt", data.path
    end
  end

  test "returns nil for original_start_line" do
    data = PullRequestReviewComment::LegacyPositionData.async_from_comment(@comment).sync

    assert_nil data.original_start_line
  end
end
