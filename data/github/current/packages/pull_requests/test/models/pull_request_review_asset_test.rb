# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestReviewAssetTest < GitHub::TestCase
  include DogstatsTestHelpers

  setup do
    reset_cache
    reset_monolith_redis_rate_limiter
  end

  fixtures do
    @owner = create(:user, login: "owner", plan: "micro")
    @forker = create(:user)

    @source = create(:private_repository, owner: @owner, name: "source", from_example: :review_comment_fork)
    create(:collaborator, collaborator: @forker, repository: @source, action: :write)

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
    @issue.pull_request = @pull

    make_trusted_oauth_apps_owner

    @review = create(:pull_request_review, pull_request: @pull, user: @owner)
  end

  context "attach_matching_assets" do
    test "does not attach matching assets when body unchanged" do
      PullRequestReview.any_instance.expects(:attach_matching_assets).never

      @review.approve!
    end

    test "attaches matching assets when body has changed" do
      PullRequestReview.any_instance.expects(:attach_matching_assets).once

      @review.update_body("new body", @owner)
    end
  end
end
