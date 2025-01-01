# typed: false
# frozen_string_literal: true

require "test_helper"

class RepoCloneStepTest < GitHub::TestCase
  fixtures do
    @user = create(:user, login: "iamuser")
    @template_repo = create(:repository, :full_creation, owner: @user, name: "test_template_repo", template: true)
    add_files(@template_repo)
    create :release, name: "Version One!", tag_name: "v1.0", author: @template_repo.owner, repository: @template_repo
    @repo = create(:repository, :full_creation, owner: @user, name: "test_new_repo")
    @stacks_instance = StacksInstance.create(template_repo: @template_repo.name_with_owner, owner_id: @repo.owner_id, actor_id: @user.id,
                                              instance_repository_id: @repo.id, template_repository_id: @template_repo.id, template_ref: "refs/tags/v1.0")
    enable_feature_flag(:stacks_toggle, @user)
    @stacks_plan = StacksPlan.create(instance_id: @stacks_instance.id, actor_id: @user.id, status: StacksStatus.statuses[:not_started])
    @stacks_flow = StacksFlow.create(instance_id: @stacks_instance.id, plan_id: @stacks_plan.id, depends_on: nil)
    @stacks_step = StacksSteps::Step.create(instance_id: @stacks_instance.id, plan_id: @stacks_plan.id, flow_id: @stacks_flow.id, type: "StacksSteps::RepoCloneStep")
    @stacks_instance.submit_plan(@stacks_plan)
  end


  context "validate_inputs" do
    test "Raises error if no ref in inputs" do
      stack_repo = create(:repository, owner: @user)

      assert_raises(Errors::ValidationError) do
        StacksSteps::RepoCloneStep.validate_inputs({}, repo: nil, actor: @user, stack_repo: stack_repo)
      end
    end

    test "Raises error if ref in inputs is not of type string" do
      stack_repo = create(:repository, owner: @user)

      assert_raises(Errors::ValidationError) do
        StacksSteps::RepoCloneStep.validate_inputs({ "ref" => 1 }, repo: nil, actor: @user, stack_repo: stack_repo)
      end
    end

    test "Raises error if user can't read stack repo" do
      private_repo = create(:private_repository, owner: @user)
      assert_raises(Errors::ValidationError) do
        StacksSteps::RepoCloneStep.validate_inputs({ "ref" => "v1.0" }, repo: nil, actor: create(:user), stack_repo: private_repo)
      end
    end

    test "Raises error if stack repo is not active" do
      stack_repo = create(:repository, owner: @user)

      # makes repo inactive
      stack_repo.remove(@user)

      assert_raises(Errors::ValidationError) do
        StacksSteps::RepoCloneStep.validate_inputs({ "ref" => "v1.0" }, repo: nil, actor: @user, stack_repo: stack_repo)
      end
    end

    test "Raises error if stack repo is disabled" do
      stack_repo = create(:repository)

      # disable repository
      create(:disabled_access_reason, flagged_item_type: "Repository", flagged_item_id: stack_repo.id)

      assert_raises(Errors::ValidationError) do
        StacksSteps::RepoCloneStep.validate_inputs({ "ref" => "v1.0" }, repo: nil, actor: @user, stack_repo: stack_repo)
      end
    end
  end

  context "run" do
    test "raises error when clone_ref is not successful" do
      repo_clone_step = StacksSteps::RepoCloneStep.new(inputs: { ref: "v1.0" }, instance_id: @stacks_instance.id)
      StacksCloneHelper.any_instance.stubs(:clone_ref).raises(Errors::CloneError.new("active template repo too large", :repo_size_too_large))

      error = assert_raises(Errors::RepoCloningError) do
        repo_clone_step.run(repo: @repo, actor: @user)
      end
      assert_match "Could not finish repository cloning. active template repo too large", error.message
      assert_equal @repo.empty?, true
    end

    test "works successfully when ref is not nil" do
      repo = create(:repository, :full_creation, owner: @user, name: "fake_new_repo")
      stacks_instance = StacksInstance.create(template_repo: @template_repo.name_with_owner, owner_id: @repo.owner_id, actor_id: @user.id,
        instance_repository_id: repo.id, template_repository_id: @template_repo.id, template_ref: "refs/tags/v1.0")
      stacks_plan = StacksPlan.create(instance_id: stacks_instance.id, actor_id: @user.id, status: StacksStatus.statuses[:not_started])
      stacks_flow = StacksFlow.create(instance_id: stacks_instance.id, plan_id: stacks_plan.id, depends_on: nil)
      repo_clone_step = StacksSteps::Step.create(instance_id: stacks_instance.id, plan_id: stacks_plan.id, flow_id: stacks_flow.id, inputs: { ref: "v1.0" }, type: "StacksSteps::RepoCloneStep")
      stacks_instance.submit_plan(stacks_plan)
      assert_nil repo_clone_step.run(repo: @repo, actor: @user)
      assert_equal repo.empty?, false
    end
  end

  context "cleanup" do

  end

  def add_files(repo)
    base_ref = repo.heads.build(repo.default_branch)
    base_ref.append_commit({ message: "Add fake files",
                             committer: repo.owner }, repo.owner) do |files|
      files.add("README.md", "RANDOM.txt")
    end
  end
end
