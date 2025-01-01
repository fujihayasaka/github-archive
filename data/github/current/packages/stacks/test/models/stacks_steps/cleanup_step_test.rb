# typed: true
# frozen_string_literal: true

require "test_helper"

class CleanupStepTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @template_repo = create(:repository, owner: @user, from_example: :repository_test_simple)
    @repo = create(:repository, owner: @user)
    create :release, name: "Version One!", tag_name: "v1.0", author: @template_repo.owner, repository: @template_repo

    @stacks_instance = StacksInstance.create(template_repo: @template_repo.name_with_owner, owner_id: @repo.owner.id, actor_id: @user.id, instance_repository_id: @repo.id, template_repository_id: @template_repo.id, template_ref: "refs/tags/v1.0")
    @stacks_plan = StacksPlan.create(instance_id: @stacks_instance.id, actor_id: @user.id, status: StacksStatus.statuses[:not_started])

    @stacks_flow_1 = StacksFlow.create(instance_id: @stacks_instance.id, plan_id: @stacks_plan.id, depends_on: nil)
    @stacks_flow_2 = StacksFlow.create(instance_id: @stacks_instance.id, plan_id: @stacks_plan.id, depends_on: @stacks_flow_1)
    @stacks_flow_3 = StacksFlow.create(instance_id: @stacks_instance.id, plan_id: @stacks_plan.id, depends_on: @stacks_flow_2)

    @stacks_step_1 = StacksSteps::Step.create(instance_id: @stacks_instance.id, plan_id: @stacks_plan.id, flow_id: @stacks_flow_1.id, type: "StacksSteps::CleanupStep")
    @stacks_step_2 = StacksSteps::Step.create(instance_id: @stacks_instance.id, plan_id: @stacks_plan.id, flow_id: @stacks_flow_2.id, type: "StacksSteps::RepoCloneStep")
    @stacks_step_3 = StacksSteps::Step.create(instance_id: @stacks_instance.id, plan_id: @stacks_plan.id, flow_id: @stacks_flow_3.id, type: "StacksSteps::RepoMetadataStep")
    @stacks_step_4 = StacksSteps::Step.create(instance_id: @stacks_instance.id, plan_id: @stacks_plan.id, flow_id: @stacks_flow_3.id, type: "StacksSteps::BranchProtectionStep")
    @stacks_step_5 = StacksSteps::Step.create(instance_id: @stacks_instance.id, plan_id: @stacks_plan.id, flow_id: @stacks_flow_3.id, type: "StacksSteps::BranchProtectionStep")
    @stacks_step_6 = StacksSteps::Step.create(instance_id: @stacks_instance.id, plan_id: @stacks_plan.id, flow_id: @stacks_flow_3.id, type: "StacksSteps::SecuritySettingsStep")
    @stacks_step_7 = StacksSteps::Step.create(instance_id: @stacks_instance.id, plan_id: @stacks_plan.id, flow_id: @stacks_flow_3.id, type: "StacksSteps::WorkflowDispatchStep")
  end

  context "run" do
    test "cleanup should be triggered for all the steps" do
      assert_nothing_raised do
        @stacks_step_1.run(repo: @repo, actor: @user)
      end
    end
  end
end
