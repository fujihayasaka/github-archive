# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/pull_requests"

class ThreadPositionerTest < GitHub::TestCase
  include GitHub::PullRequestTestHelpers

  fixtures do
    @source = create(:repository, owner: create(:user), from_example: :empty)
    @fork = create(:fork_repository, forker: create(:user), fork_repo: @source, from_example: :empty)

    lines = (1..100).map { |i| "line #{i}" }

    @base_commit = @source.commits.create({ message: "base commit", committer: @source.owner }) do |files|
      files.add "subdir/zelda.txt", lines.join("\n")
    end.freeze

    ref = @source.heads.create("master", @base_commit, @source.owner)

    @fork.rpc.fetch_commits(@source.shard_path, @base_commit.oid)

    lines = (1..15).map { |i| "intro line #{i}" } + lines

    ref = @fork.heads.create("topic1", @base_commit, @fork.owner)
    @commit1 = ref.append_commit({ message: "commit 1", committer: @fork.owner }, @fork.owner) do |files|
      files.remove "subdir/zelda.txt"
      files.add "subdir/link.txt", lines.join("\n")
    end.freeze

    lines = T.must(lines[0..40]) + (1..3).map { |i| "new line #{i}!" } + T.must(lines[41..50]) + T.must(lines[60..-1])

    ref = @fork.heads.create("topic2", @commit1, @fork.owner)
    @commit2 = ref.append_commit({ message: "commit 2", committer: @fork.owner }, @fork.owner) do |files|
      files.add "subdir/link.txt", lines.join("\n")
    end.freeze
    @commit3 = ref.append_commit({ message: "commit 3", committer: @fork.owner }, @fork.owner) do |files|
      files.add "other", "data"
    end.freeze

    missing_ref = @fork.heads.create("object-missing", @commit3, @fork.owner)
    lines = (1..15).map { |i| "extra new line #{i}!" } + lines
    missing_ref.append_commit({ message: "commit missing", committer: @fork.owner }, @fork.owner) do |files|
      files.add "subdir/link.txt", lines.join("\n")
    end

    @topic1_pr  = make_pr(@source, @fork, branch: "topic1")
    @topic2_pr  = make_pr(@source, @fork, branch: "topic2")
    @missing_pr = make_pr(@source, @fork, branch: "object-missing")

    # Create ref/commit/PR for testing positioning of thread comments
    @threads_testing_branch_name = "threads-testing"
    @threads_testing_file_path = "subdir/new_file.txt"
    @threads_testing_ref = @fork.heads.create(@threads_testing_branch_name, @base_commit, @fork.owner)
    @threads_testing_commit = @threads_testing_ref.append_commit({ message: "commit", committer: @fork.owner }, @fork.owner) do |files|
      files.add @threads_testing_file_path, (1..10).map { |i| "new line #{i}!" }.join("\n")
    end.freeze
    @threads_testing_pr = make_pr(@source, @fork, branch: @threads_testing_branch_name)
    @threads_testing_ref.freeze

    @path = "subdir/zelda.txt"
    @path2 = "subdir/link.txt"

    @viewer = @source.owner
    example_repo_snapshot
  end

  setup do
    example_repo_restore
    @comment_count = 0
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    GitHub::Diff.max_total_lines = GitHub::Diff::DEFAULT_MAX_TOTAL_LINES
  end

  context "on current diff" do
    test "groups comments" do
      comparison = PullRequest::Comparison.find(pull: @topic1_pr, start_commit_oid: @base_commit.oid,
        end_commit_oid: @commit1.oid, base_commit_oid: @base_commit.oid)

      assert_predicate comparison, :current?

      c1 = create_comment(comparison: comparison, line: 7, side: :right, path: @path2)
      c2 = create_comment(comparison: comparison, line: 7, side: :right, path: @path2)
      c3 = create_comment(comparison: comparison, line: 7, side: :right, path: @path2, parent: c1)

      comparison = PullRequest::Comparison.find(pull: @topic1_pr.reload, start_commit_oid: @base_commit.oid,
        end_commit_oid: @commit1.oid, base_commit_oid: @base_commit.oid)

      thread_positioner = PullRequest::ThreadPositioner.new(@source.owner, comparison)
      threads = thread_positioner.positioned_threads

      review_threads = threads.path(@path2).position(7)
      assert_equal 2, review_threads.count

      comments = review_threads.map { |t| t.comments.to_a.sort_by(&:id) }
      assert_same_elements [[c1, c3], [c2]], comments
    end

    test "sends a unique list of positioning data elements to gitrpc" do
      comparison = PullRequest::Comparison.find(pull: @topic1_pr, start_commit_oid: @base_commit.oid,
        end_commit_oid: @commit1.oid, base_commit_oid: @base_commit.oid)

      assert_predicate comparison, :current?

      c1 = create_comment(comparison: comparison, line: 7, side: :right, path: @path2)
      c2 = create_comment(comparison: comparison, line: 7, side: :right, path: @path2)
      c3 = create_comment(comparison: comparison, line: 7, side: :right, path: @path2, parent: c1)

      comparison = PullRequest::Comparison.find(pull: @topic1_pr.reload, start_commit_oid: @base_commit.oid,
        end_commit_oid: @commit1.oid, base_commit_oid: @base_commit.oid)

      expected_data = [{
        position: 6,
        source: {
          commit_oid: @commit1.oid,
          path:       "subdir/link.txt",
        },
        destination: {
          commit_oid: @commit1.oid,
          path:       "subdir/link.txt",
        },
      }]

      GitRPC::Client.any_instance.expects(:read_commit_adjusted_positions_with_base).at_least_once.with(expected_data, skip_bad: true).returns([7])

      thread_positioner = PullRequest::ThreadPositioner.new(@source.owner, comparison)
      threads = thread_positioner.positioned_threads
      assert_equal 2, threads.count
    end

    test "groups mixed blob and diff comments" do
      comparison = PullRequest::Comparison.find(pull: @topic1_pr, start_commit_oid: @base_commit.oid,
        end_commit_oid: @commit1.oid, base_commit_oid: @base_commit.oid)

      assert_predicate comparison, :current?

      c1 = create_comment(comparison: comparison, line: 7, side: :right, path: @path2)
      c2 = create_comment(comparison: comparison, line: 7, side: :right, path: @path2)

      c2.blob_position   = nil
      c2.blob_path       = nil
      c2.blob_commit_oid = nil
      c2.save!

      refute_predicate c2.pull_request_review_thread, :has_blob_positioning_data?

      comparison = PullRequest::Comparison.find(pull: @topic1_pr.reload, start_commit_oid: @base_commit.oid,
        end_commit_oid: @commit1.oid, base_commit_oid: @base_commit.oid)

      thread_positioner = PullRequest::ThreadPositioner.new(@source.owner, comparison)
      threads = thread_positioner.positioned_threads

      review_threads = threads.path(@path2).position(7)
      assert_equal 2, review_threads.count

      comments = review_threads.map { |t| t.comments.to_a }
      assert_equal [[c1], [c2]], comments
    end
  end

  context "on a deleted file" do
    test "threads are positioned properly" do
      ref = @fork.heads.create("file-removed", @base_commit, @fork.owner)
      removed = ref.append_commit({ message: "commit", committer: @fork.owner }, @fork.owner) do |files|
        files.remove "subdir/zelda.txt"
      end

      pull = make_pr(@source, @fork, branch: "file-removed")

      original_comparison = PullRequest::Comparison.find(pull: pull, start_commit_oid: @base_commit.oid,
        end_commit_oid: removed.oid, base_commit_oid: @base_commit.oid)

      c1 = create_comment(comparison: original_comparison, line: 7, side: :left, path: "subdir/zelda.txt")

      comparison = PullRequest::Comparison.find(pull: pull.reload, start_commit_oid: @base_commit.oid,
        end_commit_oid: removed.oid, base_commit_oid: @base_commit.oid)

      thread_positioner = PullRequest::ThreadPositioner.new(@fork.owner, comparison)
      threads = thread_positioner.positioned_threads

      assert_equal 1, threads.path("subdir/zelda.txt").position(7).count
    end
  end

  context "on a diff range" do
    test "repositions and filters when the range causes diff shift" do
      comparison = PullRequest::Comparison.find(pull: @topic2_pr, start_commit_oid: @base_commit.oid,
        end_commit_oid: @commit2.oid, base_commit_oid: @base_commit.oid)

      # We test one for each scenario, over a rename.

      # comment that will not be included in second comparison
      c1 = create_comment(comparison: comparison, line: 7, side: :right, path: @path2)  # +intro line 7

      # context comment
      c2 = create_comment(comparison: comparison, line: 53, side: :right, path: @path2) #  line 35

      # deletion comment
      c3 = create_comment(comparison: comparison, line: 42, side: :left, path: @path2) # -line 42

      # addition comment
      c4 = create_comment(comparison: comparison, line: 43, side: :right, path: @path2) # +new line 2!

      # View a different range which requires blob positions to be recalculated
      comparison2 = PullRequest::Comparison.find(pull: @topic2_pr.reload, start_commit_oid: @commit1.oid,
        end_commit_oid: @commit3.oid, base_commit_oid: @base_commit.oid)

      all_threads = comparison2.review_threads_for(viewer: @viewer)

      # The following ternary and all other following conditional statements around
      # the comment_outside_the_diff feature are explicitly altering the expectations
      # of the tests, given that the present implementation of the code under that
      # feature alters the diff such that all comments created above are included
      # in the second comparison's diff. This is a temporary solution while the approach
      # to the feature is being refined
      expected_thread_count = GitHub.flipper[:comment_outside_the_diff].enabled? ? 4 : 3
      assert_equal expected_thread_count, all_threads.path(@path2).count
      threads = if GitHub.flipper[:comment_outside_the_diff].enabled?
        all_threads.path(@path2).position(11)
      else
        all_threads.path(@path2).position(5)
      end

      assert_equal [c4], threads.first.comments

      threads = if GitHub.flipper[:comment_outside_the_diff].enabled?
        all_threads.path(@path2).position(19)
      else
        all_threads.path(@path2).position(12)
      end

      assert_equal [c2], threads.first.comments

      threads = if GitHub.flipper[:comment_outside_the_diff].enabled?
        all_threads.path(@path2).position(26)
      else
        all_threads.path(@path2).position(19)
      end

      assert_equal [c3], threads.first.comments
    end

    test "repositions multiline comments when the range causes diff shift" do
      initial_comparison1 = PullRequest::Comparison.find(pull: @missing_pr, start_commit_oid: @base_commit.oid,
        end_commit_oid: @commit1.oid, base_commit_oid: @base_commit.oid)

      comment = create_comment(comparison: initial_comparison1, start_line: 1, start_side: :right, line: 3, side: :right, path: @path2) # "+intro line 1", "+intro line 2", "+intro line 3"

      comparison1 = PullRequest::Comparison.find(pull: @missing_pr.reload, start_commit_oid: @base_commit.oid,
        end_commit_oid: @commit1.oid, base_commit_oid: @base_commit.oid)

      comparison1_threads = comparison1.review_threads_for(viewer: @viewer)
      assert_equal 1, comparison1_threads.path(@path2).count

      threads = comparison1_threads.path(@path2).position(3)
      assert_equal [comment], threads.first.comments

      review_thread = threads.first
      assert_equal 1, review_thread.start_diff_line.current
      assert_equal 3, review_thread.end_diff_line.current

      # View a different range which requires blob positions to be recalculated
      comparison2 = PullRequest::Comparison.find(pull: @missing_pr.reload, start_commit_oid: @base_commit.oid,
        end_commit_oid: @missing_pr.head_sha, base_commit_oid: @base_commit.oid)

      comparison2_threads = comparison2.review_threads_for(viewer: @viewer)
      assert_equal 1, comparison2_threads.path(@path2).count

      # 15 new lines were added at the top of the file in the latest commit,
      # so the diff position and blob positions should shift down 15 lines each.
      threads2 = comparison2_threads.path(@path2).position(18)
      assert_equal [comment], threads2.first.comments

      review_thread2 = threads2.first
      assert_equal 16, review_thread2.start_diff_line.current
      assert_equal 18, review_thread2.end_diff_line.current
    end
  end

  test "positions comments only on selected paths" do
    ref = @fork.heads.create("topic3", @base_commit, @fork.owner)

    @commit4 = ref.append_commit({ message: "commit", committer: @fork.owner }, @fork.owner) do |files|
      ("a".."g").each do |letter|
        files.add letter, ([letter] * 10).join("\n")
      end
    end

    @commit5 = ref.append_commit({ message: "commit", committer: @fork.owner }, @fork.owner) do |files|
      files.add "f", "This is the letter f\n#{(["f"] * 10).join("\n")}"
      files.add "g", "This is the letter g\n#{(["g"] * 10).join("\n")}"
    end

    pull = make_pr(@source, @fork, branch: "topic3")

    GitHub::Diff.stub_const(:DEFAULT_MAX_FILES, 1) do
      # comment on a non current diff of the PR
      original_comparison = PullRequest::Comparison.find(pull: pull, start_commit_oid: @base_commit.oid,
        end_commit_oid: @commit4.oid, base_commit_oid: @base_commit.oid)
      comment = create_comment(comparison: original_comparison, line: 2, side: :right, path: "f") # second f line

      # ensure they are repositioned, despite being beyond the max_files limit with the default diff
      assert_equal 3, comment.position

      # new comparison as the previous one describes all paths in the PR and gets truncated. This one is just for "f"
      comparison = PullRequest::Comparison.find(pull: pull.reload, start_commit_oid: @base_commit.oid,
        end_commit_oid: @commit4.oid, base_commit_oid: @base_commit.oid)
      comparison.diffs.add_path("f")

      # view that non-current part of the PR which includes the comment
      thread_positioner = PullRequest::ThreadPositioner.new(@viewer, comparison)
      threads = thread_positioner.positioned_threads

      assert_equal 1, threads.count

      thread = threads.first
      assert_equal 2, thread.position
      assert_equal "f", thread.path

      # new comparison as the previous one describes all paths in the PR and gets truncated. This one is just for "g"
      comparison = PullRequest::Comparison.find(pull: pull, start_commit_oid: @base_commit.oid,
        end_commit_oid: @commit4.oid, base_commit_oid: @base_commit.oid)
      comparison.diffs.add_path("g")

      thread_positioner = PullRequest::ThreadPositioner.new(@viewer, comparison)
      threads = thread_positioner.positioned_threads
      assert_empty threads
    end
  end

  test "shows pending review comments to the author" do
    original_comparison = PullRequest::Comparison.find(pull: @topic1_pr, start_commit_oid: @base_commit.oid,
      end_commit_oid: @commit1.oid, base_commit_oid: @base_commit.oid)

    c1 = create_comment(comparison: original_comparison, line: 7, side: :right, path: @path2)
    c2 = create_comment(comparison: original_comparison, line: 7, side: :right, path: @path2, single_comment: false)

    comparison = PullRequest::Comparison.find(pull: @topic1_pr.reload, start_commit_oid: @base_commit.oid,
      end_commit_oid: @commit1.oid, base_commit_oid: @base_commit.oid)

    thread_positioner = PullRequest::ThreadPositioner.new(@topic1_pr.head_user, comparison)
    threads = thread_positioner.positioned_threads

    assert_equal 2, threads.size

    submitted = threads.path(@path2).position(7).first.comments
    assert_equal 1, submitted.size
    assert_predicate submitted.first, :submitted?

    pending = threads.path(@path2).position(7).last.comments
    assert_equal 1, pending.size
    assert_predicate pending.first, :pending?
  end

  test "hides pending review comments from non-authors" do
    original_comparison = PullRequest::Comparison.find(pull: @topic1_pr, start_commit_oid: @base_commit.oid,
      end_commit_oid: @commit1.oid, base_commit_oid: @base_commit.oid)

    c1 = create_comment(comparison: original_comparison, line: 7, side: :right, path: @path2)
    c2 = create_comment(comparison: original_comparison, line: 7, side: :right, path: @path2, single_comment: false)

    comparison = PullRequest::Comparison.find(pull: @topic1_pr.reload, start_commit_oid: @base_commit.oid,
      end_commit_oid: @commit1.oid, base_commit_oid: @base_commit.oid)

    thread_positioner = PullRequest::ThreadPositioner.new(@source.owner, comparison)
    threads = thread_positioner.positioned_threads

    assert_equal 1, threads.size

    submitted = threads.path(@path2).position(7).first.comments
    assert_equal 1, submitted.size
    assert_predicate submitted.first, :submitted?
    assert_equal c1, submitted.first
  end

  test "outdated comments are not included" do
    ref = @fork.heads.create("deleted-file", @commit1, @fork.owner)

    @commit6 = ref.append_commit({ message: "commit", committer: @fork.owner }, @fork.owner) do |files|
      files.remove @path2
    end

    pull = make_pr(@source, @fork, branch: "deleted-file")
    comparison = PullRequest::Comparison.find(pull: pull, start_commit_oid: @base_commit.oid,
      end_commit_oid: @commit1.oid, base_commit_oid: @base_commit.oid)
    c1 = create_comment(comparison: comparison, line: 7, side: :right, path: @path)
    file_level_comment = create_comment(comparison: comparison, side: :right, path: @path, subject_type: "file")

    comparison2 = PullRequest::Comparison.find(pull: pull, start_commit_oid: @base_commit.oid,
      end_commit_oid: @commit6.oid, base_commit_oid: @base_commit.oid)

    assert_empty comparison2.review_threads_for(viewer: pull.base_user)
  end

  context "#threads_in_range" do
    test "includes line & file level threads" do
      disable_feature_flag(:comment_outside_the_diff)

      comparison = PullRequest::Comparison.find(pull: @threads_testing_pr, start_commit_oid: @base_commit.oid,
        end_commit_oid: @threads_testing_commit.oid, base_commit_oid: @base_commit.oid)

      line_level_comment = create_comment(comparison: comparison, side: :right, path: @threads_testing_file_path, subject_type: "line", line: 2)
      file_level_comment = create_comment(comparison: comparison, side: :right, path: @threads_testing_file_path, subject_type: "file")


      thread_positioner = PullRequest::ThreadPositioner.new(@threads_testing_pr.head_user, comparison)
      threads = thread_positioner.threads_in_range

      assert_equal 2, threads.size
      assert_same_elements [line_level_comment, file_level_comment], threads.flat_map { |t| t.comments.first }
    end
  end

  context "#positioned_threads" do
    test "returns only line level threads" do
      disable_feature_flag(:comment_outside_the_diff)

      comparison = PullRequest::Comparison.find(pull: @threads_testing_pr, start_commit_oid: @base_commit.oid,
        end_commit_oid: @threads_testing_commit.oid, base_commit_oid: @base_commit.oid)

      file_level_comment = create_comment(comparison: comparison, side: :right, path: @threads_testing_file_path, subject_type: "file")
      line_level_comment = create_comment(comparison: comparison, side: :right, path: @threads_testing_file_path, subject_type: "line", line: 2)

      thread_positioner = PullRequest::ThreadPositioner.new(@threads_testing_pr.head_user, comparison)
      threads = thread_positioner.positioned_threads

      assert_equal 1, threads.size

      assert_same_elements threads.threads.map { |t| t.activerecord_pull_review_thread.id }, [line_level_comment.pull_request_review_thread.id]
    end
  end

  context "#file_level_threads" do
    test "returns only file level threads" do
      disable_feature_flag(:comment_outside_the_diff)

      comparison = PullRequest::Comparison.find(pull: @threads_testing_pr, start_commit_oid: @base_commit.oid,
        end_commit_oid: @threads_testing_commit.oid, base_commit_oid: @base_commit.oid)

      file_level_comment = create_comment(comparison: comparison, side: :right, path: @threads_testing_file_path, subject_type: "file")
      line_level_comment = create_comment(comparison: comparison, side: :right, path: @threads_testing_file_path, subject_type: "line", line: 2)

      thread_positioner = PullRequest::ThreadPositioner.new(@threads_testing_pr.head_user, comparison)
      review_threads_collection = thread_positioner.file_level_threads

      assert_equal 1, review_threads_collection.size

      assert_same_elements review_threads_collection.threads.map { |t| t.activerecord_pull_review_thread.id }, [file_level_comment.pull_request_review_thread.id]
    end
  end

  context "file level threads" do
    test "included when it is part of the diff" do
      disable_feature_flag(:comment_outside_the_diff)

      comparison = PullRequest::Comparison.find(pull: @threads_testing_pr, start_commit_oid: @base_commit.oid,
        end_commit_oid: @threads_testing_commit.oid, base_commit_oid: @base_commit.oid)

      file_level_comment = create_comment(comparison: comparison, side: :right, path: @threads_testing_file_path, subject_type: "file")
      assert_nil file_level_comment.position

      thread_positioner = PullRequest::ThreadPositioner.new(@threads_testing_pr.head_user, comparison)
      threads = thread_positioner.file_level_threads

      assert_equal 1, threads.size
    end
  end

  test "unpositionable threads are abandoned" do
    original_comparison = PullRequest::Comparison.find(pull: @topic1_pr, start_commit_oid: @base_commit.oid,
      end_commit_oid: @commit1.oid, base_commit_oid: @base_commit.oid)

    c1 = create_comment(comparison: original_comparison, line: 7, side: :right, path: @path2)
    c2 = create_comment(comparison: original_comparison, line: 7, side: :right, path: @path2, single_comment: false)

    c1.update!(blob_commit_oid: "f" * 40, diff_hunk: "this is invalid diff text!")

    comparison = PullRequest::Comparison.find(pull: @topic1_pr.reload, start_commit_oid: @base_commit.oid,
      end_commit_oid: @commit1.oid, base_commit_oid: @base_commit.oid)

    thread_positioner = PullRequest::ThreadPositioner.new(@topic1_pr.head_user, comparison)
    threads = thread_positioner.positioned_threads

    assert_equal 1, threads.size
  end

  test "#review_threads on skipped entry" do
    ref = @fork.heads.create("skipped-entry", @base_commit, @fork.owner)

    @commit7 = ref.append_commit({ message: "commit", committer: @fork.owner }, @fork.owner) do |files|
      files.add "extra1.txt", ("skipme 1\n" * 100)
      files.add "extra2.txt", ("skipme 2\n" * 100)
      files.add "extra3.txt", ("skipme 3\n" * 100)
    end

    @commit8 = ref.append_commit({ message: "commit", committer: @fork.owner }, @fork.owner)

    pull = make_pr(@source, @fork, branch: "skipped-entry")

    # comment on what will be considered a skipped file when we lower the limits. This
    # simulates a user clicking to "load diff" a skipped diff and then commenting on it
    # by lowering the limit afterwards
    comparison = PullRequest::Comparison.find(pull: pull, start_commit_oid: @base_commit.oid,
      end_commit_oid: @commit7.oid, base_commit_oid: @base_commit.oid)

    c1 = create_comment(comparison: comparison, line: 1, side: :right, path: "extra3.txt")

    GitHub::Diff.max_diff_lines = 50

    # current range first:
    comparison = PullRequest::Comparison.find(pull: pull.reload, start_commit_oid: @base_commit.oid,
      end_commit_oid: @commit8.oid, base_commit_oid: @base_commit.oid)

    # now everything is skipped
    assert comparison.diffs.entries.all?(&:skipped?), "all diffs should be skipped"

    assert comparison.current?, "comparison should be current for this range"

    # ensure we still can position that comment, even though its diff is skipped. This is
    # possible because not a single entry loaded, so we use the requested paths.
    thread_positioner = PullRequest::ThreadPositioner.new(@fork.owner, comparison)
    threads = thread_positioner.positioned_threads

    assert_equal 1, threads.count

    # now partial range
    comparison = PullRequest::Comparison.find(pull: pull, start_commit_oid: @base_commit.oid,
      end_commit_oid: @commit7.oid, base_commit_oid: @base_commit.oid)

    refute comparison.current?, "comparison should be for a range"

    # ensure we still can position that comment, even though its diff is skipped
    thread_positioner = PullRequest::ThreadPositioner.new(@fork.owner, comparison)
    threads = thread_positioner.positioned_threads

    assert_equal 1, threads.count
  end

  context "#selected_paths" do

    test "returns empty list when entire diff is truncated" do
      GitHub::Diff.max_total_lines = 2
      comparison = PullRequest::Comparison.find(pull: @topic1_pr, start_commit_oid: @base_commit.oid,
        end_commit_oid: @commit1.oid, base_commit_oid: @base_commit.oid)

      comparison.diffs.load_diff

      thread_positioner = PullRequest::ThreadPositioner.new(@fork.owner, comparison)
      assert_equal [], thread_positioner.selected_paths
    end

    test "returns loaded paths" do
      GitHub::Diff.stub_const(:DEFAULT_MAX_FILES, 1) do
        comparison = PullRequest::Comparison.find(pull: @topic2_pr, start_commit_oid: @base_commit.oid,
          end_commit_oid: @commit3.oid, base_commit_oid: @base_commit.oid)

        comparison.diffs.load_diff

        thread_positioner = PullRequest::ThreadPositioner.new(@fork.owner, comparison)

        assert_equal ["other"], thread_positioner.selected_paths
      end
    end

    test "returns requested paths when diff is not loaded" do
      comparison = PullRequest::Comparison.find(pull: @topic2_pr, start_commit_oid: @base_commit.oid,
        end_commit_oid: @commit3.oid, base_commit_oid: @base_commit.oid)

      thread_positioner = PullRequest::ThreadPositioner.new(@fork.owner, comparison)

      assert_equal ["other", "subdir/zelda.txt", "subdir/link.txt"], thread_positioner.selected_paths
    end
  end

  test "position on non-current unicode heavy diffs" do
    ref = @fork.heads.create("unycode", @base_commit, @fork.owner)
    chars = "\xE3\x81\x9D\xE3\x82\x8C\xE3\x81\x9E\xE3\x82\x8C\xE3\x81\xAE\xE5\xBD\xB1\xE9\x9F\xBF\xE5\x8A\x9B\xE3\x81\xAB\xE3\x81\xA4\xE3\x81\x84\xE3\x81\xA6\xE8\xA6\x8B\xE3\x81\xA6\xE3\x81\xBF\xE3\x82\x88\xE3\x81\x86\xE3\x80\x82\xE3\x81\x9D\xE3\x81\x97\xE3\x81\xA6\xE3\x80\x81\xE7\x8F\xBE\xE5\xAE\x9F\xE3\x81\xAE\xE4\xBC\x81\xE6\xA5\xAD\xE7\xB5\x84\xE7\xB9\x94\xE3\x81\xAE\xE7\x92\xB0\xE5\xA2\x83\xE3\x82\x92\xE6\x83\xB3\xE5\x83\x8F\xE3\x81\x97\xE3\x81\xA6\xE3\x81\xBF\xE3\x82\x88\xE3\x81\x86\xE3\x80\x82".split("")
    data = chars.map { |c| "#{c}\n" }.join
    commit1 = ref.append_commit({ message: "commit", committer: @fork.owner }, @fork.owner) do |files|
      files.add "unicode.md", data
    end
    ref.append_commit({ message: "commit", committer: @fork.owner }, @fork.owner) do |files|
      files.add "unicode.md", "farewell data\n"
    end

    pull = make_pr(@source, @fork, branch: "unycode")

    original_comparison = PullRequest::Comparison.find(pull: pull, start_commit_oid: @base_commit.oid,
      end_commit_oid: commit1.oid, base_commit_oid: @base_commit.oid)

    c = create_comment(comparison: original_comparison, line: 35, side: :right, path: "unicode.md")

    comparison = PullRequest::Comparison.find(pull: pull.reload, start_commit_oid: @base_commit.oid,
      end_commit_oid: commit1.oid, base_commit_oid: @base_commit.oid)

    thread_positioner = PullRequest::ThreadPositioner.new(@fork.owner, comparison)
    threads = thread_positioner.positioned_threads

    assert_equal 1, threads.path("unicode.md").position(35).count
  end

  test "does not load the diff when there are no comments" do
    comparison = PullRequest::Comparison.find(pull: @topic1_pr, start_commit_oid: @base_commit.oid,
      end_commit_oid: @commit1.oid, base_commit_oid: @base_commit.oid)

    GitRPC::Client.any_instance.expects(:read_diff_pairs_with_base).never
    GitRPC::Client.any_instance.expects(:native_read_diff_toc).never
    GitRPC::Client.any_instance.expects(:read_diff_summary).never

    grouper = PullRequest::ThreadPositioner.new(@source.owner, comparison)
    assert_empty grouper.positioned_threads
  end

  context "with object missing" do
    test "comment on deletion" do
      original_comparison = PullRequest::Comparison.find(pull: @topic2_pr, start_commit_oid: @base_commit.oid,
        end_commit_oid: @commit3.oid, base_commit_oid: @base_commit.oid)

      c = create_comment(comparison: original_comparison, line: 39, side: :left, path: "subdir/zelda.txt") # `-line 39`

      c.update(original_commit_id: "e1" * 20, original_start_commit_id: nil)

      comparison = PullRequest::Comparison.find(pull: @topic2_pr.reload, start_commit_oid: @base_commit.oid,
        end_commit_oid: @commit3.oid, base_commit_oid: @base_commit.oid)

      thread_positioner = PullRequest::ThreadPositioner.new(@fork.owner, comparison)
      threads = thread_positioner.positioned_threads

      assert_equal 1, threads.count
    end

    test "comment on deletion with unguessable base oid" do
      original_comparison = PullRequest::Comparison.find(pull: @topic2_pr, start_commit_oid: @base_commit.oid,
        end_commit_oid: @commit3.oid, base_commit_oid: @base_commit.oid)

      c = create_comment(comparison: original_comparison, line: 39, side: :left, path: "subdir/zelda.txt") # `-line 39`

      c.update(original_commit_id: "e1" * 20, original_start_commit_id: nil,
        original_base_commit_id: nil)

      comparison = PullRequest::Comparison.find(pull: @topic2_pr.reload, start_commit_oid: @base_commit.oid,
          end_commit_oid: @commit3.oid, base_commit_oid: @base_commit.oid)

      thread_positioner = PullRequest::ThreadPositioner.new(@fork.owner, comparison)
      threads = thread_positioner.positioned_threads

      assert_equal 1, threads.count
    end

    test "comment on addition" do
      original_comparison = PullRequest::Comparison.find(pull: @missing_pr, start_commit_oid: @base_commit.oid,
        end_commit_oid: @commit3.oid, base_commit_oid: @base_commit.oid)

      c = create_comment(comparison: original_comparison, line: 56, side: :right, path: "subdir/link.txt") # ` line 47`, blob position 55

      comparison = PullRequest::Comparison.find(pull: @missing_pr.reload, start_commit_oid: @base_commit.oid,
        end_commit_oid: @missing_pr.head_sha, base_commit_oid: @base_commit.oid) # blob position 70 in this comparison

      c.update(original_commit_id: "e1" * 20, original_end_commit_id: nil)

      # TODO (mclark) remove this stub line once the backend support for :bad has shipped
      GitRPC::Client.any_instance.stubs(:read_commit_adjusted_positions_with_base).returns([:bad])

      thread_positioner = PullRequest::ThreadPositioner.new(@fork.owner, comparison)
      threads = thread_positioner.positioned_threads

      assert_equal 1, threads.path("subdir/link.txt").position(58).count
    end

    test "outdated comment" do
      comparison = PullRequest::Comparison.find(pull: @missing_pr, start_commit_oid: @base_commit.oid,
        end_commit_oid: @missing_pr.head_sha, base_commit_oid: @base_commit.oid)

      c = create_comment(comparison: comparison, line: 2, side: :right, path: "subdir/link.txt") # `+extra new line 2!`
      c.update(original_commit_id: "e1" * 20, original_end_commit_id: nil)

      comparison = PullRequest::Comparison.find(pull: @missing_pr, start_commit_oid: @base_commit.oid,
        end_commit_oid: @commit3.oid, base_commit_oid: @base_commit.oid)

      thread_positioner = PullRequest::ThreadPositioner.new(@fork.owner, comparison)
      threads = thread_positioner.positioned_threads

      assert_equal 0, threads.count
    end
  end

  def create_comment(comparison:, path:, user: nil, single_comment: true, parent: nil, side:, line: nil, start_line: nil, start_side: nil, subject_type: "line")
    user = comparison.pull.head_user if user.nil?
    review = comparison.pull.pending_review_for(user: user, head_sha: comparison.end_commit.oid)

    if parent
      thread = parent.pull_request_review_thread
      comment = thread.build_reply(
        pull_request_review: review,
        user: user,
        body: next_comment_body,
      )
    else
      thread = review.build_thread(subject_type: subject_type)
      comment = thread.build_first_comment(
        user: user,
        body: next_comment_body,
        side: side,
        line: line,
        start_side: start_side,
        start_line: start_line,
        path: path,
        diff: comparison.diffs,
      )
    end

    comment.save!
    thread.save!
    review.save!

    review.comment! if single_comment

    comparison.pull.review_comments.reload
    review.review_comments.reload

    comment
  end

  def next_comment_body
    @comment_count += 1
    "Comment #{@comment_count}"
  end
end

class ThreadPositionerWithMergedBaseTest < GitHub::TestCase
  include GitHub::PullRequestTestHelpers

  fixtures do

    # c1---c3---c8--------------------------    master
    #  \     \                    \
    #   ---c2---c4---c5---c6---c7---c9---c10    topic

    @repo = create(:repository, from_example: :empty)
    @c1 = @repo.commits.create({ message: "base commit", committer: @repo.owner }) do |files|
      files.add "notes.txt", content(1..200)
    end.freeze

    @c2 = @repo.commits.create({ message: "commit 2", committer: @repo.owner }, @c1.oid) do |files|
      files.add "notes.txt", content(1..120, 125..200)
    end.freeze

    @c3 = @repo.commits.create({ message: "commit 3", committer: @repo.owner }, @c1.oid) do |files|
      files.add "notes.txt", content(1..100, ["Foo"] * 7, 101..200)
    end.freeze

    @c4, _ = @repo.commits.create_merge_commit(@repo.owner, @c2.oid, @c3.oid, commit_message: "commit 4")
    @c4.freeze

    lines = [1..100, ["Foo"] * 7, 101..120, 125..175, 178..200]
    @c5 = @repo.commits.create({ message: "commit 5", committer: @repo.owner }, @c4.oid) do |files|
      files.add "notes.txt", content(*lines)
    end.freeze

    @c6 = @repo.commits.create({ message: "commit 6", committer: @repo.owner }, @c5.oid) do |files|
      files.add "notes.txt", T.unsafe(self).content(*(lines + [501..700]))
    end.freeze

    @c7 = @repo.commits.create({ message: "commit 7", committer: @repo.owner }, @c6.oid) do |files|
      files.add "notes.txt", T.unsafe(self).content(*(lines + [501..620, 625..700]))
    end.freeze

    @c8 = @repo.commits.create({ message: "commit 8", committer: @repo.owner }, @c3.oid) do |files|
      files.add "notes.txt", content("a".."z", 1..100, ["Foo"] * 7, 101..200)
    end.freeze

    @c9, _ = @repo.commits.create_merge_commit(@repo.owner, @c7.oid, @c8.oid, commit_message: "commit 9")
    @c9.freeze

    @c10 = @repo.commits.create({ message: "commit 10", committer: @repo.owner }, @c9.oid) do |files|
      files.add "notes.txt", T.unsafe(self).content(*(["a".."z"] + lines + [501..600, ["Foo"] * 7, 601..620, 625..675, 678..700]))
    end.freeze

    topic = @repo.refs.create("refs/heads/topic", @c10.oid, @repo.owner)
    master = @repo.refs.create("refs/heads/master", @c8.oid, @repo.owner)

    @pull = make_pr(@repo, @repo)

    @comment = create_comment
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  def content(*stuff)
    stuff.map(&:to_a).flatten.join("\n")
  end

  def create_comment
    comparison = PullRequest::Comparison.find(pull: @pull, start_commit_oid: @c2.oid,
      end_commit_oid: @c5.oid, base_commit_oid: @c3.oid)

    review = @pull.pending_review_for(user: @repo.owner, head_sha: comparison.end_commit.oid)
    thread = review.build_thread
    comment = thread.build_first_comment(
      user: @repo.owner,
      body: "good job, me!",
      path: "notes.txt",
      diff: comparison.diffs,
      line: 180,
      side: :left,
    )

    review.save!

    comment
  end

  def test_proxy_base_tree
    comparison = PullRequest::Comparison.find(pull: @pull, start_commit_oid: @c1.oid,
      end_commit_oid: @c5.oid, base_commit_oid: @c3.oid)

    thread_positioner = PullRequest::ThreadPositioner.new(@pull.user, comparison)
    threads = thread_positioner.positioned_threads

    actual = threads.path("notes.txt").position(16).count

    assert_equal 1, actual
    assert_equal 0, GitHub.dogstats.increments("thread-positioning.fallback-to-diff-positioning").count
  end

  def test_proxy_base_tree_to_proxy_base_tree
    comparison = PullRequest::Comparison.find(pull: @pull, start_commit_oid: @c2.oid,
      end_commit_oid: @c10.oid, base_commit_oid: @c8.oid)

    thread_positioner = PullRequest::ThreadPositioner.new(@pull.user, comparison)
    threads = thread_positioner.positioned_threads

    actual = threads.path("notes.txt").position(5).count

    assert_equal 1, actual
    assert_equal 0, GitHub.dogstats.increments("thread-positioning.fallback-to-diff-positioning").count
  end
end
