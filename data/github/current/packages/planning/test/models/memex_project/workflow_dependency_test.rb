# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProject::WorkflowDependencyTest < GitHub::TestCase
  fixtures do
    @project = create(:memex_project)
    @user = create(:verified_user)
  end

  context "#default_workflows" do
    test "returns a set of read-only workflows" do
      default_workflows = @project.default_workflows

      refute_empty default_workflows
      assert default_workflows.all? { |w| w.is_a?(MemexProjectWorkflow) }
      assert default_workflows.all?(&:readonly?)
    end
  end

  context "#default_workflow_attributes" do
    test "returns a set of valid default workflow attributes" do
      default_workflow_attributes = @project.default_workflow_attributes(
        creator: create(:user),
        repository: create(:repository, owner: @project.owner)
      )
      new_workflows = @project.workflows.create(default_workflow_attributes)

      assert new_workflows.all? { |w| w.valid? && w.persisted? }
    end
  end

  context "#workflow_configurations" do
    test "returns a set of workflow configurations with defaults and constraints" do
      workflow_configurations = @project.workflow_configurations(@user)

      refute_empty workflow_configurations
      assert workflow_configurations.all? { |wc| wc.is_a?(MemexProjectWorkflowConfiguration) }
    end
  end
end
