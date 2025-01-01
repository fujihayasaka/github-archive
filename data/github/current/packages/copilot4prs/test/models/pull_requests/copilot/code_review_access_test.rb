# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequests::Copilot::CodeReviewAccessTest < GitHub::TestCase
  skip_enterprise

  fixtures do
    @public_repo = create(:public_repository)
    @internal_repo = create(:internal_repository)
    @actor = create(:user)
    @integration = create(:copilot_pull_request_reviewer_integration)
    @private_repo = create(:private_repository, owner: @actor, from_example: :review_comment_fork)

    branch = create(:protected_branch, repository: @private_repo, name: "master")
    @pull_request = create(:pull_request,
      repository: @private_repo,
      base_repository: @private_repo,
      base_user: @private_repo.owner,
      base_ref: "master",
      head_repository: @private_repo,
      head_user: @private_repo.owner,
      head_ref: "topic",
      user: @actor
    )
  end

  setup do
    # Set up all repos and owners to be enabled by default
    repos = [@private_repo, @public_repo, @internal_repo]
    repos.each do |repo|
      repo.enable_feature(:copilot_reviews_automatic_pull_request_review)
      repo.owner.enable_feature(:copilot_reviews_automatic_pull_request_review)

      repo.enable_feature(:copilot_pr_reviews_repository_access)
      repo.owner.enable_feature(:copilot_pr_reviews_repository_access)

      repo.disable_feature(:copilot_reviews_automatic_repo_rule)

      repo.disable_feature(:copilot_code_review_automatic_review_denylist)
      repo.owner.disable_feature(:copilot_code_review_automatic_review_denylist)
    end

    @actor.disable_feature(:copilot_code_review_public_preview_denylist)
    @actor.disable_feature(:copilot_reviews_automatic_pull_request_review_disabled)
    @actor.disable_feature(:copilot_code_review_check_filenames_for_reviewability)
    @actor.enable_feature(:copilot_pr_reviews_v1)
    @actor.enable_feature(:copilot_code_review_public_preview)
    @actor.enable_feature(:copilot_code_review_public_repo_reviews)

    # By default, don't bypass access checks
    @actor.disable_feature(:copilot_code_review_bypass_access_checks)

    # Set up pull requests so they appear to contain reviewable files
    PullRequest.any_instance.stubs(:diffs).returns(GitHub::Diff.new(@private_repo, @private_repo.heads.find_or_build("master"), @private_repo.heads.find_or_build("topic")))
    GitHub::Diff.any_instance.stubs(:file_types).returns([".rb"])
  end

  context "#repo_rule_auto_reviewable?" do
    test "true if repo has branch rule enabled" do
      @private_repo.enable_feature(:copilot_reviews_automatic_repo_rule)
      PullRequest.any_instance.stubs(:base_branch_rule_evaluator).returns(BranchRuleEvaluator.new(@private_repo, "master"))
      BranchRuleEvaluator.any_instance.stubs(:automatic_copilot_code_review_enabled?).returns(true)
      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo, pull_request: @pull_request)
      assert_predicate access, :repo_rule_auto_reviewable?
    end

    test "false if repo has branch rule enabled but repo is on denylist" do
      @private_repo.enable_feature(:copilot_code_review_automatic_review_denylist)
      @private_repo.enable_feature(:copilot_reviews_automatic_repo_rule)
      PullRequest.any_instance.stubs(:base_branch_rule_evaluator).returns(BranchRuleEvaluator.new(@private_repo, "master"))
      BranchRuleEvaluator.any_instance.stubs(:automatic_copilot_code_review_enabled?).returns(true)
      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo, pull_request: @pull_request)
      refute_predicate access, :repo_rule_auto_reviewable?
    end

    test "false if repo has branch rule enabled but repo owner is on denylist" do
      @private_repo.owner.enable_feature(:copilot_code_review_automatic_review_denylist)
      @private_repo.enable_feature(:copilot_reviews_automatic_repo_rule)
      PullRequest.any_instance.stubs(:base_branch_rule_evaluator).returns(BranchRuleEvaluator.new(@private_repo, "master"))
      BranchRuleEvaluator.any_instance.stubs(:automatic_copilot_code_review_enabled?).returns(true)
      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo, pull_request: @pull_request)
      refute_predicate access, :repo_rule_auto_reviewable?
    end
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

      test "false for public repo, flag set on repo, not opted-out, actor has disabled public flag" do
        @actor.disable_feature(:copilot_code_review_public_repo_reviews)
        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @public_repo)
        refute_predicate access, :auto_reviewable?
      end

      test "true for public repo, public flag set on actor, not opted-out" do
        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @public_repo)
        assert_predicate access, :auto_reviewable?
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

    test "false if repo owner is on the denylist" do
      @private_repo.owner.enable_feature(:copilot_code_review_automatic_review_denylist)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      refute_predicate access, :auto_reviewable?
    end

    test "false if repo is on the denylist" do
      @private_repo.enable_feature(:copilot_code_review_automatic_review_denylist)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      refute_predicate access, :auto_reviewable?
    end

    test "false if actor not in either the copilot_pr_reviews_v1 or the copilot_code_review_public_preview flag" do
      @actor.disable_feature(:copilot_pr_reviews_v1)
      @actor.disable_feature(:copilot_code_review_public_preview)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      refute_predicate access, :auto_reviewable?
    end

    test "false if actor is in the denylist flag and not in v1" do
      @actor.disable_feature(:copilot_pr_reviews_v1)
      @actor.enable_feature(:copilot_code_review_public_preview_denylist)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      refute_predicate access, :auto_reviewable?
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

      test "false for public repo, flag set on repo, not opted-out, public flag disabled for actor" do
        @actor.disable_feature(:copilot_code_review_public_repo_reviews)
        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @public_repo)
        refute_predicate access, :can_create_review_request?
      end

      test "true for public repo, flag set on repo, not opted-out, actor has enabled public flag" do
        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @public_repo)
        assert_predicate access, :auto_reviewable?
      end

      test "false for any repo that is not flagged in, if the user only has the v1 flag" do
        @actor.disable_feature(:copilot_code_review_public_preview)
        @private_repo.disable_feature(:copilot_pr_reviews_repository_access)
        @private_repo.owner.disable_feature(:copilot_pr_reviews_repository_access)

        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
        refute_predicate access, :can_create_review_request?
      end

      test "true for any non-public repo, even if repo not flagged in, if the user has the public preview flag" do
        @private_repo.disable_feature(:copilot_pr_reviews_repository_access)
        @private_repo.owner.disable_feature(:copilot_pr_reviews_repository_access)

        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
        assert_predicate access, :can_create_review_request?
      end
    end

    test "true if flagged in" do
      # setup block flagged the user in
      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      assert_predicate access, :can_create_review_request?
    end

    test "still true if actor has opted-out of automatic reviews via feature flag" do
      @actor.enable_feature(:copilot_reviews_automatic_pull_request_review_disabled)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      assert_predicate access, :can_create_review_request?
    end

    test "false if actor not in either the copilot_pr_reviews_v1 or the copilot_code_review_public_preview flag" do
      @actor.disable_feature(:copilot_pr_reviews_v1)
      @actor.disable_feature(:copilot_code_review_public_preview)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      refute_predicate access, :can_create_review_request?
    end

    test "false if actor is in the denylist flag and not in v1" do
      @actor.disable_feature(:copilot_pr_reviews_v1)
      @actor.enable_feature(:copilot_code_review_public_preview_denylist)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      refute_predicate access, :can_create_review_request?
    end

    test "true if we bypass access checks for this user, even if they're not flagged in otherwise" do
      @actor.enable_feature(:copilot_code_review_bypass_access_checks)
      @actor.disable_feature(:copilot_pr_reviews_v1)
      @actor.disable_feature(:copilot_code_review_public_preview)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      assert_predicate access, :can_create_review_request?
    end

    test "false if in public preview, not in v1, and has a free license" do
      @actor.disable_feature(:copilot_pr_reviews_v1)
      Copilot::Public::User.any_instance.stubs(:has_copilot_access?).returns(false)
      Copilot::Public::User.any_instance.stubs(:beta_features_github_chat_enabled?).returns(true)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      refute_predicate access, :can_create_review_request?
    end

    test "false if in public preview, not in v1, and has not opted into beta features" do
      @actor.disable_feature(:copilot_pr_reviews_v1)
      Copilot::Public::User.any_instance.stubs(:has_copilot_access?).returns(true)
      Copilot::Public::User.any_instance.stubs(:beta_features_github_chat_enabled?).returns(false)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      refute_predicate access, :can_create_review_request?
    end

    test "true if in public preview, not in v1, and has a paid license and opted into beta features" do
      @actor.disable_feature(:copilot_pr_reviews_v1)
      Copilot::Public::User.any_instance.stubs(:has_copilot_access?).returns(true)
      Copilot::Public::User.any_instance.stubs(:beta_features_github_chat_enabled?).returns(true)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      assert_predicate access, :can_create_review_request?
    end
  end

  context "#should_suggest_reviewer?" do
    context "repository eligibility" do
      test "true for private repo, flags set on repo, not opted-out" do
        @private_repo.disable_feature(:copilot_reviews_automatic_pull_request_review)
        @private_repo.owner.disable_feature(:copilot_reviews_automatic_pull_request_review)

        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
        assert_predicate access, :should_suggest_reviewer?
      end

      test "true for internal repo, flag set on repo, not opted-out" do
        @internal_repo.disable_feature(:copilot_reviews_automatic_pull_request_review)
        @internal_repo.owner.disable_feature(:copilot_reviews_automatic_pull_request_review)

        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @internal_repo)
        assert_predicate access, :should_suggest_reviewer?
      end

      test "false for public repo, flag set on repo, not opted-out, public flag disabled for actor" do
        @actor.disable_feature(:copilot_code_review_public_repo_reviews)
        @public_repo.disable_feature(:copilot_reviews_automatic_pull_request_review)
        @public_repo.owner.disable_feature(:copilot_reviews_automatic_pull_request_review)

        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @public_repo)
        refute_predicate access, :should_suggest_reviewer?
      end

      test "true for public repo, flag set on repo, not opted-out, public flag enabled for actor" do
        @public_repo.disable_feature(:copilot_reviews_automatic_pull_request_review)
        @public_repo.owner.disable_feature(:copilot_reviews_automatic_pull_request_review)

        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @public_repo)
        assert_predicate access, :should_suggest_reviewer?
      end

      test "false if copilot_reviews_automatic_pull_request_review enabled" do
        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
        refute_predicate access, :should_suggest_reviewer?
      end

      test "false if actor not in either the copilot_pr_reviews_v1 or the copilot_code_review_public_preview flag" do
        # Disable auto reviews so we would suggest reviewers if the actor had access.
        @private_repo.disable_feature(:copilot_reviews_automatic_pull_request_review)
        @private_repo.owner.disable_feature(:copilot_reviews_automatic_pull_request_review)
        @private_repo.disable_feature(:copilot_reviews_automatic_repo_rule)
        @private_repo.owner.disable_feature(:copilot_reviews_automatic_repo_rule)

        @actor.disable_feature(:copilot_pr_reviews_v1)
        @actor.disable_feature(:copilot_code_review_public_preview)
        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
        refute_predicate access, :should_suggest_reviewer?
      end

      test "true if repo rule flag is enabled but rule is not enabled" do
        @private_repo.enable_feature(:copilot_reviews_automatic_repo_rule)
        @actor.disable_feature(:copilot_reviews_automatic_pull_request_review)
        @private_repo.disable_feature(:copilot_reviews_automatic_pull_request_review)

        PullRequest.any_instance.stubs(:base_branch_rule_evaluator).returns(BranchRuleEvaluator.new(@private_repo, "master"))
        BranchRuleEvaluator.any_instance.stubs(:automatic_copilot_code_review_enabled?).returns(false)

        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo, pull_request: @pull_request)
        assert_predicate access, :should_suggest_reviewer?
      end

      test "false if repo rule flag is enabled and rule is enabled" do
        @private_repo.enable_feature(:copilot_reviews_automatic_repo_rule)
        @actor.disable_feature(:copilot_reviews_automatic_pull_request_review)
        @private_repo.disable_feature(:copilot_reviews_automatic_pull_request_review)

        PullRequest.any_instance.stubs(:base_branch_rule_evaluator).returns(BranchRuleEvaluator.new(@private_repo, "master"))
        BranchRuleEvaluator.any_instance.stubs(:automatic_copilot_code_review_enabled?).returns(true)
        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo, pull_request: @pull_request)
        refute_predicate access, :should_suggest_reviewer?
      end
    end

    test "true if actor is in the copilot_pr_reviews_v1 flag" do
      # Disable auto reviews so we would suggest reviewers if the actor had access.
      @private_repo.disable_feature(:copilot_reviews_automatic_pull_request_review)
      @private_repo.owner.disable_feature(:copilot_reviews_automatic_pull_request_review)
      @private_repo.disable_feature(:copilot_reviews_automatic_repo_rule)
      @private_repo.owner.disable_feature(:copilot_reviews_automatic_repo_rule)

      @actor.enable_feature(:copilot_pr_reviews_v1)
      @actor.disable_feature(:copilot_code_review_public_preview)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      assert_predicate access, :should_suggest_reviewer?
    end

    test "true if actor is in the copilot_code_review_public_preview flag and has copilot access and copilot beta features" do
      # Disable auto reviews so we would suggest reviewers if the actor had access.
      @private_repo.disable_feature(:copilot_reviews_automatic_pull_request_review)
      @private_repo.owner.disable_feature(:copilot_reviews_automatic_pull_request_review)
      @private_repo.disable_feature(:copilot_reviews_automatic_repo_rule)
      @private_repo.owner.disable_feature(:copilot_reviews_automatic_repo_rule)

      @actor.disable_feature(:copilot_pr_reviews_v1)
      Copilot::Public::User.any_instance.stubs(:has_paid_access?).returns(true)
      Copilot::Public::User.any_instance.stubs(:beta_features_github_chat_enabled?).returns(true)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      assert_predicate access, :should_suggest_reviewer?
    end

    context "diff file reviewability" do
      test "allow supported file type" do
        @actor.disable_feature(:copilot_reviews_automatic_pull_request_review)
        @private_repo.disable_feature(:copilot_reviews_automatic_pull_request_review)
        PullRequest.any_instance.stubs(:diffs).returns(GitHub::Diff.new(@private_repo, @private_repo.heads.find_or_build("master"), @private_repo.heads.find_or_build("topic")))
        GitHub::Diff.any_instance.stubs(:file_types).returns([".rb"])

        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo, pull_request: @pull_request)
        assert access.should_suggest_reviewer?
      end

      test "reject unsupported file type" do
        @actor.disable_feature(:copilot_reviews_automatic_pull_request_review)
        @private_repo.disable_feature(:copilot_reviews_automatic_pull_request_review)
        PullRequest.any_instance.stubs(:diffs).returns(GitHub::Diff.new(@private_repo, @private_repo.heads.find_or_build("master"), @private_repo.heads.find_or_build("topic")))
        GitHub::Diff.any_instance.stubs(:file_types).returns([".abc"])

        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo, pull_request: @pull_request)
        refute access.should_suggest_reviewer?
      end

      test "ignore filename by default" do
        @actor.disable_feature(:copilot_reviews_automatic_pull_request_review)
        @private_repo.disable_feature(:copilot_reviews_automatic_pull_request_review)
        PullRequest.any_instance.stubs(:diffs).returns(GitHub::Diff.new(@private_repo, @private_repo.heads.find_or_build("master"), @private_repo.heads.find_or_build("topic")))
        GitHub::Diff.any_instance.stubs(:file_types).returns([".abc"])
        GitHub::Diff.any_instance.stubs(:filenames).returns(["Rakefile"])

        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo, pull_request: @pull_request)
        refute access.should_suggest_reviewer?
      end

      test "consider filename as part of eligibility check if flag enabled" do
        @actor.enable_feature(:copilot_code_review_check_filenames_for_reviewability)
        @actor.disable_feature(:copilot_reviews_automatic_pull_request_review)
        @private_repo.disable_feature(:copilot_reviews_automatic_pull_request_review)
        PullRequest.any_instance.stubs(:diffs).returns(GitHub::Diff.new(@private_repo, @private_repo.heads.find_or_build("master"), @private_repo.heads.find_or_build("topic")))
        GitHub::Diff.any_instance.stubs(:filenames).returns(["Rakefile"])

        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo, pull_request: @pull_request)
        assert access.should_suggest_reviewer?
      end

      test "allow C++ when feature flag enabled" do
        @actor.disable_feature(:copilot_reviews_automatic_pull_request_review)
        @private_repo.disable_feature(:copilot_reviews_automatic_pull_request_review)
        @private_repo.owner.enable_feature(:expand_supported_languages_cpp)
        PullRequest.any_instance.stubs(:diffs).returns(GitHub::Diff.new(@private_repo, @private_repo.heads.find_or_build("master"), @private_repo.heads.find_or_build("topic")))
        GitHub::Diff.any_instance.stubs(:file_types).returns([".cpp"])

        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo, pull_request: @pull_request)
        assert access.should_suggest_reviewer?
      end
    end
  end
end
