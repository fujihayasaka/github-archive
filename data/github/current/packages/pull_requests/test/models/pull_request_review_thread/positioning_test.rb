# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/pull_requests"

require "test_helpers/commit_tree_helper"


class PullRequestReviewThreadPositioningTest < GitHub::TestCase
  include GitHub::PullRequestTestHelpers
  include PullRequestIntegrationTestHelpers
  include PullRequestSynchronizationTestHelpers

  EXISTING_HEAD = "fa97e970518bb04f664a6bb7f33062ae2847ca04"
  RANGE_START = "d89726691c27a8d7b044a00ccb77728ab986a1ce"
  RANGE_END = "c4465f65f93774e1780f9979cbbd63294a0ba7b0"
  RANGE_BASE = "564af74a07da170ec3a45ef0a8cc34e8a8c1aa89"

  fixtures do
    Spokesd.enable_spokesd

    @pull = make_pr_and_repos(source_example: :review_comment_source,
                              fork_example:   :review_comment_fork,
                              branch:         "rename-topic")

    @source_repo = @pull.repository
    @fork_repo = @pull.head_repository

    @review = @pull.pending_review_for(user: @make_pr_fork_owner, head_sha: RANGE_END)

    example_repo_snapshot
  end

  setup do
    example_repo_restore
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  def assert_blob_fields(thread, position:, path:, commit_oid:, left_blob:, reload: true)
    thread.reload if reload

    assert_equal position, thread.blob_position
    assert_equal path, thread.blob_path
    assert_equal commit_oid, thread.blob_commit_oid
    assert_equal left_blob, thread.left_blob
  end

  def assert_diff_fields(thread, position:, path:, commit_oid: nil)
    thread.reload
    assert_equal position, thread.position if position
    assert_equal path, thread.path
    assert_equal commit_oid, thread.commit_id if commit_oid
  end

  # web style comment creation...
  def create_thread_with_comment(path: "aquaman.txt", side:, line:, start_line: nil)
    comparison = PullRequest::Comparison.find(pull: @pull, start_commit_oid: RANGE_START,
                                              end_commit_oid: RANGE_END, base_commit_oid: RANGE_BASE)

    thread = @review.build_thread
    thread.build_first_comment(
      user: @fork_repo.owner,
      body: "good job!",
      path: path,
      diff: comparison.diffs,
      side: side,
      line: line,
      start_line: start_line,
    )
    @review.save!
    thread
  end

  def create_file_level_thread_with_comment(path: "aquaman.txt")
    comparison = PullRequest::Comparison.find(pull: @pull, start_commit_oid: RANGE_START,
                                              end_commit_oid: RANGE_END, base_commit_oid: RANGE_BASE)
    thread = @review.build_thread
    thread.subject_type = :file

    thread.build_first_comment(
      user: @fork_repo.owner,
      body: "good job!",
      path: path,
      diff: comparison.diffs
    )
    @review.save!
    thread
  end

  test "comment on full PR diff" do
    # API style comment creation
    assert comment = create(:pull_request_review_comment,
      pull_request: @pull,
      user:      @fork_repo.owner,
      commit_id: EXISTING_HEAD,
      path:      "aquaman2.txt",
      original_position:  27,
      body:      "Hello!",
    ) # +This is an additional paragraph

    assert_blob_fields(comment.pull_request_review_thread, position: 42, path: "aquaman2.txt", commit_oid: EXISTING_HEAD, left_blob: false)
    assert_diff_fields(comment.pull_request_review_thread, position: 27, path: "aquaman2.txt")
  end

  test "returns an empty line when there is no diff" do
    # API style comment creation
    comment = create(:pull_request_review_comment,
      pull_request: @pull,
      user:      @fork_repo.owner,
      commit_id: EXISTING_HEAD,
      path:      "aquaman2.txt",
      original_position:  27,
      body:      "Hello!",
    ) # +This is an additional paragraph

    PullRequestReviewComment::LegacyPositionData.stubs(:diff_for_comparison).returns(nil)
    comment.pull_request_review_thread.position_data.stubs(:left_blob?).returns(true)
    comment.pull_request_review_thread.position_data.line
  end

  test "comment on a removal from a middle commit range" do
    thread = create_thread_with_comment(line: 30, side: :left) # -Writer Robert Bernstein and penciler-inker

    assert_blob_fields(thread, position: 29, path: "aquaman.txt", commit_oid: RANGE_START, left_blob: true)
    assert_diff_fields(thread, position: 14, path: "aquaman.txt")
  end

  test "comment on a context line for a middle commit range" do
    thread = create_thread_with_comment(line: 28, side: :right, path: "aquaman2.txt") # in Adventure Comics #229 (Oct. 1956).

    assert_blob_fields(thread, position: 27, path: "aquaman2.txt", commit_oid: RANGE_END, left_blob: false)
    assert_diff_fields(thread, position: 12, path: "aquaman2.txt")
  end

  test "comment on an addition line for a middle commit range" do
    thread = create_thread_with_comment(line: 31, side: :right, path: "aquaman2.txt") # +Robert

    assert_blob_fields(thread, position: 30, path: "aquaman2.txt", commit_oid: RANGE_END, left_blob: false)
    assert_diff_fields(thread, position: 16, path: "aquaman2.txt")
  end

  test "comment which is immediately outdated" do
    thread = create_thread_with_comment(line: 4, side: :right)

    assert_blob_fields(thread, position: 3, path: "aquaman2.txt", commit_oid: RANGE_END, left_blob: false)
    assert_diff_fields(thread, position: nil, path: "aquaman.txt")
    assert_predicate thread, :outdated?

    assert_equal 1, GitHub.dogstats.increments("pull_request.sync.position_outdated").first.value
  end

  test "existing comment after regular push that removes all file content" do
    thread = create_thread_with_comment(line: 28, side: :right, path: "aquaman2.txt")

    commit = @fork_repo.commits.create({ message: "changes", committer: @fork_repo.owner }, EXISTING_HEAD) do |files|
      files.add("aquaman2.txt", "he dies, the end!")
    end

    with_enqueued_pr_sync_jobs { @fork_repo.heads.find("rename-topic").update(commit, @fork_repo.owner) }

    assert_blob_fields(thread, position: 27, path: "aquaman2.txt", commit_oid: RANGE_END, left_blob: false)
    assert_diff_fields(thread, position: nil, path: "aquaman2.txt")
  end

  test "existing comment after force push squashes everything down to a single line in a single commit" do
    thread = create_thread_with_comment(line: 28, side: :right, path: "aquaman2.txt")

    assert_blob_fields(thread, position: 27, path: "aquaman2.txt", commit_oid: "c4465f65f93774e1780f9979cbbd63294a0ba7b0", left_blob: false)

    commit = @fork_repo.commits.create({ message: "changes", committer: @fork_repo.owner }, RANGE_BASE) do |files|
      files.add("aquaman2.txt", "he dies, the end!")
    end

    @fork_repo.heads.find("rename-topic").update(commit, @fork_repo.owner)

    assert_blob_fields(thread, position: 27, path: "aquaman2.txt", commit_oid: "c4465f65f93774e1780f9979cbbd63294a0ba7b0", left_blob: false)
    assert_diff_fields(thread, position: nil, path: "aquaman2.txt")
  end

  test "comment on removal from start_commit_oid stays after aggressive rebase" do
    thread = create_thread_with_comment(side: :left, line: 2)

    commit = @fork_repo.commits.create({ message: "changes", committer: @fork_repo.owner }, RANGE_BASE) do |files|
      files.add("aquaman2.txt", "he lives happily ever after, the end!")
    end

    with_enqueued_pr_sync_jobs { @fork_repo.heads.find("rename-topic").update(commit, @fork_repo.owner) }

    assert_blob_fields(thread, position: 1, path: "aquaman.txt", commit_oid: RANGE_BASE, left_blob: true)
    assert_diff_fields(thread, position: nil, path: "aquaman.txt")
  end

  test "comment repositioning works for a basic file-level thread" do
    new_content = <<-AQUAMAN
Shortly after the character's debut, Louis Cazeneuve succeeded Norris to become
the longest-running artist of the undersea hero's Golden Age adventures.
Cazeneuve debuted on "Aquaman" in More Fun Comics #82 (Aug. 1942), and continued
with the feature through issue #107 (Feb. 1946), and its subsequent move to
Adventure Comics #103-117, 119-120, 124 (April 1946 - June 1947, Aug.-Sept.
1947, Jan. 1948). The first recurring supporting characters in the feature were
various sea creatures, including Ark, a pet seal who appeared in several of
Aquaman's 1940s adventures, and Topo, Aquaman's pet octopus, who first appeared
    AQUAMAN
    ref = @fork_repo.refs.find("rename-topic")

    commit = ref.append_commit({ message: "changes", committer: @fork_repo.owner }, @fork_repo.owner) do |files|
      files.add("aquaman2.txt", new_content)
    end
    thread = create_file_level_thread_with_comment(path: "aquaman2.txt")

    with_enqueued_pr_sync_jobs { @fork_repo.heads.find("rename-topic").update(commit, @fork_repo.owner) }

    thread.reload

    assert_equal "aquaman2.txt", thread.path
  end

  test "comment is repositioned after squash rebase with removed lines above" do
    new_content = <<-AQUAMAN
Shortly after the character's debut, Louis Cazeneuve succeeded Norris to become
the longest-running artist of the undersea hero's Golden Age adventures.
Cazeneuve debuted on "Aquaman" in More Fun Comics #82 (Aug. 1942), and continued
with the feature through issue #107 (Feb. 1946), and its subsequent move to
Adventure Comics #103-117, 119-120, 124 (April 1946 - June 1947, Aug.-Sept.
1947, Jan. 1948). The first recurring supporting characters in the feature were
various sea creatures, including Ark, a pet seal who appeared in several of
Aquaman's 1940s adventures, and Topo, Aquaman's pet octopus, who first appeared
    AQUAMAN

    thread = create_thread_with_comment(line: 27, side: :right, path: "aquaman2.txt") # Aquaman's 1940s adventures
    assert_equal 26, thread.blob_position

    commit = @fork_repo.commits.create({ message: "changes", committer: @fork_repo.owner }, RANGE_BASE) do |files|
      files.add("aquaman2.txt", new_content)
    end

    with_enqueued_pr_sync_jobs { @fork_repo.heads.find("rename-topic").update(commit, @fork_repo.owner) }

    assert_blob_fields(thread, position: 7, path: "aquaman2.txt", commit_oid: commit.oid, left_blob: false)
    assert_diff_fields(thread, position: 8, path: "aquaman2.txt")
  end

  test "blob_commit_oid is updated after branch base changes" do
    pull = make_pr(@source_repo, @fork_repo, branch: "rebase-me")
    comment = create(:pull_request_review_comment,
      pull_request: pull,
      user:      @fork_repo.owner,
      commit_id: "f4f7ed2e29b51830146d96aed06f6768e9d8777f",
      path:      "file10",
      original_position:  2,
      body:      "Hello!",
    )
    thread = comment.pull_request_review_thread

    assert_equal 1, thread.blob_position
    with_enqueued_pr_sync_jobs { @fork_repo.heads.find("rebase-me").update(@fork_repo.heads["rebased"].sha, @fork_repo.owner) }

    assert_blob_fields(thread, position: 1, path: "file10", commit_oid: "27ff214dc0435259898aa7894e7d9ec394a0b2d1", left_blob: false)
    assert_diff_fields(thread, position: 2, path: "file10", commit_oid: "27ff214dc0435259898aa7894e7d9ec394a0b2d1")
  end

  # In this case the comment is on aquaman.txt (due to it being on the left side of the diff).
  # In the new branch, aquaman2.txt appears as an addition since the new diff is from a
  # nil merge base since there is no merge base any more.
  test "blob info is left as-is after branch is orphaned" do
    assert comment = create(:pull_request_review_comment,
      pull_request: @pull,
      user:      @fork_repo.owner,
      commit_id: EXISTING_HEAD,
      path:      "aquaman2.txt",
      original_position:  2,
      body:      "Hello!",
    )
    thread = comment.pull_request_review_thread

    original_merge_base = @pull.merge_base

    assert_blob_fields(thread, position: 1, path: "aquaman.txt", commit_oid: original_merge_base, left_blob: true)
    assert_diff_fields(thread, position: 2, path: "aquaman2.txt", commit_oid: EXISTING_HEAD)

    with_enqueued_pr_sync_jobs { @fork_repo.heads.find("rename-topic").update(@fork_repo.heads["orphan-branch"].sha, @fork_repo.owner) }

    assert_blob_fields(thread, position: 1, path: "aquaman.txt", commit_oid: original_merge_base, left_blob: true)
    op = GitHub.dogstats.increments("pull_request_review_comments.positioning_error").first
    assert_equal 1, op.value
    assert_includes op.tags, "no_merge_base"
    assert_diff_fields(thread, position: nil, path: "aquaman2.txt", commit_oid: @fork_repo.heads["orphan-branch"].sha)
  end

  test "blob repositioning when line is unchanged but others above are" do
    thread = create_thread_with_comment(line: 34, side: :right, path: "aquaman2.txt") # comic artists of that
    assert_equal 33, thread.blob_position

    new_sha = @fork_repo.heads["blob_position_shift"].sha
    with_enqueued_pr_sync_jobs { @fork_repo.heads.find("rename-topic").update(new_sha, @fork_repo.owner) }

    assert_blob_fields(thread, position: 31, path: "aquaman2.txt", commit_oid: new_sha, left_blob: false)
    assert_diff_fields(thread, position: 25, path: "aquaman2.txt", commit_oid: new_sha)
  end

  # This test tries to reposition after a comment on aquaman2.txt on a diff of aquaman.txt -> aquaman2.txt
  # is changed to a diff of aquaman.txt -> aquaman3.txt. As there is no rename detection in the gitrpc
  # adjusted blob position algorithm, it fails to find the expected file and returns :bad.
  test "blob is identical but a file was renamed" do
    thread = create_thread_with_comment(line: 34, side: :right, path: "aquaman2.txt") #  comic artists of that
    assert_blob_fields(thread, position: 33, path: "aquaman2.txt", commit_oid: "c4465f65f93774e1780f9979cbbd63294a0ba7b0", left_blob: false)

    new_sha = @fork_repo.heads["blob_renamed"].sha
    with_enqueued_pr_sync_jobs { @fork_repo.heads.find("rename-topic").update(new_sha, @fork_repo.owner) }
    assert_blob_fields(thread, position: 33, path: "aquaman2.txt", commit_oid: "c4465f65f93774e1780f9979cbbd63294a0ba7b0", left_blob: false)
    assert_diff_fields(thread, position: nil, path: "aquaman2.txt", commit_oid: new_sha)
  end

  test "changes are only after the comment" do
    # when graduating comment_outside_the_diff FF, the diff position will change.
    # this is to be expected because loading extra context lines will change diff-relative positions
    GitHub.flipper[:comment_outside_the_diff].disable
    thread = create_thread_with_comment(line: 30, side: :right, path: "aquaman2.txt") # Writer
    assert_equal 29, thread.blob_position

    new_sha = @fork_repo.heads["high_line_number_change"].sha
    with_enqueued_pr_sync_jobs { @fork_repo.heads.find("rename-topic").update(new_sha, @fork_repo.owner) }

    assert_blob_fields(thread, position: 27, path: "aquaman2.txt", commit_oid: new_sha, left_blob: false)
    assert_diff_fields(thread, position: 22, path: "aquaman2.txt", commit_oid: "005e42b6ae1cc6fcae2783aa4492fa728a3baa1a")
  end

  test "fails validation with an invalid path" do
    ex = assert_raises(ActiveRecord::RecordInvalid) { create_thread_with_comment(line: 16, side: :right, path: "bad_path.txt") }
    review = ex.record
    thread = review.review_threads.first

    assert thread.errors.include?(:path)
  end

  test "fails validation with an invalid position" do
    ex = assert_raises(ActiveRecord::RecordInvalid) { create_thread_with_comment(line: 10_000, side: :right, path: "aquaman2.txt") }

    review = ex.record
    thread = review.review_threads.first
    assert thread.errors.include?(:line)
  end

  test "#position_data.line is nil if position is nil" do
    PullRequestReviewComment::LegacyPositionData.any_instance.stubs(:calculate_blob_position).returns(nil)
    comment = create(:pull_request_review_comment,
      pull_request: @pull,
      user:      @fork_repo.owner,
      commit_id: EXISTING_HEAD,
      path:      "aquaman2.txt",
      original_position:  1,
      body:      "Hello!",
    )

    assert_equal comment.pull_request_review_thread.position_data.class, PullRequestReviewComment::LegacyPositionData
    assert_nil  comment.pull_request_review_thread.position_data.line
  end

  test "#position_data.path is computed when diff is missing" do
    comment = create(:pull_request_review_comment,
      pull_request: @pull,
      user:      @fork_repo.owner,
      commit_id: RANGE_END,
      path:      "aquaman2.txt",
      original_position:  1,
      body:      "Hello!",
    )
    thread = comment.pull_request_review_thread

    # Remove the auto-populated blob positioning data, so the comment will
    # return a LegacyPositionData when calling #position_data
    thread.update!(
      blob_position:   nil,
      blob_path:       nil,
      blob_commit_oid: nil,
    )

    # Force push to the repo such that that comment's commit is no longer part of the diff
    commit = @fork_repo.commits.create({ message: "changes", committer: @fork_repo.owner }, RANGE_BASE) do |files|
      files.add("aquaman2.txt", "he dies, the end!")
    end
    @fork_repo.heads.find("rename-topic").update(commit, @fork_repo.owner)

    # Trigger GC so the comment's commit will be cleaned up from the repo
    gc!(@fork_repo)
    refute @fork_repo.commits.exist? thread.commit_id

    assert_equal "aquaman2.txt", thread.position_data.path
  end

  test "#has_blob_positioning_data?" do
    thread = build(:pull_request_review_thread, pull_request: @pull, commit_id: "404ABC")
    refute thread.has_blob_positioning_data?

    thread.blob_position = 5
    refute thread.has_blob_positioning_data?

    thread.blob_commit_oid = "F" * 40
    refute thread.has_blob_positioning_data?

    thread.blob_path = "foo.txt"
    assert thread.has_blob_positioning_data?
  end

  test "fails validation for large diff entries with position_data setter" do
    thread = T.let(nil, T.nilable(PullRequestReviewThread))
    GitHub::Diff.stub_const(:DEFAULT_MAX_TOTAL_LINES, 5) do
      comparison = PullRequest::Comparison.find(pull: @pull, start_commit_oid: RANGE_START,
                                                end_commit_oid: RANGE_END, base_commit_oid: RANGE_BASE)

      review = @pull.pending_review_for(user: @fork_repo.owner, head_sha: comparison.end_commit.oid)
      thread = review.build_thread

      comment = thread.build_first_comment(
        user: @fork_repo.owner,
        body: "good job!",
        path: "aquaman2.txt",
        diff: comparison.diffs,
        side: :right,
        line: 2,
      )
      review.save
    end

    refute_predicate thread, :valid?
    assert_equal ["diff too large"], thread&.errors["path"]
  end

  test "passes validation for large diff entries if file-level" do
    GitHub.flipper[:file_level_commenting].enable
    thread = T.let(nil, T.nilable(PullRequestReviewThread))
    GitHub::Diff.stub_const(:DEFAULT_MAX_TOTAL_LINES, 5) do
      comparison = PullRequest::Comparison.find(pull: @pull, start_commit_oid: RANGE_START,
                                                end_commit_oid: RANGE_END, base_commit_oid: RANGE_BASE)

      review = @pull.pending_review_for(user: @fork_repo.owner, head_sha: comparison.end_commit.oid)
      thread = review.build_thread(subject_type: :file)

      comment = thread.build_first_comment(
        user: @fork_repo.owner,
        body: "good job!",
        path: "aquaman2.txt",
        diff: comparison.diffs,
        side: :right,
      )
      review.save
    end

    assert_predicate thread, :valid?
  end

  test "fails validation for large diff entries with direct setter" do
    thread = T.let(nil, T.nilable(PullRequestReviewThread))
    GitHub::Diff.stub_const(:DEFAULT_MAX_TOTAL_LINES, 5) do
      comparison = PullRequest::Comparison.find(pull: @pull, start_commit_oid: RANGE_START,
                                                end_commit_oid: RANGE_END, base_commit_oid: RANGE_BASE)

      review = @pull.pending_review_for(user: @fork_repo.owner, head_sha: comparison.end_commit.oid)
      thread = review.build_thread
      comment = thread.build_first_diff_position_comment(
        user: @fork_repo.owner,
        body: "good job!",
        diff: comparison.diffs,
        position: 3,
        path: "aquaman2.txt",
      )
      review.save
    end

    refute_predicate thread, :valid?
    assert_equal ["diff too large"], thread&.errors["path"]
  end

  test "commenting on left side of a context line" do
    thread = @review.build_thread
    comment = thread.build_first_comment(
      body: "comment",
      path: "aquaman2.txt",
      diff: @pull.historical_comparison.diffs,
      line: 1,
      side: :left,
    )

    assert comment.save, "valid comment could not save!"

    assert_blob_fields(thread, position: 0, path: "aquaman.txt", commit_oid: RANGE_BASE, left_blob: true)
    assert_diff_fields(thread, position: 1, path: "aquaman2.txt")
  end

  test "commenting on left and right side of a context line with different blob positions" do
    thread = @review.build_thread
    left_comment = thread.build_first_comment(
      body: "left side context comment",
      path: "aquaman2.txt",
      diff: @pull.historical_comparison.diffs,
      line: 37,
      side: :left,
    )

    assert thread.save, "valid thread could not save!"
    assert_blob_fields(thread, position: 36, path: "aquaman.txt", commit_oid: RANGE_BASE, left_blob: true)

    thread2 = @review.build_thread
    right_comment = thread2.build_first_comment(
      body: "right side context comment",
      path: "aquaman2.txt",
      diff: @pull.historical_comparison.diffs,
      line: 40,
      side: :right,
    )

    assert thread2.save, "valid thread could not save!"
    assert_blob_fields(thread2, position: 39, path: "aquaman2.txt", commit_oid: EXISTING_HEAD, left_blob: false)

    # Diff positions across both comments should match
    assert_diff_fields(thread, position: 24, path: "aquaman2.txt")
    assert_diff_fields(thread, position: 24, path: "aquaman2.txt")

    # And the extracted diff hunks should be identical
    assert_equal thread.diff_hunk, left_comment.diff_hunk
    assert_equal thread2.diff_hunk, right_comment.diff_hunk
  end

  context "with a start line specified" do
    test "creates a comment with the expected context line count" do
      thread = @review.build_thread
      comment = thread.build_first_comment(
        body: "comment",
        path: "aquaman2.txt",
        diff: @pull.historical_comparison.diffs,
        start_line: 2,
        start_side: :right,
        line: 6,
        side: :right,
      )

      assert comment.save, "valid comment could not save!"

      assert_equal 1, thread.async_adjusted_start_blob_position.sync
      assert_equal :right, thread.async_start_side.sync
      assert_equal 5, thread.start_position_offset
      refute_empty comment.diff_hunk
    end

    test "with a start line on a removal and end line on addition" do
      thread = @review.build_thread
      comment = thread.build_first_comment(
        body: "comment",
        path: "aquaman2.txt",
        diff: @pull.historical_comparison.diffs,
        start_line: 2,
        start_side: :left,
        line: 2,
        side: :right,
      )

      assert comment.save, "valid comment could not save!"

      assert_equal 1, thread.blob_position
      refute_predicate thread, :left_blob?
      assert_equal EXISTING_HEAD, thread.blob_commit_oid
      assert_equal "aquaman2.txt", thread.blob_path
      assert_equal 1, thread.start_position_offset
      assert_equal 1, thread.async_adjusted_start_blob_position.sync
      assert_equal :left, thread.async_start_side.sync
      refute_empty comment.diff_hunk
    end

    test "with a start line after the end line" do
      thread = @review.build_thread
      comment = thread.build_first_comment(
        body: "comment",
        path: "aquaman2.txt",
        diff: @pull.historical_comparison.diffs,
        start_line: 6,
        start_side: :right,
        line: 2,
        side: :right,
      )

      refute comment.save
      assert thread.errors.include?(:start_line)
    end

    test "with a start line & side the same as the end line & side" do
      thread = @review.build_thread
      comment = thread.build_first_comment(
        body: "comment",
        path: "aquaman2.txt",
        diff: @pull.historical_comparison.diffs,
        start_line: 2,
        start_side: :right,
        line: 2,
        side: :right,
      )

      refute comment.save
      assert thread.errors.include?(:start_line)
    end

    test "with a start line and end line beneath different hunk headers and the start_position_offset matches the diff_hunk_lines" do
      thread = @review.build_thread
      comment = thread.build_first_comment(
        body: "comment",
        path: "aquaman2.txt",
        diff: @pull.historical_comparison.diffs,
        start_line: 36,
        start_side: :right,
        line: 39,
        side: :right,
      )

      refute comment.save
      assert thread.errors.include?(:start_line)
      # This test case is modeling a situation where the computed start_position_offset
      # matches the length of the extracted diff_hunk_lines, but because the start and end
      # positions are beneath different hunk headers, we reject the comment. Since these
      # attributes are computed during validation, we're performing this assertion at the end.
      assert_equal comment.start_position_offset, thread.diff_hunk_lines.length
    end

    test "with a start line and end line beneath different hunk headers" do
      thread = @review.build_thread
      comment = thread.build_first_comment(
        body: "comment",
        path: "aquaman2.txt",
        diff: @pull.historical_comparison.diffs,
        start_line: 2,
        start_side: :right,
        line: 39,
        side: :right,
      )

      refute comment.save
      assert thread.errors.include?(:start_line)
    end

    test "copies position data onto reply comment" do
      thread = @review.build_thread
      comment = thread.build_first_comment(
        body: "comment",
        path: "aquaman2.txt",
        diff: @pull.historical_comparison.diffs,
        start_line: 2,
        start_side: :right,
        line: 6,
        side: :right,
      )
      assert comment.save, "valid comment could not save!"
      refute_nil comment.start_position_offset

      reply_comment = thread.build_reply(user: @fork_repo.owner, body: "This is a reply!")
      assert reply_comment.save, "valid reply comment could not save!"

      assert_equal comment.start_position_offset, reply_comment.start_position_offset
    end
  end

  context "#async_adjusted_start_blob_position" do
    test "returns the expected diff position for the start line of a multi line comment" do
      thread = @review.build_thread
      comment = thread.build_first_comment(
        body: "comment",
        path: "aquaman2.txt",
        diff: @pull.historical_comparison.diffs,
        start_line: 2,
        start_side: :right,
        line: 4,
        side: :right,
      )

      assert comment.save, "valid comment could not save!"
      assert_equal 1, thread.async_adjusted_start_blob_position.sync
    end

    test "returns the adjusted start diff position in a matching but updated diff" do
      thread = create_thread_with_comment(line: 34, side: :right, path: "aquaman2.txt", start_line: 31) # comic artists of that
      assert_equal 30, thread.async_adjusted_start_blob_position.sync
      assert_blob_fields(thread, position: 33, path: "aquaman2.txt", commit_oid: RANGE_END, left_blob: false)
      assert_diff_fields(thread, position: 19, path: "aquaman2.txt", commit_oid: EXISTING_HEAD)

      old_diff = @pull.async_diff.sync
      new_sha = @fork_repo.heads["blob_position_shift"].sha
      with_enqueued_pr_sync_jobs { @fork_repo.heads.find("rename-topic").update(new_sha, @fork_repo.owner) }

      assert_equal 28, thread.async_adjusted_start_blob_position.sync
      assert_blob_fields(thread, position: 31, path: "aquaman2.txt", commit_oid: new_sha, left_blob: false)
      assert_diff_fields(thread, position: 25, path: "aquaman2.txt", commit_oid: new_sha)

      # Can calculate old start position with previous diff
      assert_equal 30, thread.async_adjusted_start_blob_position(old_diff).sync
      assert_equal 30, thread.original_start_blob_position
    end

    test "is nil for single line comments" do
      thread = create_thread_with_comment(line: 34, side: :right, path: "aquaman2.txt")

      assert_nil thread.async_adjusted_start_blob_position.sync
      assert_nil thread.original_start_blob_position
      assert_equal 33, thread.blob_position
    end

    test "is nil if any intervening line has changed" do
      content = <<-AQUAMAN
 Shortly after the character's debut, Louis Cazeneuve succeeded Norris to become
 ~~~~ THE START LINE ~~~
 Cazeneuve debuted on "Aquaman" in More Fun Comics #82 (Aug. 1942), and continued
 with the feature through issue #107 (Feb. 1946), and its subsequent move to
 Adventure Comics #103-117, 119-120, 124 (April 1946 - June 1947, Aug.-Sept.
      AQUAMAN

      commit = @fork_repo.commits.create({ message: "changes", committer: @fork_repo.owner }, EXISTING_HEAD) do |files|
        files.add("multiaquaman.txt", content)
      end
      with_enqueued_pr_sync_jobs { @fork_repo.heads.find("rename-topic").update(commit, @fork_repo.owner) }

      thread = @review.build_thread
      comment = thread.build_first_comment(
        body: "comment",
        path: "multiaquaman.txt",
        diff: @pull.reload.historical_comparison.diffs,
        start_line: 2,
        start_side: :right,
        line: 4,
        side: :right,
      )

      assert thread.save
      assert_equal 1, thread.async_adjusted_start_blob_position.sync
      refute_predicate comment, :outdated?

      new_content = <<-AQUAMAN
 Shortly after the character's debut, Louis Cazeneuve succeeded Norris to become
 ~~~~ THE START LINE IS DIFFERENT ~~~
 Cazeneuve debuted on "Aquaman" in More Fun Comics #82 (Aug. 1942), and continued
 with the feature through issue #107 (Feb. 1946), and its subsequent move to
 Adventure Comics #103-117, 119-120, 124 (April 1946 - June 1947, Aug.-Sept.
      AQUAMAN

      updated_commit = @fork_repo.commits.create({ message: "changes", committer: @fork_repo.owner }, commit.oid) do |files|
        files.add("multiaquaman.txt", new_content)
      end
      with_enqueued_pr_sync_jobs { @fork_repo.heads.find("rename-topic").update(updated_commit, @fork_repo.owner) }

      thread.reload

      assert_nil thread.async_adjusted_start_blob_position.sync
      assert_predicate thread, :outdated?
    end
  end

  context "#original_start_blob_position" do
    test "handles truncated diff hunks" do
      thread = create_thread_with_comment(line: 34, side: :right, path: "aquaman2.txt", start_line: 31) # comic artists of that
      assert_equal 30, thread.original_start_blob_position

      # Simulate diff hunk truncation by setting a start position offset that is
      # higher than the line length stored in the diff_hunk column
      assert thread.update(start_position_offset: thread.diff_hunk_lines.size + 1)

      assert_nil thread.original_start_blob_position
    end
  end

  context "#async_diff_lines" do
    test "handles truncated diff hunks" do
      max_context_lines = 15
      thread = create_thread_with_comment(line: 34, side: :right, path: "aquaman2.txt", start_line: 31) # comic artists of that
      assert_equal 30, thread.original_start_blob_position

      # Simulate diff hunk truncation by setting a start position offset that is
      # higher than the line length stored in the diff_hunk column
      assert thread.update(start_position_offset: thread.diff_hunk_lines.size + 1)

      assert_equal thread.diff_hunk_lines.size,
        thread.async_diff_lines(max_context_lines: max_context_lines).sync.to_a.size
    end
  end

  context "#start_side" do
    test "handles truncated diff hunks" do
      thread = create_thread_with_comment(line: 34, side: :right, path: "aquaman2.txt", start_line: 31) # comic artists of that

      # Simulate diff hunk truncation by setting a start position offset that is
      # higher than the line length stored in the diff_hunk column
      assert thread.update(start_position_offset: thread.diff_hunk_lines.size + 1)

      assert_nil thread.start_side
    end
  end
end
