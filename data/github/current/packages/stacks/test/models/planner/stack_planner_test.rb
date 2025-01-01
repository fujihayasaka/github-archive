# typed: true
# frozen_string_literal: true

require "test_helper"
require "securerandom"

class StackPlannerTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @actor = create(:verified_user)
    @target_repo = create(:repository, name: "target_repo", owner: @actor, from_example: :stacks_parser)
    @template = create(:public_repository, owner: @actor, from_example: :stacks_parser)
    create :release, name: "Version One!", tag_name: "v1.0", author: @template.owner, repository: @template
    @workflow_path = ".github/workflows/setup.yml"
    workflow = Actions::Workflow.create(repository: @target_repo, path: @workflow_path, name: "")

    stacks_instance = StacksInstance.new(template_repo: @actor.name + "/" + @template.name, owner_id: @actor.id, actor_id: @actor.id, instance_repository_id: @target_repo.id, template_repository_id: @template.id, template_ref: "refs/tags/v1.0")
    stacks_instance.save
    @stacks_instance_id = stacks_instance.id
    @stacks_parser = StackParser.new(@template)
  end

  context "create_plan" do
    test "creates a plan" do
      inputs = { "RepoName" => "Stack-Test-Repo" }
      GitHub.stubs(:enterprise?).returns(false) # rubocop:todo GitHub/DontStubEnterpriseInTests
      GitHub.stubs(:dependabot_enabled?).returns(true)
      plan = @stacks_parser.parse_and_get_plan(@stacks_instance_id, @target_repo, @actor, inputs, "432212")
      plan.save

      refute_equal 0, plan.id
      stack_steps = StacksSteps::Step.where(plan_id: plan.id)
      assert_empty stack_steps.select { |step| step.class == StacksSteps::CleanupStep }
      assert_equal 8, stack_steps.size
      assert_equal stack_steps[0].class, StacksSteps::RepoCloneStep
      assert_equal stack_steps[1].class, StacksSteps::RepoMetadataStep
      assert_equal stack_steps[2].class, StacksSteps::BranchProtectionStep
      assert_equal stack_steps[3].class, StacksSteps::BranchProtectionStep
      assert_equal stack_steps[4].class, StacksSteps::CreateEnvironmentStep
      assert_equal stack_steps[5].class, StacksSteps::CreateEnvironmentStep
      assert_equal stack_steps[6].class, StacksSteps::SecuritySettingsStep
      assert_equal stack_steps[7].class, StacksSteps::WorkflowDispatchStep
    end

    test "creates a plan with cleanup step if its a retry plan" do
      inputs = { "RepoName" => "Stack-Test-Repo" }
      GitHub.stubs(:enterprise?).returns(false) # rubocop:todo GitHub/DontStubEnterpriseInTests
      GitHub.stubs(:dependabot_enabled?).returns(true)
      plan = @stacks_parser.parse_and_get_plan(@stacks_instance_id, @target_repo, @actor, inputs, "432212", true)
      plan.save

      refute_equal 0, plan.id
      stack_steps = StacksSteps::Step.where(plan_id: plan.id)
      assert_equal 9, stack_steps.size
      assert_equal stack_steps[0].class, StacksSteps::CleanupStep
      assert_equal stack_steps[1].class, StacksSteps::RepoCloneStep
      assert_equal stack_steps[2].class, StacksSteps::RepoMetadataStep
      assert_equal stack_steps[3].class, StacksSteps::BranchProtectionStep
      assert_equal stack_steps[4].class, StacksSteps::BranchProtectionStep
      assert_equal stack_steps[5].class, StacksSteps::CreateEnvironmentStep
      assert_equal stack_steps[6].class, StacksSteps::CreateEnvironmentStep
      assert_equal stack_steps[7].class, StacksSteps::SecuritySettingsStep
      assert_equal stack_steps[8].class, StacksSteps::WorkflowDispatchStep
    end

    test "can't create a plan if step validations fail" do
      StacksSteps::RepoCloneStep.expects(:validate_inputs).times(1).raises(Errors::ValidationError.new("error"))
      inputs = { "RepoName" => "Stack-Test-Repo" }
      GitHub.stubs(:enterprise?).returns(false) # rubocop:todo GitHub/DontStubEnterpriseInTests
      GitHub.stubs(:dependabot_enabled?).returns(true)
      assert_raises(Errors::ValidationError) do
        plan = @stacks_parser.parse_and_get_plan(@stacks_instance_id, @target_repo, @actor, inputs, "432212", true)
        assert_nil plan
      end
    end

    test "wieght threshold of each flow is respected" do
      inputs = { "RepoName" => "Stack-Test-Repo" }
      GitHub.stubs(:enterprise?).returns(false) # rubocop:todo GitHub/DontStubEnterpriseInTests
      GitHub.stubs(:dependabot_enabled?).returns(true)
      plan = @stacks_parser.parse_and_get_plan(@stacks_instance_id, @target_repo, @actor, inputs, "432212", true)
      plan.save

      flows = plan.stacks_flow
      flows.each do |flow|
        flow_steps = plan.stacks_step.fetch_steps_for_flow(plan.instance_id, flow.id)
        flow_weight = flow_steps.map(&:weight).reduce(:+)
        assert flow_weight <= StackPlanner::WEIGHT_THRESHOLD
      end
    end
  end
end
