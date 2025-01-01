# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequests::Copilot::CodeReviewAccessTest < GitHub::TestCase
  skip_enterprise

  fixtures do
    @private_repo = create(:private_repository)
    @public_repo = create(:public_repository)
    @internal_repo = create(:internal_repository)
    @actor = create(:user)
  end

  setup do
    # Set up all repos and owners to be enabled by default
    repos = [@private_repo, @public_repo, @internal_repo]
    repos.each do |repo|
      repo.enable_feature(:copilot_reviews_automatic_pull_request_review)
      repo.owner.enable_feature(:copilot_reviews_automatic_pull_request_review)

      repo.enable_feature(:copilot_pr_reviews_repository_access)
      repo.owner.enable_feature(:copilot_pr_reviews_repository_access)
    end

    # Don't opt-out the user
    @actor.disable_feature(:copilot_reviews_automatic_pull_request_review_disabled)

    @actor.enable_feature(:copilot_pr_reviews_v0)
    @actor.enable_feature(:copilot_pr_reviews_v1)
  end

  context "#auto_reviewable?" do
    context "repository eligibility" do
      test "true for private repo, flags set on repo, not opted-out" do
        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
        assert_predicate access, :auto_reviewable?
      end

      test "true for internal repo, flag set on repo, not opted-out" do
        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @internal_repo)
        assert_predicate access, :auto_reviewable?
      end

      test "false for public repo, flag set on repo, not opted-out" do
        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @public_repo)
        refute_predicate access, :auto_reviewable?
      end
    end

    test "false if actor has opted-out via feature flag" do
      @actor.enable_feature(:copilot_reviews_automatic_pull_request_review_disabled)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      refute_predicate access, :auto_reviewable?
    end

    test "false if repo and owner have auto flag disabled" do
      @private_repo.disable_feature(:copilot_reviews_automatic_pull_request_review)
      @private_repo.owner.disable_feature(:copilot_reviews_automatic_pull_request_review)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      refute_predicate access, :auto_reviewable?
    end

    test "true if repo has auto flag enabled and owner has auto flag disabled" do
      @private_repo.owner.disable_feature(:copilot_reviews_automatic_pull_request_review)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      assert_predicate access, :auto_reviewable?
    end

    test "true if repo has auto flag disabled and owner has auto flag enabled" do
      @private_repo.disable_feature(:copilot_reviews_automatic_pull_request_review)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      assert_predicate access, :auto_reviewable?
    end

    test "true if repo has access flag enabled and owner has auto flag disabled" do
      @private_repo.owner.disable_feature(:copilot_pr_reviews_repository_access)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      assert_predicate access, :auto_reviewable?
    end

    test "true if repo has access flag enabled and owner has access flag disabled" do
      @private_repo.owner.disable_feature(:copilot_pr_reviews_repository_access)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      assert_predicate access, :auto_reviewable?
    end

    test "false if actor doesn't have copilot_pr_reviews_v0 or copilot_pr_reviews_v1 flag" do
      @actor.disable_feature(:copilot_pr_reviews_v0)
      @actor.disable_feature(:copilot_pr_reviews_v1)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      refute_predicate access, :auto_reviewable?
    end
  end

  context "#can_request_via_button?" do
    context "repository eligibility" do
      test "true for private repo, flags set on repo, not opted-out" do
        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
        assert_predicate access, :can_request_via_button?
      end

      test "true for internal repo, flag set on repo, not opted-out" do
        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @internal_repo)
        assert_predicate access, :can_request_via_button?
      end

      test "false for public repo, flag set on repo, not opted-out" do
        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @public_repo)
        refute_predicate access, :can_request_via_button?
      end
    end

    test "still true if actor has opted-out of automatic reviews via feature flag" do
      @actor.enable_feature(:copilot_reviews_automatic_pull_request_review_disabled)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      assert_predicate access, :can_request_via_button?
    end

    test "false if actor not in copilot_pr_reviews_v0 flag" do
      @actor.disable_feature(:copilot_pr_reviews_v0)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      refute_predicate access, :can_request_via_button?
    end
  end

  context "#can_create_review_request?" do
    context "repository eligibility" do
      test "true for private repo, flags set on repo, not opted-out" do
        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
        assert_predicate access, :can_create_review_request?
      end

      test "true for internal repo, flag set on repo, not opted-out" do
        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @internal_repo)
        assert_predicate access, :can_create_review_request?
      end

      test "false for public repo, flag set on repo, not opted-out" do
        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @public_repo)
        refute_predicate access, :can_create_review_request?
      end
    end

    test "still true if actor has opted-out of automatic reviews via feature flag" do
      @actor.enable_feature(:copilot_reviews_automatic_pull_request_review_disabled)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      assert_predicate access, :can_create_review_request?
    end

    test "false if actor not in copilot_pr_reviews_v1 flag" do
      @actor.disable_feature(:copilot_pr_reviews_v1)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      refute_predicate access, :can_create_review_request?
    end
  end
end
