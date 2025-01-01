# typed: true
#frozen_string_literal: true

require "test_helper"

class PullRequestUserReviewsTest < GitHub::TestCase
  fixtures do
    @skalnik = create(:user, login: "skalnik")
    @source = create(:repository, owner: @skalnik, name: "user_reviewed_files", from_example: :user_reviewed_files)


    @pull = PullRequest.create_for!(@source,
      user: @skalnik,
      base: "master",
      head: "add-degree-symbol-file",
      title: "some changes",
      body: "body",
    )
  end

  context "#reviewed?" do
    test "returns true for non-ascii characters" do
      UserReviewedFile.create(
        filepath: "degree°.txt",
        user: @skalnik,
        pull_request: @pull,
        head_sha: @pull.head_sha,
      )

      assert PullRequestUserReviews.new(@pull, @skalnik).reviewed?("degree°.txt")
      refute PullRequestUserReviews.new(@pull, @skalnik).reviewed?("테스트.txt")
    end

    test "is scoped to the supplied PR" do
      source = create(:repository, owner: @skalnik, name: "scoped", from_example: :pull_request_fork)
      pull = PullRequest.create_for(
        source,
        user: @skalnik,
        base: "behind",
        head: "master-plus-one-commit",
        title: "revert: revert: revert: really fix this time",
        body: "body",
      )
      other_pull = PullRequest.create_for!(
        source,
        user: @skalnik,
        base: "behind",
        head: "master-plus-blank-commit-message",
        title: "feat: implement new mind-control protocol",
        body: "body"
      )
      UserReviewedFile.create(
        filepath: "file11",
        user: @skalnik,
        pull_request: other_pull,
        head_sha: other_pull.head_sha,
      )

      refute PullRequestUserReviews.new(pull, @skalnik).reviewed?("file11")
      assert PullRequestUserReviews.new(other_pull, @skalnik).reviewed?("file11")
    end
  end

  context "#dismissed?" do
    test "returns true for non-ascii characters" do
      UserReviewedFile.create(
        filepath: "degree°.txt",
        user: @skalnik,
        pull_request: @pull,
        head_sha: @pull.head_sha,
        dismissed: true,
      )

      assert PullRequestUserReviews.new(@pull, @skalnik).dismissed?("degree°.txt")
      refute PullRequestUserReviews.new(@pull, @skalnik).dismissed?("테스트.txt")
    end
  end
end
