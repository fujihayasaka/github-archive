# typed: false
# frozen_string_literal: true

require "test_helper"
require "securerandom"

class StackParserTest < GitHub::TestCase
  include DogstatsTestHelpers
  include PushTestHelper

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
  end

  def verify_steps(plan_id)
    steps = StacksSteps::Step.where(plan_id: plan_id, type: "StacksSteps::RepoCloneStep")
    assert_equal 1, steps.size

    steps = StacksSteps::Step.where(plan_id: plan_id, type: "StacksSteps::RepoMetadataStep")
    assert_equal 1, steps.size
    inputs = steps.first.inputs

    steps = StacksSteps::Step.where(plan_id: plan_id, type: "StacksSteps::BranchProtectionStep")
    assert_equal 2, steps.size
    inputs = steps.first.inputs
    assert_equal 2, inputs["required-pull-request-reviews"]["required-approving-review-count"]

    steps = StacksSteps::Step.where(plan_id: plan_id, type: "StacksSteps::CreateEnvironmentStep")
    assert_equal 2, steps.size
    inputs = steps.first.inputs
    assert_equal "staging", inputs["name"]

    steps = StacksSteps::Step.where(plan_id: plan_id, type: "StacksSteps::SecuritySettingsStep")
    assert_equal 1, steps.size
    inputs = steps.first.inputs
    assert_equal true, inputs["vulnerability-alerts"]

    steps = StacksSteps::Step.where(plan_id: plan_id, type: "StacksSteps::WorkflowDispatchStep")
    assert_equal 1, steps.size
    inputs = steps.first.inputs
    assert_equal @workflow_path, ".github/workflows/#{inputs["workflow_path"]}"
  end

  context "#parse" do
    test "parse stack template" do
      inputs = { "RepoName" => "Stack-Test-Repo" }
      GitHub.stubs(:enterprise?).returns(false) # rubocop:todo GitHub/DontStubEnterpriseInTests
      GitHub.stubs(:dependabot_enabled?).returns(true)
      stacks_parser = StackParser.new(@template)
      plan_object = stacks_parser.parse_and_get_plan(@stacks_instance_id, @target_repo, @actor, inputs, "124124")
      plan_object.save

      refute_equal 0, plan_object.id

      flows = StacksFlow.where(plan_id: plan_object.id)
      assert_equal 2, flows.size
      verify_steps plan_object.id

      # Testing sorter
      stacks_steps_list = StacksSteps::Step.where(plan_id: plan_object.id)
      assert_equal 8, stacks_steps_list.size
      assert_equal stacks_steps_list[0].class, StacksSteps::RepoCloneStep
      assert_equal stacks_steps_list[1].class, StacksSteps::RepoMetadataStep
      assert_equal stacks_steps_list[2].class, StacksSteps::BranchProtectionStep
      assert_equal stacks_steps_list[3].class, StacksSteps::BranchProtectionStep
      assert_equal stacks_steps_list[4].class, StacksSteps::CreateEnvironmentStep
      assert_equal stacks_steps_list[5].class, StacksSteps::CreateEnvironmentStep
      assert_equal stacks_steps_list[6].class, StacksSteps::SecuritySettingsStep
      assert_equal stacks_steps_list[7].class, StacksSteps::WorkflowDispatchStep
      assert_dogstats_distribution 1, "stack_parser.create_plan.time"
    end

    test "get_stack_github_apps_methods" do
      parser = StackParser.new(@template)
      expected_apps = [{ "slug" => "Azure", "parameters" => { "environment" => "production" } }, { "slug" => "codetree" }]
      assert_equal(parser.get_stack_github_apps, expected_apps)
      assert_dogstats_increment "stack_parser.validation.template", tags: ["action:success"]
    end

    test "get_stack_env_name_inputs_methods" do
      parser = StackParser.new(@template)
      expected_apps = ["${{ inputs.ENV_Name }}"]
      assert_equal(parser.get_stack_env_name_inputs, expected_apps)
      assert_dogstats_increment "stack_parser.validation.template", tags: ["action:success"]
    end

    test "fail on invalid yaml template" do
      stack_repo = create :repository, from_example: :simple

      # invalid stack content
      stack_yaml_content = <<-yaml
        invalid:: ok:
      yaml

      push_changes(repository: stack_repo, changes: [{
        path: ".github/stacks/stack.yml",
        content: stack_yaml_content
      }])

      assert_raises(Errors::StacksParserError) do
        StackParser.new stack_repo
      end
    end

    test "fail on invalid values yaml" do
      stack_repo = create :repository, from_example: :simple

      # sample stack content
      stack_yaml_content = <<-yaml
        valid: ok
      yaml

      # invalid values yaml
      values_yaml_content = <<-yaml
        invalid:: ok:
      yaml

      push_changes(repository: stack_repo, changes: [{
        path: ".github/stacks/stack.yml",
        content: stack_yaml_content
      }])

      push_changes(repository: stack_repo, changes: [{
        path: ".github/stacks/values.yml",
        content: values_yaml_content
      }])

      assert_raises(Errors::StacksParserError) do
        StackParser.new stack_repo
      end
    end
  end

  context "#release" do
    test "parse stack template using release repo ref" do
      inputs = { "RepoName" => "Stack-Test-Repo" }
      GitHub.stubs(:enterprise?).returns(false) # rubocop:todo GitHub/DontStubEnterpriseInTests
      GitHub.stubs(:dependabot_enabled?).returns(true)

      stacks_instance = StacksInstance.find_by(instance_repository_id: @target_repo.id)
      latest_release_ref = stacks_instance.template_ref
      repo_ref = @template.refs.find(latest_release_ref)
      stacks_parser = StackParser.new(@template, repo_ref)
      plan_object = stacks_parser.parse_and_get_plan(@stacks_instance_id, @target_repo, @actor, inputs, "124124")
      plan_object.save

      refute_equal 0, plan_object.id
    end
  end

end
