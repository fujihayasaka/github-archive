# typed: false
# frozen_string_literal: true

require "test_helper"

class StacksInstanceCleanerTest < GitHub::TestCase

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user = create(:user)
    @repo = create(:repository)
    @template_repo = create(:repository, from_example: :repository_test_simple)
    create :release, name: "Version One!", tag_name: "v1.0", author: @template_repo.owner, repository: @template_repo
    @stacks_instance = StacksInstance.create(template_repo: @template_repo.name_with_owner, owner_id: @repo.owner_id, actor_id: @user.id, instance_repository_id: @repo.id, template_repository_id: @template_repo.id, template_ref: "refs/tags/v1.0")
    @stacks_plan = StacksPlan.create(instance_id: @stacks_instance.id, actor_id: @user.id, status: StacksStatus.statuses[:not_started])

    @stacks_flow_1 = StacksFlow.create(instance_id: @stacks_instance.id, plan_id: @stacks_plan.id, depends_on: nil)
    @stacks_flow_2 = StacksFlow.create(instance_id: @stacks_instance.id, plan_id: @stacks_plan.id, depends_on: nil)
    @stacks_flow_3 = StacksFlow.create(instance_id: @stacks_instance.id, plan_id: @stacks_plan.id, depends_on: nil)

    workflow_dispatch_inputs = {
      "workflow_path" => ".github/workflows/init.yaml"
    }

    @stacks_step_1 = StacksSteps::Step.create(instance_id: @stacks_instance.id, plan_id: @stacks_plan.id, flow_id: @stacks_flow_1.id, type: "StacksSteps::RepoCloneStep")
    @stacks_step_2 = StacksSteps::Step.create(instance_id: @stacks_instance.id, plan_id: @stacks_plan.id, flow_id: @stacks_flow_2.id, type: "StacksSteps::RepoMetadataStep")
    @stacks_step_3 = StacksSteps::Step.create(instance_id: @stacks_instance.id, plan_id: @stacks_plan.id, flow_id: @stacks_flow_2.id, type: "StacksSteps::BranchProtectionStep")
    @stacks_step_4 = StacksSteps::Step.create(instance_id: @stacks_instance.id, plan_id: @stacks_plan.id, flow_id: @stacks_flow_2.id, type: "StacksSteps::SecuritySettingsStep")
    @stacks_step_5 = StacksSteps::Step.create(instance_id: @stacks_instance.id, plan_id: @stacks_plan.id, flow_id: @stacks_flow_3.id, type: "StacksSteps::WorkflowDispatchStep", inputs: workflow_dispatch_inputs)
    @stacks_orchestrator = StacksOrchestrator.new(@stacks_instance.id, @repo.id, @stacks_plan, @user)
    GitHub.flipper.enable(:stacks_toggle, @user)
  end

  context "cleanup_dependancies" do
    test "deletes all dependancies of a stack instance" do
      refute_empty @stacks_instance.stacks_flow
      refute_empty @stacks_instance.stacks_step
      refute_empty @stacks_instance.stacks_plan
      instance_status_details = @stacks_instance.get_status
      instance_status_details.status = "success"
      @stacks_instance.status_details = instance_status_details.to_json
      @stacks_instance.save

      StacksInstanceCleaner.cleanup_dependancies(@stacks_instance)
      assert_empty @stacks_instance.stacks_flow
      assert_empty @stacks_instance.stacks_step
      assert_empty @stacks_instance.stacks_plan
      assert_empty @stacks_instance.stacks_status
    end

    test "should not delete other stack instance dependancies" do
      new_repo = create(:repository)
      new_instance = StacksInstance.create(template_repo: @template_repo.name_with_owner, owner_id: new_repo.owner_id, actor_id: @user.id, instance_repository_id: new_repo.id, template_repository_id: @template_repo.id, template_ref: "refs/tags/v1.0")
      new_plan = StacksPlan.create(instance_id: new_instance.id, actor_id: @user.id, status: StacksStatus.statuses[:not_started])
      new_stacks_flow = StacksFlow.create(instance_id: new_instance.id, plan_id: new_plan.id, depends_on: nil)
      new_step = StacksSteps::Step.create(instance_id: new_instance.id, plan_id: new_plan.id, flow_id: new_stacks_flow.id, type: "StacksSteps::RepoCloneStep")

      refute_empty new_instance.stacks_flow
      refute_empty new_instance.stacks_step
      refute_empty new_instance.stacks_plan
      instance_status_details = new_instance.get_status
      instance_status_details.status = "success"
      new_instance.status_details = instance_status_details.to_json
      new_instance.save
      StacksInstanceCleaner.cleanup_dependancies(new_instance)
      assert_empty new_instance.stacks_flow
      assert_empty new_instance.stacks_step
      assert_empty new_instance.stacks_plan
      assert_empty new_instance.stacks_status

      refute_empty @stacks_instance.stacks_flow
      refute_empty @stacks_instance.stacks_step
      refute_empty @stacks_instance.stacks_plan
    end

    test "should not delete stack instance dependancies when the instance is not completed" do
      refute_empty @stacks_instance.stacks_flow
      refute_empty @stacks_instance.stacks_step
      refute_empty @stacks_instance.stacks_plan
      non_completed_statuses = StacksInstance.statuses.reject { |_k, v| v == "success" || v == "failed" }

      non_completed_statuses.each do |status, _|
        instance_status_details = @stacks_instance.get_status
        instance_status_details.status = StacksInstance.statuses.key(status)
        @stacks_instance.status_details = instance_status_details.to_json
        @stacks_instance.save

        error = assert_raises(Errors::StacksInstanceCleanupError) do
          StacksInstanceCleaner.cleanup_dependancies(@stacks_instance)
        end
        assert_equal "Stack instance cleanup failed: Cannot cleanup dependancies of an incomplete instance", error.message
        refute_empty @stacks_instance.stacks_flow
        refute_empty @stacks_instance.stacks_step
        refute_empty @stacks_instance.stacks_plan
      end
    end

    test "should not throw an error if dependancies are empty" do
      new_repo = create(:repository)
      new_instance = StacksInstance.create(template_repo: @template_repo.name_with_owner, owner_id: new_repo.owner_id, actor_id: @user.id, instance_repository_id: new_repo.id, template_repository_id: @template_repo.id, template_ref: "refs/tags/v1.0")

      instance_status_details = new_instance.get_status
      instance_status_details.status = "success"
      new_instance.status_details = instance_status_details.to_json
      new_instance.save

      StacksInstanceCleaner.cleanup_dependancies(new_instance)
      assert_empty new_instance.stacks_flow
      assert_empty new_instance.stacks_step
      assert_empty new_instance.stacks_plan
      assert_empty new_instance.stacks_status
    end
  end
end
