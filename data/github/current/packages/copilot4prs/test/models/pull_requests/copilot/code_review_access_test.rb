# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequests::Copilot::CodeReviewAccessTest < GitHub::TestCase
  skip_enterprise

  fixtures do
    @public_repo = create(:public_repository)
    @internal_repo = create(:internal_repository)
    @actor = create(:user)
    @org = create(:organization)
    @enterprise = create(:business)
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
      enable_feature_flag(:copilot_reviews_automatic_pull_request_review, repo)
      enable_feature_flag(:copilot_reviews_automatic_pull_request_review, repo.owner)
    end

    disable_feature_flag(:copilot_reviews_automatic_repo_rule, @actor)
    disable_feature_flag(:copilot_reviews_automatic_pull_request_review_disabled, @actor)
    disable_feature_flag(:copilot_code_review_check_filenames_for_reviewability, @actor)
    enable_feature_flag(:copilot_code_review_v1, @actor)
    enable_feature_flag(:copilot_code_review_public_preview, @actor)
    enable_feature_flag(:copilot_code_review_public_preview, @org)
    enable_feature_flag(:copilot_code_review_public_preview, @enterprise)
    enable_feature_flag(:copilot_code_review_public_repo_reviews, @actor)

    # By default, don't bypass access checks
    disable_feature_flag(:copilot_code_review_bypass_access_checks, @actor)

    # Set up pull requests so they appear to contain reviewable files
    PullRequest.any_instance.stubs(:diffs).returns(GitHub::Diff.new(@private_repo, @private_repo.heads.find_or_build("master"), @private_repo.heads.find_or_build("topic")))
    GitHub::Diff.any_instance.stubs(:file_types).returns([".rb"])
  end

  context "#repo_rule_auto_reviewable?" do
    test "true if repo has branch rule enabled" do
      PullRequest.any_instance.stubs(:base_branch_rule_evaluator).returns(BranchRuleEvaluator.new(@private_repo, "master"))
      BranchRuleEvaluator.any_instance.stubs(:automatic_copilot_code_review_enabled?).returns(true)
      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo, pull_request: @pull_request)
      assert access.repo_rule_auto_reviewable?
    end
  end

  context "#auto_reviewable?" do
    context "repository eligibility" do
      test "true for private repo, flags set on repo, not opted-out" do
        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
        assert access.auto_reviewable?
      end

      test "true for internal repo, flag set on repo, not opted-out" do
        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @internal_repo)
        assert access.auto_reviewable?
      end

      test "false for public repo, flag set on repo, not opted-out, actor has disabled public flag" do
        disable_feature_flag(:copilot_code_review_public_repo_reviews, @actor)
        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @public_repo)
        refute access.auto_reviewable?
      end

      test "true for public repo, public flag set on actor, not opted-out" do
        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @public_repo)
        assert access.auto_reviewable?
      end
    end

    test "false if actor has opted-out via feature flag" do
      enable_feature_flag(:copilot_reviews_automatic_pull_request_review_disabled, @actor)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      refute access.auto_reviewable?
    end

    test "false if repo and owner have auto flag disabled" do
      disable_feature_flag(:copilot_reviews_automatic_pull_request_review, @private_repo)
      disable_feature_flag(:copilot_reviews_automatic_pull_request_review, @private_repo.owner)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      refute access.auto_reviewable?
    end

    test "true if repo has auto flag enabled and owner has auto flag disabled" do
      disable_feature_flag(:copilot_reviews_automatic_pull_request_review, @private_repo.owner)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      assert access.auto_reviewable?
    end

    test "true if repo has auto flag disabled and owner has auto flag enabled" do
      disable_feature_flag(:copilot_reviews_automatic_pull_request_review, @private_repo)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      assert access.auto_reviewable?
    end

    test "false if actor not in either the copilot_code_review_v1 or the copilot_code_review_public_preview flag" do
      disable_feature_flag(:copilot_code_review_v1, @actor)
      disable_feature_flag(:copilot_code_review_public_preview, @actor)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      refute access.auto_reviewable?
    end
  end

  context "#can_create_review_request?" do
    context "repository eligibility" do
      test "true for private repo, flags set on repo, not opted-out" do
        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
        assert access.can_create_review_request?
      end

      test "true for internal repo, flag set on repo, not opted-out" do
        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @internal_repo)
        assert access.can_create_review_request?
      end

      test "false for public repo, flag set on repo, not opted-out, public flag disabled for actor" do
        disable_feature_flag(:copilot_code_review_public_repo_reviews, @actor)
        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @public_repo)
        refute access.can_create_review_request?
      end

      test "true for public repo, flag set on repo, not opted-out, actor has enabled public flag" do
        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @public_repo)
        assert access.auto_reviewable?
      end
    end

    test "true if flagged in" do
      # setup block flagged the user in
      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      assert access.can_create_review_request?
    end

    test "still true if actor has opted-out of automatic reviews via feature flag" do
      enable_feature_flag(:copilot_reviews_automatic_pull_request_review_disabled, @actor)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      assert access.can_create_review_request?
    end

    test "false if actor not in either the copilot_code_review_v1 or the copilot_code_review_public_preview flag" do
      disable_feature_flag(:copilot_code_review_v1, @actor)
      disable_feature_flag(:copilot_code_review_public_preview, @actor)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      refute access.can_create_review_request?
    end

    test "true if we bypass access checks for this user, even if they're not flagged in otherwise" do
      enable_feature_flag(:copilot_code_review_bypass_access_checks, @actor)
      disable_feature_flag(:copilot_code_review_v1, @actor)
      disable_feature_flag(:copilot_code_review_public_preview, @actor)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      assert access.can_create_review_request?
    end

    test "false if in public preview, not in v1, and has a free license" do
      disable_feature_flag(:copilot_code_review_v1, @actor)
      Copilot::Public::User.any_instance.stubs(:has_copilot_access?).returns(false)
      Copilot::Public::User.any_instance.stubs(:beta_features_github_chat_enabled?).returns(true)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      refute access.can_create_review_request?
    end

    test "false if in public preview, not in v1, and has not opted into beta features" do
      disable_feature_flag(:copilot_code_review_v1, @actor)
      Copilot::Public::User.any_instance.stubs(:has_copilot_access?).returns(true)
      Copilot::Public::User.any_instance.stubs(:beta_features_github_chat_enabled?).returns(false)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      refute access.can_create_review_request?
    end

    test "true if in public preview, not in v1, and has a paid license and opted into beta features" do
      disable_feature_flag(:copilot_code_review_v1, @actor)
      Copilot::Public::User.any_instance.stubs(:has_copilot_access?).returns(true)
      Copilot::Public::User.any_instance.stubs(:beta_features_github_chat_enabled?).returns(true)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      assert access.can_create_review_request?
    end

    context "non-user-actors / repo rule visibility" do
      test "false for public repos" do
        access = PullRequests::Copilot::CodeReviewAccess.new(current_repository: @public_repo, actor: @public_repo.owner)
        refute access.can_create_review_request?
      end

      test "true for eligible repos and orgs" do
        Copilot::Organization.any_instance.stubs(:beta_features_github_chat_enabled?).returns(true)

        access = PullRequests::Copilot::CodeReviewAccess.new(current_repository: @private_repo, actor: @org)
        assert access.can_create_review_request?
      end

      test "true for eligible orgs and nil repo (org settings)" do
        Copilot::Organization.any_instance.stubs(:beta_features_github_chat_enabled?).returns(true)

        access = PullRequests::Copilot::CodeReviewAccess.new(current_repository: nil, actor: @org)
        assert access.can_create_review_request?
      end

      test "true for eligible enterprises and nil repo (enterprise settings)" do
        Copilot::Business.any_instance.stubs(:beta_features_github_chat_enabled?).returns(true)

        access = PullRequests::Copilot::CodeReviewAccess.new(current_repository: nil, actor: @enterprise)
        assert access.can_create_review_request?
      end
    end
  end

  context "#can_create_review_request_reason" do
    has_access = PullRequests::Copilot::CodeReviewAccess::Reason.new(access: true, reason: :eligible)
    actor_ineligible = PullRequests::Copilot::CodeReviewAccess::Reason.new(access: false, reason: :actor_ineligible)
    repo_ineligible = PullRequests::Copilot::CodeReviewAccess::Reason.new(access: false, reason: :repository_ineligible)
    app_not_installed = PullRequests::Copilot::CodeReviewAccess::Reason.new(access: false, reason: :app_not_installed)
    actor_has_no_quota = PullRequests::Copilot::CodeReviewAccess::Reason.new(access: false, reason: :actor_has_no_quota_remaining)

    context "repository eligibility" do
      test "has access for private repo, flags set on repo, not opted-out" do
        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
        assert_equal has_access, access.can_create_review_request_reason
      end

      test "has access for internal repo, flag set on repo, not opted-out" do
        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @internal_repo)
        assert_equal has_access, access.can_create_review_request_reason
      end

      test "false for public repo, flag set on repo, not opted-out, public flag disabled for actor" do
        disable_feature_flag(:copilot_code_review_public_repo_reviews, @actor)
        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @public_repo)
        assert_equal repo_ineligible, access.can_create_review_request_reason
      end

      test "true for public repo, flag set on repo, not opted-out, actor has enabled public flag" do
        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @public_repo)
        assert_equal has_access, access.can_create_review_request_reason
      end
    end

    test "has_access if flagged in" do
      # setup block flagged the user in
      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      assert_equal has_access, access.can_create_review_request_reason
    end

    test "has_access if actor has opted-out of automatic reviews via feature flag" do
      enable_feature_flag(:copilot_reviews_automatic_pull_request_review_disabled, @actor)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      assert_equal has_access, access.can_create_review_request_reason
    end

    test "actor_ineligible if actor not in either the copilot_code_review_v1 or the copilot_code_review_public_preview flag" do
      disable_feature_flag(:copilot_code_review_v1, @actor)
      disable_feature_flag(:copilot_code_review_public_preview, @actor)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      assert_equal actor_ineligible, access.can_create_review_request_reason
    end

    test "has_access if we bypass access checks for this user, even if they're not flagged in otherwise" do
      enable_feature_flag(:copilot_code_review_bypass_access_checks, @actor)
      disable_feature_flag(:copilot_code_review_v1, @actor)
      disable_feature_flag(:copilot_code_review_public_preview, @actor)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      assert_equal has_access, access.can_create_review_request_reason
    end

    test "actor_ineligible if in public preview, not in v1, and has a free license" do
      disable_feature_flag(:copilot_code_review_v1, @actor)
      Copilot::Public::User.any_instance.stubs(:has_copilot_access?).returns(false)
      Copilot::Public::User.any_instance.stubs(:beta_features_github_chat_enabled?).returns(true)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      assert_equal actor_ineligible, access.can_create_review_request_reason
    end

    test "actor_ineligible if in public preview, not in v1, and has not opted into beta features" do
      disable_feature_flag(:copilot_code_review_v1, @actor)
      Copilot::Public::User.any_instance.stubs(:has_copilot_access?).returns(true)
      Copilot::Public::User.any_instance.stubs(:beta_features_github_chat_enabled?).returns(false)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      assert_equal actor_ineligible, access.can_create_review_request_reason
    end

    test "has_access if in public preview, not in v1, and has a paid license and opted into beta features" do
      disable_feature_flag(:copilot_code_review_v1, @actor)
      Copilot::Public::User.any_instance.stubs(:has_copilot_access?).returns(true)
      Copilot::Public::User.any_instance.stubs(:beta_features_github_chat_enabled?).returns(true)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      assert_equal has_access, access.can_create_review_request_reason
    end

    context "non-user-actors / repo rule visibility" do
      test "actor_ineligible for public repos" do
        access = PullRequests::Copilot::CodeReviewAccess.new(current_repository: @public_repo, actor: @public_repo.owner)
        assert_equal actor_ineligible, access.can_create_review_request_reason
      end

      test "has_access for eligible repos and orgs" do
        Copilot::Organization.any_instance.stubs(:beta_features_github_chat_enabled?).returns(true)

        access = PullRequests::Copilot::CodeReviewAccess.new(current_repository: @private_repo, actor: @org)
        assert_equal has_access, access.can_create_review_request_reason
      end

      test "has_access for eligible orgs and nil repo (org settings)" do
        Copilot::Organization.any_instance.stubs(:beta_features_github_chat_enabled?).returns(true)

        access = PullRequests::Copilot::CodeReviewAccess.new(current_repository: nil, actor: @org)
        assert_equal has_access, access.can_create_review_request_reason
      end

      test "has_access for eligible enterprises and nil repo (enterprise settings)" do
        Copilot::Business.any_instance.stubs(:beta_features_github_chat_enabled?).returns(true)

        access = PullRequests::Copilot::CodeReviewAccess.new(current_repository: nil, actor: @enterprise)
        assert_equal has_access, access.can_create_review_request_reason
      end
    end
  end

  context "Quota and premium request related methods" do
    context "#has_quota_remaining?" do
      test "true if user has quota remaining" do
        PullRequests::Copilot::CodeReviewQuota.any_instance.stubs(:has_quota_remaining?).returns(true)
        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
        assert access.has_quota_remaining?
      end

      test "false if user has no quota remaining" do
        PullRequests::Copilot::CodeReviewQuota.any_instance.stubs(:has_quota_remaining?).returns(false)
        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
        refute access.has_quota_remaining?
      end
    end

    context "#remaining_quota" do
      test "returns the remaining quota for the user" do
        PullRequests::Copilot::CodeReviewQuota.any_instance.stubs(:remaining_quota).returns(0.5)
        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
        assert_equal 0.5, access.remaining_quota
      end
    end
  end

  context "#should_suggest_reviewer?" do
    context "repository eligibility" do
      test "true for private repo, flags set on repo, not opted-out" do
        disable_feature_flag(:copilot_reviews_automatic_pull_request_review, @private_repo)
        disable_feature_flag(:copilot_reviews_automatic_pull_request_review, @private_repo.owner)

        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
        assert access.should_suggest_reviewer?
      end

      test "true for internal repo, flag set on repo, not opted-out" do
        disable_feature_flag(:copilot_reviews_automatic_pull_request_review, @internal_repo)
        disable_feature_flag(:copilot_reviews_automatic_pull_request_review, @internal_repo.owner)

        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @internal_repo)
        assert access.should_suggest_reviewer?
      end

      test "false for public repo, flag set on repo, not opted-out, public flag disabled for actor" do
        disable_feature_flag(:copilot_code_review_public_repo_reviews, @actor)
        disable_feature_flag(:copilot_reviews_automatic_pull_request_review, @public_repo)
        disable_feature_flag(:copilot_reviews_automatic_pull_request_review, @public_repo.owner)

        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @public_repo)
        refute access.should_suggest_reviewer?
      end

      test "true for public repo, flag set on repo, not opted-out, public flag enabled for actor" do
        disable_feature_flag(:copilot_reviews_automatic_pull_request_review, @public_repo)
        disable_feature_flag(:copilot_reviews_automatic_pull_request_review, @public_repo.owner)

        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @public_repo)
        assert access.should_suggest_reviewer?
      end

      test "false if copilot_reviews_automatic_pull_request_review enabled" do
        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
        refute access.should_suggest_reviewer?
      end

      test "false if actor not in either the copilot_code_review_v1 or the copilot_code_review_public_preview flag" do
        # Disable auto reviews so we would suggest reviewers if the actor had access.
        disable_feature_flag(:copilot_reviews_automatic_pull_request_review, @private_repo)
        disable_feature_flag(:copilot_reviews_automatic_pull_request_review, @private_repo.owner)

        disable_feature_flag(:copilot_code_review_v1, @actor)
        disable_feature_flag(:copilot_code_review_public_preview, @actor)
        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
        refute access.should_suggest_reviewer?
      end

      test "true if repo rule flag is enabled but rule is not enabled" do
        disable_feature_flag(:copilot_reviews_automatic_pull_request_review, @actor)
        disable_feature_flag(:copilot_reviews_automatic_pull_request_review, @private_repo)

        PullRequest.any_instance.stubs(:base_branch_rule_evaluator).returns(BranchRuleEvaluator.new(@private_repo, "master"))
        BranchRuleEvaluator.any_instance.stubs(:automatic_copilot_code_review_enabled?).returns(false)

        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo, pull_request: @pull_request)
        assert access.should_suggest_reviewer?
      end

      test "false if repo rule flag is enabled and rule is enabled" do
        disable_feature_flag(:copilot_reviews_automatic_pull_request_review, @actor)
        disable_feature_flag(:copilot_reviews_automatic_pull_request_review, @private_repo)

        PullRequest.any_instance.stubs(:base_branch_rule_evaluator).returns(BranchRuleEvaluator.new(@private_repo, "master"))
        BranchRuleEvaluator.any_instance.stubs(:automatic_copilot_code_review_enabled?).returns(true)
        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo, pull_request: @pull_request)
        refute access.should_suggest_reviewer?
      end
    end

    test "true if actor is in the copilot_code_review_v1 flag" do
      # Disable auto reviews so we would suggest reviewers if the actor had access.
      disable_feature_flag(:copilot_reviews_automatic_pull_request_review, @private_repo)
      disable_feature_flag(:copilot_reviews_automatic_pull_request_review, @private_repo.owner)

      enable_feature_flag(:copilot_code_review_v1, @actor)
      disable_feature_flag(:copilot_code_review_public_preview, @actor)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      assert access.should_suggest_reviewer?
    end

    test "true if actor is in the copilot_code_review_public_preview flag and has copilot access and copilot beta features" do
      # Disable auto reviews so we would suggest reviewers if the actor had access.
      disable_feature_flag(:copilot_reviews_automatic_pull_request_review, @private_repo)
      disable_feature_flag(:copilot_reviews_automatic_pull_request_review, @private_repo.owner)

      disable_feature_flag(:copilot_code_review_v1, @actor)
      Copilot::Public::User.any_instance.stubs(:has_paid_access?).returns(true)
      Copilot::Public::User.any_instance.stubs(:beta_features_github_chat_enabled?).returns(true)

      access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo)
      assert access.should_suggest_reviewer?
    end

    context "diff file reviewability" do
      test "allow supported file type" do
        disable_feature_flag(:copilot_reviews_automatic_pull_request_review, @actor)
        disable_feature_flag(:copilot_reviews_automatic_pull_request_review, @private_repo)
        PullRequest.any_instance.stubs(:diffs).returns(GitHub::Diff.new(@private_repo, @private_repo.heads.find_or_build("master"), @private_repo.heads.find_or_build("topic")))
        GitHub::Diff.any_instance.stubs(:file_types).returns([".rb"])

        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo, pull_request: @pull_request)
        assert access.should_suggest_reviewer?
      end

      test "reject unsupported file type" do
        disable_feature_flag(:copilot_reviews_automatic_pull_request_review, @actor)
        disable_feature_flag(:copilot_reviews_automatic_pull_request_review, @private_repo)
        PullRequest.any_instance.stubs(:diffs).returns(GitHub::Diff.new(@private_repo, @private_repo.heads.find_or_build("master"), @private_repo.heads.find_or_build("topic")))
        GitHub::Diff.any_instance.stubs(:file_types).returns([".abc"])

        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo, pull_request: @pull_request)
        refute access.should_suggest_reviewer?
      end

      test "ignore filename by default" do
        disable_feature_flag(:copilot_reviews_automatic_pull_request_review, @actor)
        disable_feature_flag(:copilot_reviews_automatic_pull_request_review, @private_repo)
        PullRequest.any_instance.stubs(:diffs).returns(GitHub::Diff.new(@private_repo, @private_repo.heads.find_or_build("master"), @private_repo.heads.find_or_build("topic")))
        GitHub::Diff.any_instance.stubs(:file_types).returns([".abc"])
        GitHub::Diff.any_instance.stubs(:filenames).returns(["Rakefile"])

        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo, pull_request: @pull_request)
        refute access.should_suggest_reviewer?
      end

      test "consider filename as part of eligibility check if flag enabled" do
        enable_feature_flag(:copilot_code_review_check_filenames_for_reviewability, @actor)
        disable_feature_flag(:copilot_reviews_automatic_pull_request_review, @actor)
        disable_feature_flag(:copilot_reviews_automatic_pull_request_review, @private_repo)
        PullRequest.any_instance.stubs(:diffs).returns(GitHub::Diff.new(@private_repo, @private_repo.heads.find_or_build("master"), @private_repo.heads.find_or_build("topic")))
        GitHub::Diff.any_instance.stubs(:filenames).returns(["Rakefile"])

        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo, pull_request: @pull_request)
        assert access.should_suggest_reviewer?
      end

      test "allow C++ when feature flag enabled" do
        disable_feature_flag(:copilot_reviews_automatic_pull_request_review, @actor)
        disable_feature_flag(:copilot_reviews_automatic_pull_request_review, @private_repo)
        enable_feature_flag(:expand_supported_languages_cpp, @private_repo.owner)
        PullRequest.any_instance.stubs(:diffs).returns(GitHub::Diff.new(@private_repo, @private_repo.heads.find_or_build("master"), @private_repo.heads.find_or_build("topic")))
        GitHub::Diff.any_instance.stubs(:file_types).returns([".cpp"])

        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo, pull_request: @pull_request)
        assert access.should_suggest_reviewer?
      end

      test "allow C when feature flag enabled" do
        disable_feature_flag(:copilot_reviews_automatic_pull_request_review, @actor)
        disable_feature_flag(:copilot_reviews_automatic_pull_request_review, @private_repo)
        enable_feature_flag(:copilot_code_review_enable_c_support, @private_repo.owner)
        PullRequest.any_instance.stubs(:diffs).returns(GitHub::Diff.new(@private_repo, @private_repo.heads.find_or_build("master"), @private_repo.heads.find_or_build("topic")))
        GitHub::Diff.any_instance.stubs(:file_types).returns([".c"])

        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @actor, current_repository: @private_repo, pull_request: @pull_request)
        assert access.should_suggest_reviewer?
      end
    end
  end
end
