# typed: true
# frozen_string_literal: true

require "test_helper"

class BranchProtectionStepTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)
    @params = {
      "name" => "release_v1",
      "required-pull-request-reviews" => {
        "dismiss-stale-reviews" => true,
        "required-approving-review-count" => 2,
        "require-code-owner-reviews" => true
      },
      "enforce-admins" => true,
      "allow-force-pushes" => true,
      "allow-deletions" => true
    }

    @step_obj = ("StacksSteps::BranchProtectionStep").constantize
  end

  setup do
    @repo.stubs(:can_update_protected_branches?).returns(true)
  end

  context "#validate_inputs" do
    test "raises error when required-pull-request-reviews exceeds max" do
      error = assert_raises(Errors::ValidationError) do
        @step_obj.validate_inputs({ "required-pull-request-reviews" => { "required-approving-review-count" => ProtectedBranch::MAX_REQUIRED_APPROVING_REVIEW_COUNT + 1 } }, repo: @repo, actor: @user)
      end
      assert_match "Step validation failed: required-approving-review-count should be between 0 - 255", error.message
    end

    test "succeeds with no error when mandatory fields present" do
      @step_obj.validate_inputs(@params, repo: @repo, actor: @user)
    end

    test "raises error when Branch protection not supported" do
      @repo.stubs(:plan_supports?).returns(false)

      error = assert_raises(Errors::ValidationError) do
        @step_obj.validate_inputs(@params, repo: @repo, actor: @user)
      end
      assert_match "Step validation failed: Branch Protection Plan not supported in given repository.", error.message
    end

    test "succeeds when configs are missing" do
      params = {
        "name" => "release_v1"
      }

      @repo.stubs(:plan_supports?).returns(true)
      @step_obj.validate_inputs(params, repo: @repo, actor: @user)
    end
  end

  context "#run:" do
    test "updates branch protection" do
      @repo.expects(:protect_branch).once
      StacksSteps::BranchProtectionStep.new(instance_id: 123, inputs: @params).run(repo: @repo, actor: @user)
    end

    test "adds all properties in branch protection" do
      StacksSteps::BranchProtectionStep.new(instance_id: 123, inputs: @params).run(repo: @repo, actor: @user)
      protected_branch = @repo.protected_branches.find_by(name: @params["name"])

      refute_nil protected_branch

      assert protected_branch.strict_required_status_checks_policy # enforce_admins
      assert_equal "everyone", protected_branch.allow_force_pushes_enforcement_level # allow_force_pushes
      assert_equal "everyone", protected_branch.allow_deletions_enforcement_level # allow_deletions

      # required_pull_request_reviews
      assert protected_branch.require_code_owner_review
      assert protected_branch.dismiss_stale_reviews_on_push
      assert_equal 2, protected_branch.required_approving_review_count
    end

    test "works with defaults when configs are missing" do
      params = {
        "name" => "release_v1"
      }

      StacksSteps::BranchProtectionStep.new(instance_id: 123, inputs: params).run(repo: @repo, actor: @user)
      protected_branch = @repo.protected_branches.find_by(name: params["name"])

      refute_nil protected_branch

      assert protected_branch.strict_required_status_checks_policy # enforce_admins
      assert_equal "off", protected_branch.allow_force_pushes_enforcement_level # allow_force_pushes
      assert_equal "off", protected_branch.allow_deletions_enforcement_level # allow_deletions

      # required_pull_request_reviews
      refute protected_branch.require_code_owner_review
      refute protected_branch.dismiss_stale_reviews_on_push
      assert_equal 1, protected_branch.required_approving_review_count
    end

    test "works for wildcards" do
      params = @params.deep_dup
      params["name"] = "releases/*"
      StacksSteps::BranchProtectionStep.new(instance_id: 123, inputs: params).run(repo: @repo, actor: @user)
      protected_branch = @repo.protected_branches.find_by(name: params["name"])
      refute_nil protected_branch
    end
  end

  context "cleanup" do
    test "cleanup all protection rules in a repo" do
      sample_user = create(:user)
      sample_repo = create(:repository, owner: sample_user)

      protected_branch_1 = create(:protected_branch,
        repository: sample_repo,
        creator: sample_user,
        name: "branch_1")
      protected_branch_2 = create(:protected_branch,
        repository: sample_repo,
        creator: sample_user,
        name: "branch_2")
      protected_branch_3 = create(:protected_branch,
        repository: sample_repo,
        creator: sample_user,
        name: "branch_3")

      assert_equal 3, sample_repo.protected_branches.size

      StacksSteps::BranchProtectionStep.new(instance_id: 123, inputs: {}).cleanup(repo: sample_repo, actor: sample_user)

      branch_protections_in_repo = Repositories::Public.find_active!(sample_repo.id).protected_branches
      assert_equal 0, branch_protections_in_repo.size
    end

    test "Don't raise exceptions when a repo does not contain any protected branches" do
      sample_user = create(:user)
      sample_repo = create(:repository, owner: sample_user)

      StacksSteps::BranchProtectionStep.new(instance_id: 123, inputs: {}).cleanup(repo: sample_repo, actor: sample_user)

      branch_protections_in_repo = Repositories::Public.find_active!(sample_repo.id).protected_branches
      assert_equal 0, branch_protections_in_repo.size
    end
  end
end
