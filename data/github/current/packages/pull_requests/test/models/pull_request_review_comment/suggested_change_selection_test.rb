# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/pull_requests"

class PullRequestReviewComment::SuggestedChangeSelectionTest < GitHub::TestCase
  include GitHub::PullRequestTestHelpers
  include PullRequestIntegrationTestHelpers
  include PullRequestSynchronizationTestHelpers

  EXISTING_HEAD = "fa97e970518bb04f664a6bb7f33062ae2847ca04" # @pull.head_sha
  RANGE_START = "d89726691c27a8d7b044a00ccb77728ab986a1ce"
  RANGE_END = "c4465f65f93774e1780f9979cbbd63294a0ba7b0"
  RANGE_BASE = "564af74a07da170ec3a45ef0a8cc34e8a8c1aa89" # @pull.base_sha

  fixtures do
    Spokesd.enable_spokesd

    # This pull request contains a file - 'aquaman.txt' - that has some modified
    # contents and then is renamed to 'aquaman2.txt'
    @pull = make_pr_and_repos(source_example: :review_comment_source,
                              fork_example:   :review_comment_fork,
                              branch:         "rename-topic")

    @source_repo = @pull.repository
    @fork_repo = @pull.head_repository

    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  def suggested_change_selection_for(pull: @pull, path:, start_commit_oid:, end_commit_oid:, base_commit_oid:, line:, side:, start_line: nil, start_side: nil)
    PullRequestReviewComment::SuggestedChangeSelection.new(
      pull: pull,
      path: path,
      start_commit_oid: start_commit_oid,
      end_commit_oid: end_commit_oid,
      base_commit_oid: base_commit_oid,
      line: line,
      side: side,
      start_line: start_line,
      start_side: start_side,
    )
  end

  # web style comment creation...
  def create_comment(path: "aquaman.txt", side:, line:, start_line: nil, start_side: nil, end_commit_oid: RANGE_END)
    comparison = PullRequest::Comparison.find(pull: @pull, start_commit_oid: RANGE_START,
      end_commit_oid: end_commit_oid, base_commit_oid: RANGE_BASE)

    review = @pull.pending_review_for(user: @fork_repo.owner, head_sha: end_commit_oid)
    thread = review.build_thread
    comment = thread.build_first_comment(
      user: @fork_repo.owner,
      body: "good job!",
      path: path,
      diff: comparison.diffs,
      side: side,
      line: line,
      start_line: start_line,
      start_side: start_side,
    )
    review.save!

    comment
  end

  test "valid selection" do
    selection = suggested_change_selection_for(
      start_commit_oid: RANGE_START,
      end_commit_oid: RANGE_END,
      base_commit_oid: RANGE_BASE,
      path: "aquaman2.txt",
      line: 2,
      side: :right,
    )
    assert_equal ["+Danger Norris and Mort Weisinger, the character debuted in More Fun Comics #73 (Nov."], selection.lines
    refute_predicate selection, :disabled?
  end

  test "valid selection when start and base oids are nil" do
    selection = suggested_change_selection_for(
      start_commit_oid: nil,
      end_commit_oid: RANGE_END,
      base_commit_oid: nil,
      path: "aquaman2.txt",
      line: 2,
      side: :right,
    )
    assert_equal ["+Danger Norris and Mort Weisinger, the character debuted in More Fun Comics #73 (Nov."], selection.lines
    refute_predicate selection, :disabled?
  end

  test "valid selection from persisted comment" do
    comment = create_comment(path: "aquaman2.txt", line: 2, side: :right)
    selection = PullRequestReviewComment::SuggestedChangeSelection.from_persisted_comment(comment)
    assert_equal ["+Danger Norris and Mort Weisinger, the character debuted in More Fun Comics #73 (Nov."], selection.lines
    refute_predicate selection, :disabled?
  end

  test "selection is on deleted lines" do
    selection = suggested_change_selection_for(
      start_commit_oid: RANGE_START,
      end_commit_oid: RANGE_END,
      base_commit_oid: RANGE_BASE,
      path: "aquaman2.txt",
      line: 2,
      side: :left,
    )
    assert_equal ["-Norris and Mort Weisinger, the character debuted in More Fun Comics #73 (Nov."], selection.lines
    assert_predicate selection, :disabled?
  end

  test "comment is outdated" do
    comment = create_comment(path: "aquaman2.txt", line: 2, side: :right)
    # Force the comment to be outdated
    comment.update!(position: nil, outdated: true)
    selection = PullRequestReviewComment::SuggestedChangeSelection.from_persisted_comment(comment)
    assert_equal [], selection.lines
    assert_predicate selection, :disabled?
  end

  test "comment is nil" do
    selection = PullRequestReviewComment::SuggestedChangeSelection.from_persisted_comment(nil)
    assert_equal [], selection.lines
    assert_predicate selection, :disabled?
  end

  test "invalid commit" do
    selection = suggested_change_selection_for(
      start_commit_oid: RANGE_START,
      end_commit_oid: "deadbeef",
      base_commit_oid: RANGE_BASE,
      path: "aquaman2.txt",
      line: 2,
      side: :right,
    )
    assert_equal [], selection.lines
    assert_predicate selection, :disabled?
  end

  test "invalid path" do
    selection = suggested_change_selection_for(
      start_commit_oid: RANGE_START,
      end_commit_oid: RANGE_END,
      base_commit_oid: RANGE_BASE,
      path: "rockquaman.txt",
      line: 2,
      side: :right,
    )
    assert_equal [], selection.lines
    assert_predicate selection, :disabled?
  end

  test "finds diff entry when path is after default max file limit" do
    commit = @fork_repo.commits.create({ message: "add a.txt", committer: @fork_repo.owner }, @pull.head_sha) do |files|
      files.add("a.txt", "hello there!")
    end
    @fork_repo.heads.find("rename-topic").update(commit, @fork_repo.owner)
    @pull.reload

    selection = suggested_change_selection_for(
      start_commit_oid: RANGE_START,
      end_commit_oid: commit.oid,
      base_commit_oid: RANGE_BASE,
      path: "a.txt",
      line: 1,
      side: :right,
    )
    assert_equal ["+hello there!"], selection.lines

    GitHub::Diff.stub_const(:DEFAULT_MAX_FILES, 1) do
      selection = suggested_change_selection_for(
        start_commit_oid: RANGE_START,
        end_commit_oid: commit.oid,
        base_commit_oid: RANGE_BASE,
        path: "a.txt",
        line: 1,
        side: :right,
      )
      assert_equal ["+hello there!"], selection.lines
    end
  end

  test "finds selection after rebase loses changes" do
    commit = @fork_repo.commits.create({ message: "add hello", committer: @fork_repo.owner }, @pull.head_sha) do |files|
      files.add("hello.txt", "hello there!")
    end

    with_enqueued_pr_sync_jobs(additional_jobs: [MaintainTrackingRefJob]) { @fork_repo.heads.find("rename-topic").update(commit, @fork_repo.owner) }
    @pull.reload

    selection = suggested_change_selection_for(
      start_commit_oid: RANGE_START,
      end_commit_oid: commit.oid,
      base_commit_oid: RANGE_BASE,
      path: "hello.txt",
      line: 1,
      side: :right,
    )
    assert_equal ["+hello there!"], selection.lines

    comment = create_comment(path: "hello.txt", side: :right, line: 1, end_commit_oid: @pull.head_sha)

    # Add the same file and contents to the base repo
    base_commit = @source_repo.commits.create({ message: "add hello", committer: @source_repo.owner }, @pull.merge_base) do |files|
      files.add("hello.txt", "hello there!")
    end

    # Merge base into head so the hello.txt file is no longer in the pull's diff
    @source_repo.heads.find("master").update(base_commit, @source_repo.owner)
    @pull.merge_base_into_head(user: @fork_repo.owner)
    @pull.reload

    selection = PullRequestReviewComment::SuggestedChangeSelection.from_persisted_comment(comment)
    refute_predicate selection, :disabled?
    assert_equal ["+hello there!"], selection.lines

    # ensure we can still find the diff when sending commit oids instead of
    # persisted comment
    selection = suggested_change_selection_for(
      start_commit_oid: RANGE_START,
      end_commit_oid: commit.oid,
      base_commit_oid: RANGE_BASE,
      path: "hello.txt",
      line: 1,
      side: :right,
    )
    refute_predicate selection, :disabled?
    assert_equal ["+hello there!"], selection.lines
  end

  context "multi line" do
    test "valid selection" do
      selection = suggested_change_selection_for(
        start_commit_oid: RANGE_START,
        end_commit_oid: RANGE_END,
        base_commit_oid: RANGE_BASE,
        path: "aquaman2.txt",
        start_line: 2,
        start_side: :right,
        line: 3,
        side: :right,
      )
      refute_predicate selection, :contains_deletions?
      refute_predicate selection, :disabled?

      selected_lines = [
        "+Danger Norris and Mort Weisinger, the character debuted in More Fun Comics #73 (Nov.",
        " 1941). Initially a backup feature in DC's anthology titles, Aquaman later",
       ]
      assert_equal selected_lines, selection.lines
    end

    test "suggestion with deletions is disabled" do
      selection = suggested_change_selection_for(
        start_commit_oid: RANGE_START,
        end_commit_oid: RANGE_END,
        base_commit_oid: RANGE_BASE,
        path: "aquaman2.txt",
        start_line: 1,
        start_side: :right,
        line: 2,
        side: :right,
      )
      assert_predicate selection, :contains_deletions?
      assert_predicate selection, :disabled?
    end

    test "lines is empty when `comment_outside_the_diff` FF disabled for comment outside diff" do
      GitHub.flipper[:comment_outside_the_diff].disable(@source_repo)
      selection = suggested_change_selection_for(
        start_commit_oid: RANGE_START,
        end_commit_oid: RANGE_END,
        base_commit_oid: RANGE_BASE,
        path: "aquaman2.txt",
        start_line: 10,
        start_side: :right,
        line: 12,
        side: :right,
      )
      assert_empty selection.lines
    end

    test "lines has content when `comment_outside_the_diff` FF enabled for comment outside diff" do
      GitHub.flipper[:comment_outside_the_diff].enable(@source_repo)
      selection = suggested_change_selection_for(
        start_commit_oid: RANGE_START,
        end_commit_oid: RANGE_END,
        base_commit_oid: RANGE_BASE,
        path: "aquaman2.txt",
        start_line: 10,
        start_side: :right,
        line: 12,
        side: :right,
      )
      refute_empty selection.lines
    end
  end
end
