# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestReviewsReviewRequestTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, login: "owner", plan: "micro")
    @forker = create(:user)

    @source = create(:private_repository, owner: @owner, name: "source", from_example: :review_comment_fork)
    @source.add_member @forker, action: :write

    @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :review_comment_fork)

    @issue = create(:issue, user: @forker, repository: @source)
    @pull =
      create(:pull_request,
        repository: @source,
        base_repository: @source,
        base_user: @source.owner,
        base_ref: "master",
        head_repository: @fork,
        head_user: @fork.owner,
        head_ref: "topic",
        issue: @issue,
        user: @forker,
      )
  end

  test "sets `repository_id` on create" do
    @pull.request_review_from(reviewers: [@owner], actor: @owner)
    review = @pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @owner, body: "blah")
    review.comment!
    pull_request_reviews_review_request = review.pull_request_reviews_review_requests.last
    review_request = @pull.review_requests.last

    # This test isn't critical, but we've just recently changed over to a has_many :through format
    # instead of has_many_and_belongs_to, so just adding extra confidence.
    assert_equal review.pull_request_reviews_review_requests, review_request.pull_request_reviews_review_requests

    refute_nil pull_request_reviews_review_request.repository_id
    assert_equal @pull.repository_id, pull_request_reviews_review_request.repository_id
  end
end
