# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/pull_requests"

class AsyncAdjustedBlobPositionTest < GitHub::TestCase
  include GitHub::PullRequestTestHelpers

  fixtures do
    @pull = make_pr_and_repos(source_example: :review_comment_source,
      fork_example:   :review_comment_fork,
      branch:         "high_line_number_change",
    )
    @fork_repo = @pull.head_repository

    @diff = @pull.async_diff(
      start_commit_oid: "564af74a07da170ec3a45ef0a8cc34e8a8c1aa89",
      end_commit_oid: "a11d2cbabdc03d2d98914329dca9fb43a80ae0b0",
    ).sync

    @diff.freeze
  end

  setup { GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new) }

  def assert_adjusted_position_metrics(algorithm:, outdated:)
    metric = GitHub.dogstats.increments("diff.comments.adjusted_blob_position")
    assert_equal 1, metric.count
    metric = metric.first
    assert metric.tags.include?("algorithm:#{algorithm}")
    assert metric.tags.include?("outdated:#{outdated}")
  end

  test "returns the expected adjusted position and reports expected metrics" do
    thread = @pull.pending_review_for(user: @fork_repo.owner).build_thread
    comment = thread.build_first_comment(
      body: "text",
      line: 34,
      path: "aquaman2.txt",
      diff: @diff,
    )

    comment.save!

    full_diff = @pull.historical_comparison.diffs

    # clear cached values
    comment = PullRequestReviewComment.find(comment.id)
    GitHub.dogstats.reset

    assert_equal 31, T.must(comment.pull_request_review_thread).async_adjusted_blob_position(full_diff).sync
    assert_adjusted_position_metrics(algorithm: "blob_offsets", outdated: false)

    GitHub.dogstats.reset

    # the default should be the full diff too
    assert_equal 31, T.must(comment.pull_request_review_thread).async_adjusted_blob_position.sync
    assert_adjusted_position_metrics(algorithm: "blob_offsets", outdated: false)
  end

  test "returns nil for outdated comments and reports expected metrics" do
    thread = @pull.pending_review_for(user: @fork_repo.owner).build_thread
    comment = thread.build_first_comment(
      body: "text",
      line: 11,
      path: "aquaman2.txt",
      diff: @diff,
    )

    comment.save!

    # clear cached values
    comment = PullRequestReviewComment.find(comment.id)
    GitHub.dogstats.reset

    assert_nil T.must(comment.pull_request_review_thread).async_adjusted_blob_position.sync
    assert_adjusted_position_metrics(algorithm: "blob_offsets", outdated: true)

    # make the comment invalid
    comment.update!(blob_commit_oid: nil, blob_path: nil, blob_position: nil)
    comment.update!(original_end_commit_id: "f" * 40, original_start_commit_id: "a" * 40)

    # clear cached values
    comment = PullRequestReviewComment.find(T.must(comment.id))
    GitHub.dogstats.reset

    assert_nil T.must(comment.pull_request_review_thread).async_adjusted_blob_position.sync
    assert_adjusted_position_metrics(algorithm: "excerpt_match", outdated: true)
  end

  test "falls back on legacy hunk matching on failure and reports expected metrics" do
    thread = @pull.pending_review_for(user: @fork_repo.owner).build_thread
    assert comment = create(:pull_request_review_comment,
      pull_request: @pull,
      user:      @fork_repo.owner,
      commit_id: "a11d2cbabdc03d2d98914329dca9fb43a80ae0b0",
      path:      "aquaman2.txt",
      original_position:  22,
      body:      "Hello!",
    )

    # remove the blob position information so we are forced to extrapolate it from the
    # legacy fields
    comment.update!(blob_commit_oid: nil, blob_path: nil, blob_position: nil)

    # alter the diff fields to simulate a comment referencing a deleted, corrupt, or inaccessible commit
    comment.update!(original_end_commit_id: "f" * 40, original_start_commit_id: "a" * 40)

    # clear cached values
    comment = PullRequestReviewComment.find(comment.id)
    GitHub.dogstats.reset

    # should fall back on legacy diff hunk match positioning to still succeed
    assert_equal 29, T.must(comment.pull_request_review_thread).async_adjusted_blob_position.sync
    assert_adjusted_position_metrics(algorithm: "excerpt_match", outdated: false)
  end
end
