# typed: true
# frozen_string_literal: true

require "test_helper"

class Actions::WorkflowRunExecutionTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers

  fixtures do
    make_trusted_oauth_apps_owner

    @repository = create :repository
  end

  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
  end

  def create_workflow_run_execution(creator: nil)
    check_suite = create(:check_suite_for_actions_app, repository: @repository)
    check_suite.workflow_run.latest_workflow_run_execution
  end

  context "#previous_execution" do
    test "returns the correct value" do
      execution1 = create_workflow_run_execution
      assert_equal 1, execution1.attempt

      workflow_run = execution1.workflow_run
      execution2 = workflow_run.workflow_run_executions.create!(external_id: SimpleUUID::UUID.new.to_guid, attempt: 2)
      execution3 = workflow_run.workflow_run_executions.create!(external_id: SimpleUUID::UUID.new.to_guid, attempt: 3)

      assert_nil execution1.previous_execution
      assert_equal execution1, execution2.previous_execution
      assert_equal execution2, execution3.previous_execution
    end
  end

  test "doesn't scope in the referenced workflows by default" do
    execution = create_workflow_run_execution
    referenced_workflows = [{ "path": "github/internal-server/.github/workflows/called.yml@main", "sha": "735e3728915a6022535fa7ecbd6926ed0e44f5f5", "ref": "refs/heads/main" }].to_json
    execution.referenced_workflows = referenced_workflows
    execution.save!

    same_execution = Actions::WorkflowRunExecution.where(repository: @repository).first

    refute same_execution.respond_to?(:referenced_workflows)

    same_execution_with_scope = Actions::WorkflowRunExecution.with_referenced_workflows.where(repository: @repository).first

    assert_equal referenced_workflows, same_execution_with_scope&.referenced_workflows
  end

  test "doesn't scope in the graph by default" do
    execution = create_workflow_run_execution
    execution.update!(execution_graph: "{}")

    refute Actions::WorkflowRunExecution.find(execution.id).respond_to?(:execution_graph)
    assert Actions::WorkflowRunExecution.with_execution_graph.find(execution.id).respond_to?(:execution_graph)
  end

  test "scopes don't include other large fields" do
    referenced_workflows = [{ "path": "github/internal-server/.github/workflows/called.yml@main", "sha": "735e3728915a6022535fa7ecbd6926ed0e44f5f5", "ref": "refs/heads/main" }].to_json
    execution = create_workflow_run_execution
    execution.update!(execution_graph: "{}", referenced_workflows: referenced_workflows)

    assert Actions::WorkflowRunExecution.with_execution_graph.find(execution.id).respond_to?(:execution_graph)
    assert Actions::WorkflowRunExecution.with_referenced_workflows.find(execution.id).respond_to?(:referenced_workflows)

    refute Actions::WorkflowRunExecution.with_referenced_workflows.find(execution.id).respond_to?(:execution_graph)
    refute Actions::WorkflowRunExecution.with_execution_graph.find(execution.id).respond_to?(:referenced_workflows)
  end
end
