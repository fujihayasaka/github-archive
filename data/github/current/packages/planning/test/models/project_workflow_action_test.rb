# typed: true
# frozen_string_literal: true

require "test_helper"

class ProjectWorkflowActionTest < GitHub::TestCase
  fixtures do
    @workflow = create :project_workflow
  end

  test "can create a workflow" do
    action = create :project_workflow_action, project_workflow: @workflow
    assert_predicate action, :valid?
  end

  context "validate" do
    test "creator is present" do
      action = create :project_workflow_action, project_workflow: @workflow
      action.creator = nil
      refute_predicate action, :valid?
    end

    test "action_type is present" do
      action = create :project_workflow_action, project_workflow: @workflow
      action.action_type = nil
      refute_predicate action, :valid?
    end

    test "workflow is present" do
      action = create :project_workflow_action
      action.project_workflow = nil
      refute_predicate action, :valid?
    end
  end

  context "deletes" do
    test "deletes project workflow action when project workflow is deleted" do
      action = create :project_workflow_action, project_workflow: @workflow
      assert_difference("ProjectWorkflowAction.count", -1) do
        @workflow.destroy
      end
    end

    test "does not delete project workflow when action is deleted" do
      action = create :project_workflow_action, project_workflow: @workflow
      assert_no_difference("ProjectWorkflow.count") do
        action.destroy
      end
    end
  end
end
