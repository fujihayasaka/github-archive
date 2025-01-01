# typed: true
# frozen_string_literal: true

require "test_helper"

class DeprecatedPullRequestReviewThreadTest < GitHub::TestCase
  setup do
    @user = create(:user)
    @site_admin = create(:staff_admin_user)
    @org  = create(:organization, admin: @user)
    @repo = create(:repository, owner: @org, from_example: :simple)

    example_repo_snapshot

    ref = @repo.heads.create("topic", @repo.heads.find("master").target, @repo.owner)
    @commit = ref.append_commit({ message: "Add file1", committer: @repo.owner }, @repo.owner) do |files|
      files.add("file1.txt", "file1\nline 2\nline 3")
    end

    @issue = create(:issue, repository: @repo)
    @pull = PullRequest.create_for(
      @repo,
      base: "master",
      head: ref.name,
      user: @user,
      issue: @issue,
    )

    @legacy_comment = create(:pull_request_review_comment,
      pull_request: @pull,
      body: ":+1: totally rad!",
      user: create(:user),
      commit_id: @pull.head_sha,
      path: "file1.txt",
      original_position: 1,
    ).submit!

    @spammy_legacy_comment = create(:pull_request_review_comment,
      pull_request: @pull,
      body: "spammy comment",
      user: create(:user, spammy: true),
      commit_id: @pull.head_sha,
      path: "file1.txt",
      original_position: 1,
    ).submit!

    @review = @pull.reviews.create!(
      user: @user,
      head_sha: @pull.head_sha,
      body: "review body!",
    )
    @comment = create(:pull_request_review_comment,
      pull_request: @pull,
      pull_request_review: @review,
      user: @user,
      body: "review comment.",
      commit_id: @pull.head_sha,
      path: "file1.txt",
      original_position: 1,
    )
    assert @review.comment!
    @comment.reload

    @pending_review = @pull.reviews.create!(
      user: @user,
      head_sha: @pull.head_sha,
      body: "review body!",
    )

    @pending_comment = @comment.pull_request_review_thread.build_reply(
      pull_request_review: @pending_review,
      user: @user,
      body: "pending review.",
    )
    @pending_review.review_comments << @pending_comment

    @thread_with_spammy_comment = DeprecatedPullRequestReviewThread.new(
      pull: @pull,
      pull_comparison: @legacy_comment.original_pull_request_comparison,
      path: @legacy_comment.path,
      position: @legacy_comment.original_position,
      comments: [@legacy_comment, @spammy_legacy_comment]
    )

    @thread = DeprecatedPullRequestReviewThread.new(
      pull: @pull,
      pull_comparison: @comment.original_pull_request_comparison,
      path: @comment.path,
      position: @comment.original_position,
      comments: [@comment, @pending_comment],
    )
  end

  context "#comments_for" do
    if GitHub.spamminess_check_enabled?
      test "returns no spammy comments" do
        assert_equal [@legacy_comment], @thread_with_spammy_comment.comments_for(@user)
        assert_equal [@legacy_comment, @spammy_legacy_comment], @thread_with_spammy_comment.comments_for(@site_admin)
      end

      test "returns spammy comments for comment author or site admin" do
        assert_equal [@legacy_comment, @spammy_legacy_comment], @thread_with_spammy_comment.comments_for(@spammy_legacy_comment.user)
      end
    else
      test "returns spammy comments" do
        assert_equal [@legacy_comment, @spammy_legacy_comment], @thread_with_spammy_comment.comments_for(@user)
      end
    end

    test "returns only submitted comments" do
      assert_equal [@comment], @thread.comments_for(create(:user))
    end

    test "returns pending comments for comment author" do
      assert_equal [@comment, @pending_comment], @thread.comments_for(@user)
    end
  end

  context "resolved?" do
    test "is false by default" do
      refute_predicate @thread, :resolved?
    end

    test "can be resolved" do
      @comment.async_pull_request_review_thread.sync.resolve(resolver: @user)

      assert_predicate @thread, :resolved?
    end
  end

  context "#pull_request_review_id" do
    test "returns ID of PullRequestReviewThread" do
      pull_request_review_thread = @comment.pull_request_review_thread
      assert_equal pull_request_review_thread.id, @thread.pull_request_review_thread_id
    end
  end
end
