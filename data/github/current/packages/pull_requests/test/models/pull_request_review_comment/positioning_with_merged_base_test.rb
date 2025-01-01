# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/pull_requests"

require "test_helpers/commit_tree_helper"


class PullRequestReviewCommentPositioningWithMergedBaseTest < GitHub::TestCase
  include GitHub::PullRequestTestHelpers
  include GitHub::CommitTreeHelper

  fixtures do
    @repo = create(:repository, from_example: :empty)

    @c1 = make_commit nil, "notes" => 1..200
    @c2 = make_commit @c1, "notes" => [1..120, 125..200]
    @c3 = make_commit @c1, "notes" => [1..100, ["Foo"], 101..200]
    @c4 = merge_commits(@c2, @c3)
    @c5 = make_commit @c4, "notes" => [1..100, ["Foo"], 101..120, 125..175, 178..200]

    topic = repo.refs.create("refs/heads/topic", @c5, repo.owner)
    master = repo.refs.create("refs/heads/master", @c3, repo.owner)

    @pull = make_pr(repo, repo)

    @c1.freeze
    @c2.freeze
    @c3.freeze
    @c4.freeze
    @c5.freeze
  end

  def test_proxy_base_tree
    comparison = PullRequest::Comparison.find(pull: @pull, start_commit_oid: @c2.oid,
                                              end_commit_oid: @c5.oid, base_commit_oid: @c3.oid)

    review = @pull.pending_review_for(user: repo.owner, head_sha: comparison.end_commit.oid)
    thread = review.build_thread
    comment = thread.build_first_comment(
      user: repo.owner,
      body: "good job, me!",
      line: 174,
      side: :left,
      path: "notes",
      diff: comparison.diffs,
    )
    review.save!

    assert_equal 172, comment.blob_position
  end
end
