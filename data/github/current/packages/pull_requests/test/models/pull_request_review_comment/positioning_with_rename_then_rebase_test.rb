# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/pull_requests"

require "test_helpers/commit_tree_helper"

class PullRequestReviewCommentPositioningWithRenameThenRebaseTest < GitHub::TestCase
  include GitHub::PullRequestTestHelpers
  include GitHub::CommitTreeHelper
  include PullRequestSynchronizationTestHelpers

  Spokesd.share_spokesdb(self)

  setup do
    Spokesd.enable_spokesd

    @repo = create(:repository, from_example: :empty)

    @c1 = make_commit nil, "notes" => 1..100
    @c1.freeze
    @c2 = make_commit @c1, "notes" => 1..150
    @c2.freeze

    master = repo.refs.create("refs/heads/master", @c1, repo.owner)
    topic = repo.refs.create("refs/heads/topic", @c2, repo.owner)

    @pull = make_pr(repo, repo)
  end

  def test_renames_followed_after_rebase
    comparison = PullRequest::Comparison.find(pull: @pull, start_commit_oid: @c1.oid,
                                              end_commit_oid: @c2.oid, base_commit_oid: @c1.oid)

    review = @pull.pending_review_for(user: repo.owner, head_sha: comparison.end_commit.oid)
    thread = review.build_thread
    comment = thread.build_first_comment(
      user: repo.owner,
      body: "good job, me!",
      line: 104,
      side: :right,
      path: "notes",
      diff: comparison.diffs,
    )
    review.save!

    assert_equal "notes", comment.blob_path

    master = make_commit @c1, "something" => [["data"]]
    c3 = make_commit master, "notes2" => 1..155, "notes" => nil

    with_enqueued_pr_sync_jobs { repo.heads.find("topic").update(c3, repo.owner) }

    comment.reload

    assert_equal "notes2", comment.blob_path
  end
end
