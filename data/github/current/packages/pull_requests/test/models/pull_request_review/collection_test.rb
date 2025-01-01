# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestReviewCollectionTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, login: "owner", plan: "micro")
    @user = create(:user, login: "pull-creator")

    @source = create(:private_repository, name: "repo", owner: @owner, from_example: :pull_request_source)
    @source.add_member @user

    example_repo_snapshot

    @pull = PullRequest.create_for!(@source,
      base: "master",
      head: "master-forward-2",
      user: @user,
      title: "PR for master-forward-2",
      body: "most valuable PR ever A++++ please do merge",
    )

    @pending = create(:pull_request_review, pull_request: @pull)
    @approval = create(:pull_request_review, pull_request: @pull)
    @approval.approve!

    @changes_requested = create(:pull_request_review, pull_request: @pull, body: "bad")
    @changes_requested.request_changes!

    @commented = create(:pull_request_review, pull_request: @pull, body: "commented")
    @commented.comment!
  end

  test "excluding_dismissed" do
    @approval.dismiss!(@user, message: "dismiss msg")
    @changes_requested.dismiss!(@user, message: "another dismiss")

    collection = PullRequestReview::Collection.new(@pull.reviews).excluding_dismissed
    assert_equal [@pending, @commented], collection.to_a
  end

  test "has_rejected_reviews returns true if there are requested changes" do
    collection = PullRequestReview::Collection.new([])
    refute_predicate collection, :changes_requested?

    collection = PullRequestReview::Collection.new(@pull.reviews)
    assert_predicate collection, :changes_requested?
  end
end
