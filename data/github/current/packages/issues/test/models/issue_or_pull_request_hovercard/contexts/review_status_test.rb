# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueOrPullRequestHovercardContextsReviewStatusTest < GitHub::TestCase
  fixtures do
    @collaborator = create(:user)
    @repo = create(:repository)
    @repo.add_member(@collaborator, action: :write)
    @pull = create(:pull_request, :disable_disk_access, repository: @repo)
  end

  def async_resolve(*args, **kwargs)
    T.unsafe(IssueOrPullRequestHovercard::Contexts::ReviewStatus).async_resolve(*args, **kwargs)
  end

  context ".async_resolve" do
    test "returns nil when only someone without write access to the repo has reviewed" do
      viewer = create(:user)
      create(:pull_request_review, :approved, pull_request: @pull)
      context = async_resolve(issue_or_pull_request: @pull, viewer: viewer).sync

      assert_nil context
    end

    test "returns nil when viewer has not reviewed and a review is not required" do
      viewer = create(:user)
      create(:pull_request_review, :commented, pull_request: @pull, user: @collaborator)
      context = async_resolve(issue_or_pull_request: @pull, viewer: viewer).sync

      assert_nil context
    end

    test "returns nil when the base branch is protected with no minimum review count" do
      viewer = create(:user)
      create(:protected_branch, repository: @repo,
        pull_request_reviews_enforcement_level: :everyone, required_approving_review_count: 0)
      context = async_resolve(issue_or_pull_request: @pull, viewer: viewer).sync

      assert_nil context
    end

    test "returns a context with a message when viewer has been asked to review a pull request" do
      viewer = @collaborator
      create(:review_request, pull_request_id: @pull.id, reviewer_id: @collaborator.id, reviewer_type: "User")
      context = async_resolve(issue_or_pull_request: @pull, viewer: viewer).sync

      refute_nil context
      assert_equal "You have a pending review request", context.message
    end

    test "returns a context with a message when a team the viewer is on has been asked to review a pull request" do
      org = create(:organization)
      team = create(:team, organization: org, privacy: :closed)
      repo = create(:repository, owner: org, from_example: :pull_request_source)
      team.add_repository(repo, :push)

      viewer = create(:user)

      repo.add_member(viewer)
      team.add_member(viewer)

      pull =
        PullRequest.create_for! repo,
          base: "master",
          head: "master-merged-topic",
          user: viewer,
          title: "best animals",
          body: "hyenas, squirrels, capybaras",
          reviewer_team_ids: [team.id]

      pull.reload

      context = async_resolve(issue_or_pull_request: pull, viewer: viewer).sync

      refute_nil context
      assert_equal "Your team has a pending review request", context.message
    end

    test "returns a context with a message when viewer approved a pull request" do
      viewer = @collaborator
      create(:pull_request_review, :approved, pull_request: @pull, user: viewer)
      context = async_resolve(issue_or_pull_request: @pull, viewer: viewer).sync

      refute_nil context
      assert_equal "You approved this pull request", context.message
    end

    test "returns a context with a message when viewer and others approved a pull request" do
      viewer = @collaborator
      create(:pull_request_review, :approved, pull_request: @pull, user: viewer)
      other_review = create(:pull_request_review, :approved, pull_request: @pull)
      context = async_resolve(issue_or_pull_request: @pull, viewer: viewer).sync

      refute_nil context
      assert_equal "You and #{other_review.user} approved this pull request", context.message
    end

    test "returns a context with a message when viewer and others approved a pull request but someone requested changes" do
      viewer = @collaborator
      create(:pull_request_review, :approved, pull_request: @pull, user: viewer)
      other_review1 = create(:pull_request_review, :approved, pull_request: @pull)
      other_review2 = create(:pull_request_review, :changes_requested, pull_request: @pull)
      context = async_resolve(issue_or_pull_request: @pull, viewer: viewer).sync

      refute_nil context
      assert_equal "Changes requested by #{other_review2.user}, " \
                   "you and #{other_review1.user} approved", context.message
    end

    test "returns a context with a message when viewer requested changes to a pull request" do
      viewer = @collaborator
      create(:pull_request_review, :changes_requested, pull_request: @pull, user: viewer)
      context = async_resolve(issue_or_pull_request: @pull, viewer: viewer).sync

      refute_nil context
      assert_equal "You requested changes", context.message
    end

    test "returns a context with a message when viewer and others requested changes to a pull request" do
      viewer = @collaborator
      create(:pull_request_review, :changes_requested, pull_request: @pull, user: viewer)
      other_review = create(:pull_request_review, :changes_requested, pull_request: @pull)
      context = async_resolve(issue_or_pull_request: @pull, viewer: viewer).sync

      refute_nil context
      assert_equal "You and #{other_review.user} requested changes", context.message
    end

    test "returns a context with a message when viewer and others requested changes to a pull request but someone else approved" do
      viewer = @collaborator
      create(:pull_request_review, :changes_requested, pull_request: @pull, user: viewer)
      other_review1 = create(:pull_request_review, :changes_requested, pull_request: @pull)
      other_review2 = create(:pull_request_review, :approved, pull_request: @pull)
      context = async_resolve(issue_or_pull_request: @pull, viewer: viewer).sync

      refute_nil context
      assert_equal "You and #{other_review1.user} requested changes, " \
                   "#{other_review2.user} approved", context.message
    end

    test "returns a context with a message when viewer reviewed a pull request" do
      viewer = @collaborator
      create(:pull_request_review, :commented, pull_request: @pull, user: viewer)
      context = async_resolve(issue_or_pull_request: @pull, viewer: viewer).sync

      refute_nil context
      assert_equal "You left a review", context.message
    end

    test "returns a context with a message when viewer's review was dismissed" do
      viewer = @collaborator
      create(:pull_request_review, :dismissed, pull_request: @pull, user: viewer)
      context = async_resolve(issue_or_pull_request: @pull, viewer: viewer).sync

      refute_nil context
      assert_equal "You left a dismissed review", context.message
    end

    test "returns a context with a message when viewer's review was dismissed and there was another review" do
      viewer = @collaborator
      create(:pull_request_review, :dismissed, pull_request: @pull, user: viewer)
      other_review = create(:pull_request_review, :approved, pull_request: @pull)
      context = async_resolve(issue_or_pull_request: @pull, viewer: viewer).sync

      refute_nil context
      assert_equal "#{other_review.user} approved, you left a dismissed review", context.message
    end

    test "returns a context with a message that only includes the latest review per user" do
      viewer = @collaborator
      create(:pull_request_review, :dismissed, pull_request: @pull, user: viewer)
      other_reviewer = create(:user)
      Timecop.freeze(1.day.ago) do
        create(:pull_request_review, :approved, pull_request: @pull, user: other_reviewer)
      end
      other_review = create(:pull_request_review, :changes_requested, pull_request: @pull,
                            user: other_reviewer)
      context = async_resolve(issue_or_pull_request: @pull, viewer: viewer).sync

      refute_nil context
      assert_equal "#{other_review.user} requested changes, you left a dismissed review",
        context.message
    end

    test "returns a context with a message when viewer approved, another requested changes" do
      viewer = @collaborator
      create(:pull_request_review, :approved, pull_request: @pull, user: viewer)
      other_review = create(:pull_request_review, :changes_requested, pull_request: @pull)
      context = async_resolve(issue_or_pull_request: @pull, viewer: viewer).sync

      refute_nil context
      assert_equal "Changes requested by #{other_review.user}, you approved", context.message
    end

    test "returns a context with a message when viewer requested changes, another approved" do
      viewer = @collaborator
      create(:pull_request_review, :changes_requested, pull_request: @pull, user: viewer)
      other_review = create(:pull_request_review, :approved, pull_request: @pull)
      context = async_resolve(issue_or_pull_request: @pull, viewer: viewer).sync

      refute_nil context
      assert_equal "You requested changes, #{other_review.user} approved", context.message
    end

    test "returns a context with a message when viewer commented, another approved" do
      viewer = @collaborator
      create(:pull_request_review, :commented, pull_request: @pull, user: viewer)
      other_review = create(:pull_request_review, :approved, pull_request: @pull)
      context = async_resolve(issue_or_pull_request: @pull, viewer: viewer).sync

      refute_nil context
      assert_equal "#{other_review.user} approved, you commented", context.message
    end

    test "returns a context with a message when viewer commented, another requested changes" do
      viewer = @collaborator
      create(:pull_request_review, :commented, pull_request: @pull, user: viewer)
      other_review = create(:pull_request_review, :changes_requested, pull_request: @pull)
      context = async_resolve(issue_or_pull_request: @pull, viewer: viewer).sync

      refute_nil context
      assert_equal "#{other_review.user} requested changes, you commented", context.message
    end

    test "returns a context with a message when viewer commented, multiple others reviewed" do
      viewer = @collaborator
      create(:pull_request_review, :commented, pull_request: @pull, user: viewer)
      other_review1 = create(:pull_request_review, :approved, pull_request: @pull)
      other_review2 = create(:pull_request_review, :changes_requested, pull_request: @pull)
      context = async_resolve(issue_or_pull_request: @pull, viewer: viewer).sync

      refute_nil context
      assert_equal "#{other_review2.user} requested changes, #{other_review1.user} approved, " \
                   "you commented", context.message
    end

    test "returns a context with a message when approved but viewer hasn't reviewed" do
      viewer = @collaborator
      other_collaborator = create(:user)
      @repo.add_member(other_collaborator, action: :write)
      create(:pull_request_review, :approved, pull_request: @pull, user: other_collaborator)
      context = async_resolve(issue_or_pull_request: @pull, viewer: viewer).sync

      refute_nil context
      assert_equal "Approved", context.message
    end

    test "returns a context with a message when changes requested but viewer hasn't reviewed" do
      viewer = @collaborator
      other_collaborator = create(:user)
      @repo.add_member(other_collaborator, action: :write)
      create(:pull_request_review, :changes_requested, pull_request: @pull,
             user: other_collaborator)
      context = async_resolve(issue_or_pull_request: @pull, viewer: viewer).sync

      refute_nil context
      assert_equal "Changes requested", context.message
    end

    test "returns a context with a message when review is required but viewer hasn't reviewed" do
      viewer = @collaborator
      PullRequest.any_instance.stubs(:review_decision).returns(:review_required)
      context = async_resolve(issue_or_pull_request: @pull, viewer: viewer).sync

      refute_nil context
      assert_equal "Review required", context.message
    end

    test "returns a context with a message when approved but the base branch is protected with no minimum review count" do
      viewer = create(:user)
      create(:protected_branch, repository: @repo,
        pull_request_reviews_enforcement_level: :everyone, required_approving_review_count: 0)
      create(:pull_request_review, :approved, pull_request: @pull, user: @collaborator)
      context = async_resolve(issue_or_pull_request: @pull, viewer: viewer).sync

      refute_nil context
      assert_equal "Approved", context.message
    end

    test "returns a context with a message when changes requested but the base branch is protected with no minimum review count" do
      viewer = create(:user)
      create(:protected_branch, repository: @repo,
        pull_request_reviews_enforcement_level: :everyone, required_approving_review_count: 0)
      create(:pull_request_review, :changes_requested, pull_request: @pull, user: @collaborator)
      context = async_resolve(issue_or_pull_request: @pull, viewer: viewer).sync

      refute_nil context
      assert_equal "Changes requested", context.message
    end

    test "returns a context with an octicon when a review has been requested from the viewer and is pending" do
      viewer = @collaborator
      create(:review_request, pull_request_id: @pull.id, reviewer_id: @collaborator.id, reviewer_type: "User")
      context = async_resolve(issue_or_pull_request: @pull, viewer: viewer).sync

      refute_nil context
      assert_equal "dot-fill", context.octicon
    end

    test "returns a context with an octicon when a review has been requested from a team the viewer is on and is pending" do
      org = create(:organization)
      team = create(:team, organization: org, privacy: :closed)
      repo = create(:repository, owner: org, from_example: :pull_request_source)
      team.add_repository(repo, :push)

      viewer = create(:user)

      repo.add_member(viewer)
      team.add_member(viewer)

      pull =
        PullRequest.create_for! repo,
          base: "master",
          head: "master-merged-topic",
          user: viewer,
          title: "best animals",
          body: "hyenas, squirrels, capybaras",
          reviewer_team_ids: [team.id]

      pull.reload

      context = async_resolve(issue_or_pull_request: pull, viewer: viewer).sync

      refute_nil context
      assert_equal "dot-fill", context.octicon
    end

    test "returns a context with an octicon when a reviewer requested changes on the pull request" do
      viewer = @collaborator
      create(:pull_request_review, :changes_requested, pull_request: @pull, user: viewer)
      context = async_resolve(issue_or_pull_request: @pull, viewer: viewer).sync

      refute_nil context
      assert_equal "file-diff", context.octicon
    end

    test "returns a context with an octicon when the pull request has been approved" do
      viewer = @collaborator
      create(:pull_request_review, :approved, pull_request: @pull, user: viewer)
      context = async_resolve(issue_or_pull_request: @pull, viewer: viewer).sync

      refute_nil context
      assert_equal "check", context.octicon
    end

    test "returns a context with an octicon when a review is required and hasn't been done yet" do
      viewer = @collaborator
      PullRequest.any_instance.stubs(:review_decision).returns(:review_required)
      context = async_resolve(issue_or_pull_request: @pull, viewer: viewer).sync

      refute_nil context
      assert_equal "comment", context.octicon
    end

    test "returns a context with an octicon when approved but the base branch is protected with no minimum review count" do
      viewer = create(:user)
      create(:protected_branch, repository: @repo,
        pull_request_reviews_enforcement_level: :everyone, required_approving_review_count: 0)
      create(:pull_request_review, :approved, pull_request: @pull, user: @collaborator)
      context = async_resolve(issue_or_pull_request: @pull, viewer: viewer).sync

      refute_nil context
      assert_equal "check", context.octicon
    end

    test "returns a context with an octicon when changes requested but the base branch is protected with no minimum review count" do
      viewer = create(:user)
      create(:protected_branch, repository: @repo,
        pull_request_reviews_enforcement_level: :everyone, required_approving_review_count: 0)
      create(:pull_request_review, :changes_requested, pull_request: @pull, user: @collaborator)
      context = async_resolve(issue_or_pull_request: @pull, viewer: viewer).sync

      refute_nil context
      assert_equal "file-diff", context.octicon
    end

    test "context message handles deleted reviewer" do
      create(:pull_request_review, :approved, pull_request: @pull, user: @collaborator)

      other_review = create(:pull_request_review, :approved, pull_request: @pull)
      other_review.user.delete
      other_review.reload

      context = async_resolve(issue_or_pull_request: @pull, viewer: @collaborator).sync

      refute_nil context
      assert_equal "You approved this pull request", context.message
    end

    test "returns nil when only reviewer has been deleted" do
      review = create(:review_request, pull_request_id: @pull.id, reviewer_id: @collaborator.id, reviewer_type: "User")
      @collaborator.delete
      review.reload

      viewer = create(:user)
      context = async_resolve(issue_or_pull_request: @pull, viewer: viewer).sync

      assert_nil context
    end
  end

  context ".pending_user_review_request?" do
    test "returns true when viewer has been asked to review a pull request" do
      viewer = @collaborator
      create(:review_request, pull_request_id: @pull.id, reviewer_id: viewer.id, reviewer_type: "User")

      resolver = IssueOrPullRequestHovercard::Contexts::ReviewStatus::Resolver.new(issue_or_pull_request: @pull, viewer: viewer)

      assert resolver.send(:pending_user_review_request?)
    end

    test "returns false when viewer has completed a requested review" do
      viewer = @collaborator
      create(:review_request, pull_request_id: @pull.id, reviewer_id: viewer.id, reviewer_type: "User")

      resolver = IssueOrPullRequestHovercard::Contexts::ReviewStatus::Resolver.new(issue_or_pull_request: @pull, viewer: viewer)
      assert resolver.send(:pending_user_review_request?)

      create(:pull_request_review, :approved, pull_request: @pull, user: viewer)

      resolver = IssueOrPullRequestHovercard::Contexts::ReviewStatus::Resolver.new(issue_or_pull_request: @pull, viewer: viewer)
      refute resolver.send(:pending_user_review_request?)
    end

    test "returns false when no reviews are requested" do
      viewer = @collaborator

      resolver = IssueOrPullRequestHovercard::Contexts::ReviewStatus::Resolver.new(issue_or_pull_request: @pull, viewer: viewer)

      refute resolver.send(:pending_user_review_request?)
    end

    test "returns false when a team the viewer is on has been asked to review a pull request" do
      org = create(:organization)
      team = create(:team, organization: org, privacy: :closed)
      repo = create(:repository, owner: org, from_example: :pull_request_source)
      team.add_repository(repo, :push)

      viewer = create(:user)

      repo.add_member(viewer)
      team.add_member(viewer)

      pull =
        PullRequest.create_for! repo,
          base: "master",
          head: "master-merged-topic",
          user: viewer,
          title: "best animals",
          body: "hyenas, squirrels, capybaras",
          reviewer_team_ids: [team.id]

      pull.reload

      resolver = IssueOrPullRequestHovercard::Contexts::ReviewStatus::Resolver.new(issue_or_pull_request: pull, viewer: viewer)

      refute resolver.send(:pending_user_review_request?)
    end
  end

  context ".pending_user_team_review_request?" do
    test "returns true when a team the viewer is on has been asked to review a pull request" do
      org = create(:organization)
      team = create(:team, organization: org, privacy: :closed)
      repo = create(:repository, owner: org, from_example: :pull_request_source)
      team.add_repository(repo, :push)

      viewer = create(:user)

      repo.add_member(viewer)
      team.add_member(viewer)

      pull =
        PullRequest.create_for! repo,
          base: "master",
          head: "master-merged-topic",
          user: viewer,
          title: "best animals",
          body: "hyenas, squirrels, capybaras",
          reviewer_team_ids: [team.id]

      pull.reload

      resolver = IssueOrPullRequestHovercard::Contexts::ReviewStatus::Resolver.new(issue_or_pull_request: pull, viewer: viewer)

      assert resolver.send(:pending_user_team_review_request?)
    end

    test "returns false when a team the viewer is on has been asked to review a pull request and the viewer has reviewed it" do
      org = create(:organization)
      team = create(:team, organization: org, privacy: :closed)
      repo = create(:repository, owner: org, from_example: :pull_request_source)
      team.add_repository(repo, :push)

      viewer = create(:user)

      repo.add_member(viewer)
      team.add_member(viewer)

      pull =
        PullRequest.create_for! repo,
          base: "master",
          head: "master-merged-topic",
          user: viewer,
          title: "best animals",
          body: "hyenas, squirrels, capybaras",
          reviewer_team_ids: [team.id]

      pull.reload

      # This is done to ensure that the ReviewRequest and PullRequestReviews are properly associated
      rr = ReviewRequest.last
      prv = create(:pull_request_review, :approved, pull_request: pull, user: viewer)
      T.must(rr).pull_request_reviews << prv

      resolver = IssueOrPullRequestHovercard::Contexts::ReviewStatus::Resolver.new(issue_or_pull_request: pull, viewer: viewer)

      refute resolver.send(:pending_user_team_review_request?)
    end

    test "returns false when a team the viewer is on has been asked to review a pull request and another team member has reviewed it" do
      org = create(:organization)
      team = create(:team, organization: org, privacy: :closed)
      repo = create(:repository, owner: org, from_example: :pull_request_source)
      team.add_repository(repo, :push)

      viewer = create(:user)
      other_member = create(:user)

      team.add_member(viewer)
      team.add_member(other_member)

      pull =
        PullRequest.create_for! repo,
          base: "master",
          head: "master-merged-topic",
          user: viewer,
          title: "best animals",
          body: "hyenas, squirrels, capybaras",
          reviewer_team_ids: [team.id]

      pull.reload

      # This is done to ensure that the ReviewRequest and PullRequestReviews are properly associated
      rr = ReviewRequest.last
      prv = create(:pull_request_review, :approved, pull_request: pull, user: other_member)
      T.must(rr).pull_request_reviews << prv

      resolver = IssueOrPullRequestHovercard::Contexts::ReviewStatus::Resolver.new(issue_or_pull_request: pull, viewer: viewer)

      refute resolver.send(:pending_user_team_review_request?)
    end

    test "returns false when viewer has been asked to review a pull request" do
      viewer = @collaborator
      create(:review_request, pull_request_id: @pull.id, reviewer_id: viewer.id, reviewer_type: "User")

      resolver = IssueOrPullRequestHovercard::Contexts::ReviewStatus::Resolver.new(issue_or_pull_request: @pull, viewer: viewer)

      refute resolver.send(:pending_user_team_review_request?)
    end

    test "returns false when no reviews are requested" do
      viewer = @collaborator

      resolver = IssueOrPullRequestHovercard::Contexts::ReviewStatus::Resolver.new(issue_or_pull_request: @pull, viewer: viewer)

      refute resolver.send(:pending_user_team_review_request?)
    end
  end

  context "#review_authors_from" do
    test "handles deleted authors" do
      review = create(:pull_request_review, :approved, pull_request: @pull, user: @collaborator)
      review.user.delete
      review.reload

      review_status = IssueOrPullRequestHovercard::Contexts::ReviewStatus.new(issue_or_pull_request: nil, viewer: nil, viewer_review: nil,
                                 other_reviews: nil, review_decision: nil,
                                 pending_user_review_request: nil,
                                 pending_user_team_review_request: nil)

      assert_empty review_status.send(:review_authors_from, [review])
    end
  end
end
