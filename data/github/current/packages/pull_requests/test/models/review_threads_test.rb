# typed: true
# frozen_string_literal: true

require "test_helper"

class ReviewThreadsTest < GitHub::TestCase
  setup do
    id = 1
    @first_comment = PullRequestReviewComment.new(
      pull_request_review_thread: PullRequestReviewThread.new(path: "README", position: 42),
      pull_request_review_id: 12,
    )
    @first_comment.id = id += 1

    @reply_comment = PullRequestReviewComment.new(
      pull_request_review_thread: PullRequestReviewThread.new(path: "README", position: 42),
      pull_request_review_id: 12,
      reply_to_id: @first_comment.id,
    )
    @reply_comment.id = id += 1

    @second_comment = PullRequestReviewComment.new(
      pull_request_review_thread: PullRequestReviewThread.new(path: "README", position: 42),
      pull_request_review_id: 13,
    )
    @second_comment.id = id += 1

    @other_comment = PullRequestReviewComment.new(
      pull_request_review_thread: PullRequestReviewThread.new(path: "README", position: 43),
      pull_request_review_id: 14,
    )
    @other_comment.id = id += 1

    @legacy_comment1 = PullRequestReviewComment.new(
      pull_request_review_thread: PullRequestReviewThread.new(path: "README", position: 42),
      pull_request_review_id: nil,
    )
    @legacy_comment1.id = id += 1

    @legacy_comment2 = PullRequestReviewComment.new(
      pull_request_review_thread: PullRequestReviewThread.new(path: "README", position: 42),
      pull_request_review_id: nil,
    )
    @legacy_comment2.id = id += 1

    @threads = make_threads
  end

  def make_threads
    comments = [@first_comment, @reply_comment, @second_comment, @other_comment, @legacy_comment1, @legacy_comment2]

    pull = PullRequest.new
    repository = build(:repository)
    start_commit = Commit.new(repository, oid: "aaa")
    end_commit = Commit.new(repository, oid: "aaa")
    base_commit = Commit.new(repository, oid: "aaa")
    pull_comparison = PullRequest::Comparison.new(pull: pull, start_commit: start_commit, end_commit: end_commit, base_commit: start_commit)

    location_grouped_comments = comments.group_by { |comment| [comment.position, comment.path] }

    threads = location_grouped_comments.flat_map do |_, comments|
      leader = comments.find(&:legacy_comment?)
      thread_grouped_comments = comments.group_by do |comment|
        if comment.legacy_comment? # All legacy comments belong to the single legacy thread on this line.
          leader.id
        else # New-style comments use explicit reply_to_id to identify thread.
          comment.reply_to_id || comment.id
        end
      end.values
      thread_grouped_comments.map do |comments|
        DeprecatedPullRequestReviewThread.new(
          pull: pull_comparison.pull,
          pull_comparison: pull_comparison,
          path: comments.first.path,
          position: comments.first.position,
          comments: comments,
        )
      end
    end
    ReviewThreads.new(threads)
  end

  test "groups comments into several threads on same line" do
    assert @threads.any?
    refute @threads.empty?
    assert_equal 4, @threads.size
  end

  test "retrieves threads for a path" do
    readme = @threads.path("README")
    assert_equal 4, readme.size
    assert readme.any?
    refute readme.empty?
  end

  test "returns empty threads for missing path" do
    readme = @threads.path("404")
    assert_equal 0, readme.size
    refute readme.any?
    assert readme.empty?
  end

  test "retrieves threads at a line position" do
    threads = @threads.path("README").position(42)
    assert_equal 3, threads.size
    assert threads.any?
    refute threads.empty?
  end

  test "returns empty threads for missing line position" do
    threads = @threads.path("README").position(-1)
    assert_equal 0, threads.size
    refute threads.any?
    assert threads.empty?
  end

  test "iterates through all threads" do
    assert_equal 4, @threads.count
    expected = [@first_comment, @second_comment, @legacy_comment1, @other_comment]
    assert_equal expected, @threads.each.map { |thread| thread.comments.first }
  end

  test "iterates through each path" do
    @threads.each_path.all? { |_path, threads| threads.is_a?(ReviewThreads) }

    paths = @threads.each_path.map { |path, threads| [path, threads] }
    assert_equal 1, paths.size
    assert_equal "README", paths.first[0]
    assert_equal 4, paths.first[1].size
  end

  test "iterates through each position at a path" do
    readme = @threads.path("README")
    readme.each_position.all? { |_position, threads| threads.is_a?(ReviewThreads) }

    positions = readme.each_position.map { |position, threads| [position, threads] }
    assert_equal 2, positions.size

    assert_equal 42, positions.first[0]
    assert_equal 3, positions.first[1].size

    assert_equal 43, positions.second[0]
    assert_equal 1, positions.second[1].size
  end

  test "can return only outdated threads" do
    assert_equal 0, @threads.outdated.size
    @first_comment.position = nil
    @first_comment.outdated = true
    assert_predicate @first_comment, :outdated?

    assert_equal 1, @threads.outdated.size
    assert @first_comment, @threads.outdated.first.comments.first
  end
end
