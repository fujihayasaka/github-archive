# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/pull_requests"

class PullRequestComparisonTest < GitHub::TestCase
  include GitHub::PullRequestTestHelpers
  fixtures do
    @forker = create(:user)
    @second_user = create(:user)
    @source = create(:private_repository, owner: create(:user, plan: "business"), from_example: :review_comment_source)
    @source.add_member @forker, action: :write
    @source.add_member @second_user, action: :write

    @forked = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :review_comment_fork)

    issue = create(:issue, repository: @source, user: @forker)

    @pull =
      create(:pull_request,
        repository:      @source,
        base_repository: @source,
        base_user:       @source.owner,
        base_ref:        "master",
        head_repository: @forked,
        head_user:       @forker,
        head_ref:        "rename-topic",
        issue:           issue,
      )
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  EXISTING_HEAD = "fa97e970518bb04f664a6bb7f33062ae2847ca04"

  RANGE_START = "d89726691c27a8d7b044a00ccb77728ab986a1ce"
  RANGE_END = "c4465f65f93774e1780f9979cbbd63294a0ba7b0"
  RANGE_BASE = "564af74a07da170ec3a45ef0a8cc34e8a8c1aa89"

  def default_comparison(pull)
    pull.pull_comparison(start_oid: RANGE_START, end_oid: RANGE_END, base_oid: RANGE_BASE)
  end

  context "#codeowners" do
    test "returns a codeowners instance for the current comparison" do
      comparison = default_comparison(@pull)
      assert comparison.codeowners.is_a?(Repository::Codeowners)
      refute comparison.codeowners.file
    end
  end

  context "#review_threads_for" do
    test "for the current comparison" do
      comparison = default_comparison(@pull)

      review = @pull.pending_review_for(user: @pull.head_user, head_sha: comparison.end_commit.oid)
      thread1 = review.build_thread
      thread1.build_first_comment(
        user: @pull.head_user, body: "comment1",
        side: :left, line: 2, path: "aquaman2.txt", diff: comparison.diffs
      )
      thread2 = review.build_thread
      thread2.build_first_comment(
        user: @pull.head_user, body: "comment2",
        side: :right, line: 32, path: "aquaman2.txt", diff: comparison.diffs
      )
      review.save!

      thread2.build_reply(
        user: @pull.head_user, body: "comment3", pull_request_review: review,
      ).tap(&:save!)

      review.comment!

      start_oid, end_oid = @pull.merge_base, @pull.head_sha
      start_commit, end_commit = @pull.compare_repository.commits.find([start_oid, end_oid])
      @pull.reload
      comparison = PullRequest::Comparison.new(pull: @pull, start_commit: start_commit, end_commit: end_commit, base_commit: start_commit)

      assert comparison.current?

      threads = comparison.review_threads_for(viewer: @pull.head_user)
      assert_equal 2, threads.size
    end

    test "for a range comparison" do
      comparison = default_comparison(@pull)

      review = @pull.pending_review_for(user: @pull.head_user, head_sha: comparison.end_commit.oid)
      thread1 = review.build_thread
      thread1.build_first_comment(
        user: @pull.head_user, body: "comment1",
        line: 2, side: :left, path: "aquaman2.txt", diff: comparison.diffs
      )
      thread2 = review.build_thread
      thread2.build_first_comment(
        user: @pull.head_user, body: "comment2",
        line: 32, side: :right, path: "aquaman2.txt", diff: comparison.diffs
      )
      review.save!

      thread2.build_reply(
        user: @pull.head_user, body: "comment3", pull_request_review: review,
      ).tap(&:save!)

      review.comment!

      @pull.reload

      # re-creating the comparison because the default comparison is never current
      # but the pull request needs to be reloaded to pick up the association of the new
      # threads to the '@pull' object in memory
      comparison = default_comparison(@pull)

      refute comparison.current?

      threads = comparison.review_threads_for(viewer: @pull.head_user)
      assert_equal 2, threads.size
    end

    test "loads the diff only once per passed key" do
      comparison = default_comparison(@pull)

      review = @pull.pending_review_for(user: @pull.head_user, head_sha: comparison.end_commit.oid)
      thread1 = review.build_thread
      thread1.build_first_comment(
        user: @pull.head_user, body: "comment1",
        side: :left, line: 2, path: "aquaman2.txt", diff: comparison.diffs
      )
      thread2 = review.build_thread
      thread2.build_first_comment(
        user: @pull.head_user, body: "comment2",
        side: :right, line: 32, path: "aquaman2.txt", diff: comparison.diffs
      )
      review.save!

      thread2.build_reply(
        user: @pull.head_user, body: "comment3", pull_request_review: review,
      ).tap(&:save!)

      review.comment!

      start_oid, end_oid = @pull.merge_base, @pull.head_sha
      start_commit, end_commit = @pull.compare_repository.commits.find([start_oid, end_oid])
      @pull.reload
      comparison = PullRequest::Comparison.new(pull: @pull, start_commit: start_commit, end_commit: end_commit, base_commit: start_commit)

      # load review threads for an initial viewer

      comparison.review_threads_for(viewer: @pull.head_user)

      assert_equal 1, comparison.review_threads.keys.count

      # load review threads for a second viewer

      comparison.review_threads_for(viewer: @second_user)

      assert_equal 2, comparison.review_threads.keys.count

      # check that we don't load more review threads by requesting the threads
      # for the initial viewer/user

      comparison.review_threads_for(viewer: @pull.head_user)

      assert_equal 2, comparison.review_threads.keys.count

      # load the threads for a nil viewer

      comparison.review_threads_for(viewer: nil)

      assert_equal 3, comparison.review_threads.keys.count
    end
  end
end
